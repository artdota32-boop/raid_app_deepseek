import sys
import math
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

BASE = Path(__file__).resolve().parent
PROJECT_ROOT = BASE.parents[1]

sys.path.insert(0, str(BASE))

import test_det_vs_morph as dbnet
import test_ocr_ab as ab

IMAGE_PATH = BASE / "dbnet_samples_v1/card_001_t0p6s.jpg"
CRAFT_MODEL_PATH = BASE / "craft/craft_mlt_25k.onnx"

PROVIDERS = ["CPUExecutionProvider"]


def craft_detect(image, session):
    h, w = image.shape[:2]

    # Сохраняем пропорции изображения
    scale = 384.0 / max(h, w)
    nw = int(round(w * scale))
    nh = int(round(h * scale))

    resized = cv2.resize(
        image, (nw, nh), interpolation=cv2.INTER_LINEAR
    )
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)

    # Размеры дополнения до кратности 32
    pad_w = ((nw + 31) // 32) * 32 - nw
    pad_h = ((nh + 31) // 32) * 32 - nh

    left = pad_w // 2
    top = pad_h // 2

    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)

    normalized = rgb.astype(np.float32) / 255.0
    normalized = (normalized - mean) / std

    # Нулевое дополнение после нормализации
    canvas = np.zeros((nh + pad_h, nw + pad_w, 3), dtype=np.float32)
    canvas[top:top + nh, left:left + nw] = normalized

    tensor = np.transpose(canvas, (2, 0, 1))[None, ...]

    output = session.run(
        None,
        {session.get_inputs()[0].name: tensor}
    )[0]

    if output.ndim != 4 or output.shape[0] != 1 or output.shape[3] != 2:
        raise RuntimeError(f"Неожиданная форма CRAFT: {output.shape}")

    textmap = output[0, :, :, 0]
    linkmap = output[0, :, :, 1]

    text_threshold = 0.7
    low_text = 0.4
    link_threshold = 0.4

    text_score = (textmap > low_text).astype(np.uint8)
    link_score = (linkmap > link_threshold).astype(np.uint8)

    combined = np.clip(
        text_score + link_score, 0, 1
    ).astype(np.uint8)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        combined, connectivity=4
    )

    boxes = []

    for k in range(1, count):
        size = stats[k, cv2.CC_STAT_AREA]

        if size < 10:
            continue

        component = labels == k

        if float(textmap[component].max()) < text_threshold:
            continue

        segmap = np.zeros(textmap.shape, dtype=np.uint8)
        segmap[component] = 255

        segmap[(link_score == 1) & (text_score == 0)] = 0

        px = stats[k, cv2.CC_STAT_LEFT]
        py = stats[k, cv2.CC_STAT_TOP]
        pw = stats[k, cv2.CC_STAT_WIDTH]
        ph = stats[k, cv2.CC_STAT_HEIGHT]

        niter = int(
            math.sqrt(size * min(pw, ph) / (pw * ph)) * 2
        )

        sx = max(0, px - niter)
        ex = min(textmap.shape[1], px + pw + niter + 1)
        sy = max(0, py - niter)
        ey = min(textmap.shape[0], py + ph + niter + 1)

        kernel = cv2.getStructuringElement(
            cv2.MORPH_RECT,
            (1 + niter, 1 + niter)
        )

        segmap[sy:ey, sx:ex] = cv2.dilate(
            segmap[sy:ey, sx:ex], kernel
        )

        ys, xs = np.where(segmap != 0)

        if len(xs) == 0:
            continue

        points = np.column_stack((xs, ys)).astype(np.float32)
        rect = cv2.minAreaRect(points)
        box = cv2.boxPoints(rect)

        # Перевод координат heatmap в исходный кадр
        box[:, 0] = (box[:, 0] * 2 - left) / scale
        box[:, 1] = (box[:, 1] * 2 - top) / scale

        box[:, 0] = np.clip(box[:, 0], 0, w - 1)
        box[:, 1] = np.clip(box[:, 1], 0, h - 1)

        pts = box.astype(int)

        x1 = max(0, int(pts[:, 0].min()))
        y1 = max(0, int(pts[:, 1].min()))
        x2 = min(w, int(pts[:, 0].max()) + 1)
        y2 = min(h, int(pts[:, 1].max()) + 1)

        if x2 > x1 and y2 > y1:
            boxes.append((x1, y1, x2 - x1, y2 - y1))

    return sorted(boxes, key=lambda b: (b[1], b[0]))


def print_ocr_results(title, boxes, image, rec_session, rec_input, dictionary):
    print(f"\n========== {title} ==========")
    print("Областей:", len(boxes))

    for i, (x, y, bw, bh) in enumerate(boxes, 1):
        roi = image[y:y + bh, x:x + bw]

        if roi.size == 0:
            print(f"[{i:02d}] Пустая область — пропуск")
            continue

        text = ab.recognize(
            roi,
            ab.preprocess_a,
            rec_session,
            rec_input.name,
            dictionary,
        ).strip()

        print(
            f"[{i:02d}] x={x}, y={y}, "
            f"w={bw}, h={bh} -> {text!r}"
        )


def main():
    ab.check_files()

    if not CRAFT_MODEL_PATH.is_file():
        raise FileNotFoundError(CRAFT_MODEL_PATH)

    image = cv2.imread(str(IMAGE_PATH))

    if image is None:
        raise RuntimeError(f"Не удалось загрузить изображение: {IMAGE_PATH}")

    h, w = image.shape[:2]
    print(f"ИЗОБРАЖЕНИЕ: {w}x{h}")

    dictionary = ab.load_dictionary()

    print("\nЗагрузка DBNet...")
    dbnet_session = ort.InferenceSession(
        str(dbnet.MODEL_PATH),
        providers=PROVIDERS,
    )

    print("Загрузка CRAFT...")
    craft_session = ort.InferenceSession(
        str(CRAFT_MODEL_PATH),
        providers=PROVIDERS,
    )

    print("Загрузка OCR...")
    rec_session = ort.InferenceSession(
        str(ab.REC_MODEL_PATH),
        providers=PROVIDERS,
    )

    rec_input = rec_session.get_inputs()[0]

    print("Вход OCR:", rec_input.name, rec_input.shape)
    print("Выход OCR:", rec_session.get_outputs()[0].shape)

    print("\nОбнаружение областей DBNet...")
    dbnet_boxes = ab.detect_regions(image, dbnet_session)

    print("Обнаружение областей CRAFT...")
    craft_boxes = craft_detect(image, craft_session)

    print("\n========== СРАВНЕНИЕ ДЕТЕКТОРОВ ==========")
    print("DBNet:", len(dbnet_boxes))
    print("CRAFT:", len(craft_boxes))

    print_ocr_results(
        "DBNet OCR",
        dbnet_boxes,
        image,
        rec_session,
        rec_input,
        dictionary,
    )

    print_ocr_results(
        "CRAFT OCR",
        craft_boxes,
        image,
        rec_session,
        rec_input,
        dictionary,
    )

    print("\n========== СРАВНЕНИЕ ЗАВЕРШЕНО ==========")


if __name__ == "__main__":
    main()

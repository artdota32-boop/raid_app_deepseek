import sys
import math
from pathlib import Path
from collections import Counter

import cv2
import numpy as np
import onnxruntime as ort

BASE = Path(__file__).resolve().parent
SAMPLES_DIR = BASE / "dbnet_samples_v1"
CRAFT_MODEL_PATH = BASE / "craft" / "craft_mlt_25k.onnx"

sys.path.insert(0, str(BASE))
import test_det_vs_morph as dbnet
import test_ocr_ab as ab


def craft_detect(image, session):
    h, w = image.shape[:2]

    scale = 384.0 / max(h, w)
    nw = int(round(w * scale))
    nh = int(round(h * scale))

    resized = cv2.resize(
        image, (nw, nh), interpolation=cv2.INTER_LINEAR
    )
    rgb = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB)

    pad_w = ((nw + 31) // 32) * 32 - nw
    pad_h = ((nh + 31) // 32) * 32 - nh
    left, top = pad_w // 2, pad_h // 2

    mean = np.array([0.485, 0.456, 0.406], np.float32)
    std = np.array([0.229, 0.224, 0.225], np.float32)

    normalized = rgb.astype(np.float32) / 255.0
    normalized = (normalized - mean) / std

    canvas = np.zeros(
        (nh + pad_h, nw + pad_w, 3), dtype=np.float32
    )
    canvas[top:top + nh, left:left + nw] = normalized

    tensor = np.transpose(canvas, (2, 0, 1))[None, ...]

    output = session.run(
        None, {session.get_inputs()[0].name: tensor}
    )[0]

    textmap = output[0, :, :, 0]
    linkmap = output[0, :, :, 1]

    text_threshold = 0.7
    low_text = 0.4
    link_threshold = 0.4

    text_score = (textmap > low_text).astype(np.uint8)
    link_score = (linkmap > link_threshold).astype(np.uint8)
    combined = np.clip(text_score + link_score, 0, 1).astype(np.uint8)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        combined, connectivity=4
    )

    boxes = []

    for k in range(1, count):
        size = stats[k, cv2.CC_STAT_AREA]
        if size < 10:
            continue

        comp = labels == k
        if float(textmap[comp].max()) < text_threshold:
            continue

        segmap = np.zeros(textmap.shape, dtype=np.uint8)
        segmap[comp] = 255
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
            cv2.MORPH_RECT, (1 + niter, 1 + niter)
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


def box_iou(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b

    x1 = max(ax, bx)
    y1 = max(ay, by)
    x2 = min(ax + aw, bx + bw)
    y2 = min(ay + ah, by + bh)

    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    area_a = aw * ah
    area_b = bw * bh
    union = area_a + area_b - intersection

    return intersection / union if union > 0 else 0.0


def match_boxes(boxes_a, boxes_b, threshold=0.30):
    candidates = []

    for i, a in enumerate(boxes_a):
        for j, b in enumerate(boxes_b):
            score = box_iou(a, b)
            if score >= threshold:
                candidates.append((score, i, j))

    candidates.sort(reverse=True)

    used_a = set()
    used_b = set()
    matches = []

    for score, i, j in candidates:
        if i in used_a or j in used_b:
            continue

        used_a.add(i)
        used_b.add(j)
        matches.append((i, j, score))

    return matches, used_a, used_b


def recognize_boxes(image, boxes, session, input_name, dictionary):
    results = []

    for x, y, w, h in boxes:
        roi = image[y:y + h, x:x + w]

        if roi.size == 0:
            results.append("")
            continue

        text = ab.recognize(
            roi,
            ab.preprocess_a,
            session,
            input_name,
            dictionary
        ).strip()

        results.append(text)

    return results


def main():
    ab.check_files()

    if not CRAFT_MODEL_PATH.is_file():
        raise FileNotFoundError(CRAFT_MODEL_PATH)

    samples = sorted(SAMPLES_DIR.glob("card_*.jpg"))

    print(f"\nНайдено кадров: {len(samples)}")

    if len(samples) != 7:
        raise RuntimeError(
            f"Ожидалось 7 кадров, найдено: {len(samples)}"
        )

    print("\nЗагрузка словаря...")
    dictionary = ab.load_dictionary()

    providers = ["CPUExecutionProvider"]

    print("\nЗагрузка DBNet...")
    dbnet_session = ort.InferenceSession(
        str(dbnet.MODEL_PATH), providers=providers
    )

    print("Загрузка CRAFT...")
    craft_session = ort.InferenceSession(
        str(CRAFT_MODEL_PATH), providers=providers
    )

    print("Загрузка OCR...")
    rec_session = ort.InferenceSession(
        str(ab.REC_MODEL_PATH), providers=providers
    )
    rec_input = rec_session.get_inputs()[0]

    all_results = {"DBNet": [], "CRAFT": []}

    total_dbnet = 0
    total_craft = 0
    total_geo_matches = 0
    total_same_text = 0
    total_different_text = 0
    total_unmatched_dbnet = 0
    total_unmatched_craft = 0

    for sample_path in samples:
        print(f"\n{'=' * 18} {sample_path.name} {'=' * 18}")

        image = cv2.imread(str(sample_path))

        if image is None:
            raise RuntimeError(
                f"Не удалось загрузить: {sample_path}"
            )

        print(f"Размер изображения: {image.shape[1]}x{image.shape[0]}")

        db_boxes = ab.detect_regions(image, dbnet_session)
        craft_boxes = craft_detect(image, craft_session)

        db_texts = recognize_boxes(
            image, db_boxes, rec_session, rec_input.name, dictionary
        )
        craft_texts = recognize_boxes(
            image, craft_boxes, rec_session, rec_input.name, dictionary
        )

        all_results["DBNet"].append((db_boxes, db_texts))
        all_results["CRAFT"].append((craft_boxes, craft_texts))

        total_dbnet += len(db_boxes)
        total_craft += len(craft_boxes)

        matches, used_d, used_c = match_boxes(
            db_boxes, craft_boxes
        )

        same = 0
        different = 0

        for i, j, score in matches:
            if db_texts[i] == craft_texts[j]:
                same += 1
            else:
                different += 1

        unmatched_d = len(db_boxes) - len(used_d)
        unmatched_c = len(craft_boxes) - len(used_c)

        total_geo_matches += len(matches)
        total_same_text += same
        total_different_text += different
        total_unmatched_dbnet += unmatched_d
        total_unmatched_craft += unmatched_c

        print(
            f"DBNet: {len(db_boxes)} областей | "
            f"CRAFT: {len(craft_boxes)} областей"
        )
        print(
            f"Геометрически сопоставлено: {len(matches)} | "
            f"Одинаковый OCR: {same} | "
            f"Разный OCR: {different}"
        )
        print(
            f"Без пары: DBNet={unmatched_d}, CRAFT={unmatched_c}"
        )

        print("\nDBNet OCR:")
        for i, (box, text) in enumerate(zip(db_boxes, db_texts), 1):
            print(f" D{i:02d} {box} -> {text!r}")

        print("\nCRAFT OCR:")
        for i, (box, text) in enumerate(zip(craft_boxes, craft_texts), 1):
            print(f" C{i:02d} {box} -> {text!r}")

        if matches:
            print("\nСопоставленные области:")
            for i, j, score in matches:
                print(
                    f" D{i + 1:02d} {db_texts[i]!r} "
                    f"<-> C{j + 1:02d} {craft_texts[j]!r} "
                    f"IoU={score:.2f}"
                )

    print("\n" + "=" * 16 + " ОБЩИЙ ИТОГ " + "=" * 16)
    print(f"Кадров обработано: {len(samples)}")
    print(f"Всего областей DBNet: {total_dbnet}")
    print(f"Всего областей CRAFT: {total_craft}")
    print(f"Среднее DBNet на кадр: {total_dbnet / 7:.2f}")
    print(f"Среднее CRAFT на кадр: {total_craft / 7:.2f}")
    print(f"Геометрических совпадений: {total_geo_matches}")
    print(f"Совпавший OCR в парных областях: {total_same_text}")
    print(f"Различающийся OCR в парных областях: {total_different_text}")
    print(f"Областей DBNet без пары: {total_unmatched_dbnet}")
    print(f"Областей CRAFT без пары: {total_unmatched_craft}")

    print("\n" + "=" * 16 + " СТАБИЛЬНОСТЬ " + "=" * 16)

    for detector in ("DBNet", "CRAFT"):
        frames = all_results[detector]
        base_boxes, base_texts = frames[0]

        print(f"\n{detector}: сравнение остальных кадров с первым")

        stable_geometry = 0
        stable_text = 0
        total_baseline_matches = 0

        for frame_index, (boxes, texts) in enumerate(frames[1:], 2):
            matches, _, _ = match_boxes(
                base_boxes, boxes, threshold=0.30
            )

            same_text = sum(
                1 for i, j, _ in matches
                if base_texts[i] == texts[j]
            )

            stable_geometry += len(matches)
            stable_text += same_text
            total_baseline_matches += len(matches)

            print(
                f"Кадр {frame_index}: "
                f"областей={len(boxes)}, "
                f"совпадений с первым={len(matches)}, "
                f"тот же текст={same_text}"
            )

        print(
            f"Всего геометрических совпадений с первым кадром: "
            f"{stable_geometry}"
        )
        print(
            f"Из них с одинаковым текстом: {stable_text}"
        )

        text_frames = Counter()

        for _, texts in frames:
            for text in set(t for t in texts if t):
                text_frames[text] += 1

        print("Тексты, повторившиеся в нескольких кадрах:")
        repeated = [
            (text, count)
            for text, count in text_frames.most_common()
            if count >= 2
        ]

        if repeated:
            for text, count in repeated:
                print(f" {count}/7 кадров: {text!r}")
        else:
            print(" Повторяющихся текстов не найдено")

    print("\nТЕСТ 7 КАДРОВ ЗАВЕРШЁН")


if __name__ == "__main__":
    main()

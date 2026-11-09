import sys
import math
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

BASE = Path(__file__).resolve().parent
PROJECT_ROOT = BASE.parents[1]

IMAGE_PATH = BASE / "dbnet_samples_v1/card_001_t0p6s.jpg"
DET_MODEL_PATH = BASE / "det_inference.onnx"
REC_MODEL_PATH = PROJECT_ROOT / "assets/inference.onnx"
DICT_PATH = PROJECT_ROOT / "assets/dict.txt"

sys.path.insert(0, str(BASE))
import test_det_vs_morph as detector


def check_files():
    for path in (
        IMAGE_PATH,
        DET_MODEL_PATH,
        REC_MODEL_PATH,
        DICT_PATH,
    ):
        if not path.is_file():
            raise FileNotFoundError(f"Файл не найден: {path}")


def dart_round(value):
    return int(math.floor(value + 0.5))


def load_dictionary():
    symbols = [
        line.strip()
        for line in DICT_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    symbols.append(" ")

    print("Символов словаря:", len(symbols))
    print("Ожидаемое число классов с blank:", len(symbols) + 1)

    return symbols


def preprocess_common(padded):
    tensor = np.empty((1, 3, 48, 320), dtype=np.float32)

    for c in range(3):
        tensor[0, c] = (
            (padded[:, :, c].astype(np.float32) / 255.0 - 0.5)
            / 0.5
        )

    return tensor


def preprocess_a(roi):
    # A: центральная выборка, как в Flutter
    inverted = 255 - roi

    h, w = inverted.shape[:2]
    if h <= 0 or w <= 0:
        raise ValueError("Пустая область OCR")

    target_w = max(1, min(320, dart_round(48 * w / h)))

    ys = (
        (2 * np.arange(48, dtype=np.int64) + 1) * h
    ) // (2 * 48)

    xs = (
        (2 * np.arange(target_w, dtype=np.int64) + 1) * w
    ) // (2 * target_w)

    resized = inverted[ys[:, None], xs[None, :]]

    padded = np.full((48, 320, 3), 255, dtype=np.uint8)
    padded[:, :target_w, :] = resized

    return preprocess_common(padded)


def preprocess_b(roi):
    # B: OpenCV INTER_LINEAR
    inverted = 255 - roi

    h, w = inverted.shape[:2]
    if h <= 0 or w <= 0:
        raise ValueError("Пустая область OCR")

    target_w = max(1, min(320, dart_round(48 * w / h)))

    resized = cv2.resize(
        inverted,
        (target_w, 48),
        interpolation=cv2.INTER_LINEAR,
    )

    padded = np.full((48, 320, 3), 255, dtype=np.uint8)
    padded[:, :target_w, :] = resized

    return preprocess_common(padded)


def detect_regions(image, session):
    h, w = image.shape[:2]

    input_info = session.get_inputs()[0]
    tensor, _, _ = detector.dbnet_preprocess(image)

    output = session.run(
        None,
        {input_info.name: tensor},
    )[0]

    polygons = detector.dbnet_postprocess(
        np.asarray(output, dtype=np.float32),
        h,
        w,
    )

    boxes = []

    for polygon in polygons:
        points = polygon.reshape(-1, 2)

        x1 = max(0, int(np.floor(points[:, 0].min())))
        y1 = max(0, int(np.floor(points[:, 1].min())))
        x2 = min(w, int(np.ceil(points[:, 0].max())) + 1)
        y2 = min(h, int(np.ceil(points[:, 1].max())) + 1)

        if x2 > x1 and y2 > y1:
            boxes.append((x1, y1, x2 - x1, y2 - y1))

    return sorted(boxes, key=lambda box: (box[1], box[0]))


def ctc_decode(output, dictionary):
    if output.ndim != 3 or output.shape[0] != 1:
        raise RuntimeError(f"Неожиданная форма OCR: {output.shape}")

    expected_classes = len(dictionary) + 1

    if output.shape[2] != expected_classes:
        raise RuntimeError(
            f"Число классов модели: {output.shape[2]}, "
            f"ожидалось: {expected_classes}"
        )

    result = []
    last_idx = -1

    for t in range(output.shape[1]):
        best_idx = int(np.argmax(output[0, t, :]))

        if best_idx != 0 and best_idx != last_idx:
            result.append(dictionary[best_idx - 1])

        last_idx = best_idx

    return "".join(result)


def recognize(roi, preprocess_fn, session, input_name, dictionary):
    tensor = preprocess_fn(roi)

    output = session.run(
        None,
        {input_name: tensor},
    )[0]

    return ctc_decode(output, dictionary)


def main():
    check_files()

    dictionary = load_dictionary()

    image = cv2.imread(str(IMAGE_PATH))
    if image is None:
        raise RuntimeError("Не удалось загрузить тестовое изображение")

    h, w = image.shape[:2]
    print(f"Изображение: {w}x{h}")

    providers = ["CPUExecutionProvider"]

    print("\nЗагрузка DBNet...")
    det_session = ort.InferenceSession(
        str(DET_MODEL_PATH),
        providers=providers,
    )

    print("Загрузка OCR...")
    rec_session = ort.InferenceSession(
        str(REC_MODEL_PATH),
        providers=providers,
    )

    rec_input = rec_session.get_inputs()[0]

    print("Вход OCR:", rec_input.name, rec_input.shape)
    print("Выход OCR:", rec_session.get_outputs()[0].shape)

    boxes = detect_regions(image, det_session)
    print("\nОбластей DBNet:", len(boxes))

    same = 0
    different = 0
    processed = 0

    print("\n========== A/B OCR ==========")

    for i, (x, y, box_w, box_h) in enumerate(boxes, 1):
        roi = image[y:y + box_h, x:x + box_w]

        if roi.size == 0:
            print(f"[{i:02d}] Пустая область — пропуск")
            continue

        text_a = recognize(
            roi, preprocess_a, rec_session,
            rec_input.name, dictionary,
        )

        text_b = recognize(
            roi, preprocess_b, rec_session,
            rec_input.name, dictionary,
        )

        processed += 1

        if text_a == text_b:
            same += 1
            status = "СОВПАЛИ"
        else:
            different += 1
            status = "РАЗЛИЧАЮТСЯ"

        print(
            f"\n[{i:02d}] x={x}, y={y}, "
            f"w={box_w}, h={box_h} — {status}"
        )
        print(f"  A: {text_a!r}")
        print(f"  B: {text_b!r}")

    print("\n========== ИТОГ ==========")
    print("Обработано областей:", processed)
    print("Совпали:", same)
    print("Различаются:", different)
    print("ТЕСТ ЗАВЕРШЁН")


if __name__ == "__main__":
    main()

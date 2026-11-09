from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
import csv
import sys

BASE = Path("experiments/card_localization")
SAMPLES_DIR = BASE / "dbnet_samples_v1"
REC_MODEL_PATH = Path("assets/inference.onnx")
DICT_PATH = Path("assets/dict.txt")
OUTPUT_DIR = BASE / "dbnet_samples_v1_results"

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(BASE.resolve()))
import test_det_vs_morph as detector


def dbnet_detect(image, session):
    h, w = image.shape[:2]
    input_info = session.get_inputs()[0]
    tensor, _, _ = detector.dbnet_preprocess(image)

    outputs = session.run(None, {input_info.name: tensor})

    polygons = detector.dbnet_postprocess(
        np.asarray(outputs[0], dtype=np.float32), h, w
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

    return sorted(boxes, key=lambda b: (b[1], b[0]))


def preprocess(roi):
    inverted = 255 - roi
    h, w = inverted.shape[:2]

    if h <= 0 or w <= 0:
        raise ValueError("Пустая область OCR")

    ratio = w / h
    target_w = max(1, min(320, round(48 * ratio)))

    ys = ((2 * np.arange(48) + 1) * h) // (2 * 48)
    xs = ((2 * np.arange(target_w) + 1) * w) // (2 * target_w)

    resized = inverted[ys[:, None], xs[None, :]]

    padded = np.full((48, 320, 3), 255, dtype=np.uint8)
    padded[:, :target_w, :] = resized

    tensor = np.empty((1, 3, 48, 320), dtype=np.float32)

    for c in range(3):
        tensor[0, c] = (
            padded[:, :, c].astype(np.float32) / 255.0 - 0.5
        ) / 0.5

    return tensor


def ctc_decode(output, dictionary):
    if output.ndim != 3 or output.shape[0] != 1:
        raise RuntimeError(
            f"Неожиданная форма выхода Rec: {output.shape}"
        )

    result = []
    last_idx = -1

    for t in range(output.shape[1]):
        best_idx = int(np.argmax(output[0, t, :]))

        if best_idx != 0 and best_idx != last_idx:
            if 1 <= best_idx <= len(dictionary):
                result.append(dictionary[best_idx - 1])

        last_idx = best_idx

    return "".join(result)


def main():
    for path in (REC_MODEL_PATH, DICT_PATH):
        if not path.is_file():
            raise FileNotFoundError(f"Файл не найден: {path}")

    if not SAMPLES_DIR.is_dir():
        raise FileNotFoundError(f"Папка образцов не найдена: {SAMPLES_DIR}")

    samples = sorted(SAMPLES_DIR.glob("card_*.jpg"))

    if not samples:
        raise RuntimeError("В папке нет образцов card_*.jpg")

    with open(DICT_PATH, encoding="utf-8") as f:
        dictionary = [line.strip() for line in f.read().splitlines()]
        dictionary.append(" ")  # CTC: последний класс — пробел

    print("=== ЗАГРУЗКА ONNX МОДЕЛЕЙ ===")
    print("Образцов:", len(samples))
    print("Словарь:", len(dictionary))

    dbnet_session = ort.InferenceSession(
        str(detector.MODEL_PATH),
        providers=["CPUExecutionProvider"]
    )

    rec_session = ort.InferenceSession(
        str(REC_MODEL_PATH),
        providers=["CPUExecutionProvider"]
    )

    rec_input = rec_session.get_inputs()[0]

    print("DBNet:", detector.MODEL_PATH)
    print("Rec вход:", rec_input.name, rec_input.shape)
    print("Rec выход:", rec_session.get_outputs()[0].shape)

    summary_path = OUTPUT_DIR / "summary.csv"

    with open(summary_path, "w", newline="", encoding="utf-8-sig") as csv_file:
        writer = csv.writer(csv_file, delimiter=";")
        writer.writerow([
            "sample", "width", "height",
            "dbnet_regions", "nonempty_ocr", "result_image"
        ])

        for sample_path in samples:
            print(f"\n--- {sample_path.name} ---")

            image = cv2.imread(str(sample_path))

            if image is None:
                print("ОШИБКА: не удалось загрузить изображение")
                continue

            h, w = image.shape[:2]
            print(f"Размер: {w}x{h}")

            boxes = dbnet_detect(image, dbnet_session)
            print(f"DBNet областей: {len(boxes)}")

            preview = image.copy()
            nonempty = 0
            result_image = f"result_{sample_path.stem}.jpg"
            result_path = OUTPUT_DIR / result_image

            for i, (x, y, bw, bh) in enumerate(boxes, 1):
                roi = image[y:y + bh, x:x + bw]

                if roi.size == 0:
                    text = ""
                else:
                    tensor = preprocess(roi)
                    output = rec_session.run(
                        None, {rec_input.name: tensor}
                    )[0]
                    text = ctc_decode(output, dictionary)

                if text.strip():
                    nonempty += 1

                print(
                    f"[{i:02d}] x={x}, y={y}, "
                    f"w={bw}, h={bh} -> {text!r}"
                )

                cv2.rectangle(
                    preview, (x, y), (x + bw, y + bh), (0, 0, 255), 1
                )

                cv2.putText(
                    preview, str(i), (x, max(12, y - 3)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 0, 255), 1
                )

            if not cv2.imwrite(str(result_path), preview):
                print("ОШИБКА: не удалось сохранить изображение")
                continue

            print(f"Непустых OCR: {nonempty}/{len(boxes)}")
            print(f"Изображение: {result_path}")

            writer.writerow([
                sample_path.name, w, h,
                len(boxes), nonempty, result_image
            ])

    print("\n=== ИТОГ ===")
    print("Сводная таблица:", summary_path)
    print("Результаты:", OUTPUT_DIR)


if __name__ == "__main__":
    main()

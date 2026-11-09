from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
import sys

BASE = Path("experiments/card_localization")
IMAGE_PATH = BASE / "card_crop.jpg"
REC_MODEL_PATH = Path("assets/inference.onnx")
DICT_PATH = Path("assets/dict.txt")

OUT_MORPH = BASE / "ocr_morphology.jpg"
OUT_DBNET = BASE / "ocr_dbnet.jpg"
OUT_COMPARE = BASE / "ocr_compare.jpg"

# Используем уже проверенную реализацию DBNet.
sys.path.insert(0, str(BASE.resolve()))
import test_det_vs_morph as detector


def morphology_detect(image):
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, mask = cv2.threshold(gray, 150, 255, cv2.THRESH_BINARY)

    kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (15, 3)
    )

    closed = cv2.morphologyEx(
        mask, cv2.MORPH_CLOSE, kernel, iterations=1
    )

    contours, _ = cv2.findContours(
        closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )

    boxes = []

    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        if w > 5 and h > 5:
            boxes.append((x, y, w, h))

    return sorted(boxes, key=lambda b: (b[1], b[0]))


def dbnet_detect(image):
    h, w = image.shape[:2]

    session = ort.InferenceSession(
        str(detector.MODEL_PATH),
        providers=["CPUExecutionProvider"]
    )

    input_info = session.get_inputs()[0]
    tensor, _, _ = detector.dbnet_preprocess(image)

    outputs = session.run(
        None, {input_info.name: tensor}
    )

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
    target_w = round(48 * ratio)
    target_w = max(1, min(320, target_w))

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


def recognize(image, boxes, session, input_name, dictionary, title, color, output_path):
    preview = image.copy()
    results = []

    print(f"\n=== {title} OCR ===")
    print(f"Областей: {len(boxes)}")

    for i, (x, y, w, h) in enumerate(boxes, 1):
        roi = image[y:y+h, x:x+w]

        if roi.size == 0:
            text = ""
        else:
            tensor = preprocess(roi)
            output = session.run(
                None, {input_name: tensor}
            )[0]
            text = ctc_decode(output, dictionary)

        results.append((x, y, w, h, text))

        print(
            f"[{i:02d}] x={x}, y={y}, w={w}, h={h}"
            f" -> {text!r}"
        )

        cv2.rectangle(
            preview, (x, y), (x+w, y+h), color, 1
        )

        cv2.putText(
            preview, str(i), (x, max(12, y-3)),
            cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1
        )

    cv2.imwrite(str(output_path), preview)

    nonempty = sum(bool(item[4].strip()) for item in results)
    print(f"Непустых распознаваний: {nonempty}/{len(results)}")
    print(f"Изображение: {output_path}")

    return results, preview


def main():
    for path in (IMAGE_PATH, REC_MODEL_PATH, DICT_PATH):
        if not path.is_file():
            raise FileNotFoundError(f"Файл не найден: {path}")

    image = cv2.imread(str(IMAGE_PATH))
    if image is None:
        raise RuntimeError("Не удалось загрузить карточку")

    with open(DICT_PATH, encoding="utf-8") as f:
        dictionary = [line.strip() for line in f.read().split("\n")]

    print("=== REC MODEL ===")
    print("Словарь:", len(dictionary))

    rec_session = ort.InferenceSession(
        str(REC_MODEL_PATH),
        providers=["CPUExecutionProvider"]
    )

    rec_input = rec_session.get_inputs()[0]

    print("Вход:", rec_input.name, rec_input.shape)
    print("Выход:", rec_session.get_outputs()[0].shape)

    morph_boxes = morphology_detect(image)
    dbnet_boxes = dbnet_detect(image)

    print("\n=== DETECTION COUNTS ===")
    print("Morphology:", len(morph_boxes))
    print("DBNet:", len(dbnet_boxes))

    morph_results, morph_image = recognize(
        image, morph_boxes, rec_session, rec_input.name,
        dictionary, "MORPHOLOGY", (0, 255, 0), OUT_MORPH
    )

    dbnet_results, dbnet_image = recognize(
        image, dbnet_boxes, rec_session, rec_input.name,
        dictionary, "DBNET", (0, 0, 255), OUT_DBNET
    )

    compare = cv2.hconcat([morph_image, dbnet_image])
    cv2.imwrite(str(OUT_COMPARE), compare)

    print("\n=== FINAL ===")
    print("Morphology распознано:", len(morph_results))
    print("DBNet распознано:", len(dbnet_results))
    print("Сравнение:", OUT_COMPARE)


if __name__ == "__main__":
    main()

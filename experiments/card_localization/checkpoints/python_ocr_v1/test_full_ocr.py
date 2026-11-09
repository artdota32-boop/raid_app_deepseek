import cv2
import numpy as np
import onnxruntime as ort
import re

IMAGE_PATH = "experiments/card_localization/card_crop.jpg"
MODEL_PATH = "assets/inference.onnx"
DICT_PATH = "assets/dict.txt"
OUTPUT_PATH = "experiments/card_localization/test_full_ocr.jpg"

# 1. Загружаем карточку
image = cv2.imread(IMAGE_PATH)
if image is None:
    raise RuntimeError(f"Не удалось загрузить {IMAGE_PATH}")

print("=== КАРТОЧКА ===")
print("Размер:", image.shape)

# 2. Загружаем словарь и ONNX
with open(DICT_PATH, encoding="utf-8") as f:
    dictionary = [line.strip() for line in f.read().split("\n")]

session = ort.InferenceSession(
    MODEL_PATH,
    providers=["CPUExecutionProvider"]
)

print("\n=== ONNX ===")
print("Вход:", session.get_inputs()[0].shape)
print("Выход:", session.get_outputs()[0].shape)
print("Символов в словаре:", len(dictionary))

# 3. Preprocessing — повторяем Dart
def preprocess(roi_bgr):
    # Инверсия
    inverted = 255 - roi_bgr

    h, w = inverted.shape[:2]
    ratio = w / h

    target_w = round(48 * ratio)
    target_w = max(1, min(320, target_w))

    # Та же центральная выборка пикселей, что в Dart
    ys = ((2 * np.arange(48) + 1) * h) // (2 * 48)
    xs = ((2 * np.arange(target_w) + 1) * w) // (2 * target_w)

    resized = inverted[ys[:, None], xs[None, :]]

    # Белое дополнение справа
    padded = np.full((48, 320, 3), 255, dtype=np.uint8)
    padded[:, :target_w, :] = resized

    # OpenCV уже использует BGR — порядок каналов совпадает с Dart
    tensor = np.empty((1, 3, 48, 320), dtype=np.float32)

    for c in range(3):
        tensor[0, c] = (
            padded[:, :, c].astype(np.float32) / 255.0 - 0.5
        ) / 0.5

    return tensor

# 4. CTC-декодер — логика как в Dart
def ctc_decode(output):
    if output.ndim != 3 or output.shape[0] != 1:
        raise RuntimeError(f"Неожиданная форма выхода: {output.shape}")

    time_steps = output.shape[1]
    vocab_size = output.shape[2]

    result = []
    last_idx = -1

    for t in range(time_steps):
        best_idx = int(np.argmax(output[0, t, :]))

        if best_idx != 0 and best_idx != last_idx:
            if 1 <= best_idx <= len(dictionary):
                result.append(dictionary[best_idx - 1])

        last_idx = best_idx

    return "".join(result)

# 5. Ищем горизонтальные текстовые области
gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
_, mask = cv2.threshold(gray, 150, 255, cv2.THRESH_BINARY)

kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (15, 3))
closed = cv2.morphologyEx(
    mask, cv2.MORPH_CLOSE, kernel, iterations=1
)

contours, _ = cv2.findContours(
    closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
)

lines = []

for contour in contours:
    x, y, w, h = cv2.boundingRect(contour)

    if w > 5 and h > 5:
        lines.append((x, y, w, h))

lines.sort(key=lambda box: (box[1], box[0]))

print("\n=== ПОИСК СТРОК ===")
print("Найдено областей:", len(lines))

# 6. Распознаём каждую область
preview = image.copy()
first_output = None
recognized = []  # Сохраняем результаты первого OCR

for i, (x, y, w, h) in enumerate(lines, 1):
    roi = image[y:y+h, x:x+w]

    tensor = preprocess(roi)
    output = session.run(None, {"x": tensor})[0]

    if first_output is None:
        first_output = output
        row_sums = output[0].sum(axis=1)
        print("\n=== ДИАГНОСТИКА ВЫХОДА ===")
        print("Форма:", output.shape)
        print("Минимум:", float(output.min()))
        print("Максимум:", float(output.max()))
        print("Сумма по классам, среднее:", float(row_sums.mean()))

    text = ctc_decode(output)
    recognized.append((x, y, w, h, text))

    print(
        f"[{i}/{len(lines)}] "
        f"x={x}, y={y}, w={w}, h={h} -> {text!r}"
    )

    cv2.rectangle(preview, (x, y), (x+w, y+h), (0, 255, 0), 2)
    cv2.putText(
        preview, str(i), (x, max(12, y-4)),
        cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 255, 0), 1
    )

# 6.5. Объединяем названия характеристик с числовыми значениями
print("\n=== ГРУППИРОВКА ===")

number_re = re.compile(r"^[+-]?\d+(?:[.,]\d+)?%?$")
paired_values = set()
pairs = {}

# Максимальный промежуток между названием и значением
max_gap = int(image.shape[1] * 0.40)

for i, (x, y, w, h, text) in enumerate(recognized):
    label = text.strip()

    if not label or number_re.fullmatch(label):
        continue

    label_center = y + h / 2
    candidates = []

    for j, (vx, vy, vw, vh, value_text) in enumerate(recognized):
        value = value_text.strip()

        if j == i or j in paired_values:
            continue

        if not number_re.fullmatch(value):
            continue

        if vx <= x:
            continue

        gap = vx - (x + w)
        if gap < 0 or gap > max_gap:
            continue

        center_diff = abs((vy + vh / 2) - label_center)

        if center_diff <= 8:
            candidates.append((center_diff, gap, j, value))

    if candidates:
        _, _, j, value = min(candidates)
        pairs[i] = j
        paired_values.add(j)

print("Итоговые строки:")

for i, (x, y, w, h, text) in enumerate(recognized):
    if i in paired_values:
        continue

    label = text.strip()

    if not label:
        continue

    if i in pairs:
        value = recognized[pairs[i]][4].strip()
        print(f"  {label} {value!s}")
    else:
        print(f"  {label}")

# 7. Сохраняем изображение с найденными областями
cv2.imwrite(OUTPUT_PATH, preview)

print("\n=== ИТОГ ===")
print("Распознано областей:", len(lines))
print("Изображение:", OUTPUT_PATH)

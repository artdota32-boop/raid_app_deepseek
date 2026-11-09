import os
import shutil
import numpy as np
import onnxruntime as ort

from PIL import Image, ImageOps, ImageDraw


# ============================================================
# НАСТРОЙКИ
# ============================================================

SOURCE = "screenshots/outputs/speed_ru_card_crop.png"
MODEL = "assets/inference.onnx"
DICT = "assets/dict.txt"

OUT_DIR = "screenshots/outputs/trainer"
DOWNLOAD_DIR = "/sdcard/Download/RAID_RESULTS"

IMG_HEIGHT = 48
IMG_MAX_WIDTH = 320
VOCAB_SIZE = 852
BLANK_IDX = 0

# Цветовые пороги для предварительного поиска текста
WHITE_THRESHOLD = 10
ORANGE_THRESHOLD = 20

# Минимальная высота найденной области
MIN_LINE_HEIGHT = 5

os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(DOWNLOAD_DIR, exist_ok=True)


# ============================================================
# ЗАГРУЗКА ONNX И СЛОВАРЯ
# ============================================================

print("[INIT] Loading ONNX model...")

session = ort.InferenceSession(
    MODEL,
    providers=["CPUExecutionProvider"]
)

input_name = session.get_inputs()[0].name
output_name = session.get_outputs()[0].name

print("[MODEL] Input:", input_name)
print("[MODEL] Output:", output_name)

with open(DICT, encoding="utf-8") as f:
    dictionary = [line.strip() for line in f if line.strip()]

print("[DICT] Entries:", len(dictionary))

if len(dictionary) != 850:
    raise RuntimeError(
        f"Expected 850 dictionary entries, got {len(dictionary)}"
    )


# ============================================================
# ПРЕДОБРАБОТКА — ПО ЛОГИКЕ DART OnnxOcr
# ============================================================

def preprocess(image):
    # Инверсия RGB
    image = ImageOps.invert(image.convert("RGB"))

    width, height = image.size

    ratio = width / height
    target_width = round(IMG_HEIGHT * ratio)
    target_width = max(1, min(IMG_MAX_WIDTH, target_width))

    # Предварительно используем nearest:
    # это соответствует стандартному варианту copyResize
    # в распространённых версиях Dart image package.
    resized = image.resize(
        (target_width, IMG_HEIGHT),
        Image.Resampling.NEAREST
    )

    padded = Image.new(
        "RGB",
        (IMG_MAX_WIDTH, IMG_HEIGHT),
        (255, 255, 255)
    )

    padded.paste(resized, (0, 0))

    # RGB -> BGR, затем нормализация
    arr = np.asarray(padded, dtype=np.float32)[:, :, ::-1]

    arr = np.transpose(arr, (2, 0, 1))
    arr = np.expand_dims(arr, axis=0)

    arr = (arr / 255.0 - 0.5) / 0.5

    return arr.astype(np.float32)


# ============================================================
# CTC DECODER
# ============================================================

def recognize(image):
    tensor = preprocess(image)

    output = session.run(
        [output_name],
        {input_name: tensor}
    )[0]

    # Ожидаем [1, T, 852]
    if output.ndim != 3 or output.shape[0] != 1:
        raise RuntimeError(
            f"Unexpected output shape: {output.shape}"
        )

    predictions = np.argmax(output[0], axis=1)
    probabilities = np.max(output[0], axis=1)

    result = []
    confidence_values = []

    last_idx = -1

    for t, idx in enumerate(predictions):
        idx = int(idx)

        if idx != BLANK_IDX and idx != last_idx:
            dict_idx = idx - 1

            if 0 <= dict_idx < len(dictionary):
                result.append(dictionary[dict_idx])
                confidence_values.append(
                    float(probabilities[t])
                )

        last_idx = idx

    text = "".join(result)

    confidence = (
        sum(confidence_values) / len(confidence_values)
        if confidence_values else 0.0
    )

    return text, confidence


# ============================================================
# ПОИСК ТЕКСТОВЫХ ОБЛАСТЕЙ
# ============================================================

def detect_lines(image):
    rgb = np.asarray(image.convert("RGB")).astype(np.int16)

    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]

    max_rgb = np.maximum(np.maximum(r, g), b)
    min_rgb = np.minimum(np.minimum(r, g), b)

    white = (
        (r > 175) &
        (g > 175) &
        (b > 165) &
        ((max_rgb - min_rgb) < 65)
    )

    orange = (
        (r > 155) &
        (g > 75) &
        (r > g * 1.15) &
        (g > b * 1.15) &
        (b < 190)
    )

    # Ищем белые и оранжевые строки раздельно.
    # Это позволяет не объединять разные цвета в одну область.
    profiles = [
        ("white", np.sum(white, axis=1), white, WHITE_THRESHOLD),
        ("orange", np.sum(orange, axis=1), orange, ORANGE_THRESHOLD),
    ]

    detected = []

    for color_name, profile, mask, threshold in profiles:
        active = profile >= threshold

        start = None

        for y in range(len(active) + 1):
            is_active = y < len(active) and active[y]

            if is_active and start is None:
                start = y

            elif not is_active and start is not None:
                end = y - 1

                if end - start + 1 >= MIN_LINE_HEIGHT:
                    region = mask[start:end + 1, :]

                    ys, xs = np.where(region)

                    if len(xs) > 0:
                        x1 = int(xs.min())
                        x2 = int(xs.max()) + 1

                        detected.append({
                            "color": color_name,
                            "x1": x1,
                            "y1": start,
                            "x2": x2,
                            "y2": end + 1,
                        })

                start = None

    # Сортировка сверху вниз
    detected.sort(key=lambda item: (item["y1"], item["x1"]))

    return detected


# ============================================================
# ЗАПУСК
# ============================================================

print("\n[IMAGE] Loading:", SOURCE)

if not os.path.isfile(SOURCE):
    raise FileNotFoundError(SOURCE)

source = Image.open(SOURCE).convert("RGB")

print("[IMAGE] Size:", source.size)

lines = detect_lines(source)
lines = [line for line in lines if line['y1'] < 330]

# Дополнительные области, проверенные отдельным ONNX-тестом.
# Добавляем только если такая область ещё не обнаружена.
extra_lines = [
    {
        "color": "white",
        "x1": 0, "y1": 180,
        "x2": source.width, "y2": 200,
    },
    {
        "color": "white",
        "x1": 0, "y1": 280,
        "x2": source.width, "y2": 305,
    },
]

for extra in extra_lines:
    duplicate = any(
        line["color"] == extra["color"]
        and abs(line["y1"] - extra["y1"]) <= 3
        and abs(line["y2"] - extra["y2"]) <= 3
        for line in lines
    )
    if not duplicate:
        lines.append(extra)

lines.sort(key=lambda item: (item["y1"], item["x1"]))

print("\n[DETECT] Found areas:", len(lines))

debug = source.copy()
draw = ImageDraw.Draw(debug)

results = []

for i, line in enumerate(lines, start=1):
    x1 = line["x1"]
    y1 = line["y1"]
    x2 = line["x2"]
    y2 = line["y2"]

    # Небольшой запас вокруг найденной области
    pad_x = 4
    pad_y = 3

    left = max(0, x1 - pad_x)
    top = max(0, y1 - pad_y)
    right = min(source.width, x2 + pad_x)
    bottom = min(source.height, y2 + pad_y)

    crop = source.crop((left, top, right, bottom))

    filename = f"line_{i:02d}_{line['color']}.png"
    crop_path = os.path.join(OUT_DIR, filename)

    crop.save(crop_path)

    text, confidence = recognize(crop)

    results.append({
        "number": i,
        "color": line["color"],
        "coordinates": (left, top, right, bottom),
        "text": text,
        "confidence": confidence,
        "file": filename,
    })

    draw.rectangle(
        (left, top, right - 1, bottom - 1),
        outline="red" if line["color"] == "white" else "orange",
        width=2
    )

    draw.text(
        (left, max(0, top - 12)),
        str(i),
        fill="lime"
    )

    print(
        f"[OCR {i:02d}] "
        f"{line['color']} "
        f"box=({left},{top},{right},{bottom}) "
        f"confidence={confidence:.3f} "
        f"text={text!r}"
    )


# ============================================================
# СОХРАНЕНИЕ РЕЗУЛЬТАТОВ
# ============================================================

debug_path = os.path.join(OUT_DIR, "detected_overlay.png")
debug.save(debug_path)

report_path = os.path.join(OUT_DIR, "results.txt")

with open(report_path, "w", encoding="utf-8") as f:
    f.write(f"Source: {SOURCE}\n")
    f.write(f"Image size: {source.size}\n")
    f.write(f"Detected areas: {len(results)}\n\n")

    for item in results:
        f.write(
            f"[{item['number']:02d}] "
            f"{item['color']} "
            f"box={item['coordinates']} "
            f"confidence={item['confidence']:.3f}\n"
        )
        f.write(f"Text: {item['text']}\n")
        f.write(f"Image: {item['file']}\n\n")


# ============================================================
# КОПИРОВАНИЕ В DOWNLOAD
# ============================================================

for filename in os.listdir(OUT_DIR):
    source_path = os.path.join(OUT_DIR, filename)

    if os.path.isfile(source_path):
        shutil.copy2(
            source_path,
            os.path.join(DOWNLOAD_DIR, filename)
        )

print("\n[DONE] Trainer finished.")
print("[OUTPUT]", OUT_DIR)
print("[DOWNLOAD]", DOWNLOAD_DIR)


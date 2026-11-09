import os
import numpy as np
from PIL import Image, ImageDraw, ImageOps
import onnxruntime as ort

SOURCE = "screenshots/outputs/speed_ru_frame.png"
MODEL = "assets/inference.onnx"
DICT = "assets/dict.txt"

IMG_HEIGHT = 48
IMG_MAX_WIDTH = 320
BLANK_IDX = 0

X1, Y1, X2, Y2 = 80, 364, 449, 718

print("[INIT] Loading ONNX model...")
session = ort.InferenceSession(MODEL, providers=["CPUExecutionProvider"])
input_name = session.get_inputs()[0].name
output_name = session.get_outputs()[0].name

with open(DICT, encoding="utf-8") as f:
    dictionary = [line.strip() for line in f if line.strip()]

def preprocess(image):
    image = ImageOps.invert(image.convert("RGB"))
    width, height = image.size
    ratio = width / height
    target_width = round(IMG_HEIGHT * ratio)
    target_width = max(1, min(IMG_MAX_WIDTH, target_width))
    resized = image.resize((target_width, IMG_HEIGHT), Image.Resampling.NEAREST)
    padded = Image.new("RGB", (IMG_MAX_WIDTH, IMG_HEIGHT), (255, 255, 255))
    padded.paste(resized, (0, 0))
    arr = np.asarray(padded, dtype=np.float32)[:, :, ::-1]
    arr = np.transpose(arr, (2, 0, 1))
    arr = np.expand_dims(arr, axis=0)
    arr = (arr / 255.0 - 0.5) / 0.5
    return arr.astype(np.float32)

def recognize(image):
    tensor = preprocess(image)
    output = session.run([output_name], {input_name: tensor})[0]
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
                confidence_values.append(float(probabilities[t]))
        last_idx = idx
    text = "".join(result)
    confidence = sum(confidence_values) / len(confidence_values) if confidence_values else 0.0
    return text, confidence

def detect_rows(mask, y_start, y_end, x_start, x_end, zone_name, merge_gap=3):
    zone = mask[y_start:y_end, x_start:x_end]
    zone_width = x_end - x_start
    profile = np.sum(zone, axis=1)
    active = profile >= max(3, int(zone_width * 0.01))
    bands = []
    start = None
    for y in range(len(active)):
        if active[y] and start is None: start = y
        elif not active[y] and start is not None:
            bands.append([start, y - 1])
            start = None
    if start is not None: bands.append([start, len(active) - 1])
    merged = []
    for band in bands:
        if merged and band[0] - merged[-1][1] - 1 <= merge_gap: merged[-1][1] = band[1]
        else: merged.append(band)
    rows = []
    for y1, y2 in merged:
        part = zone[y1:y2 + 1, :]
        ys, xs = np.where(part)
        if len(xs) == 0: continue
        rows.append({
            "zone": zone_name,
            "x1": int(x_start + xs.min()),
            "y1": int(y_start + y1),
            "x2": int(x_start + xs.max()) + 1,
            "y2": int(y_start + y2 + 1)
        })
    return rows

print("[TEST] Loading:", SOURCE)
img = Image.open(SOURCE).convert("RGB")
card = img.crop((X1, Y1, X2, Y2))
rgb = np.asarray(card).astype(np.int16)
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
height, width = r.shape

white = ((r > 175) & (g > 175) & (b > 165) & ((np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)) < 65))
orange = ((r > 155) & (g > 75) & (r > g * 1.15) & (g > b * 1.15) & (b < 190))
cyan = ((r < 150) & (g > 110) & (b > 140) & (g > r * 1.25) & (b > r * 1.25))

zones = [
    ("HEADER", 0.00, 0.08),
    ("ITEM_INFO", 0.08, 0.24),
    ("STATS", 0.23, 0.52),
    ("SET_BONUS", 0.71, 0.82),
]

all_rows = []
for name, start_ratio, end_ratio in zones:
    y1 = int(height * start_ratio)
    y2 = int(height * end_ratio)
    x1 = 0
    x2 = width
    zone_mask = cyan if name == "SET_BONUS" else white | orange
    rows = detect_rows(zone_mask, y1, y2, x1, x2, name)
    all_rows.extend(rows)
    print(f"[ZONE {name}] Found: {len(rows)}")

print("\n[OCR RESULTS]")
final_text = []
for i, row in enumerate(all_rows):
    crop = card.crop((row["x1"], row["y1"], row["x2"], row["y2"]))
    text, conf = recognize(crop)
    print(f"[{i+1}] {row['zone']} | conf={conf:.2f} | text={text!r}")
    if text.strip():
        final_text.append(text.strip())

print("\n=== FINAL TEXT ===")
print(" ".join(final_text))

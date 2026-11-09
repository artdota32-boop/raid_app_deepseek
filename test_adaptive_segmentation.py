import ast
import numpy as np
from PIL import Image, ImageDraw

SOURCE = "/sdcard/Download/raid_dataset/android_crop.jpg"
OUTPUT = "screenshots/outputs/adaptive_test"

WHITE_THRESHOLD = 10
ORANGE_THRESHOLD = 20
MIN_LINE_HEIGHT = 5

# Загружаем только исходную функцию detect_lines(),
# не запуская остальной код trainer_ocr.py.
with open("trainer_ocr.py", "r", encoding="utf-8") as f:
    tree = ast.parse(f.read())

function_node = next(
    node for node in tree.body
    if isinstance(node, ast.FunctionDef)
    and node.name == "detect_lines"
)

namespace = {
    "np": np,
    "WHITE_THRESHOLD": WHITE_THRESHOLD,
    "ORANGE_THRESHOLD": ORANGE_THRESHOLD,
    "MIN_LINE_HEIGHT": MIN_LINE_HEIGHT,
}

exec(compile(
    ast.Module(body=[function_node], type_ignores=[]),
    "trainer_ocr.py",
    "exec"
), namespace)

detect_lines = namespace["detect_lines"]

image = Image.open(SOURCE).convert("RGB")
lines = detect_lines(image)

print(f"\n[IMAGE] Размер: {image.size}")
print(f"[DETECT] Найдено областей: {len(lines)}\n")

debug = image.copy()
draw = ImageDraw.Draw(debug)

for i, line in enumerate(lines, 1):
    box = (
        line["x1"], line["y1"],
        line["x2"], line["y2"]
    )
    color = "red" if line["color"] == "white" else "orange"
    draw.rectangle(box, outline=color, width=2)
    draw.text((line["x1"], max(0, line["y1"] - 12)), str(i), fill="lime")

    print(
        f"[{i:02d}] {line['color']}: "
        f"x={line['x1']} y={line['y1']} "
        f"x2={line['x2']} y2={line['y2']}"
    )

import os
os.makedirs(OUTPUT, exist_ok=True)

debug.save(f"{OUTPUT}/detected_overlay.png")

with open(f"{OUTPUT}/results.txt", "w", encoding="utf-8") as f:
    f.write(f"Image size: {image.size}\n")
    f.write(f"Detected areas: {len(lines)}\n\n")
    for i, line in enumerate(lines, 1):
        f.write(f"[{i:02d}] {line}\n")

print(f"\n[OK] Рамки: {OUTPUT}/detected_overlay.png")
print(f"[OK] Отчёт: {OUTPUT}/results.txt")

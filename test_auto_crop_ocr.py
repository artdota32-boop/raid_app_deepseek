import os
import numpy as np
from PIL import Image, ImageDraw

SOURCE = "screenshots/outputs/speed_ru_frame.png"
OUT_DIR = "/sdcard/Download/RAID_RESULTS"

os.makedirs(OUT_DIR, exist_ok=True)

print("[TEST] Loading:", SOURCE)
img = Image.open(SOURCE).convert("RGB")

# Временные координаты Area 1 из предыдущего теста.
# Автоматический поиск Union-Find подключим после проверки crop.
x1, y1, x2, y2 = 80, 364, 449, 718

card = img.crop((x1, y1, x2, y2))
card.save(os.path.join(OUT_DIR, "auto_cropped_card.png"))

rgb = np.asarray(card).astype(np.int16)
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

white = (
    (r > 175) & (g > 175) & (b > 165) &
    ((np.maximum(np.maximum(r, g), b) -
      np.minimum(np.minimum(r, g), b)) < 65)
)

orange = (
    (r > 155) & (g > 75) &
    (r > g * 1.15) & (g > b * 1.15) & (b < 190)
)

def find_lines(mask, color_name):
    profile = np.sum(mask, axis=1)
    active = profile > 10
    lines = []
    start = None

    for y in range(len(active) + 1):
        current = y < len(active) and active[y]

        if current and start is None:
            start = y
        elif not current and start is not None:
            end = y - 1

            if end - start + 1 >= 5:
                ys, xs = np.where(mask[start:end + 1, :])

                if len(xs):
                    lines.append({
                        "color": color_name,
                        "x1": int(xs.min()),
                        "y1": int(start),
                        "x2": int(xs.max()) + 1,
                        "y2": int(end + 1)
                    })
            start = None

    return lines

lines = find_lines(white, "white") + find_lines(orange, "orange")
lines.sort(key=lambda item: item["y1"])

debug = card.copy()
draw = ImageDraw.Draw(debug)

print(f"[LINES] Found: {len(lines)}")

for i, line in enumerate(lines):
    color = "red" if line["color"] == "white" else "orange"
    draw.rectangle(
        (line["x1"], line["y1"], line["x2"], line["y2"]),
        outline=color,
        width=2
    )
    draw.text((line["x1"], max(0, line["y1"] - 12)),
              str(i + 1), fill="lime")
    print(f"[LINE {i + 1}] {line}")

debug.save(os.path.join(OUT_DIR, "auto_detected_lines.png"))

print("[DONE]")
print("[SAVED] auto_cropped_card.png")
print("[SAVED] auto_detected_lines.png")

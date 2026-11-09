import os
import numpy as np
from PIL import Image, ImageDraw

SOURCE = "screenshots/outputs/speed_ru_frame.png"
OUT_DIR = "/sdcard/Download/RAID_RESULTS"

os.makedirs(OUT_DIR, exist_ok=True)

print("[TEST] Loading:", SOURCE)
img = Image.open(SOURCE).convert("RGB")

# Временные координаты карточки из предыдущего теста
card = img.crop((80, 364, 449, 718))
card.save(os.path.join(OUT_DIR, "zoned_card.png"))

rgb = np.asarray(card).astype(np.int16)
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
height, width = r.shape

white = (
    (r > 175) & (g > 175) & (b > 165) &
    ((np.maximum(np.maximum(r, g), b) -
      np.minimum(np.minimum(r, g), b)) < 65)
)

orange = (
    (r > 155) & (g > 75) &
    (r > g * 1.15) & (g > b * 1.15) & (b < 190)
)

cyan = (
    (r < 150) & (g > 110) & (b > 140) &
    (g > r * 1.25) & (b > r * 1.25)
)

def detect_rows(mask, y_start, y_end, zone_name,
                merge_gap=3, x_start=0, x_end=None):
    if x_end is None:
        x_end = width

    zone = mask[y_start:y_end, x_start:x_end]
    zone_width = x_end - x_start
    profile = np.sum(zone, axis=1)
    active = profile >= max(3, int(zone_width * 0.01))

    bands = []
    start = None

    for y in range(len(active)):
        if active[y] and start is None:
            start = y
        elif not active[y] and start is not None:
            bands.append([start, y - 1])
            start = None

    if start is not None:
        bands.append([start, len(active) - 1])

    merged = []

    for band in bands:
        if merged and band[0] - merged[-1][1] - 1 <= merge_gap:
            merged[-1][1] = band[1]
        else:
            merged.append(band)

    rows = []

    for y1, y2 in merged:
        part = zone[y1:y2 + 1, :]
        ys, xs = np.where(part)

        if len(xs) == 0:
            continue

        rows.append({
            "zone": zone_name,
            "x1": int(x_start + xs.min()),
            "y1": int(y_start + y1),
            "x2": int(x_start + xs.max()) + 1,
            "y2": int(y_start + y2 + 1)
        })

    return rows

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

    zone_mask = cyan if name == "SET_BONUS" else white | orange

    x1 = 0
    x2 = width
    rows = detect_rows(
        zone_mask, y1, y2, name,
        x_start=x1, x_end=x2
    )
    all_rows.extend(rows)

    print(f"[ZONE {name}] Found: {len(rows)}")

debug = card.copy()
draw = ImageDraw.Draw(debug)

colors = {
    "HEADER": "red",
    "ITEM_INFO": "orange",
    "STATS": "lime",
    "SET_BONUS": "cyan",
}

for i, row in enumerate(all_rows):
    draw.rectangle(
        (row["x1"], row["y1"], row["x2"], row["y2"]),
        outline=colors[row["zone"]],
        width=2
    )

    draw.text(
        (row["x1"], max(0, row["y1"] - 12)),
        f"{row['zone']} {i + 1}",
        fill="yellow"
    )

    print(f"[ROW {i + 1}] {row}")

debug.save(os.path.join(OUT_DIR, "zoned_lines_overlay.png"))

print("[DONE]")
print("[SAVED] zoned_card.png")
print("[SAVED] zoned_lines_overlay.png")

import numpy as np
from PIL import Image, ImageDraw
import os

SOURCE = "screenshots/outputs/speed_ru_frame.png"
OUT_PATH = "/sdcard/Download/RAID_RESULTS/card_detection_test.png"

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

print("[TEST] Loading:", SOURCE)

img = Image.open(SOURCE).convert("RGB")
w, h = img.size
print(f"[IMAGE] Size: {w}x{h}")

rgb = np.asarray(img).astype(np.int16)
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]

mask = (r < 60) & (g < 90) & (b > 90) & (b > r + 40) & (b > g + 20)
ys, xs = np.where(mask)

if len(xs) == 0:
    print("[FAIL] Blue panel not found!")
else:
    x1, x2 = int(xs.min()), int(xs.max()) + 1
    y1, y2 = int(ys.min()), int(ys.max()) + 1

    print(f"[DETECT] x1={x1}, y1={y1}, x2={x2}, y2={y2}")
    print(f"[SIZE] {x2-x1}x{y2-y1}")

    debug = img.copy()
    draw = ImageDraw.Draw(debug)
    draw.rectangle((x1, y1, x2-1, y2-1), outline="red", width=4)
    debug.save(OUT_PATH)

    card = rgb[y1:y2, x1:x2]
    cr, cg, cb = card[:,:,0], card[:,:,1], card[:,:,2]
    white = ((cr > 175) & (cg > 175) & (cb > 165)).sum()

    print("[WHITE PIXELS]", int(white))
    print("[RESULT]", "TEXT CANDIDATE" if white > 100 else "CHECK PANEL")
    print("[SAVED]", OUT_PATH)

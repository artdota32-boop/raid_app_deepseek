from PIL import Image, ImageChops
from pathlib import Path

raw_path = Path("screenshots/outputs/polygon_raw_crop.png")
ref_path = Path("screenshots/outputs/speed_ru_card_crop.png")

if not raw_path.exists() or not ref_path.exists():
    raise SystemExit("ERROR: raw crop or reference image missing")

raw = Image.open(raw_path).convert("RGB")
ref = Image.open(ref_path).convert("RGB")

print("===== POLYGON TEXT REPORT =====")
print("RAW SIZE:", raw.size)
print("REFERENCE SIZE:", ref.size)

# Known coordinate offset:
# raw detector: x=76, y=363
# reference:    x=50, y=352
dx = 26
dy = 11

common_w = min(raw.width, ref.width - dx)
common_h = min(raw.height, ref.height - dy)

if common_w <= 0 or common_h <= 0:
    raise SystemExit("ERROR: reference overlap is invalid")

a = raw.crop((0, 0, common_w, common_h))
b = ref.crop((dx, dy, dx + common_w, dy + common_h))

diff = ImageChops.difference(a, b)
pixels = list(diff.getdata())
total = len(pixels)

exact = sum(1 for p in pixels if p == (0, 0, 0))
max_errors = [max(p) for p in pixels]

mae = sum(sum(p) for p in pixels) / (total * 3)
max_error = max(max_errors)
p95 = sorted(max_errors)[int((total - 1) * 0.95)]

print("\n===== REFERENCE COMPARISON =====")
print("OVERLAP SIZE:", (common_w, common_h))
print("EXACT MATCH:", round(100 * exact / total, 3), "%")
print("MAE:", round(mae, 4))
print("P95 MAX CHANNEL ERROR:", p95)
print("MAX CHANNEL ERROR:", max_error)

print("\n===== IMAGE ASCII PREVIEW =====")

preview_w = 74
preview_h = max(
    1,
    round(preview_w * 0.5 * raw.height / raw.width)
)

small = raw.resize(
    (preview_w, preview_h),
    Image.Resampling.BOX
).convert("L")

chars = " .:-=+*#%@"

for y in range(small.height):
    line = ""
    for x in range(small.width):
        value = small.getpixel((x, y))
        index = value * (len(chars) - 1) // 256
        line += chars[index]
    print(line)

print("\n===== EDGE CHECK =====")

def cyan(r, g, b):
    return (
        g > 100 and b > 120
        and g > r * 1.35
        and b > r * 1.35
        and abs(g - b) < 100
    )

for y in range(raw.height - 10, raw.height):
    count = sum(
        1 for x in range(raw.width)
        if cyan(*raw.getpixel((x, y)))
    )
    print(f"ROW {y}: CYAN PIXELS={count}")

print("\n===== END REPORT =====")

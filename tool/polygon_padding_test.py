from PIL import Image, ImageChops
from pathlib import Path
import json

report_path = Path("screenshots/outputs/polygon_diagnostics.json")
reference_path = Path("screenshots/outputs/speed_ru_card_crop.png")
output_path = Path("screenshots/outputs/polygon_padded_crop.png")
diff_path = Path("screenshots/outputs/polygon_full_diff.png")

if not report_path.exists():
    raise SystemExit("ERROR: polygon diagnostics JSON missing")

if not reference_path.exists():
    raise SystemExit("ERROR: reference image missing")

report = json.loads(report_path.read_text())

bbox = report["bbox"]

source_path = Path(report["source"])

if not source_path.exists():
    raise SystemExit(f"ERROR: source image missing: {source_path}")

source = Image.open(source_path).convert("RGB")
reference = Image.open(reference_path).convert("RGB")

raw_left = bbox["left"]
raw_top = bbox["top"]
raw_right = raw_left + bbox["width"]
raw_bottom = raw_top + bbox["height"]

# Experimental padding
pad_left = 26
pad_right = 72
pad_top = 11
pad_bottom = -10

final_left = max(0, raw_left - pad_left)
final_top = max(0, raw_top - pad_top)
final_right = min(source.width, raw_right + pad_right)
final_bottom = min(source.height, raw_bottom + pad_bottom)

print("===== POLYGON PADDING TEST =====")
print("SOURCE:", source.size)

print("\nRAW BBOX:")
print(f"x={raw_left}, y={raw_top}")
print(f"right={raw_right}, bottom={raw_bottom}")

print("\nPADDING:")
print("LEFT:", pad_left)
print("RIGHT:", pad_right)
print("TOP:", pad_top)
print("BOTTOM:", pad_bottom)

print("\nFINAL BBOX:")
print(f"x={final_left}, y={final_top}")
print(f"right={final_right}, bottom={final_bottom}")

crop = source.crop((
    final_left,
    final_top,
    final_right,
    final_bottom
))

crop.save(output_path)

print("\nFINAL CROP:", crop.size)
print("SAVED:", output_path)
print("REFERENCE:", reference.size)

if crop.size != reference.size:
    print("\nERROR: image dimensions differ; comparison stopped")
    raise SystemExit(2)

diff = ImageChops.difference(crop, reference)
pixels = list(diff.getdata())

total = len(pixels)
exact = sum(1 for p in pixels if p == (0, 0, 0))
errors = [max(p) for p in pixels]

mae = sum(sum(p) for p in pixels) / (total * 3)
p95 = sorted(errors)[int((total - 1) * 0.95)]
max_error = max(errors)

diff.save(diff_path)

print("\n===== FULL IMAGE COMPARISON =====")
print("TOTAL PIXELS:", total)
print("EXACT PIXELS:", exact)
print("DIFFERENT PIXELS:", total - exact)
print("EXACT MATCH:", round(exact / total * 100, 4), "%")
print("MAE:", round(mae, 6))
print("P95 MAX CHANNEL ERROR:", p95)
print("MAX CHANNEL ERROR:", max_error)
print("DIFFERENCE BBOX:", diff.getbbox())
print("DIFF IMAGE:", diff_path)

print("\n===== CONCLUSION =====")

if exact == total:
    print("FULL PIXEL MATCH: YES")
else:
    print("FULL PIXEL MATCH: NO")
    print("Inspect difference metrics before changing detector.")

print("===== END REPORT =====")

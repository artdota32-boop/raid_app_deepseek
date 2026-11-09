from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
import test_det_vs_morph as d

BASE = Path("experiments/card_localization")
IMAGE_PATH = BASE / "dbnet_samples_v1/card_001_t0p6s.jpg"
OLD_MODEL = BASE / "det_inference.onnx"
NEW_MODEL = BASE / "ppocrv6_small_det.onnx"
OUT_DIR = BASE / "dbnet_samples_v1_results"
OUT_FILE = OUT_DIR / "ppocrv6_vs_dbnet_t0p6s.jpg"

def detect(model_path, thresh, box_thresh, unclip, max_candidates):
    d.THRESH = thresh
    d.BOX_THRESH = box_thresh
    d.UNCLIP_RATIO = unclip
    d.MAX_CANDIDATES = max_candidates

    session = ort.InferenceSession(
        str(model_path),
        providers=["CPUExecutionProvider"]
    )
    input_info = session.get_inputs()[0]
    output_info = session.get_outputs()[0]

    result = session.run(
        [output_info.name],
        {input_info.name: tensor}
    )[0]

    boxes = d.dbnet_postprocess(result, height, width)
    return boxes, result

image = cv2.imread(str(IMAGE_PATH))
if image is None:
    raise SystemExit(f"Image not found: {IMAGE_PATH}")

height, width = image.shape[:2]
tensor, resized_h, resized_w = d.dbnet_preprocess(image)

print("IMAGE:", width, "x", height)
print("INPUT TENSOR:", tensor.shape)
print("RESIZED:", resized_w, "x", resized_h)

old_boxes, old_map = detect(
    OLD_MODEL, 0.3, 0.6, 1.5, 1000
)
print("\nDBNet regions:", len(old_boxes))
print("DBNet output:", old_map.shape)

new_boxes, new_map = detect(
    NEW_MODEL, 0.2, 0.45, 1.4, 3000
)
print("\nPP-OCRv6 regions:", len(new_boxes))
print("PP-OCRv6 output:", new_map.shape)

left = image.copy()
right = image.copy()

for i, box in enumerate(old_boxes, 1):
    points = box.reshape(-1, 1, 2)
    cv2.polylines(left, [points], True, (0, 255, 0), 2)
    x, y = box[0]
    cv2.putText(left, str(i), (int(x), max(15, int(y))),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 180, 0), 1)

for i, box in enumerate(new_boxes, 1):
    points = box.reshape(-1, 1, 2)
    cv2.polylines(right, [points], True, (255, 0, 0), 2)
    x, y = box[0]
    cv2.putText(right, str(i), (int(x), max(15, int(y))),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 0, 0), 1)

header = 38
canvas = np.full(
    (height + header, width * 2, 3), 255, dtype=np.uint8
)
canvas[header:, :width] = left
canvas[header:, width:] = right

cv2.putText(canvas, f"DBNet: {len(old_boxes)} regions",
            (8, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.65,
            (0, 130, 0), 2)
cv2.putText(canvas, f"PP-OCRv6: {len(new_boxes)} regions",
            (width + 8, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.65,
            (180, 0, 0), 2)

OUT_DIR.mkdir(parents=True, exist_ok=True)
if not cv2.imwrite(str(OUT_FILE), canvas):
    raise SystemExit("Failed to save comparison image")

print("\nCOMPARISON IMAGE:", OUT_FILE)
print("TEST: OK")

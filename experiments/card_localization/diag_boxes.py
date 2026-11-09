import sys
from pathlib import Path
import cv2

BASE = Path("experiments/card_localization").resolve()
sys.path.insert(0, str(BASE))

import test_dbnet_on_samples as test

image_path = BASE / "dbnet_samples_v1/card_001_t0p6s.jpg"
image = cv2.imread(str(image_path))

if image is None:
    raise SystemExit("ОШИБКА: образец не найден")

session = test.ort.InferenceSession(
    str(test.detector.MODEL_PATH),
    providers=["CPUExecutionProvider"]
)

h, w = image.shape[:2]
tensor, _, _ = test.detector.dbnet_preprocess(image)

outputs = session.run(
    None,
    {session.get_inputs()[0].name: tensor}
)

boxes = test.detector.dbnet_postprocess(outputs[0], h, w)

print("=== КООРДИНАТЫ ОБЛАСТЕЙ DBNET ===")
print("Количество:", len(boxes))

for i, box in enumerate(boxes, 1):
    points = box.reshape(-1, 2)
    x1, y1 = points.min(axis=0)
    x2, y2 = points.max(axis=0)
    print(f"{i:02d}: x={x1:.1f}, y={y1:.1f}, w={x2-x1:.1f}, h={y2-y1:.1f}")

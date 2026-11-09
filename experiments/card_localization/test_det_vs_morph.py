from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
import pyclipper
import math

# ============================================================
# CONFIG
# ============================================================

BASE = Path("experiments/card_localization")

IMAGE_PATH = BASE / "card_crop.jpg"
MODEL_PATH = BASE / "det_inference.onnx"

OUT_MORPH = BASE / "morphology_result.jpg"
OUT_DBNET = BASE / "dbnet_result.jpg"
OUT_COMPARE = BASE / "det_vs_morph.jpg"

LIMIT_SIDE_LEN = 960
LIMIT_TYPE = "max"
MAX_SIDE_LIMIT = 4000

THRESH = 0.3
BOX_THRESH = 0.6
UNCLIP_RATIO = 1.5

# Остальные параметры постпроцессора.
MAX_CANDIDATES = 1000
USE_DILATION = False
SCORE_MODE = "fast"
BOX_TYPE = "quad"
IMG_MODE = "BGR"

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# ============================================================
# UTILS
# ============================================================

def round_half_to_even(value):
    """Повторяет MathUtils.roundHalfToEven() из Kotlin."""
    floored = math.floor(value)
    diff = value - floored

    if diff < 0.5:
        return int(floored)
    if diff > 0.5:
        return int(floored + 1)

    return int(floored if floored % 2 == 0 else floored + 1)

def order_min_area_rect_points(points):
    """Повторяет QuadGeometry.orderMinAreaRectPoints()."""
    points = sorted(points, key=lambda p: p[0])

    if points[1][1] > points[0][1]:
        top_left, bottom_left = points[0], points[1]
    else:
        top_left, bottom_left = points[1], points[0]

    if points[3][1] > points[2][1]:
        top_right, bottom_right = points[2], points[3]
    else:
        top_right, bottom_right = points[3], points[2]

    return np.array(
        [top_left, top_right, bottom_right, bottom_left],
        dtype=np.float32
    )

def polygon_score(prob_map, points):
    """Средняя вероятность внутри маски многоугольника."""
    h, w = prob_map.shape
    mask = np.zeros((h, w), dtype=np.uint8)

    pts = np.round(points).astype(np.int32)
    cv2.fillPoly(mask, [pts], 1)

    selected = prob_map[mask > 0]
    if selected.size == 0:
        return 0.0

    return float(selected.mean())

# ============================================================
# DBNET PREPROCESS
# ============================================================

def dbnet_preprocess(image):
    h, w = image.shape[:2]

    if LIMIT_TYPE == "max":
        ratio = (
            LIMIT_SIDE_LEN / max(h, w)
            if max(h, w) > LIMIT_SIDE_LEN else 1.0
        )
    elif LIMIT_TYPE == "min":
        ratio = (
            LIMIT_SIDE_LEN / min(h, w)
            if min(h, w) < LIMIT_SIDE_LEN else 1.0
        )
    elif LIMIT_TYPE == "resize_long":
        ratio = LIMIT_SIDE_LEN / max(h, w)
    else:
        raise ValueError(f"Unsupported limit type: {LIMIT_TYPE}")

    new_h = int(h * ratio)
    new_w = int(w * ratio)

    if max(new_h, new_w) > MAX_SIDE_LIMIT:
        ratio2 = MAX_SIDE_LIMIT / max(new_h, new_w)
        new_h = int(new_h * ratio2)
        new_w = int(new_w * ratio2)

    new_h = max(round_half_to_even(new_h / 32.0) * 32, 32)
    new_w = max(round_half_to_even(new_w / 32.0) * 32, 32)

    if IMG_MODE.upper() == "RGB":
        source = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    else:
        source = image

    resized = cv2.resize(
        source,
        (new_w, new_h),
        interpolation=cv2.INTER_LINEAR
    )

    normalized = resized.astype(np.float32) / 255.0
    normalized = (normalized - MEAN) / STD

    tensor = normalized.transpose(2, 0, 1)[None, ...].astype(np.float32)

    return tensor, new_h, new_w

# ============================================================
# DBNET POSTPROCESS
# ============================================================

def dbnet_postprocess(pred, original_h, original_w):
    if pred.ndim != 4 or pred.shape[0] != 1 or pred.shape[1] != 1:
        raise RuntimeError(f"Unexpected DBNet output shape: {pred.shape}")

    prob_map = pred[0, 0].astype(np.float32)
    pred_h, pred_w = prob_map.shape

    scale_x = original_w / pred_w
    scale_y = original_h / pred_h

    bitmap = (prob_map > THRESH).astype(np.uint8) * 255

    if USE_DILATION:
        kernel = np.ones((2, 2), dtype=np.uint8)
        bitmap = cv2.dilate(bitmap, kernel)

    contours, _ = cv2.findContours(
        bitmap,
        cv2.RETR_LIST,
        cv2.CHAIN_APPROX_SIMPLE
    )

    boxes = []

    for contour in contours[:MAX_CANDIDATES]:
        rect = cv2.minAreaRect(contour)
        (cx, cy), (rw, rh), angle = rect

        if min(rw, rh) < 3:
            continue

        ordered = order_min_area_rect_points(
            cv2.boxPoints(rect)
        )

        score_points = (
            contour.reshape(-1, 2)
            if SCORE_MODE.lower() == "slow"
            else ordered
        )

        score = polygon_score(prob_map, score_points)

        if score < BOX_THRESH:
            continue

        area = abs(cv2.contourArea(ordered.astype(np.float32)))
        perimeter = cv2.arcLength(
            ordered.astype(np.float32), True
        )

        if perimeter <= 0:
            continue

        distance = area * UNCLIP_RATIO / perimeter

        offset = pyclipper.PyclipperOffset()
        path = np.round(ordered).astype(np.int32).tolist()
        offset.AddPath(
            path,
            pyclipper.JT_ROUND,
            pyclipper.ET_CLOSEDPOLYGON
        )

        expanded_paths = offset.Execute(distance)

        if not expanded_paths:
            continue

        expanded = np.asarray(
            expanded_paths[0], dtype=np.float32
        )

        expanded_rect = cv2.minAreaRect(expanded)
        (_, _), (expanded_w, expanded_h), _ = expanded_rect

        if min(expanded_w, expanded_h) < 5:
            continue

        expanded_points = order_min_area_rect_points(
            cv2.boxPoints(expanded_rect)
        )

        scaled = expanded_points.copy()
        scaled[:, 0] *= scale_x
        scaled[:, 1] *= scale_y

        scaled[:, 0] = [
            max(0, min(original_w - 1, round_half_to_even(x)))
            for x in scaled[:, 0]
        ]
        scaled[:, 1] = [
            max(0, min(original_h - 1, round_half_to_even(y)))
            for y in scaled[:, 1]
        ]

        box_w = math.hypot(
            scaled[1][0] - scaled[0][0],
            scaled[1][1] - scaled[0][1]
        )
        box_h = math.hypot(
            scaled[3][0] - scaled[0][0],
            scaled[3][1] - scaled[0][1]
        )

        if box_w <= 3 or box_h <= 3:
            continue

        boxes.append(scaled.astype(np.int32))

    return boxes

# ============================================================
# MAIN
# ============================================================

def main():
    if not IMAGE_PATH.is_file():
        raise FileNotFoundError(f"Image not found: {IMAGE_PATH}")

    if not MODEL_PATH.is_file():
        raise FileNotFoundError(f"Model not found: {MODEL_PATH}")

    image = cv2.imread(str(IMAGE_PATH))
    if image is None:
        raise RuntimeError("OpenCV could not read card_crop.jpg")

    h, w = image.shape[:2]

    print("=== CARD ===")
    print(f"Image: {w}x{h}")

    # ---------------- MORPHOLOGY ----------------

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    _, mask = cv2.threshold(
        gray, 150, 255, cv2.THRESH_BINARY
    )

    kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (15, 3)
    )

    closed = cv2.morphologyEx(
        mask, cv2.MORPH_CLOSE, kernel, iterations=1
    )

    contours, _ = cv2.findContours(
        closed,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE
    )

    morph_boxes = []

    for contour in contours:
        x, y, bw, bh = cv2.boundingRect(contour)

        if bw > 5 and bh > 5:
            morph_boxes.append((x, y, bw, bh))

    morph_boxes.sort(key=lambda b: (b[1], b[0]))

    print("\n=== MORPHOLOGY ===")
    print(f"Regions: {len(morph_boxes)}")

    # ---------------- DBNET ----------------

    session = ort.InferenceSession(
        str(MODEL_PATH),
        providers=["CPUExecutionProvider"]
    )

    input_info = session.get_inputs()[0]
    print("\n=== ONNX MODEL ===")
    print(f"Input name: {input_info.name}")
    print(f"Input shape: {input_info.shape}")
    print(f"Input type: {input_info.type}")

    tensor, resized_h, resized_w = dbnet_preprocess(image)

    print("\n=== DBNET INPUT ===")
    print(f"Tensor: {tensor.shape}")
    print(f"Resized image: {resized_w}x{resized_h}")
    print(f"Image mode: {IMG_MODE}")
    print(f"Normalization mean: {MEAN.tolist()}")
    print(f"Normalization std: {STD.tolist()}")

    outputs = session.run(
        None,
        {input_info.name: tensor}
    )

    pred = np.asarray(outputs[0], dtype=np.float32)

    print("\n=== DBNET OUTPUT ===")
    print(f"Shape: {pred.shape}")
    print(f"Min probability: {float(pred.min()):.6f}")
    print(f"Max probability: {float(pred.max()):.6f}")

    dbnet_boxes = dbnet_postprocess(pred, h, w)

    print("\n=== DBNET ===")
    print(f"Regions: {len(dbnet_boxes)}")

    # ---------------- DRAW MORPHOLOGY ----------------

    morph_img = image.copy()

    for x, y, bw, bh in morph_boxes:
        cv2.rectangle(
            morph_img,
            (x, y),
            (x + bw, y + bh),
            (0, 255, 0),
            1
        )

    cv2.imwrite(str(OUT_MORPH), morph_img)

    # ---------------- DRAW DBNET ----------------

    dbnet_img = image.copy()

    for box in dbnet_boxes:
        cv2.polylines(
            dbnet_img,
            [box.reshape(-1, 1, 2)],
            True,
            (0, 0, 255),
            1
        )

    cv2.imwrite(str(OUT_DBNET), dbnet_img)

    # ---------------- COMPARISON ----------------

    compare_img = image.copy()

    for x, y, bw, bh in morph_boxes:
        cv2.rectangle(
            compare_img,
            (x, y),
            (x + bw, y + bh),
            (0, 255, 0),
            1
        )

    for box in dbnet_boxes:
        cv2.polylines(
            compare_img,
            [box.reshape(-1, 1, 2)],
            True,
            (0, 0, 255),
            1
        )

    cv2.imwrite(str(OUT_COMPARE), compare_img)

    # ---------------- RESULTS ----------------

    print("\n=== RESULTS ===")
    print(f"Morphology: {len(morph_boxes)}")
    print(f"DBNet: {len(dbnet_boxes)}")
    print(f"Green = morphology")
    print(f"Red = DBNet")
    print(f"Saved: {OUT_MORPH}")
    print(f"Saved: {OUT_DBNET}")
    print(f"Saved: {OUT_COMPARE}")

    print("\n=== DBNET BOXES ===")
    for i, box in enumerate(dbnet_boxes, 1):
        print(f"{i}: {box.tolist()}")

if __name__ == "__main__":
    main()

import cv2
from pathlib import Path
from collections import Counter

VIDEO_DIR = Path("/sdcard/Pictures/Screenshots")

videos = sorted(
    p for p in VIDEO_DIR.rglob("*")
    if p.is_file() and p.suffix.lower() in (".mp4", ".mkv")
)

if not videos:
    raise SystemExit("Видеофайлы не найдены")

def detect(frame):
    height, width = frame.shape[:2]
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 50, 150)

    kernel = cv2.getStructuringElement(
        cv2.MORPH_RECT, (9, 9)
    )
    closed = cv2.morphologyEx(
        edges, cv2.MORPH_CLOSE, kernel, iterations=2
    )

    contours, _ = cv2.findContours(
        closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE
    )

    candidates = []

    for contour in contours:
        area = cv2.contourArea(contour)
        if area < width * height * 0.002:
            continue

        perimeter = cv2.arcLength(contour, True)
        polygon = cv2.approxPolyDP(
            contour, 0.02 * perimeter, True
        )

        if len(polygon) != 4 or not cv2.isContourConvex(polygon):
            continue

        x, y, w, h = cv2.boundingRect(polygon)
        ratio = w / h if h else 0

        if (
            area >= width * height * 0.05
            and w >= width * 0.15
            and h >= height * 0.30
            and 0.65 <= ratio <= 1.5
        ):
            candidates.append((area, x, y, w, h))

    if not candidates:
        return None

    candidates.sort(reverse=True)
    _, x, y, w, h = candidates[0]
    return (x, y, w, h)


print("Найдено видео:", len(videos))

for path in videos:
    cap = cv2.VideoCapture(str(path))

    if not cap.isOpened():
        print(f"\nОШИБКА ОТКРЫТИЯ: {path.name}")
        continue

    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    checked = 0
    hits = 0
    boxes = Counter()

    while True:
        ok, frame = cap.read()
        if not ok:
            break

        checked += 1
        box = detect(frame)

        if box:
            hits += 1
            boxes[box] += 1

    cap.release()

    print(f"\n=== {path.name} ===")
    print(f"Размер видео: {width}x{height}")
    print(f"FPS: {fps:.2f} | кадров в файле: {total}")
    print(f"Проверено: {checked}")
    print(f"Кадров с кандидатом: {hits}")

    if checked:
        print(f"Доля кадров с кандидатом: {hits / checked * 100:.1f}%")

    print(f"Разных границ: {len(boxes)}")

    for box, count in boxes.most_common(3):
        print(f"  {box}: {count} кадров")

    if boxes:
        for i, name in enumerate(("X", "Y", "Ширина", "Высота")):
            values = [box[i] for box in boxes]
            print(f"{name}: {min(values)}–{max(values)}")

import cv2
import os

BASE = os.path.dirname(os.path.abspath(__file__))
IMAGE = os.path.join(BASE, "speed_ru_frame_2s.jpg")
OUTPUT = os.path.join(BASE, "card_candidates.jpg")

image = cv2.imread(IMAGE)

if image is None:
    raise SystemExit(f"Не удалось открыть изображение: {IMAGE}")

height, width = image.shape[:2]
print(f"Кадр: {width}x{height}")

gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
blur = cv2.GaussianBlur(gray, (5, 5), 0)
edges = cv2.Canny(blur, 50, 150)

kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=2)

contours, _ = cv2.findContours(
    closed, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE
)

candidates = []

for contour in contours:
    area = cv2.contourArea(contour)

    if area < width * height * 0.002:
        continue

    perimeter = cv2.arcLength(contour, True)
    polygon = cv2.approxPolyDP(contour, 0.02 * perimeter, True)

    if len(polygon) != 4 or not cv2.isContourConvex(polygon):
        continue

    x, y, w, h = cv2.boundingRect(polygon)
    ratio = w / h if h else 0

    if ratio < 0.5 or ratio > 3.0:
        continue

    candidates.append((area, x, y, w, h, ratio))

candidates.sort(reverse=True)

preview = image.copy()

for index, (area, x, y, w, h, ratio) in enumerate(candidates[:30], 1):
    cv2.rectangle(preview, (x, y), (x + w, y + h), (0, 255, 0), 2)
    cv2.putText(
        preview, str(index), (x, max(20, y - 5)),
        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2
    )
    print(
        f"#{index}: x={x}, y={y}, w={w}, h={h}, "
        f"ratio={ratio:.2f}, area={int(area)}"
    )

cv2.imwrite(OUTPUT, preview)
print(f"\nКандидатов найдено: {len(candidates)}")
print(f"Изображение результатов: {OUTPUT}")

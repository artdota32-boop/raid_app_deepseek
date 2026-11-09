import cv2

VIDEO = "/sdcard/Pictures/Screenshots/speed_ru.mp4"

cap = cv2.VideoCapture(VIDEO)
if not cap.isOpened():
    raise SystemExit("ОШИБКА: не удалось открыть видео")

fps = cap.get(cv2.CAP_PROP_FPS)
total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

step = 1

print("=== АВТОМАТИЧЕСКОЕ СКАНИРОВАНИЕ ВИДЕО ===")
print(f"Видео: {width}x{height}, {fps:.2f} FPS")
print(f"Всего кадров: {total}")
print(f"Шаг анализа: {step} кадров (~0.5 сек)")
print()

checked = 0
detected = 0
frame_index = 0

while frame_index < total:
    ok, frame = cap.read()

    if not ok:
        break

    checked += 1
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    blur = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blur, 50, 150)

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
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
            candidates.append((area, x, y, w, h, ratio))

    if candidates:
        candidates.sort(reverse=True)
        area, x, y, w, h, ratio = candidates[0]
        detected += 1
        print(
            f"{frame_index / fps:5.2f} сек | "
            f"НАЙДЕНА | x={x}, y={y}, "
            f"размер={w}x{h}, ratio={ratio:.2f}"
        )
    else:
        print(f"{frame_index / fps:5.2f} сек | не обнаружена")

    frame_index += step

cap.release()

print()
print("=== ИТОГ ===")
print(f"Проверено кадров: {checked}")
print(f"Кадров с кандидатом: {detected}")
print(f"Без кандидата: {checked - detected}")

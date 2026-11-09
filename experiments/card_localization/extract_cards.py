import cv2
import os
import csv

BASE = os.path.dirname(os.path.abspath(__file__))
VIDEO = "/sdcard/Pictures/Screenshots/speed_ru.mp4"
OUTPUT_DIR = os.path.join(BASE, "dbnet_samples_v1")

START_SEC = 0.6
INTERVAL_SEC = 1.0

os.makedirs(OUTPUT_DIR, exist_ok=True)

def find_card(frame):
    height, width = frame.shape[:2]

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

    if not candidates:
        return None

    candidates.sort(reverse=True)
    return candidates[0]

cap = cv2.VideoCapture(VIDEO)

if not cap.isOpened():
    raise SystemExit(f"ОШИБКА: не удалось открыть видео: {VIDEO}")

fps = cap.get(cv2.CAP_PROP_FPS)
total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

if fps <= 0 or total <= 0:
    cap.release()
    raise SystemExit("ОШИБКА: некорректные параметры видео")

duration = total / fps

print("=== ИЗВЛЕЧЕНИЕ ОБРАЗЦОВ ДЛЯ DBNET ===")
print(f"Видео: {total} кадров, {fps:.2f} FPS")
print(f"Продолжительность: {duration:.2f} сек")
print(f"Интервал образцов: {INTERVAL_SEC:.1f} сек")
print()

csv_path = os.path.join(OUTPUT_DIR, "samples.csv")
saved = 0
sample_number = 0

with open(csv_path, "w", newline="", encoding="utf-8") as csv_file:
    writer = csv.writer(csv_file)
    writer.writerow([
        "time_sec", "frame_index", "x", "y",
        "width", "height", "ratio", "crop_file"
    ])

    timestamp = START_SEC

    while timestamp < duration:
        sample_number += 1
        frame_index = min(round(timestamp * fps), total - 1)

        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_index)
        ok, frame = cap.read()

        if not ok:
            print(f"{timestamp:.1f} сек | ОШИБКА чтения кадра")
            timestamp += INTERVAL_SEC
            continue

        result = find_card(frame)

        if result is None:
            print(f"{timestamp:.1f} сек | карточка не найдена")
            timestamp += INTERVAL_SEC
            continue

        area, x, y, w, h, ratio = result
        crop = frame[y:y + h, x:x + w]

        if crop.size == 0:
            print(f"{timestamp:.1f} сек | ОШИБКА пустого кропа")
            timestamp += INTERVAL_SEC
            continue

        time_label = f"{timestamp:.1f}".replace(".", "p")
        filename = f"card_{sample_number:03d}_t{time_label}s.jpg"
        output_path = os.path.join(OUTPUT_DIR, filename)

        success = cv2.imwrite(
            output_path,
            crop,
            [cv2.IMWRITE_JPEG_QUALITY, 95]
        )

        if success:
            saved += 1
            writer.writerow([
                f"{timestamp:.2f}", frame_index,
                x, y, w, h, f"{ratio:.3f}", filename
            ])
            print(
                f"{timestamp:.1f} сек | СОХРАНЕНО {filename} | "
                f"{w}x{h} | x={x}, y={y} | ratio={ratio:.2f}"
            )
        else:
            print(f"{timestamp:.1f} сек | ОШИБКА сохранения")

        timestamp += INTERVAL_SEC

cap.release()

print()
print("=== ИТОГ ===")
print(f"Образцов сохранено: {saved}")
print(f"Папка: {OUTPUT_DIR}")
print(f"Таблица координат: {csv_path}")

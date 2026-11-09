import cv2, os

base = os.path.dirname(os.path.abspath(__file__))
marked = cv2.imread(os.path.join(base, "card_candidates.jpg"))
image = cv2.imread(os.path.join(base, "speed_ru_frame_2s.jpg"))
output = os.path.join(base, "filtered_candidates.jpg")

if marked is None or image is None:
    raise SystemExit("Ошибка открытия изображений.")
if marked.shape[:2] != image.shape[:2]:
    raise SystemExit("Размеры изображений не совпадают.")

H, W = image.shape[:2]
mask = cv2.inRange(cv2.cvtColor(marked, cv2.COLOR_BGR2HSV),
                   (35, 70, 50), (90, 255, 255))
contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

keep, drop = [], []

for c in contours:
    x, y, w, h = cv2.boundingRect(c)
    area, ratio = w * h, w / h if h else 0
    reasons = []
    if area < W * H * 0.05: reasons.append("площадь")
    if w < W * 0.15: reasons.append("ширина")
    if h < H * 0.30: reasons.append("высота")
    if not 0.65 <= ratio <= 1.5: reasons.append("пропорции")
    (drop if reasons else keep).append((x, y, w, h, area, ", ".join(reasons)))

result = image.copy()

for i, (x, y, w, h, area, _) in enumerate(keep, 1):
    cv2.rectangle(result, (x, y), (x+w, y+h), (0,255,0), 3)
    cv2.putText(result, str(i), (x, max(25,y-8)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0,0,255), 2)
    print(f"ОСТАВЛЕНА #{i}: {x}, {y}, {w}x{h}, area={area}")

for x, y, w, h, area, reason in drop:
    print(f"ОТБРОШЕНА: {x}, {y}, {w}x{h} — {reason}")

if not cv2.imwrite(output, result):
    raise SystemExit("Ошибка сохранения.")

print(f"\nОставлено: {len(keep)}")
print(f"Отброшено: {len(drop)}")
print(f"Результат: {output}")

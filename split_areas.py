from PIL import Image, ImageDraw
import numpy as np

img = Image.open("screenshots/outputs/speed_ru_card_crop.png").convert("RGB")
pixels = np.array(img).astype(np.int16)
r, g, b = pixels[:,:,0], pixels[:,:,1], pixels[:,:,2]

white = ((r > 175) & (g > 175) & (b > 165) & 
         ((np.maximum.reduce([r,g,b]) - np.minimum.reduce([r,g,b])) < 65))
gold = (r > 155) & (g > 105) & (r > g * 1.08) & (b < 190)
mask = white | gold

# Наши проблемные области
areas = [("Область 2", 43, 110), ("Область 7", 314, 358)]

debug = img.copy()
draw = ImageDraw.Draw(debug)

for name, start, end in areas:
    print(f"\n--- {name} (y={start}-{end}) ---")
    
    # Считаем пиксели в каждой строке
    counts = np.sum(mask[start:end, :], axis=1)
    
    # Ищем провалы (меньше 10 пикселей)
    in_gap = False
    gap_start = 0
    lines = []
    line_start = start
    
    for i, count in enumerate(counts):
        y = start + i
        if count < 10:
            if not in_gap:
                in_gap = True
                gap_start = y
        else:
            if in_gap and (y - gap_start) >= 3:  # разрыв >= 3 пикселей
                if y - line_start >= 5:  # минимальная высота строки
                    lines.append((line_start, gap_start))
                line_start = y
            in_gap = False
    
    # Последняя строка
    if end - line_start >= 5:
        lines.append((line_start, end))
    
    # Рисуем рамки
    for y1, y2 in lines:
        area = mask[y1:y2, :]
        ys, xs = np.where(area)
        if len(xs) > 0:
            x1, x2 = int(xs.min()), int(xs.max()) + 1
            draw.rectangle((x1, y1, x2, y2), outline="green", width=2)
            print(f"  Строка: y={y1}-{y2}, x={x1}-{x2}")

debug.save("screenshots/outputs/split_areas.png")
print("\n✅ Сохранено: screenshots/outputs/split_areas.png")

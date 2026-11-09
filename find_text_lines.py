from PIL import Image, ImageDraw
import numpy as np

SOURCE = "screenshots/outputs/speed_ru_card_crop.png"
OUTPUT = "screenshots/outputs/detected_text_lines.png"

img = Image.open(SOURCE).convert("RGB")
pixels = np.array(img).astype(np.int16)

r = pixels[:, :, 0]
g = pixels[:, :, 1]
b = pixels[:, :, 2]

# Светлые нейтральные пиксели (белый/серый текст)
white = (
    (r > 175) &
    (g > 175) &
    (b > 165) &
    (np.maximum.reduce([r, g, b]) -
     np.minimum.reduce([r, g, b]) < 65)
)

# Золотистые пиксели текста
gold = (
    (r > 155) &
    (g > 105) &
    (r > g * 1.08) &
    (b < 190)
)

mask = white | gold

# Горизонтальный профиль: количество текстовых пикселей в каждой строке
counts = np.sum(mask, axis=1)

# Строка считается активной, если в ней достаточно пикселей текста
active = counts >= 4

# Объединяем небольшие вертикальные разрывы до 2 пикселей
for y in range(1, len(active) - 2):
    if active[y - 1] and active[y + 1]:
        active[y] = True
    if active[y - 1] and active[y + 2]:
        active[y] = True

# Получаем вертикальные интервалы
bands = []
start = None

for y, value in enumerate(active):
    if value and start is None:
        start = y
    elif not value and start is not None:
        if y - start >= 2:
            bands.append((start, y))
        start = None

if start is not None:
    bands.append((start, len(active)))

# Рисуем найденные области
debug = img.copy()
draw = ImageDraw.Draw(debug)

print(f"Размер изображения: {img.width}x{img.height}")
print(f"Найдено областей: {len(bands)}")

for i, (y1, y2) in enumerate(bands, 1):
    area = mask[y1:y2, :]
    ys, xs = np.where(area)

    if len(xs) == 0:
        continue

    x1 = int(xs.min())
    x2 = int(xs.max()) + 1

    print(
        f"Область {i}: "
        f"x={x1}-{x2}, y={y1}-{y2}, "
        f"ширина={x2-x1}, высота={y2-y1}"
    )

    draw.rectangle((x1, y1, x2, y2), outline="red", width=1)

debug.save(OUTPUT)
print(f"\nДиагностика сохранена: {OUTPUT}")

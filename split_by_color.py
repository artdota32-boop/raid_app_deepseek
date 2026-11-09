from PIL import Image, ImageDraw
import numpy as np

path = "screenshots/outputs/speed_ru_card_crop.png"
img = Image.open(path).convert("RGB")
p = np.array(img).astype(np.int16)

r, g, b = p[:,:,0], p[:,:,1], p[:,:,2]

white = (
    (r > 175) & (g > 175) & (b > 165) &
    ((np.maximum.reduce([r,g,b]) -
      np.minimum.reduce([r,g,b])) < 65)
)

orange = (
    (r > 155) & (g > 75) & (r > g * 1.15) &
    (g > b * 1.15) & (b < 190)
)

debug = img.copy()
draw = ImageDraw.Draw(debug)

for name, mask, color in [
    ("Легендарный", orange, "orange"),
    ("Скр 26", white, "lime")
]:
    ys, xs = np.where(mask[67:107, :])
    ys += 67

    if len(xs):
        x1, x2 = int(xs.min()), int(xs.max()) + 1
        y1, y2 = int(ys.min()), int(ys.max()) + 1

        draw.rectangle((x1, y1, x2, y2), outline=color, width=2)
        print(f"{name}: x={x1}-{x2}, y={y1}-{y2}")

debug.save("screenshots/outputs/split_by_color.png")
print("Сохранено: screenshots/outputs/split_by_color.png")

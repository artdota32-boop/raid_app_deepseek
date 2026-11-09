from PIL import Image
import numpy as np

img = Image.open(
    "screenshots/outputs/speed_ru_card_crop.png"
).convert("RGB")

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

print(" y | white | orange | combined")
print("-" * 34)

for y in range(67, 111):
    w = int(np.sum(white[y, :]))
    o = int(np.sum(orange[y, :]))
    if w or o:
        print(f"{y:2} | {w:5} | {o:6} | {w+o:8}")

from PIL import Image
import numpy as np

img = np.array(
    Image.open("screenshots/outputs/speed_ru_card_crop.png").convert("RGB")
).astype(np.int16)

r, g, b = img[:,:,0], img[:,:,1], img[:,:,2]

white = (
    (r > 175) & (g > 175) & (b > 165) &
    ((np.maximum.reduce([r,g,b]) -
      np.minimum.reduce([r,g,b])) < 65)
)

gold = (r > 155) & (g > 105) & (r > g * 1.08) & (b < 190)

counts = np.sum(white | gold, axis=1)

for name, start, end in [
    ("ОБЛАСТЬ 2", 43, 110),
    ("ОБЛАСТЬ 7", 314, 358)
]:
    print(f"\n--- {name} ---")
    for y in range(start, end):
        n = int(counts[y])
        bar = "#" * min(n // 2, 60)
        print(f"{y:3}: {n:3} {bar}")

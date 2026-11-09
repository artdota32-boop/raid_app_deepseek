import os
import numpy as np
from PIL import Image, ImageDraw

SOURCE = "screenshots/outputs/speed_ru_frame.png"
OUT_PATH = "/sdcard/Download/RAID_RESULTS/card_components_test.png"

# Минимальный размер области для отображения
MIN_PIXELS = 100
MAX_BOXES = 40

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

print("[TEST] Loading:", SOURCE)

img = Image.open(SOURCE).convert("RGB")
rgb = np.asarray(img).astype(np.int16)

height, width = rgb.shape[:2]
print(f"[IMAGE] Size: {width}x{height}")

r = rgb[:, :, 0]
g = rgb[:, :, 1]
b = rgb[:, :, 2]

# Маска синих пикселей — пока те же пороги, что в первом тесте
mask = (
    (r < 60) &
    (g < 90) &
    (b > 90) &
    (b > r + 40) &
    (b > g + 20)
)

print("[MASK] Blue pixels:", int(mask.sum()))

# Union-Find: объединение горизонтальных отрезков
parent = []
rank = []

def make_set():
    idx = len(parent)
    parent.append(idx)
    rank.append(0)
    return idx

def find(x):
    while parent[x] != x:
        parent[x] = parent[parent[x]]
        x = parent[x]
    return x

def union(a, b):
    ra = find(a)
    rb = find(b)

    if ra == rb:
        return

    if rank[ra] < rank[rb]:
        ra, rb = rb, ra

    parent[rb] = ra

    if rank[ra] == rank[rb]:
        rank[ra] += 1

# Каждая строка разбивается на горизонтальные отрезки синих пикселей.
# Отрезки соседних строк объединяются, если соприкасаются
# (связность по 8 соседям).
previous = []

for y in range(height):
    row = mask[y]

    changes = np.diff(
        np.concatenate(([False], row, [False])).astype(np.int8)
    )

    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1) - 1

    current = []

    for x1, x2 in zip(starts, ends):
        x1 = int(x1)
        x2 = int(x2)

        idx = make_set()
        current.append((x1, x2, idx))

    # Сравниваем отрезки текущей строки с предыдущей
    j = 0

    for x1, x2, idx in current:
        while j < len(previous) and previous[j][1] < x1 - 1:
            j += 1

        k = j

        while k < len(previous) and previous[k][0] <= x2 + 1:
            px1, px2, pidx = previous[k]

            if px2 >= x1 - 1:
                union(idx, pidx)

            k += 1

    # Сохраняем статистику каждого отрезка
    for x1, x2, idx in current:
        runs.append((y, x1, x2, idx)) if False else None

    if y == 0:
        all_runs = []

    all_runs.extend((y, x1, x2, idx) for x1, x2, idx in current)

    previous = current

# Собираем статистику объединённых областей
components = {}

for y, x1, x2, idx in all_runs:
    root = find(idx)
    pixels = x2 - x1 + 1

    if root not in components:
        components[root] = {
            "x1": x1,
            "y1": y,
            "x2": x2,
            "y2": y,
            "pixels": 0
        }

    c = components[root]
    c["x1"] = min(c["x1"], x1)
    c["y1"] = min(c["y1"], y)
    c["x2"] = max(c["x2"], x2)
    c["y2"] = max(c["y2"], y)
    c["pixels"] += pixels

# Отбираем достаточно крупные области
valid = []

for c in components.values():
    if c["pixels"] >= MIN_PIXELS:
        c["width"] = c["x2"] - c["x1"] + 1
        c["height"] = c["y2"] - c["y1"] + 1
        valid.append(c)

valid.sort(key=lambda c: c["pixels"], reverse=True)

print("[DETECT] Total components:", len(components))
print("[DETECT] Components above threshold:", len(valid))

debug = img.copy()
draw = ImageDraw.Draw(debug)

colors = [
    "red", "lime", "yellow", "magenta", "cyan",
    "orange", "white", "blue"
]

for i, c in enumerate(valid[:MAX_BOXES]):
    color = colors[i % len(colors)]

    x1, y1 = c["x1"], c["y1"]
    x2, y2 = c["x2"], c["y2"]

    draw.rectangle((x1, y1, x2, y2), outline=color, width=3)
    draw.text(
        (x1 + 3, max(0, y1 - 12)),
        f"{i+1}: {c['pixels']} px",
        fill=color
    )

    print(
        f"[AREA {i+1}] "
        f"x={x1} y={y1} "
        f"w={c['width']} h={c['height']} "
        f"pixels={c['pixels']}"
    )

debug.save(OUT_PATH)

print("[RESULT] Displayed:", min(len(valid), MAX_BOXES))
print("[SAVED]", OUT_PATH)

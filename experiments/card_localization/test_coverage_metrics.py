#!/usr/bin/env python3

import os
import sys
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort


HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent.parent

# DBNet configuration contains relative paths.
# Set project root before importing existing modules.
os.chdir(PROJECT_ROOT)
sys.path.insert(0, str(HERE))

import test_craft960_vs_dbnet_ru2 as experiment


COVERAGE_LOW = 0.30
COVERAGE_HIGH = 0.50
CHILD_CONTAINMENT = 0.50


def clipped_box(box, width, height):
    x, y, w, h = map(int, box)

    x1 = max(0, x)
    y1 = max(0, y)
    x2 = min(width, x + w)
    y2 = min(height, y + h)

    if x2 <= x1 or y2 <= y1:
        return None

    return x1, y1, x2, y2


def box_intersection_area(a, b):
    x1 = max(a[0], b[0])
    y1 = max(a[1], b[1])
    x2 = min(a[2], b[2])
    y2 = min(a[3], b[3])

    return max(0, x2 - x1) * max(0, y2 - y1)


def build_union_mask(boxes, width, height):
    mask = np.zeros((height, width), dtype=bool)

    for box in boxes:
        rect = clipped_box(box, width, height)

        if rect is None:
            continue

        x1, y1, x2, y2 = rect
        mask[y1:y2, x1:x2] = True

    return mask


def coverage_stats(source_boxes, target_boxes, width, height):
    target_mask = build_union_mask(
        target_boxes, width, height
    )

    coverages = []
    covered_pixels = 0
    source_pixels = 0

    for box in source_boxes:
        rect = clipped_box(box, width, height)

        if rect is None:
            continue

        x1, y1, x2, y2 = rect

        area = (x2 - x1) * (y2 - y1)
        covered = int(
            np.count_nonzero(target_mask[y1:y2, x1:x2])
        )

        coverage = covered / area

        coverages.append(coverage)
        covered_pixels += covered
        source_pixels += area

    return {
        "coverages": coverages,
        "covered_pixels": covered_pixels,
        "source_pixels": source_pixels,
        "low": sum(
            value < COVERAGE_LOW for value in coverages
        ),
        "high": sum(
            value >= COVERAGE_HIGH for value in coverages
        ),
    }


def fragmentation_stats(
    parent_boxes,
    child_boxes,
    width,
    height
):
    parents = [
        rect for box in parent_boxes
        if (rect := clipped_box(box, width, height))
        is not None
    ]

    children = [
        rect for box in child_boxes
        if (rect := clipped_box(box, width, height))
        is not None
    ]

    counts = []

    for parent in parents:
        count = 0

        for child in children:
            child_area = (
                (child[2] - child[0]) *
                (child[3] - child[1])
            )

            intersection = box_intersection_area(
                parent, child
            )

            if child_area > 0:
                if intersection / child_area >= CHILD_CONTAINMENT:
                    count += 1

        counts.append(count)

    return counts


def print_coverage(label, stats):
    values = stats["coverages"]

    mean = float(np.mean(values)) if values else 0.0

    weighted = (
        stats["covered_pixels"] / stats["source_pixels"]
        if stats["source_pixels"] else 0.0
    )

    print(
        f"{label}: "
        f"среднее покрытие={mean:.3f} | "
        f"площадное покрытие={weighted:.3f} | "
        f">=50%: {stats['high']}/{len(values)} | "
        f"<30%: {stats['low']}/{len(values)}"
    )


def print_fragmentation(label, counts):
    if not counts:
        print(f"{label}: данных нет")
        return

    print(
        f"{label}: "
        f"среднее дочерних регионов={np.mean(counts):.2f} | "
        f"родителей с 2+ регионами="
        f"{sum(n >= 2 for n in counts)}/{len(counts)}"
    )


def create_aggregate():
    return {
        "coverages": [],
        "covered_pixels": 0,
        "source_pixels": 0,
        "low": 0,
        "high": 0,
    }


def add_stats(total, current):
    total["coverages"].extend(current["coverages"])
    total["covered_pixels"] += current["covered_pixels"]
    total["source_pixels"] += current["source_pixels"]
    total["low"] += current["low"]
    total["high"] += current["high"]


def main():
    dbnet_model = Path(
        experiment.dbnet.MODEL_PATH
    ).resolve()

    craft_model = experiment.CRAFT_MODEL_PATH

    samples = sorted(
        experiment.SAMPLES_DIR.glob("ru_*.jpg")
    )

    print("=== COVERAGE EXPERIMENT ===")
    print("PROJECT ROOT:", PROJECT_ROOT)
    print("DBNet model:", dbnet_model)
    print("CRAFT model:", craft_model)
    print("Найдено кадров:", len(samples))

    if not dbnet_model.is_file():
        raise FileNotFoundError(dbnet_model)

    if not craft_model.is_file():
        raise FileNotFoundError(craft_model)

    if len(samples) != 7:
        raise RuntimeError(
            f"Ожидалось 7 кадров, найдено: {len(samples)}"
        )

    providers = ["CPUExecutionProvider"]

    print("\nЗагрузка DBNet...")
    dbnet_session = ort.InferenceSession(
        str(dbnet_model),
        providers=providers
    )

    print("Загрузка CRAFT...")
    craft_session = ort.InferenceSession(
        str(craft_model),
        providers=providers
    )

    db_aggregate = create_aggregate()
    craft_aggregate = create_aggregate()

    db_fragments = []
    craft_fragments = []

    total_db = 0
    total_craft = 0

    for sample in samples:
        print("\n" + "=" * 55)
        print("КАДР:", sample.name)

        image = cv2.imread(str(sample))

        if image is None:
            raise RuntimeError(
                f"Не удалось загрузить изображение: {sample}"
            )

        height, width = image.shape[:2]

        db_boxes = experiment.ab.detect_regions(
            image, dbnet_session
        )

        craft_boxes = experiment.craft_detect(
            image, craft_session
        )

        total_db += len(db_boxes)
        total_craft += len(craft_boxes)

        print(f"Размер: {width}x{height}")
        print(f"DBNet: {len(db_boxes)}")
        print(f"CRAFT: {len(craft_boxes)}")

        # DBNet regions covered by the union of CRAFT regions.
        db_coverage = coverage_stats(
            db_boxes, craft_boxes, width, height
        )

        # CRAFT regions covered by the union of DBNet regions.
        craft_coverage = coverage_stats(
            craft_boxes, db_boxes, width, height
        )

        print("\nПОКРЫТИЕ:")
        print_coverage("DBNet -> CRAFT", db_coverage)
        print_coverage("CRAFT -> DBNet", craft_coverage)

        # How many child boxes are substantially inside each parent.
        db_frag = fragmentation_stats(
            db_boxes, craft_boxes, width, height
        )

        craft_frag = fragmentation_stats(
            craft_boxes, db_boxes, width, height
        )

        print("\nДРОБЛЕНИЕ:")
        print_fragmentation(
            "CRAFT regions внутри DBNet regions",
            db_frag
        )

        print_fragmentation(
            "DBNet regions внутри CRAFT regions",
            craft_frag
        )

        add_stats(db_aggregate, db_coverage)
        add_stats(craft_aggregate, craft_coverage)

        db_fragments.extend(db_frag)
        craft_fragments.extend(craft_frag)

    print("\n" + "=" * 55)
    print("ОБЩИЙ ИТОГ — 7 КАДРОВ")
    print("=" * 55)

    print("Всего областей DBNet:", total_db)
    print("Всего областей CRAFT:", total_craft)

    print("\nПОКРЫТИЕ:")
    print_coverage("DBNet -> CRAFT", db_aggregate)
    print_coverage("CRAFT -> DBNet", craft_aggregate)

    print("\nДРОБЛЕНИЕ:")
    print_fragmentation(
        "CRAFT regions внутри DBNet regions",
        db_fragments
    )

    print_fragmentation(
        "DBNet regions внутри CRAFT regions",
        craft_fragments
    )

    print("\nТЕСТ COVERAGE METRICS ЗАВЕРШЁН")


if __name__ == "__main__":
    main()

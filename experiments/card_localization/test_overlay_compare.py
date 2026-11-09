#!/usr/bin/env python3

import os
import sys
from pathlib import Path

import cv2
import onnxruntime as ort

HERE = Path(__file__).resolve().parent
PROJECT_ROOT = HERE.parent.parent

os.chdir(PROJECT_ROOT)
sys.path.insert(0, str(HERE))

import test_craft960_vs_dbnet_ru2 as experiment


TARGETS = [
    "ru_001_t0p6s.jpg",
    "ru_002_t1p6s.jpg",
    "ru_007_t6p6s.jpg",
]

OUT_DIR = HERE / "overlays"


def draw_boxes(image, boxes, color, prefix, thickness=2):
    height, width = image.shape[:2]
    labels = []

    for index, box in enumerate(boxes, start=1):
        x, y, w, h = map(int, box)

        if w <= 0 or h <= 0:
            continue

        x1 = max(0, x)
        y1 = max(0, y)
        x2 = min(width - 1, x + w - 1)
        y2 = min(height - 1, y + h - 1)

        if x2 < x1 or y2 < y1:
            continue

        cv2.rectangle(
            image,
            (x1, y1),
            (x2, y2),
            color,
            thickness,
        )

        label_y = y1 - 5 if y1 >= 16 else min(height - 1, y1 + 14)
        labels.append((f"{prefix}{index}", x1, label_y))

    for label, x, y in labels:
        cv2.putText(
            image, label, (x, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38, (0, 0, 0), 3, cv2.LINE_AA,
        )
        cv2.putText(
            image, label, (x, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.38, color, 1, cv2.LINE_AA,
        )


def main():
    dbnet_model = Path(experiment.dbnet.MODEL_PATH).resolve()
    craft_model = Path(experiment.CRAFT_MODEL_PATH).resolve()

    print("=== OVERLAY COMPARE ===")
    print("PROJECT ROOT:", PROJECT_ROOT)
    print("DBNet model:", dbnet_model)
    print("CRAFT model:", craft_model)
    print("Кадров:", len(TARGETS))

    if not dbnet_model.is_file():
        raise FileNotFoundError(dbnet_model)

    if not craft_model.is_file():
        raise FileNotFoundError(craft_model)

    for name in TARGETS:
        sample = experiment.SAMPLES_DIR / name
        if not sample.is_file():
            raise FileNotFoundError(sample)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    providers = ["CPUExecutionProvider"]

    print("\nЗагрузка DBNet...")
    dbnet_session = ort.InferenceSession(
        str(dbnet_model),
        providers=providers,
    )

    print("Загрузка CRAFT...")
    craft_session = ort.InferenceSession(
        str(craft_model),
        providers=providers,
    )

    for name in TARGETS:
        sample = experiment.SAMPLES_DIR / name

        image = cv2.imread(str(sample))
        if image is None:
            raise RuntimeError(f"Не удалось загрузить: {sample}")

        print(f"\nОбработка: {name}")

        db_boxes = experiment.ab.detect_regions(
            image, dbnet_session
        )

        craft_boxes = experiment.craft_detect(
            image, craft_session
        )

        print(
            f"  DBNet: {len(db_boxes)} | "
            f"CRAFT: {len(craft_boxes)}"
        )

        overlay = image.copy()

        # Зелёный — DBNet
        draw_boxes(
            overlay, db_boxes, (0, 255, 0), "D"
        )

        # Пурпурный — CRAFT
        draw_boxes(
            overlay, craft_boxes, (255, 0, 255), "C"
        )

        out_path = OUT_DIR / (
            f"overlay_{Path(name).stem}.png"
        )

        if not cv2.imwrite(str(out_path), overlay):
            raise RuntimeError(
                f"Не удалось сохранить: {out_path}"
            )

        print(f"  Сохранено: {out_path}")

    print("\nOVERLAY COMPARE ЗАВЕРШЁН")


if __name__ == "__main__":
    main()

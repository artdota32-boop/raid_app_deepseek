# Raid Scanner — cleaned technical development history

This chronology is distilled from the private project notes. Personal/conversational instructions, private notes and raw diagnostic logs are deliberately not reproduced here.

## 22 October 2026 — parser and UI stabilization

- The main-stat vertical search zone was narrowed/fixed to y=250..340 for the tested artifact layout.
- The parser began returning an explicit `main_stat` field, and the UI was changed to use that field rather than selecting the first recognized stat.
- Substat presentation was restored and consolidated from `stats`, `stats_percent` and `dop_stats`.
- The UI was simplified: compact text, dark artifact card and empty DOP/glyph sections hidden.
- Earlier open issues included Protection's two-number line and missing percent signs on glyph values.

## 23 October 2026 — local parser trainer

A standalone Dart trainer was created to exercise parser rules without rebuilding the Android APK for every iteration.

The trainer sequence helped isolate:
- MAIN being lost when the TWO-NUM rule ran before zone-aware main-stat selection;
- ordering differences introduced when substats were combined from multiple sources;
- percent signs being lost from glyph values;
- low numeric values such as SPD 9 being filtered incorrectly.

This established a faster development loop: reproduce a case in a small trainer/test, fix one rule, rerun the regression, then use a full Android build for integration validation.

## 24 October 2026 — v3.5.84 / Build #56 historical milestone

The notes record these fixes:
- Protection's `ATK 143 ATK 11` case: keep the main ATK value and retain the second ATK value as a glyph.
- Preserve percent signs in glyph values.
- Stop dropping values below 10, including SPD 9.
- Normalize a common OCR character confusion (accented A to plain A).

The project notes report successful results on ten artifact examples: Perception, Swift Parry, Instinct, Feral, Cruel, Speed, Relentless, Stalwart, Divine Life and Protection. This is a historical report, not a substitute for re-running tests against the current source revision.

## Earlier technical experiments recorded in the project notes

- Crop enlargement and crop export were introduced to improve small-text recognition and build reusable test inputs.
- Roboflow API integration was explored; external-service integration was not treated as a substitute for the local OCR pipeline.
- OpenCV and TFLite build approaches were tested, then removed after Android/CI compatibility problems.
- Android builds were moved toward Codemagic after repeated build-environment friction in GitHub Actions.
- UI and parser work continued through versions v3.5.75–v3.5.84.

## November 2026 — current comparison work

The source branch `paddle-onnx-crop-compare-20261108` contains current OCR and image-processing comparison work, including:
- Dart ONNX preprocessing and inference in `lib/onnx_ocr.dart`;
- Python OCR trainer and comparison scripts;
- DBNet, CRAFT and PP-OCRv6 detector experiments;
- card/crop diagnostics and polygon detection code;
- tests and small reference images now included in this mirror.

## Current engineering priority

Establish whether Flutter/Dart and Python feed equivalent pixels/tensors to the OCR model. Compare the pipeline stage by stage:
1. original input image;
2. detected/cropped rectangle and exact coordinates;
3. resize and padding;
4. inversion, color/channel order and normalization;
5. final tensor shape and values;
6. ONNX output shape and decoder result;
7. parsed MAIN / DOP / glyph fields.

Only after input parity is demonstrated should recognition-decoder changes be evaluated.

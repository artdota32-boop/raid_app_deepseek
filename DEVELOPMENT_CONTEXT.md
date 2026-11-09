# Raid Scanner — technical context for code review

This document is a cleaned technical handover for reviewers. It intentionally excludes personal notes and conversational instructions.

## Project purpose

Raid Scanner is an Android application for Raid: Shadow Legends artifact inspection. Its intended flow is to obtain an artifact image, detect/crop relevant areas, recognize text, parse artifact properties (main stat, substats, glyphs, level/set information), validate the result, and display it in the Flutter UI.

The project combines:
- Flutter/Dart for the Android app and image-processing logic
- Native OCR integration through the `paddle_ocr_native` dependency
- ONNX Runtime code and Python/OpenCV experiments for OCR and text-region detection comparisons
- Tests and standalone trainer/diagnostic scripts for faster iteration without a full APK build

## Source map

| Area | Main files | Responsibility |
|---|---|---|
| App/UI and orchestration | `lib/main.dart` | Main screen, image flow, OCR orchestration, artifact display |
| Text parsing | `lib/parser.dart` | Converts recognized text into artifact fields |
| OCR / ONNX | `lib/onnx_ocr.dart`, `trainer_ocr.py` | ONNX recognition, preprocessing, decoding and diagnostics |
| Crop calibration | `lib/crop_calibrator.dart` | Crop calibration helpers |
| Polygon detection | `lib/polygon/` | Artifact/polygon geometry and diagnostics |
| Validation | `lib/game_validator.dart`, `test/` | Game-data validation and regression tests |
| OCR research | `experiments/card_localization/` | Morphology, DBNet, CRAFT and PP-OCRv6 comparison scripts |
| Development tools | `tool/`, root `trainer_*.dart` | Standalone diagnostic/trainer utilities |
| Android integration | `android/` | Manifest, Gradle configuration and app entry point |

Trainer files at the repository root are development utilities; do not assume every `trainer_*.dart` file is part of the runtime application.

## ONNX recognition path visible in the current source

`lib/onnx_ocr.dart` loads:
- model: `assets/inference.onnx`
- character dictionary: `assets/dict.txt`

The implementation currently:
1. Decodes the input image.
2. Inverts the image (light text on a dark UI becomes dark text on a light background).
3. Resizes to a height of 48 while preserving aspect ratio and caps the width at 320.
4. Pads the remaining width with white pixels.
5. Builds a `[1, 3, 48, 320]` tensor in channel-first order and normalizes values to [-1, 1].
6. Runs the ONNX session and applies a greedy CTC decoder. The source currently expects a vocabulary size of 852.

Treat these values as implementation facts from the reviewed source file, not as independently verified properties of the ONNX binary.

## Parsing rules recorded in the project history

The October 2026 notes record these important parser decisions:
- Main-stat selection uses an explicit `main_stat` field rather than assuming the first detected stat is the main stat.
- The main-stat vertical search area was fixed to approximately y=250..340 for the tested screenshot layout.
- Substats are assembled from multiple parser result collections (`stats`, `stats_percent`, and `dop_stats`).
- Glyph values preserve the percent sign.
- The Protection case containing two ATK values (for example, main ATK 143 and glyph ATK 11) received a dedicated TWO-NUM handling fix.
- Small values such as SPD 9 must not be discarded by a generic low-value filter.
- OCR normalization includes handling a misread accented A character.

The recorded regression set contains Perception, Swift Parry, Instinct, Feral, Cruel, Speed, Relentless, Stalwart, Divine Life and Protection. The historical notes report 10/10 successful reads after the v3.5.84 / Build #56 fixes. This is a historical result; re-run the current tests before treating it as a present-day guarantee.

## Current review focus

The source branch mirrored by this project is `paddle-onnx-crop-compare-20261108`. Its useful review areas are:
- parity between Flutter/Dart and Python image decoding, cropping, resizing, padding, channel order and normalization;
- polygon/card boundary detection and crop geometry;
- text-line detection (morphology vs DBNet vs CRAFT/PP-OCRv6 experiments);
- ONNX recognition output shape and CTC decoding;
- parser behavior after OCR, especially MAIN / DOP / glyph separation.

For a fair parity test, both implementations must receive the same source image and use explicitly documented crop coordinates. Compare intermediate images and tensors before comparing recognized strings. Do not jump directly to changing the OCR decoder when the input pixels may already differ.

## Collaboration and review rules

- The private `raid_app` repository is the source of truth; this public repository is a curated review mirror.
- Reviewers should cite exact paths and line numbers and separate confirmed findings from hypotheses.
- Do not invent files, test outcomes, or model metadata that are not present in the mirror.
- Prefer one isolated fix at a time and define a regression case before changing behavior.
- Do not commit or change code unless the project owner explicitly asks.
- Only committed files from the configured source branch are mirrored. Local uncommitted Termux files do not appear automatically.

## Build and reproducibility limitations

This mirror is suitable for source review, but it is not a complete standalone build package:
- ONNX model binaries are not included; see `MODEL_CATALOG.md`.
- The local OCR plugin/vendor source is excluded pending license review. The dependency declaration remains visible in `pubspec.yaml`.
- Some experiment scripts expect model files and image fixtures. The reviewed image fixtures are listed in `REFERENCE_FIXTURES.md`.
- A reviewer may need to provide models and install the corresponding Python/Flutter dependencies locally to execute every experiment.

## Security note

Never add API keys, access tokens, passwords, signing keys, private user data or credentials to this mirror. A compile-time Dart define is not a secure secret store for a mobile application: values shipped in an APK should be treated as extractable. The source should contain only a placeholder/configuration mechanism, never a live credential.

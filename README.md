# Raid Scanner — expanded public source mirror

This is a curated public snapshot of the private Raid Scanner project, synchronized from the private working branch.

## Included
- All Flutter/Dart application files under lib/ and the current test suites.
- The local flutter_paddle_ocr_v5 plugin source, with accompanying license files and third-party notices.
- All tracked Python/Dart OCR experiments under experiments/, including their input fixtures, generated comparisons, diagnostic JSON/text and experiment logs.
- The tracked datasets under dataset_final/, dataset_icons/ and dataset_roboflow/.
- The complete tracked Android project files, including the Gradle wrapper and launcher icon.
- The reviewed root card-filter log after removal of the local device/project path.
- Sanitized development context/history, the model catalog, fixture notes and the reviewed PROJECT_HISTORY.md project wiki.
- Read-only reference copies of the private GitHub Actions workflows under project_docs/workflows/; these are documentation files, not active workflows.

## Model/build limitations
- assets/inference.onnx is deliberately not mirrored until its exact origin and redistribution license are confirmed.
- The experiment detector and CRAFT ONNX files included here have corresponding third-party license notices under licenses/.
- The private source repository remains the source of truth. This mirror is for code review and technical analysis; it is not guaranteed to be a self-contained build package.

## Security and privacy
- No private Git history, API credentials, local secrets, private conversation notes, raw backups or generated APKs are included.
- The reviewed PROJECT_HISTORY.md project wiki is intentionally included; it is a curated context document, not the private Git commit history.
- New source files are not published automatically unless their paths are added to the allowlist in the private workflow.
- This repository is public. Do not put secrets, private user data or confidential material here.

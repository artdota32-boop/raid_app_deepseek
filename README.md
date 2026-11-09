# Raid Scanner — expanded DeepSeek review mirror

This is an expanded, curated public source snapshot of the private Raid Scanner project.

## Included
- All current Flutter/Dart files under lib/
- Dart and Python tests, tools, OCR trainers, and root-level maintenance scripts
- Python source experiments under experiments/card_localization/
- Android text configuration and app entry-point sources
- Flutter dependency manifests and selected text assets
- Codemagic and GitLab build configuration

## How to interpret the code
- The active Flutter application is under lib/.
- Root-level trainer_*.dart and trainer_*.py files are standalone trainers or experiments; they are not all runtime entry points.
- The experiments/ directory contains research and comparison scripts. Some require image fixtures or model files that are deliberately not mirrored.
- The private repository remains the source of truth.

## Build limitations
- Large model binaries, including assets/inference.onnx, are intentionally excluded. A complete local build needs the model supplied separately.
- The local_plugins/ vendor source is excluded pending a license review.
- This is intended for source review and architecture analysis, not as a self-contained APK build package.

## Security and privacy
- No private Git history, API credentials, local secrets, personal notes, datasets, screenshots, generated diagnostics, or logs are included.
- The publishing workflow checks staged text files for common credential formats before publishing.
- Do not treat this public mirror as a secure place to store credentials or private data.

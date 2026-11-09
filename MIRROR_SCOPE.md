# Mirror scope

This repository is an explicit allowlist snapshot from the private Raid Scanner repository.

## Included paths
- lib/: all current Flutter/Dart application source
- test/ and root test_*.py / test_*.dart files
- tool/: diagnostic and development utilities
- experiments/card_localization/: Python source scripts only
- Root-level Python/Dart trainer and maintenance scripts
- android/: text build configuration, manifest, and app entry-point sources
- pubspec.yaml, pubspec.lock, selected text assets, and Codemagic/GitLab build configuration

## Excluded paths and data
- GitHub Actions workflow files (kept out to avoid granting the mirror token workflow permission)
- Private Git history
- CONTEXT.md, HISTORY.md, history.md, PROJECT_HISTORY.md, PROJECT_PASSPORT.txt, and backups
- local_plugins/ source pending license review
- ONNX/TFLite and other model binaries
- dataset_* directories and other datasets
- screenshots/, experiment image fixtures, generated diagnostics, logs, and tensors
- local machine configuration, credentials, API keys, and personal data

New files are not published automatically. Add a reviewed file path to the allowlist in
.github/workflows/publish-public-mirror.yml before it can appear in this public repository.

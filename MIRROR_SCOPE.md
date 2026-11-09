# Mirror scope

This repository is an explicit allowlist snapshot from the private Raid Scanner repository.

## Included paths
- lib/: all current Flutter/Dart application source
- test/ and root test_*.py / test_*.dart files
- tool/: diagnostic and development utilities
- experiments/card_localization/: Python source scripts and three reviewed OCR input crops / frame fixtures
- Root-level Python/Dart trainer and maintenance scripts
- android/: text build configuration, manifest, and app entry-point sources
- screenshots/: only the two reviewed Speed reference images listed below
- assets/diagnostics/: one reviewed OCR line crop
- Four sanitized review documents, selected text assets, and Codemagic/GitLab build configuration

## Excluded paths and data
- GitHub Actions workflow files (kept out to avoid granting the mirror token workflow permission)
- Private Git history
- CONTEXT.md, HISTORY.md, history.md, PROJECT_HISTORY.md, PROJECT_PASSPORT.txt, and backups
- local_plugins/ source pending license review
- ONNX/TFLite and other model binaries
- dataset_* directories and other datasets
- all screenshots and experiment images except the exact six reviewed fixtures listed in REFERENCE_FIXTURES.md; generated diagnostics, logs, and tensors
- local machine configuration, credentials, API keys, and personal data

New files are not published automatically. Add a reviewed file path to the allowlist in
.github/workflows/publish-public-mirror.yml before it can appear in this public repository.

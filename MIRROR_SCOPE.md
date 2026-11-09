# Mirror scope

This repository is an explicit allowlist snapshot from the private Raid Scanner working branch.

## Included
- lib/: all tracked Flutter/Dart application source.
- test/ and root test_*.py / test_*.dart files.
- tool/: all allowlisted development and diagnostic utilities.
- local_plugins/flutter_paddle_ocr_v5/: tracked local plugin source; license copies and third-party notices are generated into this mirror.
- experiments/: all tracked experiment source, fixtures, images, ONNX detector candidates, generated comparisons, diagnostic outputs and the reviewed scan_video.log.
- dataset_final/, dataset_icons/ and dataset_roboflow/: tracked image datasets and Roboflow export metadata.
- android/: all tracked Android project files, including wrapper JAR and launcher icon.
- card_filter.log: published only after replacing the local Termux/project path.
- selected text assets, manifests and build configuration.
- project_docs/workflows/: read-only .yml.txt copies of the private build and mirror workflows (not installed as active GitHub Actions workflows).
- sanitized development documents and third-party license texts.

## Excluded
- assets/inference.onnx: model origin and redistribution license have not been independently identified.
- Raw private Git history. Historical commits can retain revoked credentials; publishing history would expose more than the current snapshot.
- CONTEXT.md, HISTORY.md, history.md, PROJECT_HISTORY.md, PROJECT_PASSPORT.txt and backups; these contain private conversation notes, personal addressing/preferences or unreviewed historical material. Sanitized development summaries are mirrored instead.
- The actual .github/workflows/ paths; read-only copies are published under project_docs/workflows/ to avoid granting workflow-write permission to the mirror token.
- Unreviewed screenshots outside the allowlisted experiment and dataset paths, generated APKs, local machine configuration, credentials, API keys and personal data.

Only reviewed paths in the private workflow allowlist are copied. New files are not published automatically.

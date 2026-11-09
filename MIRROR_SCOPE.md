# Mirror scope

This repository contains an explicit allowlist of source files copied from the private project.
New files are not published automatically unless they are added to the allowlist in
.github/workflows/publish-public-mirror.yml in the private repository.

Excluded content includes secrets, history, backups, logs, screenshots, datasets, model binaries,
and the local Paddle OCR plugin source pending license review.

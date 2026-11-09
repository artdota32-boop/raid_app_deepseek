# Raid Scanner — reviewed OCR reference fixtures

These are a small, curated set of game-interface images selected to make code review more concrete. They are not a general dataset and do not replace the private training/evaluation data.

| Fixture | Purpose |
|---|---|
| `experiments/card_localization/speed_ru_frame_2s.jpg` | Full game frame showing the artifact card in context; useful for understanding detection and crop selection |
| `screenshots/speed_ru_frame.png` | Full reference frame used in the crop/parity work |
| `experiments/card_localization/card_crop.jpg` | Cropped artifact image consumed by `test_det_vs_morph.py` |
| `experiments/card_localization/dbnet_samples_v1/card_001_t0p6s.jpg` | Small card crop used by DBNet/CRAFT/recognition comparison scripts |
| `screenshots/outputs/speed_ru_card_crop.png` | Reference crop output for image-processing comparison |
| `assets/diagnostics/line_08_white.png` | A small text-line crop used for OCR diagnostics |

## Expected text visible in the Speed artifact example

The reviewed Speed boots crop visibly contains these fields (transcription for qualitative comparison):
- Set: Speed
- Item: Boots
- Rarity: Legendary
- Main stat: Speed 26
- Substats shown: ATK 10%, Accuracy 9, Resistance 28, DEF 15
- Set bonus shown: Speed +12%

The exact rendered labels and OCR output may vary by preprocessing and OCR engine. Treat the list above as a human-readable visual reference, not a machine-checked assertion.

## Image-use boundaries

Only the six paths listed above are included as reference fixtures. Other screenshots, generated overlays, intermediate crops, datasets and tensors remain excluded. If a new fixture is needed, add only the exact reviewed file path to the private workflow allowlist.

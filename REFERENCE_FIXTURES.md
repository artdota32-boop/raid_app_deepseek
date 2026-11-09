# Raid Scanner — reference fixtures and experiment data

The public mirror now includes the tracked experiment fixtures and three project dataset folders:
- experiments/card_localization/: source crops, selected full-frame examples, detector comparisons, CRAFT/DBNet experiment images and generated overlays.
- experiments/polygon_test_frames/ and experiments/polygon_time_probe/: tracked source fixtures and diagnostic outputs.
- dataset_final/: curated 5-star and 6-star icon crops.
- dataset_icons/: icon crop collection used during training/validation work.
- dataset_roboflow/: ten-image Roboflow export, with train/validation/test subsets and export metadata.
- screenshots/: only the previously reviewed Speed reference images; other screenshot paths remain private.

The images are game-interface captures/crops intended for OCR and image-processing analysis. The datasets are not guaranteed to be complete or independently re-annotated in this mirror. Use the file paths and script references to identify the exact sample corresponding to each experiment.

The reviewed Speed fixture's visible expected fields are described in the original technical context; treat those notes as qualitative references rather than automated test assertions.

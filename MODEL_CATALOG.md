# Raid Scanner — ONNX model catalog

Model binaries are intentionally not copied into the public mirror. This catalog exposes filenames, observed sizes and the roles inferred from the source scripts, so reviewers can understand the model graph without distributing the binary files.

Sizes below are the exact Git blob sizes at the mirrored source revision. Approximate decimal MB values are provided for readability.

| Model path in private source | Size (bytes) | Approx. size | Role indicated by source |
|---|---:|---:|---|
| `assets/inference.onnx` | 62,762,162 | 62.76 MB | OCR text-recognition model; loaded by `lib/onnx_ocr.dart` and Python OCR comparison scripts |
| `experiments/card_localization/det_inference.onnx` | 9,880,512 | 9.88 MB | DBNet text-detection model used by detector/OCR comparison scripts |
| `experiments/card_localization/ppocrv6_small_det.onnx` | 9,880,512 | 9.88 MB | PP-OCRv6 small detector candidate compared with the DBNet reference |
| `experiments/card_localization/craft/craft_mlt_25k.onnx` | 83,060,718 | 83.06 MB | CRAFT text-detection model used in CRAFT-vs-DBNet experiments |

## Verified from source

- `lib/onnx_ocr.dart` loads `assets/inference.onnx` and `assets/dict.txt`.
- The Dart ONNX recognition helper creates an input tensor with shape `[1, 3, 48, 320]`, normalizes it to [-1, 1] and performs greedy CTC decoding. It currently sets `vocabSize = 852`.
- Python `test_ocr_ab.py` refers to `det_inference.onnx` for detection and `assets/inference.onnx` for recognition.
- `test_ppocrv6_vs_dbnet.py` compares `det_inference.onnx` with `ppocrv6_small_det.onnx`.
- CRAFT comparison scripts load `craft/craft_mlt_25k.onnx`.

## Not independently verified

The actual ONNX graphs are not included here, so this catalog does not claim to verify:
- graph input/output names and shapes for every model;
- ONNX opset, training/export version or model checksum;
- quantization, precision or provider-specific compatibility;
- whether each experiment model remains the best or current candidate.

Those details should be inspected from the actual model files when they are available in a trusted local environment. Do not infer them from filenames alone.

## Reproducibility

The scripts that consume these models are included where safe. To run them, provide the corresponding model files at the listed paths and install their Python dependencies. Do not commit model binaries to this public mirror unless the project owner explicitly decides to distribute them.

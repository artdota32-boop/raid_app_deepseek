# Raid Scanner — ONNX model catalog

| Private source path | Size | Public mirror status | Notes |
|---|---:|---|---|
| assets/inference.onnx | 62,762,162 bytes | Excluded | Recognition model used by lib/onnx_ocr.dart. Its exact upstream origin and redistribution license were not established during this review. |
| experiments/card_localization/det_inference.onnx | 9,880,512 bytes | Included | Same Git blob as ppocrv6_small_det.onnx at this source revision. |
| experiments/card_localization/ppocrv6_small_det.onnx | 9,880,512 bytes | Included | Project labels this as a PP-OCRv6 small detector candidate; PaddlePaddle model card declares Apache-2.0. |
| experiments/card_localization/craft/craft_mlt_25k.onnx | 83,060,718 bytes | Included | CRAFT text-detection experiment; corresponding MIT license copy is included under licenses/. |

## Source parity
- det_inference.onnx and ppocrv6_small_det.onnx have the same Git blob SHA in the private source branch, so they are duplicate binary contents at this revision.
- The actual ONNX graph metadata, inputs/outputs, opset and runtime compatibility still require inspection from the binary files.
- Do not infer the identity or license of assets/inference.onnx from the generic filename alone.

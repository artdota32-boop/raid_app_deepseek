# Third-party notices

This file records the upstream license information identified for source and model artifacts included in this public review mirror. It is not a legal opinion; verify the exact provenance of redistributed artifacts before commercial distribution.

## flutter_paddle_ocr_v5 plugin
The local plugin identifies its upstream repository as https://github.com/mencomao/flutter-paddle-ocr and declares Apache License 2.0. A copy of the upstream license is included at local_plugins/LICENSE.

The plugin contains Clipper 6.4.2-derived polygon clipping code in:
- local_plugins/flutter_paddle_ocr_v5/android/src/main/cpp/ocr_clipper.cpp
- local_plugins/flutter_paddle_ocr_v5/android/src/main/cpp/ocr_clipper.hpp

Those source headers identify Angus Johnson and the Boost Software License 1.0. The full license is included at licenses/Boost-1.0.txt.

The plugin's native pipeline also acknowledges PaddleOCR / Paddle-Lite demo code. PaddleOCR's Apache License 2.0 text is included at licenses/PaddleOCR-LICENSE.txt.

## OCR experiment models
- experiments/card_localization/ppocrv6_small_det.onnx and det_inference.onnx have identical Git blob contents in the source revision. The project labels the former as a PP-OCRv6 small detector candidate. The PaddlePaddle PP-OCRv6 model card declares Apache-2.0; see https://huggingface.co/PaddlePaddle/PP-OCRv6_small_det_onnx and licenses/PaddleOCR-LICENSE.txt.
- experiments/card_localization/craft/craft_mlt_25k.onnx is identified by the project as a CRAFT detector model. The upstream CRAFT-pytorch repository publishes its code under the MIT license; a copy is included at licenses/CRAFT-MIT.txt. The original repository is https://github.com/clovaai/CRAFT-pytorch.

## External build dependencies
ONNX Runtime, OpenCV, Flutter and other dependencies are resolved by the build configuration rather than vendored as full source trees in this mirror. Their respective upstream license terms continue to apply.

## Local modifications
This plugin directory is a local project copy/fork. Review the upstream history and changed-file notices before redistributing the plugin separately. The presence of a license file does not mean every dependency or model in the wider project is covered by that same license.

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_paddle_ocr_platform_interface.dart';
import 'src/model_source.dart';
import 'src/models.dart';

/// Web backend for flutter_paddle_ocr. Binds to the `PaddleOCR` global exposed
/// by the @paddleocr/paddleocr-js UMD bundle. Consumers must load the SDK in
/// their `web/index.html` — see the plugin README.
class FlutterPaddleOcrWeb extends FlutterPaddleOcrPlatform {
  FlutterPaddleOcrWeb();

  static void registerWith(Registrar registrar) {
    FlutterPaddleOcrPlatform.instance = FlutterPaddleOcrWeb();
  }

  @override
  Future<Object> create({
    required ModelSource source,
    int cpuThreadNum = 4,
    CpuPower cpuPower = CpuPower.high,
    bool useOpenCL = false,
    bool useSpaceChar = true,
    bool useDilation = false,
    double? detDbThresh,
    double? detDbBoxThresh,
    double? detDbUnclipRatio,
  }) async {
    final bundled = switch (source) {
      BundledModelSource s => s,
      FilePathsModelSource() => throw UnsupportedError(
        'Web only supports ModelSource.bundled. paddleocr-js fetches models '
        'itself — no file paths needed.',
      ),
    };
    await _waitForSdk();
    // onnxruntime-web can't infer its WASM path when paddleocr-js is bundled
    // into a single script, so point it at the published CDN build.
    final options = _Options(
      lang: bundled.lang,
      ocrVersion: bundled.version,
      textDetectionModelName: bundled.textDetectionModelName,
      textRecognitionModelName: bundled.textRecognitionModelName,
      textDetThresh: detDbThresh,
      textDetBoxThresh: detDbBoxThresh,
      textDetUnclipRatio: detDbUnclipRatio,
      ortOptions: _OrtOptions(
        wasmPaths: 'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.24.3/dist/',
      ),
    );
    final ocr = await _paddleOcrSdk.create(options).toDart;
    return ocr;
  }

  // paddleocr-js is published as ESM-only. Most consumers load it via
  // `<script type="module">` which resolves asynchronously, so Flutter's
  // initState can race the script tag — poll briefly before giving up.
  Future<void> _waitForSdk({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_paddleOcrSdk.isUndefinedOrNull) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError(
          'window.PaddleOCR is not loaded. Add the paddleocr-js script tag to '
          'your web/index.html — see the flutter_paddle_ocr README.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<List<OcrResult>> recognize(
    Object handle,
    Uint8List imageBytes, {
    int maxSideLen = 960,
    bool runDetection = true,
    bool runClassification = false,
    bool runRecognition = true,
  }) async {
    final ocr = handle as _JsOcr;
    final blob = web.Blob(
      [imageBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    final jsResult = await ocr.predict(blob).toDart;
    final list = jsResult.toDart;
    if (list.isEmpty) return const [];
    final first = list.first;
    final items = first.items;
    if (items == null) return const [];
    return items.toDart.map(_fromJs).toList(growable: false);
  }

  @override
  Future<void> dispose(Object handle) async {
    final ocr = handle as _JsOcr;
    final maybePromise = ocr.dispose();
    if (maybePromise != null) await maybePromise.toDart;
  }
}

OcrResult _fromJs(_JsItem item) {
  final poly = item.poly;
  final points = poly == null
      ? const <Offset>[]
      : poly.toDart
            .map((p) {
              final pair = p.toDart;
              return Offset(pair[0].toDartDouble, pair[1].toDartDouble);
            })
            .toList(growable: false);
  return OcrResult(
    text: item.text ?? '',
    confidence: item.score ?? 0.0,
    points: points,
  );
}

@JS('PaddleOCR')
external _PaddleOcrSdk get _paddleOcrSdk;

extension type _PaddleOcrSdk(JSObject _) implements JSObject {
  external JSPromise<_JsOcr> create(_Options options);
}

extension type _JsOcr(JSObject _) implements JSObject {
  external JSPromise<JSArray<_JsPrediction>> predict(JSAny input);
  external JSPromise<JSAny?>? dispose();
}

extension type _JsPrediction(JSObject _) implements JSObject {
  external JSArray<_JsItem>? get items;
}

extension type _JsItem(JSObject _) implements JSObject {
  external String? get text;
  external double? get score;
  external JSArray<JSArray<JSNumber>>? get poly;
}

extension type _Options._(JSObject _) implements JSObject {
  external factory _Options({
    String? lang,
    String? ocrVersion,
    String? textDetectionModelName,
    String? textRecognitionModelName,
    double? textDetThresh,
    double? textDetBoxThresh,
    double? textDetUnclipRatio,
    _OrtOptions? ortOptions,
  });
}

extension type _OrtOptions._(JSObject _) implements JSObject {
  external factory _OrtOptions({String? wasmPaths});
}

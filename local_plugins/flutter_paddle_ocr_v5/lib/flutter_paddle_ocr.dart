import 'dart:typed_data';

import 'flutter_paddle_ocr_platform_interface.dart';
import 'src/model_source.dart';
import 'src/models.dart';

export 'src/model_source.dart';
export 'src/models.dart';

/// On-device OCR engine backed by PaddleOCR + ONNX Runtime (Android/iOS) or
/// paddleocr-js (web).
///
/// Create one instance per set of models, then call [recognize] repeatedly.
/// Call [dispose] when done to release native memory.
class PaddleOcr {
  PaddleOcr._(this._handle) {
    _finalizer.attach(this, _handle, detach: this);
  }

  final Object _handle;
  bool _disposed = false;

  // Safety net: if the caller forgets to await dispose(), release the native
  // engine when the Dart object gets GC'd. Disposing explicitly is still
  // strongly recommended — a GC pass is not guaranteed.
  static final Finalizer<Object> _finalizer = Finalizer<Object>(
    (handle) => FlutterPaddleOcrPlatform.instance.dispose(handle),
  );

  /// Loads the models described by [source] and returns a ready-to-use engine.
  ///
  /// See [ModelSource] for the two variants:
  ///  * [ModelSource.filePaths] — Android/iOS; supply .onnx files + dictionary
  ///  * [ModelSource.bundled]  — Web; paddleocr-js fetches .onnx by lang/version
  static Future<PaddleOcr> create({
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
    final handle = await FlutterPaddleOcrPlatform.instance.create(
      source: source,
      cpuThreadNum: cpuThreadNum,
      cpuPower: cpuPower,
      useOpenCL: useOpenCL,
      useSpaceChar: useSpaceChar,
      useDilation: useDilation,
      detDbThresh: detDbThresh,
      detDbBoxThresh: detDbBoxThresh,
      detDbUnclipRatio: detDbUnclipRatio,
    );
    return PaddleOcr._(handle);
  }

  /// Runs OCR on [imageBytes], which must be in a format the host platform can
  /// decode (PNG, JPEG, BMP, WebP, and on modern Android, HEIF).
  Future<List<OcrResult>> recognize(
    Uint8List imageBytes, {
    int maxSideLen = 960,
    bool runDetection = true,
    bool runClassification = false,
    bool runRecognition = true,
  }) {
    _checkNotDisposed();
    return FlutterPaddleOcrPlatform.instance.recognize(
      _handle,
      imageBytes,
      maxSideLen: maxSideLen,
      runDetection: runDetection,
      runClassification: runClassification,
      runRecognition: runRecognition,
    );
  }

  /// Releases native resources. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    await FlutterPaddleOcrPlatform.instance.dispose(_handle);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PaddleOcr instance has been disposed');
  }
}

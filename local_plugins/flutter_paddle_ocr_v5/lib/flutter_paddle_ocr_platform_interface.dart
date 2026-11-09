import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_paddle_ocr_method_channel.dart';
import 'src/model_source.dart';
import 'src/models.dart';

abstract class FlutterPaddleOcrPlatform extends PlatformInterface {
  FlutterPaddleOcrPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPaddleOcrPlatform _instance = MethodChannelFlutterPaddleOcr();

  static FlutterPaddleOcrPlatform get instance => _instance;

  static set instance(FlutterPaddleOcrPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Loads models and returns an opaque engine handle.
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
  }) {
    throw UnimplementedError('create() has not been implemented.');
  }

  /// Runs OCR on an image encoded in a browser/native-decodable format.
  Future<List<OcrResult>> recognize(
    Object handle,
    Uint8List imageBytes, {
    int maxSideLen = 960,
    bool runDetection = true,
    bool runClassification = false,
    bool runRecognition = true,
  }) {
    throw UnimplementedError('recognize() has not been implemented.');
  }

  /// Releases the native engine associated with [handle].
  Future<void> dispose(Object handle) {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}

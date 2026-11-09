import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_paddle_ocr_platform_interface.dart';
import 'src/model_source.dart';
import 'src/models.dart';

class MethodChannelFlutterPaddleOcr extends FlutterPaddleOcrPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel(_Channel.name);

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
    final paths = switch (source) {
      FilePathsModelSource s => s,
      BundledModelSource() => throw UnsupportedError(
        'ModelSource.bundled is not yet supported on Android/iOS in v0.2. '
        'Use ModelSource.filePaths(...) and supply .onnx files and a dictionary. '
        'See example/lib/main.dart for a download helper.',
      ),
    };
    final id = await methodChannel.invokeMethod<int>(_Channel.create, {
      _Channel.detModelPath: paths.det,
      _Channel.recModelPath: paths.rec,
      _Channel.clsModelPath: paths.cls ?? '',
      _Channel.labelPath: paths.dict,
      _Channel.cpuThreadNum: cpuThreadNum,
      _Channel.cpuPower: cpuPower.value,
      _Channel.useOpenCL: useOpenCL,
      _Channel.useSpaceChar: useSpaceChar,
      _Channel.useDilation: useDilation,
      _Channel.detDbThresh: detDbThresh,
      _Channel.detDbBoxThresh: detDbBoxThresh,
      _Channel.detDbUnclipRatio: detDbUnclipRatio,
    });
    return id!;
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
    final raw = await methodChannel
        .invokeListMethod<dynamic>(_Channel.recognize, {
          _Channel.instanceId: handle as int,
          _Channel.imageBytes: imageBytes,
          _Channel.maxSideLen: maxSideLen,
          _Channel.runDetection: runDetection,
          _Channel.runClassification: runClassification,
          _Channel.runRecognition: runRecognition,
        });
    return (raw ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map(OcrResult.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> dispose(Object handle) => methodChannel.invokeMethod<void>(
    _Channel.dispose,
    {_Channel.instanceId: handle as int},
  );
}

// Method + argument names shared across the Dart/Kotlin/Swift boundary. Kept
// as strings here because there's no cross-language symbol to reuse — but at
// least the Dart side is centralized. Keep in sync with
// android/src/main/kotlin/.../FlutterPaddleOcrPlugin.kt and
// ios/Classes/FlutterPaddleOcrPlugin.swift.
abstract final class _Channel {
  static const name = 'flutter_paddle_ocr';

  static const create = 'create';
  static const recognize = 'recognize';
  static const dispose = 'dispose';

  static const detModelPath = 'detModelPath';
  static const recModelPath = 'recModelPath';
  static const clsModelPath = 'clsModelPath';
  static const labelPath = 'labelPath';
  static const cpuThreadNum = 'cpuThreadNum';
  static const cpuPower = 'cpuPower';
  static const useOpenCL = 'useOpenCL';
  static const useSpaceChar = 'useSpaceChar';
  static const useDilation = 'useDilation';
  static const detDbThresh = 'detDbThresh';
  static const detDbBoxThresh = 'detDbBoxThresh';
  static const detDbUnclipRatio = 'detDbUnclipRatio';
  static const instanceId = 'instanceId';
  static const imageBytes = 'imageBytes';
  static const maxSideLen = 'maxSideLen';
  static const runDetection = 'runDetection';
  static const runClassification = 'runClassification';
  static const runRecognition = 'runRecognition';
}

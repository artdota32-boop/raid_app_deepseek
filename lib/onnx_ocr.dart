import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

class OnnxOcr {
  static List<String>? _dictionary;
  static String lastDiagnostics = '';

  // A/B TEST:
  // false = старый белый padding (режим A).
  // true  = нулевой padding после нормализации (режим B).
  static bool useZeroPadding = false;

  static Future<void> _loadDict() async {
    if (_dictionary != null) return;
    final dictStr = await rootBundle.loadString('assets/dict.txt');
    final symbols = dictStr
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    symbols.add(' ');
    _dictionary = symbols;
  }

  /// Распознаёт одно изображение. Сессия закрывается после одного вызова.
  static Future<String> recognize(Uint8List imageBytes) async {
    lastDiagnostics = '';
    try {
      await _loadDict();
      final session =
          await OnnxRuntime().createSessionFromAsset('assets/inference.onnx');
      try {
        return await _recognizeWithSession(session, imageBytes);
      } finally {
        await session.close();
      }
    } catch (e) {
      lastDiagnostics = 'ERROR: ' + e.toString();
      return 'ONNX Error: ' + e.toString();
    }
  }

  /// Пакетный диагностический запуск: одна ONNX-сессия на весь список кропов.
  /// Препроцессинг и CTC-декодирование каждого изображения остаются теми же,
  /// что и в recognize().
  static Future<List<String>> recognizeBatch(
    List<Uint8List> images,
  ) async {
    if (images.isEmpty) return <String>[];

    await _loadDict();
    final session =
        await OnnxRuntime().createSessionFromAsset('assets/inference.onnx');

    try {
      final results = <String>[];
      for (final imageBytes in images) {
        try {
          results.add(await _recognizeWithSession(session, imageBytes));
        } catch (e) {
          results.add('ONNX Error: ' + e.toString());
        }
      }
      return results;
    } finally {
      await session.close();
    }
  }

  static Future<String> _recognizeWithSession(
    OrtSession session,
    Uint8List imageBytes,
  ) async {
    // 1. Декодируем картинку.
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException('Не удалось декодировать картинку');
    }

    // 2. Инверсия (белый текст на тёмном -> чёрный на белом).
    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final p = decoded.getPixel(x, y);
        decoded.setPixelRgb(x, y, 255 - p.r, 255 - p.g, 255 - p.b);
      }
    }

    // 3. Сохраняем пропорции и добиваем белым до 320.
    final double ratio = decoded.width / decoded.height;
    int targetW = (48 * ratio).round();
    if (targetW > 320) targetW = 320;
    if (targetW < 1) targetW = 1;
    debugPrint('[ONNX WIDTH] input=${decoded.width}x${decoded.height} targetW=$targetW padding=${320 - targetW}');
    final resized = img.Image(width: targetW, height: 48);

    for (int y = 0; y < 48; y++) {
      final srcY = (((2 * y + 1) * decoded.height) ~/ (2 * 48))
          .clamp(0, decoded.height - 1)
          .toInt();

      for (int x = 0; x < targetW; x++) {
        final srcX = (((2 * x + 1) * decoded.width) ~/ (2 * targetW))
            .clamp(0, decoded.width - 1)
            .toInt();

        final p = decoded.getPixel(srcX, srcY);
        resized.setPixelRgb(x, y, p.r, p.g, p.b);
      }
    }

    final padded = img.Image(width: 320, height: 48);
    img.fill(padded, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(padded, resized, dstX: 0, dstY: 0);

    // 4. Конвертируем в тензор (BGR, CHW, нормализация [-1, 1]).
    final Float32List tensorData = Float32List(1 * 3 * 48 * 320);
    int idx = 0;
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < 48; y++) {
        for (int x = 0; x < 320; x++) {
          // Режим B: нулевой padding ПОСЛЕ нормализации.
          if (useZeroPadding && x >= targetW) {
            tensorData[idx++] = 0.0;
            continue;
          }
          final p = padded.getPixel(x, y);
          double val = 0.0;
          if (c == 0) val = p.b.toDouble();
          if (c == 1) val = p.g.toDouble();
          if (c == 2) val = p.r.toDouble();
          tensorData[idx++] = (val / 255.0 - 0.5) / 0.5;
        }
      }
    }

    debugPrint(
      'ONNX PREPROCESS PADDING: ' + (useZeroPadding ? 'ZERO' : 'WHITE'),
    );

    OrtValue? inputOrt;
    Map<String, OrtValue>? outputs;
    try {
      inputOrt = await OrtValue.fromList(tensorData, [1, 3, 48, 320]);
      outputs = await session.run({'x': inputOrt});
      if (outputs.isEmpty) {
        throw StateError('ONNX Runtime вернул пустой набор выходов');
      }

      debugPrint('ONNX OUTPUT NAMES: ' + outputs.keys.toList().toString());
      final output = outputs.values.first;
      debugPrint('ONNX OUTPUT SHAPE: ' + output.shape.toString());
      debugPrint('ONNX OUTPUT TYPE: ' + output.dataType.toString());

      final floatData = await output.asFlattenedList();
      debugPrint('ONNX OUTPUT ELEMENTS: ' + floatData.length.toString());

      lastDiagnostics = 'NAMES: ' +
          outputs.keys.toList().toString() +
          ' | SHAPE: ' +
          output.shape.toString() +
          ' | TYPE: ' +
          output.dataType.toString() +
          ' | ELEMENTS: ' +
          floatData.length.toString() +
          ' | PADDING: ' +
          (useZeroPadding ? 'ZERO' : 'WHITE');

      // 5. Упрощённый CTC greedy decoder.
      const int vocabSize = 852;
      if (floatData.isEmpty || floatData.length % vocabSize != 0) {
        throw StateError(
          'Неожиданный размер ONNX output: ' + floatData.length.toString(),
        );
      }
      final int timeSteps = floatData.length ~/ vocabSize;

      final result = StringBuffer();
      int lastIdx = -1;

      for (int t = 0; t < timeSteps; t++) {
        int bestIdx = 0;
        double maxProb = -1.0;

        for (int c = 0; c < vocabSize; c++) {
          final double prob = floatData[t * vocabSize + c];
          if (prob > maxProb) {
            maxProb = prob;
            bestIdx = c;
          }
        }

        if (bestIdx != 0 && bestIdx != lastIdx) {
          if (bestIdx >= 1 && bestIdx <= _dictionary!.length) {
            result.write(_dictionary![bestIdx - 1]);
          }
        }
        lastIdx = bestIdx;
      }

      return 'Текст: ' + result.toString();
    } finally {
      if (inputOrt != null) {
        await inputOrt.dispose();
      }
      if (outputs != null) {
        for (final tensor in outputs.values) {
          await tensor.dispose();
        }
      }
    }
  }
}

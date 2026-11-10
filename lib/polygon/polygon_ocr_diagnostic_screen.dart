import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;

import '../game_validator.dart';
import '../onnx_ocr.dart';
import '../parser.dart';

class PolygonOcrDiagnosticScreen extends StatefulWidget {
  const PolygonOcrDiagnosticScreen({super.key});

  @override
  State<PolygonOcrDiagnosticScreen> createState() =>
      _PolygonOcrDiagnosticScreenState();
}

class _OcrLine {
  final int index;
  final String text;
  final double confidence;
  final double? centerX;
  final double? centerY;
  final List<Map<String, num>> points;

  const _OcrLine({
    required this.index,
    required this.text,
    required this.confidence,
    required this.centerX,
    required this.centerY,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'text': text,
        'confidence': confidence,
        'center_x': centerX,
        'center_y': centerY,
        'points': points,
      };
}

class _PolygonOcrDiagnosticScreenState
    extends State<PolygonOcrDiagnosticScreen> {
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _jsonController = TextEditingController(
    text: '''{
  "main_stat": { "name": "SPD", "value": 26, "unit": "flat" },
  "substats": [
    { "name": "ATK", "value": 10, "unit": "percent", "glyph": 1 },
    { "name": "ACC", "value": 9, "unit": "flat" },
    { "name": "RES", "value": 28, "unit": "flat", "glyph": 2 },
    { "name": "DEF", "value": 15, "unit": "flat" }
  ],
  "set": "Speed",
  "set_bonus": "SPD +12% (2pc)",
  "type": "Boots",
  "rarity": "Legendary"
}''',
  );

  bool _busy = false;
  Uint8List? _previewBytes;
  String _sourceName = '';
  String _report = 'Выбери polygon_padded_crop.png из галереи.\n'
      'Поддерживаемые размеры: 470x358 или 1410x1074.\n'
      'Для 470x358 будет выполнено увеличение x3, как в основном приложении.';

  // Координаты заданы как (x, y, width, height) в исходной сетке 470x358.
  // Кропы соответствуют тем же областям, которые проверялись в Python compare_ocr.py.
  static const List<Map<String, Object>> _comparisonCrops = [
    {
      'id': 'MAIN_STAT',
      'x': 65,
      'y': 86,
      'w': 180,
      'h': 32,
      'expected': 'Скр 26'
    },
    {
      'id': 'ATK_LABEL',
      'x': 30,
      'y': 110,
      'w': 105,
      'h': 29,
      'expected': 'Атк(1)'
    },
    {
      'id': 'ATK_VALUE',
      'x': 175,
      'y': 110,
      'w': 80,
      'h': 29,
      'expected': '10%'
    },
    {
      'id': 'ACCURACY_LABEL',
      'x': 30,
      'y': 132,
      'w': 105,
      'h': 29,
      'expected': 'Метк'
    },
    {
      'id': 'ACCURACY_VALUE',
      'x': 175,
      'y': 132,
      'w': 80,
      'h': 29,
      'expected': '9'
    },
    {
      'id': 'RES_LABEL',
      'x': 30,
      'y': 154,
      'w': 105,
      'h': 29,
      'expected': 'Сопр(2)'
    },
    {'id': 'RES_VALUE', 'x': 175, 'y': 154, 'w': 80, 'h': 29, 'expected': '28'},
    {
      'id': 'DEF_LABEL',
      'x': 30,
      'y': 176,
      'w': 105,
      'h': 29,
      'expected': 'Зщт'
    },
    {'id': 'DEF_VALUE', 'x': 175, 'y': 176, 'w': 80, 'h': 29, 'expected': '15'},
    {
      'id': 'SET_BONUS',
      'x': 20,
      'y': 275,
      'w': 170,
      'h': 39,
      'expected': 'Скорость +12%'
    },
  ];

  static const Map<String, List<String>> _statAliases = {
    'speed': ['speed', 'Скорость', 'Скр', 'SPD', 'Speed'],
    'attack': ['attack', 'Атк', 'Атака', 'ATK', 'Attack'],
    'accuracy': ['accuracy', 'Метк', 'Точность', 'ACC', 'Accuracy'],
    'resistance': ['resistance', 'Сопр', 'Сопротивление', 'RES', 'Resistance'],
    'defense': ['defense', 'Зщт', 'Защита', 'DEF', 'Defense'],
    'hp': ['hp', 'Здр', 'Здоровье', 'HP', 'Health'],
    'crit_rate': [
      'crit_rate',
      'Крит. ш',
      'Крит. шанс',
      'C.RATE',
      'C RATE',
      'CRATE'
    ],
    'crit_dmg': [
      'crit_dmg',
      'Крит. ур',
      'Крит. урон',
      'C.DMG',
      'C DMG',
      'CDMG'
    ],
  };

  static String _norm(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^0-9a-zа-яё%+]'), '');
  }

  static String _canonicalStat(String value) {
    final normalized = _norm(value);
    for (final entry in _statAliases.entries) {
      for (final alias in entry.value) {
        if (normalized == _norm(alias)) return entry.key;
      }
    }
    return normalized;
  }

  static bool _hasExactNumber(String text, int expected) {
    final matches = RegExp(r'\d+').allMatches(text);
    return matches
        .any((match) => int.tryParse(match.group(0) ?? '') == expected);
  }

  static bool _lineHasLabel(String text, String statKey) {
    final normalized = _norm(text);
    final aliases = _statAliases[statKey] ?? const <String>[];
    return aliases.any((alias) => normalized.contains(_norm(alias)));
  }

  static String _rawDiagnosis(
    List<_OcrLine> lines,
    String statKey,
    int expectedValue,
  ) {
    final labelLines =
        lines.where((line) => _lineHasLabel(line.text, statKey)).toList();
    final valueLines = lines
        .where((line) => _hasExactNumber(line.text, expectedValue))
        .toList();

    for (final labelLine in labelLines) {
      if (_hasExactNumber(labelLine.text, expectedValue)) {
        return 'OCR уже выдал название и значение в одном блоке. '
            'Вероятнее всего, проверь правила Parser и координаты OCR-блоков.';
      }
      for (final valueLine in valueLines) {
        if (labelLine.centerY != null &&
            valueLine.centerY != null &&
            (labelLine.centerY! - valueLine.centerY!).abs() <=
                ArtifactParser.yThreshold &&
            (labelLine.centerX == null ||
                valueLine.centerX == null ||
                valueLine.centerX! >= labelLine.centerX! - 10)) {
          return 'OCR нашёл название и число на одной строке. '
              'Проверь связывание блоков и порог yThreshold в Parser.';
        }
      }
    }

    if (labelLines.isNotEmpty && valueLines.isEmpty) {
      return 'OCR видит название характеристики, но ожидаемое число не найдено. '
          'Проверь распознавание цифр и качество входного кропа.';
    }
    if (labelLines.isEmpty && valueLines.isNotEmpty) {
      return 'Ожидаемое число встречается в OCR, но название характеристики не найдено. '
          'Проверь распознавание текста и входной кроп.';
    }
    if (labelLines.isNotEmpty && valueLines.isNotEmpty) {
      return 'Название и число встречаются в OCR, но не образуют подтверждённую пару. '
          'Нужна проверка OCR-блоков и координат.';
    }
    return 'Ожидаемая пара не обнаружена в сырых OCR-блоках. '
        'Сначала проверь содержимое кропа и качество распознавания.';
  }

  static Map<String, List<int>> _intListMap(dynamic value) {
    final output = <String, List<int>>{};
    if (value is! Map) return output;

    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! Iterable) continue;
      final numbers = (entry.value as Iterable)
          .whereType<num>()
          .map((number) => number.toInt())
          .toList();
      output[entry.key as String] = numbers;
    }
    return output;
  }

  static List<int> _valuesFor(
    List<Map<String, List<int>>> maps,
    String statKey,
  ) {
    final values = <int>[];
    for (final map in maps) {
      for (final entry in map.entries) {
        if (_canonicalStat(entry.key) == statKey) {
          values.addAll(entry.value);
        }
      }
    }
    return values;
  }

  Future<void> _runEngineComparison() async {
    final temporaryFiles = <File>[];
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      if (mounted) {
        setState(() {
          _busy = true;
          _sourceName = picked.name;
          _report = 'Готовлю десять одинаковых кропов для PaddleOCR и ONNX...';
        });
      }

      final sourceBytes = await picked.readAsBytes();
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        throw const FormatException(
            'Не удалось декодировать выбранное изображение.');
      }

      final int scale;
      if (decoded.width == 470 && decoded.height == 358) {
        scale = 1;
      } else if (decoded.width == 1410 && decoded.height == 1074) {
        scale = 3;
      } else {
        throw FormatException(
          'Неподдерживаемый размер: ' +
              decoded.width.toString() +
              'x' +
              decoded.height.toString() +
              '. Нужен 470x358 или 1410x1074.',
        );
      }

      final cropBytes = <Uint8List>[];
      for (final crop in _comparisonCrops) {
        final int x = (crop['x'] as int) * scale;
        final int y = (crop['y'] as int) * scale;
        final int width = (crop['w'] as int) * scale;
        final int height = (crop['h'] as int) * scale;

        final cropped = img.copyCrop(
          decoded,
          x: x,
          y: y,
          width: width,
          height: height,
        );
        final bytes = Uint8List.fromList(img.encodePng(cropped));
        cropBytes.add(bytes);

        final id = (crop['id'] as String).toLowerCase();
        final file = File(
          Directory.systemTemp.path + '/raid_engine_compare_' + id + '.png',
        );
        await file.writeAsBytes(bytes, flush: true);
        temporaryFiles.add(file);
      }

      if (mounted) {
        setState(() {
          _previewBytes = sourceBytes;
          _report = 'Кропы подготовлены из ' +
              decoded.width.toString() +
              'x' +
              decoded.height.toString() +
              ' (scale=' +
              scale.toString() +
              '). Запускаю ONNX...';
        });
      }

      final onnxWatch = Stopwatch()..start();
      final onnxResults = await OnnxOcr.recognizeBatch(cropBytes);
      onnxWatch.stop();

      final paddle = pn.PaddleOcr();
      var paddleInitialized = false;
      final paddleResults = <String>[];
      final paddleTimings = <String>[];
      var paddleInitMs = 0;
      var paddleTotalMs = 0;

      try {
        final initWatch = Stopwatch()..start();
        await paddle.init(
          config: const pn.PaddleOcrConfig(),
          engine: const pn.EngineConfig(numThreads: 4),
        );
        initWatch.stop();
        paddleInitMs = initWatch.elapsedMilliseconds;
        paddleInitialized = true;

        final paddleWatch = Stopwatch()..start();
        for (var i = 0; i < temporaryFiles.length; i++) {
          try {
            final run = await paddle.recognize(temporaryFiles[i].path);
            final text = run.results
                .map((region) => region.text.trim())
                .where((value) => value.isNotEmpty)
                .join(' | ');
            paddleResults.add(text.isEmpty ? '<нет текстовых областей>' : text);
            paddleTimings.add(
              'det=' +
                  run.detectionTimeMs.toString() +
                  'ms, rec=' +
                  run.recognitionTimeMs.toString() +
                  'ms',
            );
          } catch (error) {
            paddleResults.add('Paddle ERROR: ' + error.toString());
            paddleTimings.add('ошибка вызова');
          }
        }
        paddleWatch.stop();
        paddleTotalMs = paddleWatch.elapsedMilliseconds;
      } finally {
        if (paddleInitialized) {
          try {
            await paddle.dispose();
          } catch (_) {
            // Не затираем диагностический отчёт ошибкой native dispose.
          }
        }
      }

      final report = StringBuffer()
        ..writeln('RAID SCANNER — PADDLEOCR vs ONNX / CROP TEST')
        ..writeln('SOURCE: ' + picked.name)
        ..writeln(
          'IMAGE: ' +
              decoded.width.toString() +
              'x' +
              decoded.height.toString() +
              '; crop coordinate scale=' +
              scale.toString(),
        )
        ..writeln('CROPS: ' + cropBytes.length.toString())
        ..writeln(
          'ONNX TOTAL: session init + ' +
              cropBytes.length.toString() +
              ' inferences + session close = ' +
              onnxWatch.elapsedMilliseconds.toString() +
              ' ms',
        )
        ..writeln(
          'PADDLE: init=' +
              paddleInitMs.toString() +
              ' ms; ' +
              cropBytes.length.toString() +
              ' detect+recognize calls=' +
              paddleTotalMs.toString() +
              ' ms',
        )
        ..writeln('')
        ..writeln(
            'RESULTS (same PNG crop bytes are supplied to both engines):');

      for (var i = 0; i < _comparisonCrops.length; i++) {
        final crop = _comparisonCrops[i];
        final id = crop['id'] as String;
        final expected = crop['expected'] as String;
        final onnxText = i < onnxResults.length
            ? onnxResults[i].replaceFirst(RegExp(r'^Текст:\s*'), '')
            : '<нет результата ONNX>';
        final paddleText = i < paddleResults.length
            ? paddleResults[i]
            : '<нет результата PaddleOCR>';
        final paddleTiming = i < paddleTimings.length ? paddleTimings[i] : '';

        report
          ..writeln('')
          ..writeln('[' + id + '] expected: ' + expected)
          ..writeln('  ONNX:   ' + onnxText)
          ..writeln('  Paddle: ' + paddleText + ' (' + paddleTiming + ')');
      }

      report
        ..writeln('')
        ..writeln('METHOD NOTES:')
        ..writeln(
          '- ONNX uses the existing preprocessing, model, dictionary and CTC decoder.',
        )
        ..writeln(
          '- One ONNX session is reused for all ten crops; input/output tensors are disposed after each inference.',
        )
        ..writeln(
          '- PaddleOCR receives the exact same PNG crop bytes, but recognize() runs its detector and recognizer on each crop.',
        )
        ..writeln(
          '- Therefore this is an end-to-end crop comparison, not a pure recognition-only benchmark. A tiny or partial crop may be rejected by the Paddle detector before recognition.',
        )
        ..writeln(
          '- Crop coordinates are based on 470x358. For a 1410x1074 input they are multiplied by 3.',
        );

      if (mounted) setState(() => _report = report.toString());
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _report = 'ENGINE COMPARISON ERROR\n' +
              error.toString() +
              '\n\n' +
              stackTrace.toString();
        });
      }
    } finally {
      for (final file in temporaryFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Temporary files are diagnostic only; cleanup failure is non-fatal.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runGoldenTest() async {
    try {
      Map<String, dynamic> expectedJson;
      try {
        final decoded = jsonDecode(_jsonController.text);
        if (decoded is! Map) {
          throw const FormatException("Корень JSON должен быть объектом.");
        }
        expectedJson = Map<String, dynamic>.from(decoded);

        if (expectedJson.isEmpty) {
          throw const FormatException("JSON не должен быть пустым.");
        }

        final main = expectedJson["main_stat"];
        if (main != null) {
          if (main is! Map ||
              main["name"] is! String ||
              main["value"] is! num ||
              !["flat", "percent"].contains(main["unit"])) {
            throw const FormatException(
              "main_stat: нужны name, числовой value и unit flat/percent.",
            );
          }
        }

        final subs = expectedJson["substats"];
        if (subs != null) {
          if (subs is! List) {
            throw const FormatException("substats должен быть списком.");
          }
          for (final item in subs) {
            if (item is! Map ||
                item["name"] is! String ||
                item["value"] is! num ||
                !["flat", "percent"].contains(item["unit"])) {
              throw const FormatException(
                "Каждый substat должен содержать name, value и unit flat/percent.",
              );
            }
            if (item["glyph"] != null && item["glyph"] is! num) {
              throw const FormatException("glyph должен быть числом.");
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _report = "ОШИБКА JSON: $e");
        }
        return;
      }

      // Загружаем базу комплектов для сравнения по ID
      await ArtifactParser.loadSetsDb();

      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() {
        _busy = true;
        _sourceName = picked.name;
        _report = 'Загружаю изображение и готовлю вход PaddleOCR...';
      });

      final sourceBytes = await picked.readAsBytes();
      final decoded = img.decodeImage(sourceBytes);
      if (decoded == null) {
        throw const FormatException(
            'Не удалось декодировать выбранное изображение.');
      }

      final sourceWidth = decoded.width;
      final sourceHeight = decoded.height;
      late img.Image ocrImage;

      if (sourceWidth == 470 && sourceHeight == 358) {
        ocrImage = img.copyResize(
          decoded,
          width: 1410,
          height: 1074,
          interpolation: img.Interpolation.nearest,
        );
      } else if (sourceWidth == 1410 && sourceHeight == 1074) {
        ocrImage = decoded;
      } else {
        throw FormatException(
          'Неподдерживаемый размер изображения: ' +
              sourceWidth.toString() +
              'x' +
              sourceHeight.toString() +
              '. Ожидается 470x358 или 1410x1074.',
        );
      }

      final ocrBytes = Uint8List.fromList(
        img.encodeJpg(ocrImage, quality: 95),
      );
      final ocrFile = File(
        Directory.systemTemp.path + '/raid_speed_ru_golden_ocr.jpg',
      );
      await ocrFile.writeAsBytes(ocrBytes, flush: true);

      if (mounted) {
        setState(() {
          _previewBytes = sourceBytes;
          _report = 'Вход готов: ' +
              sourceWidth.toString() +
              'x' +
              sourceHeight.toString() +
              ' -> ' +
              ocrImage.width.toString() +
              'x' +
              ocrImage.height.toString() +
              ' JPEG quality=95.\nЗапускаю PaddleOCR...';
        });
      }

      await ArtifactParser.loadPrefs();
      ArtifactParser.setsLog.clear();

      final ocr = pn.PaddleOcr();
      var initialized = false;

      try {
        await ocr.init(
          config: const pn.PaddleOcrConfig(),
          engine: const pn.EngineConfig(numThreads: 4),
        );
        initialized = true;

        final run = await ocr.recognize(ocrFile.path);
        final results = run.results;

        final lines = <_OcrLine>[];
        for (var i = 0; i < results.length; i++) {
          final region = results[i];
          final List<Map<String, num>> points = region.points
              .map((point) => <String, num>{
                    'x': point.x,
                    'y': point.y,
                  })
              .toList();

          final xs = region.points.map((point) => point.x.toDouble()).toList();
          final ys = region.points.map((point) => point.y.toDouble()).toList();

          final centerX =
              xs.isEmpty ? null : (xs.reduce((a, b) => a + b) / xs.length);
          final centerY =
              ys.isEmpty ? null : (ys.reduce((a, b) => a + b) / ys.length);

          lines.add(
            _OcrLine(
              index: i,
              text: region.text,
              confidence: region.confidence,
              centerX: centerX,
              centerY: centerY,
              points: points,
            ),
          );
        }

        final parsed = ArtifactParser.parse(results);
        final validationNotes = GameValidator.validate(parsed);

        final stats = _intListMap(parsed['stats']);
        final percentStats = _intListMap(parsed['stats_percent']);
        final dopStats = _intListMap(parsed['dop_stats']);
        final glyphs = _intListMap(parsed['glyphs']);

        final mainStat = parsed['main_stat'] is Map
            ? parsed['main_stat'] as Map
            : const <String, dynamic>{};
        final mainName = mainStat['name']?.toString() ?? '';
        final mainValue = mainStat['value'];
        final mainIsPercent = mainStat['isPercent'] == true;

        final checks = <Map<String, dynamic>>[];

        void addCheck(
          String label,
          String expected,
          String actual,
          bool passed, {
          String? statKey,
          int? rawValue,
        }) {
          checks.add({
            'field': label,
            'expected': expected,
            'actual': actual,
            'status': passed ? 'OK' : 'FAIL',
            'diagnosis': passed
                ? null
                : statKey != null && rawValue != null
                    ? _rawDiagnosis(lines, statKey, rawValue)
                    : 'Смотри сырые OCR-блоки: если нужное слово там есть, '
                        'проверяй правила выбора и разбора Parser; если нет — '
                        'проверяй кроп и OCR.',
          });
        }

        String? _resolveSetId(String value) {
          final normalized = _norm(value);
          if (normalized.isEmpty) return null;

          final rawSets = ArtifactParser.setsDb['sets'];
          if (rawSets is! List) return null;

          final matches = <String>{};

          for (final rawSet in rawSets) {
            if (rawSet is! Map) continue;

            final id = _norm(rawSet['id']?.toString() ?? '');
            if (id.isEmpty) continue;

            final candidates = <String>{
              id,
              _norm(rawSet['name_en']?.toString() ?? ''),
              _norm(rawSet['name_ru']?.toString() ?? ''),
            };

            if (candidates.contains(normalized)) {
              matches.add(id);
            }
          }

          return matches.length == 1 ? matches.single : null;
        }

        String _localizeTextField(String key, String value) {
          final v = _norm(value);
          if (v.isEmpty) return v;

          if (key == "type") {
            if (v.contains("boot") || v.contains("сапог")) return "boots";
            if (v.contains("helmet") || v.contains("шлем")) return "helmet";
            if (v.contains("chestplate") ||
                v.contains("chest") ||
                v.contains("доспех") ||
                v.contains("броня")) return "chest";
            if (v.contains("glove") ||
                v.contains("gauntlet") ||
                v.contains("перчат") ||
                v.contains("рукавиц")) return "gloves";
            if (v.contains("weapon") || v.contains("оруж")) return "weapon";
            if (v.contains("shield") || v.contains("щит")) return "shield";
            if (v.contains("ring") || v.contains("кольцо")) return "ring";
            if (v.contains("amulet") || v.contains("амулет")) return "amulet";
            if (v.contains("banner") || v.contains("знамя")) return "banner";
          }

          if (key == "rarity") {
            if (v.contains("legend") || v.contains("легендар"))
              return "legendary";
            if (v.contains("epic") || v.contains("эпич")) return "epic";
            if (v.contains("rare") || v.contains("редк")) return "rare";
            if (v.contains("common") || v.contains("обычн")) return "common";
            if (v.contains("myth") || v.contains("мифич")) return "mythical";
          }

          return v;
        }

        void compareTextField(String key, String label) {
          if (!expectedJson.containsKey(key)) return;

          final expectedValue = expectedJson[key].toString();
          final actual = parsed[key]?.toString() ?? "";

          if (key == "set") {
            final wantedId = expectedJson.containsKey("set_id")
                ? _resolveSetId(expectedJson["set_id"].toString())
                : _resolveSetId(expectedValue);

            final actualId = parsed["set_id"]?.toString();
            final gotId = actualId == null ? null : _resolveSetId(actualId);

            final passed =
                wantedId != null && gotId != null && wantedId == gotId;

            final expectedDisplay = wantedId == null
                ? "$expectedValue (ID не определён или неоднозначно)"
                : "$expectedValue [$wantedId]";

            final actualDisplay = actual.isEmpty
                ? "не найдено"
                : actualId == null
                    ? "$actual (ID не найден)"
                    : "$actual [$actualId]";

            addCheck(label, expectedDisplay, actualDisplay, passed);
            return;
          }

          final wanted = _localizeTextField(key, expectedValue);
          final got = _localizeTextField(key, actual);
          final passed =
              wanted.isNotEmpty && actual.isNotEmpty && got == wanted;

          addCheck(
            label,
            expectedValue,
            actual.isEmpty ? "не найдено" : actual,
            passed,
          );
        }

        final expectedMain = expectedJson["main_stat"];
        if (expectedMain is Map) {
          final wantedName = _canonicalStat(expectedMain["name"].toString());
          final wantedValue = (expectedMain["value"] as num).toInt();
          final wantedPercent = expectedMain["unit"] == "percent";
          final mainPassed = _canonicalStat(mainName) == wantedName &&
              mainValue is num &&
              mainValue.toInt() == wantedValue &&
              mainIsPercent == wantedPercent;

          addCheck(
            "Главный стат",
            "${expectedMain["name"]} $wantedValue${wantedPercent ? "%" : ""}",
            mainName.isEmpty
                ? "не найден"
                : "$mainName ${mainValue ?? "?"}${mainIsPercent ? "%" : ""}",
            mainPassed,
            statKey: wantedName,
            rawValue: wantedValue,
          );
        }

        final expectedSubs = expectedJson["substats"];
        if (expectedSubs is List) {
          for (final item in expectedSubs) {
            final name = item["name"].toString();
            final key = _canonicalStat(name);
            final value = (item["value"] as num).toInt();
            final percent = item["unit"] == "percent";

            final sourceMaps = percent ? [percentStats] : [stats, dopStats];

            final values = _valuesFor(sourceMaps, key);
            final passed = values.contains(value);

            addCheck(
              "Доп. стат $name",
              "$value${percent ? "%" : ""}",
              values.isEmpty
                  ? "не найден"
                  : values.join(", ") + (percent ? "%" : ""),
              passed,
              statKey: key,
              rawValue: value,
            );

            if (item["glyph"] != null) {
              final glyphValue = (item["glyph"] as num).toInt();
              final glyphValues = _valuesFor([glyphs], key);

              addCheck(
                "Глиф $name",
                "+$glyphValue",
                glyphValues.isEmpty
                    ? "не найден"
                    : "+" + glyphValues.join(", +"),
                glyphValues.contains(glyphValue),
                statKey: key,
                rawValue: glyphValue,
              );
            }
          }
        }

        compareTextField("set", "Комплект");

        if (expectedJson.containsKey("set_bonus")) {
          final actual = parsed["set_bonus"]?.toString() ?? "";

          List<String> normalizeBonusTokens(String s) {
            var res = s.toLowerCase();
            res = res.replaceAll(RegExp(r"\bspd\b|скорост"), "speed");
            res = res.replaceAll(RegExp(r"\batk\b|атак"), "attack");
            res = res.replaceAll(RegExp(r"\bdef\b|защит"), "defense");
            res = res.replaceAll(RegExp(r"\bres\b|сопр"), "resistance");
            res = res.replaceAll(RegExp(r"\bacc\b|метк|точност"), "accuracy");
            res = res.replaceAll(RegExp(r"\bhp\b|здоров"), "hp");
            res = res.replaceAll(
                RegExp(r"\bc\s*\.?\s*rate\b|\bc\.?\s*rat\b|крит\.\s*ш"),
                "crit_rate");
            res = res.replaceAll(
                RegExp(r"\bc\s*\.?\s*dmg\b|\bcdmg\b|крит\.\s*ур"), "crit_dmg");
            return res
                .split(RegExp(r"[^a-z0-9%]+"))
                .where((v) => v.isNotEmpty)
                .toList();
          }

          final expTokens =
              normalizeBonusTokens(expectedJson["set_bonus"].toString());
          final actTokens = normalizeBonusTokens(actual);
          // Все значимые токены из эталона должны быть в результате
          final passed = expTokens.isNotEmpty &&
              actual.isNotEmpty &&
              expTokens.every((t) => actTokens.contains(t));

          addCheck(
            "Бонус комплекта",
            expectedJson["set_bonus"].toString(),
            actual.isEmpty ? "не найден" : actual,
            passed,
          );
        }

        compareTextField("type", "Тип предмета");
        compareTextField("rarity", "Редкость");

        if (checks.isEmpty) {
          throw const FormatException(
            "В JSON нет полей для сравнения с результатом Parser.",
          );
        }

        final passedCount =
            checks.where((check) => check['status'] == 'OK').length;
        final allPassed = passedCount == checks.length;
        final rawText = lines.map((line) => line.text).join('\n');

        final reportData = <String, dynamic>{
          'test_case': 'custom_golden',
          'source_image': {
            'name': picked.name,
            'width': sourceWidth,
            'height': sourceHeight,
            'bytes': sourceBytes.length,
          },
          'ocr_input': {
            'path': ocrFile.path,
            'width': ocrImage.width,
            'height': ocrImage.height,
            'format': 'JPEG',
            'quality': 95,
            'bytes': ocrBytes.length,
          },
          'ocr_timing_ms': {
            'detection': run.detectionTimeMs,
            'recognition': run.recognitionTimeMs,
          },
          'ocr_regions': lines.map((line) => line.toJson()).toList(),
          'ocr_text': rawText,
          'parser_settings': {
            'y_threshold': ArtifactParser.yThreshold,
            'x_split': ArtifactParser.xSplit,
            'y_max_for_set': ArtifactParser.yMaxForSet,
            'y_min_for_stats': ArtifactParser.yMinForStats,
            'is_main_stat_y1': ArtifactParser.isMainStatY1,
            'is_main_stat_y2': ArtifactParser.isMainStatY2,
            'is_main_stat_x1': ArtifactParser.isMainStatX1,
            'is_main_stat_x2': ArtifactParser.isMainStatX2,
            'set_desc_cy': ArtifactParser.setDescCy,
            'x_max_for_set': ArtifactParser.xMaxForSet,
          },
          'parsed': parsed,
          'structural_validation': {
            'passed': validationNotes.isEmpty,
            'notes': validationNotes,
          },
          'golden_comparison': {
            'passed': allPassed,
            'passed_count': passedCount,
            'total_count': checks.length,
            'checks': checks,
          },
        };

        final report = StringBuffer()
          ..writeln('RAID SCANNER — CUSTOM GOLDEN TEST')
          ..writeln('RESULT: ' + (allPassed ? 'PASS' : 'FAIL'))
          ..writeln('SOURCE: ' + picked.name)
          ..writeln(
            'IMAGE: ' +
                sourceWidth.toString() +
                'x' +
                sourceHeight.toString() +
                ' -> ' +
                ocrImage.width.toString() +
                'x' +
                ocrImage.height.toString() +
                ' JPEG q95',
          )
          ..writeln(
            'OCR TIME: detection=' +
                run.detectionTimeMs.toString() +
                'ms, recognition=' +
                run.recognitionTimeMs.toString() +
                'ms',
          )
          ..writeln('OCR REGIONS: ' + lines.length.toString())
          ..writeln('')
          ..writeln('RAW OCR:');

        if (lines.isEmpty) {
          report.writeln('  <no text regions>');
        } else {
          for (final line in lines) {
            report.writeln(
              '  [' +
                  line.index.toString() +
                  '] conf=' +
                  line.confidence.toStringAsFixed(3) +
                  ' center=(' +
                  (line.centerX?.toStringAsFixed(1) ?? '?') +
                  ',' +
                  (line.centerY?.toStringAsFixed(1) ?? '?') +
                  ') text=' +
                  line.text,
            );
          }
        }

        report
          ..writeln('')
          ..writeln('PARSER RESULT:')
          ..writeln(const JsonEncoder.withIndent('  ').convert(parsed))
          ..writeln('')
          ..writeln('STRUCTURAL VALIDATION: ' +
              (validationNotes.isEmpty ? 'OK' : 'NOT OK'));

        if (validationNotes.isEmpty) {
          report.writeln('  No structural issues.');
        } else {
          for (final note in validationNotes) {
            report.writeln('  - ' + note);
          }
        }

        report
          ..writeln('')
          ..writeln('GOLDEN COMPARISON: ' +
              passedCount.toString() +
              '/' +
              checks.length.toString() +
              ' OK');

        for (final check in checks) {
          report.writeln(
            '[' +
                check['status'].toString() +
                '] ' +
                check['field'].toString() +
                ': expected=' +
                check['expected'].toString() +
                '; actual=' +
                check['actual'].toString(),
          );
          if (check['diagnosis'] != null) {
            report.writeln('    WHY: ' + check['diagnosis'].toString());
          }
        }

        report
          ..writeln('')
          ..writeln('MACHINE-READABLE REPORT:')
          ..writeln(const JsonEncoder.withIndent('  ').convert(reportData));

        if (mounted) {
          setState(() => _report = report.toString());
        }
      } finally {
        if (initialized) {
          try {
            await ocr.dispose();
          } catch (_) {
            // Preserve the OCR/parser report if native disposal fails.
          }
        }
      }
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _report = 'TEST ERROR\n' +
              error.toString() +
              '\n\n' +
              stackTrace.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Эталонный OCR-тест'),
        actions: [
          IconButton(
            tooltip: 'Скопировать отчёт',
            onPressed: _report.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _report));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Отчёт скопирован')),
                    );
                  },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _runGoldenTest,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner),
                label: Text(
                  _busy
                      ? 'Выполняется OCR + Parser...'
                      : 'Выбрать polygon_padded_crop.png и запустить',
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _runEngineComparison,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Сравнить PaddleOCR и ONNX на 10 кропах'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _jsonController,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              decoration: const InputDecoration(
                labelText: 'Эталонный JSON',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ),
          if (_sourceName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Файл: ' + _sourceName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_previewBytes != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.memory(
                _previewBytes!,
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _report,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

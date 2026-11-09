// Тест нормальной шмотки (Perception)
// Запуск: dart run test_perception.dart

class FakeOcrResult {
  final String text;
  final List<FakePoint> points;
  FakeOcrResult({required this.text, required this.points});
}

class FakePoint {
  final double x;
  final double y;
  FakePoint({required this.x, required this.y});
}

class TestParser {
  static double isMainStatY1 = 250.0;
  static double isMainStatY2 = 340.0;
  static double xSplit = 250.0;

  static double _centerY(FakeOcrResult r) {
    final ys = r.points.map((p) => p.y).toList();
    return (ys.reduce((a, b) => a < b ? a : b) + ys.reduce((a, b) => a > b ? a : b)) / 2;
  }

  static double _centerX(FakeOcrResult r) {
    final xs = r.points.map((p) => p.x).toList();
    return (xs.reduce((a, b) => a < b ? a : b) + xs.reduce((a, b) => a > b ? a : b)) / 2;
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> blocks) {
    final main = <String, dynamic>{};
    final dop = <String, dynamic>{};
    final glyphs = <String, dynamic>{};

    for (final r in blocks) {
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = r.text;

      // 🔥 Логика для глифов (как в реальном парсере)
      if (text.contains('+') && text.contains('%')) {
        final parts = text.split('+');
        if (parts.length == 2) {
          glyphs['GLYPH'] = parts[1].replaceAll('%', '');
          continue;
        }
      }

      // Проверка зоны MAIN
      if (cy > isMainStatY1 && cy < isMainStatY2) {
        final val = RegExp(r'\d+').firstMatch(text);
        if (val != null) {
          main['MAIN_STAT'] = val.group(0);
        }
      } else if (cx >= xSplit) {
        final val = RegExp(r'\d+').firstMatch(text);
        if (val != null) {
          dop['DOP_STAT'] = val.group(0);
        }
      }
    }
    return {'main': main, 'dop': dop, 'glyphs': glyphs};
  }
}

void main() {
  print('=== ТЕСТ PERCEPTION ===');

  // Данные, которые OCR прочитал с Perception
  final perception = [
    FakeOcrResult(text: "C. RATE 60%", points: [FakePoint(x: 356, y: 273), FakePoint(x: 709, y: 332)]),
    FakeOcrResult(text: "DEF", points: [FakePoint(x: 124, y: 342), FakePoint(x: 243, y: 406)]),
    FakeOcrResult(text: "6%+4%", points: [FakePoint(x: 578, y: 344), FakePoint(x: 788, y: 408)]),
    FakeOcrResult(text: "DEF", points: [FakePoint(x: 122, y: 406), FakePoint(x: 244, y: 473)]),
    FakeOcrResult(text: "23", points: [FakePoint(x: 575, y: 407), FakePoint(x: 662, y: 472)]),
    FakeOcrResult(text: "SPD(3)", points: [FakePoint(x: 120, y: 468), FakePoint(x: 327, y: 543)]),
    FakeOcrResult(text: "23+5", points: [FakePoint(x: 575, y: 469), FakePoint(x: 735, y: 536)]),
    FakeOcrResult(text: "ATK", points: [FakePoint(x: 121, y: 534), FakePoint(x: 253, y: 600)]),
    FakeOcrResult(text: "6%", points: [FakePoint(x: 575, y: 533), FakePoint(x: 674, y: 602)]),
  ];

  final res = TestParser.parse(perception);

  print('MAIN: ${res['main']}');
  print('DOP: ${res['dop']}');
  print('GLYPHS: ${res['glyphs']}');

  // Проверка, что MAIN правильный
  if (res['main']['MAIN_STAT'] == '60') {
    print('[✅] MAIN правильный (C.RATE 60%)');
  } else {
    print('[❌] MAIN не найден!');
  }
}

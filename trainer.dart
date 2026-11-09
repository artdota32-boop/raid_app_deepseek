// ТРЕНАЖЕР RAID SCANNER v2.0 (Серьезная проверка)
// Запуск: dart run trainer.dart

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
  // Настройки (должны совпадать с реальными)
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

  // Проверка на два числа (как в Protection)
  static bool _isStatWithTwoNumbers(String text) {
    // Ищем два числа в одной строке
    final matches = RegExp(r'\d+').allMatches(text).toList();
    return matches.length >= 2;
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> blocks) {
    final main = <String, dynamic>{};
    final dop = <String, dynamic>{};
    final debugLog = <String>[];

    for (final r in blocks) {
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = r.text;

      debugLog.add('[ZONE] text="$text" cx=${cx.toStringAsFixed(0)} cy=${cy.toStringAsFixed(0)}');

      // 🔥 ПРОВЕРКА НА PROTECTION (два числа в строке)
      if (_isStatWithTwoNumbers(text)) {
        debugLog.add('[ITER] TWO-NUM: $text');
        final nums = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!)).toList();
        if (nums.length >= 2) {
          main['ATK'] = nums[0];
          dop['ATK_GLYPH'] = nums[1];
        }
        continue;
      }

      // Проверка зоны MAIN
      if (cy > isMainStatY1 && cy < isMainStatY2) {
        final val = RegExp(r'\d+').firstMatch(text);
        if (val != null) {
          main['STAT'] = val.group(0);
          debugLog.add('[ITER] MAIN-STAT: $text');
        }
      } else if (cx >= xSplit) {
        final val = RegExp(r'\d+').firstMatch(text);
        if (val != null) {
          dop['STAT'] = val.group(0);
          debugLog.add('[ITER] DOP-STAT: $text');
        }
      }
    }

    return {'main': main, 'dop': dop, 'log': debugLog};
  }
}

void main() {
  print('=== ТРЕНАЖЕР RAID SCANNER v2.0 ===');

  bool allOk = true;

  // --- ТЕСТ 1: Perception (нормальная шмотка) ---
  print('\n--- ТЕСТ 1: Perception ---');
  final perception = [
    FakeOcrResult(text: "C. RATE 60%", points: [FakePoint(x: 356, y: 273), FakePoint(x: 709, y: 332)]),
    FakeOcrResult(text: "DEF 6%+4%", points: [FakePoint(x: 578, y: 344), FakePoint(x: 788, y: 408)]),
    FakeOcrResult(text: "SPD 23+5", points: [FakePoint(x: 575, y: 469), FakePoint(x: 735, y: 536)]),
  ];
  final res1 = TestParser.parse(perception);
  print('MAIN: ${res1['main']}');
  print('DOP: ${res1['dop']}');
  
  if (res1['main']['STAT'] == '60') {
    print('[✅] Perception: MAIN найден (C.RATE 60%)');
  } else {
    print('[❌] Perception: MAIN не найден!');
    allOk = false;
  }

  // --- ТЕСТ 2: Protection (проблемная шмотка) ---
  print('\n--- ТЕСТ 2: Protection ---');
  final protection = [
    FakeOcrResult(text: "ATK 143 ATK 11", points: [FakePoint(x: 356, y: 274), FakePoint(x: 860, y: 330)]),
    FakeOcrResult(text: "HP 378", points: [FakePoint(x: 124, y: 343), FakePoint(x: 696, y: 408)]),
    FakeOcrResult(text: "SPD(2) 13", points: [FakePoint(x: 120, y: 468), FakePoint(x: 664, y: 544)]),
  ];
  final res2 = TestParser.parse(protection);
  print('MAIN: ${res2['main']}');
  print('DOP: ${res2['dop']}');

  if (res2['main']['ATK'] == 143) {
    print('[✅] Protection: MAIN найден (ATK 143)');
  } else {
    print('[❌] Protection: MAIN не найден! (Пустой или не тот)');
    allOk = false;
  }
  if (res2['dop']['ATK_GLYPH'] == 11) {
    print('[✅] Protection: Глиф найден (ATK 11)');
  } else {
    print('[❌] Protection: Глиф ATK 11 потерян!');
    allOk = false;
  }

  // --- ИТОГ ---
  print('\n=== ПРОВЕРКА ПЕРЕД СБОРОЙ ===');
  if (allOk) {
    print('[✅] Все тесты пройдены! Можно пушить и собирать APK.');
  } else {
    print('[❌] Есть ошибки! Сборку запускать нельзя. Исправь код.');
  }
}

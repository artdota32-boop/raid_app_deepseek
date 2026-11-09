// ПОЛНЫЙ ТРЕНАЖЕР RAID SCANNER v3.0
// Запуск: dart run trainer_full.dart

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

class ArtifactParser {
  static double yThreshold = 15.0;
  static double xSplit = 250.0;
  static double isMainStatY1 = 250.0;
  static double isMainStatY2 = 340.0;
  static double isMainStatX1 = 180.0;
  static double isMainStatX2 = 600.0;

  static const List<String> statNames = [
    'Метк', 'Крит. ш', 'Крит. ур', 'Атк', 'Здр', 'Скр', 'Зщт', 'Сопр',
    'ACC', 'C.RATE', 'C.RAT', 'C. RATE', 'C. RAT', 'C RATE', 'CRATE',
    'C.DMG', 'C. DMG', 'C DMG', 'CDMG', 'ATK', 'HP', 'SPD', 'DEF', 'RES',
  ];

  static String _cleanText(String text) => text.trim();
  static String _stripGlyphMarkers(String text) => text.replaceAll(RegExp(r'\(\d+\)?'), '').trim();

  static double _minY(FakeOcrResult r) => r.points.map((p) => p.y).reduce((a, b) => a < b ? a : b);
  static double _maxY(FakeOcrResult r) => r.points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
  static double _minX(FakeOcrResult r) => r.points.map((p) => p.x).reduce((a, b) => a < b ? a : b);
  static double _maxX(FakeOcrResult r) => r.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
  static double _centerY(FakeOcrResult r) => (_minY(r) + _maxY(r)) / 2;
  static double _centerX(FakeOcrResult r) => (_minX(r) + _maxX(r)) / 2;

  static String _normForIsStat(String s) => s.replaceAll(RegExp(r'[\s\.]'), '').toUpperCase();

  static String? _findStatName(FakeOcrResult r) {
    final text = _cleanText(r.text);
    if (text.isEmpty) return null;
    final cleaned = _stripGlyphMarkers(text);
    if (cleaned.isEmpty) return null;
    final normalized = _normForIsStat(cleaned);

    for (final stat in statNames) {
      if (normalized.contains(_normForIsStat(stat))) return stat;
    }
    return null;
  }

  static bool _isStatWithNumber(String text) {
    final cleaned = _cleanText(text);
    final normCleaned = _normForIsStat(cleaned);
    for (final stat in statNames) {
      final normStat = _normForIsStat(stat);
      if (normCleaned.startsWith(normStat)) {
        final rest = normCleaned.substring(normStat.length).trim();
        final stripped = rest.replaceAll(RegExp(r'\(\d+\)?'), '').trim();
        if (RegExp(r'^\d+$').hasMatch(stripped)) return true;
        if (rest.isNotEmpty && RegExp(r'^\(\d+\)?$').hasMatch(rest)) return true;
        if (RegExp(r'^\d+\%').hasMatch(stripped)) return true;
      }
    }
    return false;
  }

  static bool _hasGlyphPattern(String text) {
    final t = _cleanText(text).trim();
    return RegExp(r'^(\d+%?)\+(\d+%?)$').hasMatch(t);
  }

  static Map<String, int> _extractBaseAndGlyph(String text) {
    final t = _cleanText(text).trim();
    final re = RegExp(r'^(\d+)%?\+(\d+)%?$');
    final m = re.firstMatch(t);
    if (m == null) return {};
    final base = int.tryParse(m.group(1) ?? '');
    final glyph = int.tryParse(m.group(2) ?? '');
    if (base == null || glyph == null) return {};
    return {'base': base, 'glyph': glyph};
  }

  static int? _extractNumber(FakeOcrResult r) {
    String text = _cleanText(r.text);
    text = text.replaceAll(RegExp(r'\(\d+\)?'), ' ');
    text = text.replaceAll(RegExp(r'\d+\)'), ' ');
    text = text.replaceAll(RegExp(r'\(\d+'), ' ');
    text = text.trim();
    if (text.isEmpty) return null;
    final matches = RegExp(r'\d+').allMatches(text).toList();
    if (matches.isEmpty) return null;
    int? best;
    for (final m in matches) {
      final val = int.tryParse(m.group(0) ?? '');
      if (val == null) continue;
      if (val < 10) continue;
      if (best == null || val > best) best = val;
    }
    return best;
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> mainBlocks) {
    final stats = <String, List<int>>{};
    final percents = <String, List<int>>{};
    final dopStats = <String, List<int>>{};
    final glyphs = <String, List<int>>{};
    final mainStat = <String, dynamic>{};
    final debug = <String>[];

    final leftBlocks = <FakeOcrResult>[];
    final rightBlocks = <FakeOcrResult>[];

    for (int idx = 0; idx < mainBlocks.length; idx++) {
      final r = mainBlocks[idx];
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = _cleanText(r.text);

      debug.add('[ZONE] #$idx text="$text" cx=${cx.toStringAsFixed(0)} cy=${cy.toStringAsFixed(0)}');

      // 🔥 Правило двух чисел
      final matches = RegExp(r'\d+').allMatches(text).toList();
      if (matches.length >= 2 && text.toUpperCase().contains('ATK')) {
        final nums = matches.map((m) => int.parse(m.group(0)!)).toList();
        debug.add('[ITER] #$idx → TWO-NUM: ATK = ${nums[0]} (glyph=${nums[1]})');
        mainStat['name'] = 'ATK';
        mainStat['value'] = nums[0];
        mainStat['isPercent'] = false;
        glyphs.putIfAbsent('ATK', () => []).add(nums[1]);
        continue;
      }

      final statName = _findStatName(r);
      final isMainStatZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;

      if (isMainStatZone && statName != null && _isStatWithNumber(r.text)) {
        final val = _extractNumber(r);
        if (val != null) {
          mainStat['name'] = statName;
          mainStat['value'] = val;
          mainStat['isPercent'] = text.contains('%');
          if (text.contains('%')) {
            percents.putIfAbsent(statName, () => []).add(val);
          } else {
            stats.putIfAbsent(statName, () => []).add(val);
          }
          debug.add('[ITER] #$idx → MAIN-STAT $statName = $val');
          continue;
        }
      }

      if (_hasGlyphPattern(r.text) && cx >= xSplit) {
        final pair = _extractBaseAndGlyph(r.text);
        if (pair.isNotEmpty) {
          String? glyphStat;
          double bestDy = double.infinity;
          for (final lb in leftBlocks) {
            final dy = (_centerY(lb) - cy).abs();
            if (dy < yThreshold && dy < bestDy) {
              glyphStat = _findStatName(lb);
              bestDy = dy;
            }
          }
          if (glyphStat != null) {
            debug.add('[ITER] #$idx → GLYPH $glyphStat base=${pair['base']} glyph=${pair['glyph']}');
            final baseVal = pair['base']!;
            final glyphVal = pair['glyph']!;
            if (text.contains('%')) {
              percents.putIfAbsent(glyphStat, () => []).add(baseVal);
            } else {
              stats.putIfAbsent(glyphStat, () => []).add(baseVal);
            }
            glyphs.putIfAbsent(glyphStat, () => []).add(glyphVal);
            continue;
          }
        }
      }

      if (statName != null && cx >= xSplit && _isStatWithNumber(r.text)) {
        final val = _extractNumber(r);
        if (val != null) {
          dopStats.putIfAbsent(statName, () => []).add(val);
          debug.add('[ITER] #$idx → DOP-STAT $statName = $val');
          continue;
        }
      }

      if (_isStatWithNumber(r.text) && cx < xSplit) {
        leftBlocks.add(r);
        continue;
      }
      if (statName != null && (cx < xSplit || statName == "C.RATE" || statName == "C.DMG")) {
        leftBlocks.add(r);
        continue;
      }
      if (cx >= xSplit && RegExp(r'\d').hasMatch(text)) {
        rightBlocks.add(r);
      }
    }

    // Обработка leftBlocks
    for (final left in leftBlocks) {
      final statName = _findStatName(left);
      if (statName == null) continue;
      final leftY = _centerY(left);
      final selfValue = _extractNumber(left);
      if (_isStatWithNumber(left.text) && selfValue != null) {
        stats.putIfAbsent(statName, () => []).add(selfValue);
        debug.add('[PARSER] MATCH (self): $statName = $selfValue');
        continue;
      }
      FakeOcrResult? bestNum;
      double bestDist = double.infinity;
      for (final right in rightBlocks) {
        final dy = (_centerY(right) - leftY).abs();
        if (dy < yThreshold && dy < bestDist) {
          bestNum = right;
          bestDist = dy;
        }
      }
      if (bestNum == null) continue;
      final value = _extractNumber(bestNum);
      if (value == null) continue;
      debug.add('[PARSER] MATCH: $statName = $value (from "${bestNum.text}")');
      if (bestNum.text.contains('%')) {
        percents.putIfAbsent(statName, () => []).add(value);
      } else {
        stats.putIfAbsent(statName, () => []).add(value);
      }
    }

    return {
      'stats': stats,
      'stats_percent': percents,
      'dop_stats': dopStats,
      'glyphs': glyphs,
      'main_stat': mainStat,
      'debug': debug,
    };
  }
}

void main() {
  print('=== ТРЕНАЖЕР RAID SCANNER v3.0 ===');

  bool allOk = true;

  // --- ТЕСТ 1: Perception ---
  print('\n--- ТЕСТ 1: Perception ---');
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
  final res1 = ArtifactParser.parse(perception);
  print('MAIN: ${res1['main_stat']}');
  print('DOP: ${res1['dop_stats']}');
  print('GLYPHS: ${res1['glyphs']}');

  if (res1['main_stat']['name'] == 'C.RATE' && res1['main_stat']['value'] == 60) {
    print('[✅] Perception: MAIN правильный');
  } else {
    print('[❌] Perception: MAIN не найден!');
    allOk = false;
  }

  // --- ТЕСТ 2: Protection ---
  print('\n--- ТЕСТ 2: Protection ---');
  final protection = [
    FakeOcrResult(text: "ATK 143 ATK 11", points: [FakePoint(x: 356, y: 274), FakePoint(x: 860, y: 330)]),
    FakeOcrResult(text: "HP 378", points: [FakePoint(x: 124, y: 343), FakePoint(x: 696, y: 408)]),
    FakeOcrResult(text: "SPD(2)", points: [FakePoint(x: 120, y: 468), FakePoint(x: 325, y: 544)]),
    FakeOcrResult(text: "13", points: [FakePoint(x: 577, y: 470), FakePoint(x: 664, y: 537)]),
  ];
  final res2 = ArtifactParser.parse(protection);
  print('MAIN: ${res2['main_stat']}');
  print('DOP: ${res2['dop_stats']}');
  print('GLYPHS: ${res2['glyphs']}');

  if (res2['main_stat']['name'] == 'ATK' && res2['main_stat']['value'] == 143) {
    print('[✅] Protection: MAIN найден (ATK 143)');
  } else {
    print('[❌] Protection: MAIN не найден!');
    allOk = false;
  }
  if (res2['glyphs']['ATK']?.contains(11) == true) {
    print('[✅] Protection: Глиф ATK 11 найден!');
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

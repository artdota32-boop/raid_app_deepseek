// ФИНАЛЬНЫЙ ТРЕНАЖЕР RAID SCANNER v7.0
// Запуск: dart run trainer_final2.dart

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
  static double setDescCy = 550.0;
  static double yMinForStats = 900.0;

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

  static String? _findStatName(FakeOcrResult r, [List<String>? debugOut]) {
    final text = _cleanText(r.text);
    debugOut?.add('[FINDSTAT] input="$text"');
    if (text.isEmpty) return null;
    final cleaned = _stripGlyphMarkers(text);
    if (cleaned.isEmpty) return null;
    final normalized = _normForIsStat(cleaned);
    for (final stat in statNames) {
      if (normalized.contains(_normForIsStat(stat))) return stat;
    }
    return null;
  }

  static bool _isStatWithNumber(String text, [List<String>? debugOut]) {
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

  static bool _hasGlyphPattern(String text) => RegExp(r'^(\d+%?)\+(\d+%?)$').hasMatch(_cleanText(text).trim());

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

      if (cy > yMinForStats) continue;
      if (cy > setDescCy) continue;

      debug.add('[ZONE] #$idx text="$text" cx=${cx.toStringAsFixed(0)} cy=${cy.toStringAsFixed(0)}');

      // Правило двух чисел (для Protection)
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

      final statName = _findStatName(r, debug);
      
      // 🔥 ПРОВЕРКА ЗОНЫ MAIN (но только если это не левый блок для связывания)
      final isMainStatZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;
      if (isMainStatZone && statName != null && _isStatWithNumber(r.text, debug)) {
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

      // 🔥 ЛОГИКА ГЛИФОВ (для блоков справа)
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

      // 🔥 DOP-STAT (справа)
      if (statName != null && cx >= xSplit && _isStatWithNumber(r.text, debug)) {
        final val = _extractNumber(r);
        if (val != null) {
          dopStats.putIfAbsent(statName, () => []).add(val);
          debug.add('[ITER] #$idx → DOP-STAT $statName = $val');
          continue;
        }
      }

      // 🔥 ЛЕВЫЕ БЛОКИ (для связывания)
      if (_isStatWithNumber(r.text, debug) && cx < xSplit) {
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

    // Обработка leftBlocks (связывание с правыми блоками)
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
  print('=== ФИНАЛЬНЫЙ ТРЕНАЖЕР v7.0 ===');

  // --- ТЕСТ: Cruel (Shield) ---
  print('\n--- ТЕСТ: Cruel (Shield) ---');
  final cruel = [
    FakeOcrResult(text: "DEF 104", points: [FakePoint(x: 356, y: 274), FakePoint(x: 589, y: 332)]),
    FakeOcrResult(text: "C. RATE", points: [FakePoint(x: 124, y: 345), FakePoint(x: 352, y: 405)]),
    FakeOcrResult(text: "5%", points: [FakePoint(x: 576, y: 340), FakePoint(x: 672, y: 411)]),
    FakeOcrResult(text: "C. DMG", points: [FakePoint(x: 124, y: 409), FakePoint(x: 339, y: 470)]),
    FakeOcrResult(text: "6%", points: [FakePoint(x: 577, y: 407), FakePoint(x: 671, y: 473)]),
    FakeOcrResult(text: "HP(2)", points: [FakePoint(x: 117, y: 464), FakePoint(x: 293, y: 547)]),
    FakeOcrResult(text: "629", points: [FakePoint(x: 576, y: 470), FakePoint(x: 693, y: 537)]),
    FakeOcrResult(text: "SPD", points: [FakePoint(x: 121, y: 534), FakePoint(x: 249, y: 600)]),
    FakeOcrResult(text: "4", points: [FakePoint(x: 575, y: 535), FakePoint(x: 628, y: 599)]),
  ];
  final res = ArtifactParser.parse(cruel);

  print('\n=== РЕЗУЛЬТАТ ===');
  print('MAIN: ${res['main_stat']}');
  print('STATS (обычные): ${res['stats']}');
  print('PERCENT (проценты): ${res['stats_percent']}');
  print('DOP_STATS: ${res['dop_stats']}');
  print('GLYPHS: ${res['glyphs']}');

  print('\n=== ФУЛЛ ЛОГ ===');
  for (final line in res['debug']) {
    print(line);
  }
}

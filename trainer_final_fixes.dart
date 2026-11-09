// ТРЕНАЖЕР С ФИКСАМИ v11.0 (Финальная проверка)
// Запуск: dart run trainer_final_fixes.dart

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
  
  static double _centerY(FakeOcrResult r) => (r.points.map((p) => p.y).reduce((a, b) => a < b ? a : b) + r.points.map((p) => p.y).reduce((a, b) => a > b ? a : b)) / 2;
  static double _centerX(FakeOcrResult r) => (r.points.map((p) => p.x).reduce((a, b) => a < b ? a : b) + r.points.map((p) => p.x).reduce((a, b) => a > b ? a : b)) / 2;

  static String _norm(String s) => s
      .replaceAll('À', 'A').replaceAll('Á', 'A')
      .replaceAll('È', 'E').replaceAll('É', 'E')
      .replaceAll('Ì', 'I').replaceAll('Í', 'I')
      .replaceAll('Ò', 'O').replaceAll('Ó', 'O')
      .replaceAll('Ù', 'U').replaceAll('Ú', 'U')
      .replaceAll(RegExp(r'[\s\.]'), '').toUpperCase();

  static String? _findStatName(FakeOcrResult r) {
    final text = _cleanText(r.text);
    final cleaned = _stripGlyphMarkers(text);
    if (cleaned.isEmpty) return null;
    final normalized = _norm(cleaned);
    for (final stat in statNames) {
      if (normalized.contains(_norm(stat))) return stat;
    }
    return null;
  }

  static bool _isStatWithNumber(String text) {
    final cleaned = _cleanText(text);
    final normCleaned = _norm(cleaned);
    for (final stat in statNames) {
      final normStat = _norm(stat);
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

  static int? _extractNumber(FakeOcrResult r) {
    String text = _cleanText(r.text);
    text = text.replaceAll(RegExp(r'\(\d+\)?'), ' ');
    text = text.trim();
    if (text.isEmpty) return null;
    final matches = RegExp(r'\d+').allMatches(text).toList();
    if (matches.isEmpty) return null;
    int? best;
    for (final m in matches) {
      final val = int.tryParse(m.group(0) ?? '');
      if (val == null) continue;
      if (val == 0) continue; // Пропускаем только 0
      if (best == null || val > best) best = val;
    }
    return best;
  }

  // 🔥 ФИКС: Возвращаем флаг процента для глифа
  static Map<String, dynamic> _extractBaseAndGlyph(String text) {
    final t = _cleanText(text).trim();
    final re = RegExp(r'^(\d+)(%?)\+(\d+)(%?)$');
    final m = re.firstMatch(t);
    if (m == null) return {};
    final base = int.tryParse(m.group(1) ?? '');
    final glyph = int.tryParse(m.group(3) ?? '');
    if (base == null || glyph == null) return {};
    return {
      'base': base, 
      'glyph': glyph,
      'glyphPercent': m.group(4) == '%', // Запоминаем, был ли %
    };
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> mainBlocks) {
    final stats = <String, List<int>>{};
    final percents = <String, List<int>>{};
    final dopStats = <String, List<int>>{};
    final glyphs = <String, List<int>>{};
    final glyphPercents = <String, bool>{}; // 🔥 Новый словарь для флагов
    final mainStat = <String, dynamic>{};
    final leftBlocks = <FakeOcrResult>[];
    final rightBlocks = <FakeOcrResult>[];

    for (final r in mainBlocks) {
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = _cleanText(r.text);
      final statName = _findStatName(r);
      final isMainZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;

      // 🔥 ФИКС PROTECTION: Правило двух чисел
      final matches = RegExp(r'\d+').allMatches(text).toList();
      if (matches.length >= 2 && text.toUpperCase().contains('ATK')) {
        final nums = matches.map((m) => int.parse(m.group(0)!)).toList();
        mainStat['name'] = 'ATK';
        mainStat['value'] = nums[0];
        mainStat['isPercent'] = false;
        glyphs.putIfAbsent('ATK', () => []).add(nums[1]);
        continue;
      }

      if (isMainZone && statName != null && _isStatWithNumber(r.text)) {
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
          continue;
        }
      }

      // 🔥 Обработка глифов
      if (RegExp(r'^(\d+%?)\+(\d+%?)$').hasMatch(text) && cx >= xSplit) {
        final pair = _extractBaseAndGlyph(text);
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
            final baseVal = pair['base']!;
            final glyphVal = pair['glyph']!;
            if (text.contains('%')) {
              percents.putIfAbsent(glyphStat, () => []).add(baseVal);
            } else {
              stats.putIfAbsent(glyphStat, () => []).add(baseVal);
            }
            glyphs.putIfAbsent(glyphStat, () => []).add(glyphVal);
            glyphPercents[glyphStat] = pair['glyphPercent']!; // 🔥 Сохраняем флаг
            continue;
          }
        }
      }

      if (statName != null && cx >= xSplit && _isStatWithNumber(r.text)) {
        final val = _extractNumber(r);
        if (val != null) {
          dopStats.putIfAbsent(statName, () => []).add(val);
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

    for (final left in leftBlocks) {
      final statName = _findStatName(left);
      if (statName == null) continue;
      final leftY = _centerY(left);
      final selfValue = _extractNumber(left);
      if (_isStatWithNumber(left.text) && selfValue != null) {
        stats.putIfAbsent(statName, () => []).add(selfValue);
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
      'glyph_percents': glyphPercents,
      'main_stat': mainStat,
    };
  }
}

void main() {
  print('=== ТРЕНАЖЕР С ФИКСАМИ v11.0 ===');

  // --- ТЕСТ 1: Perception (глифы с %) ---
  print('\n--- ТЕСТ 1: Perception (глифы с %) ---');
  final perception = [
    FakeOcrResult(text: "C. RATE 60%", points: [FakePoint(x: 356, y: 273), FakePoint(x: 709, y: 332)]),
    FakeOcrResult(text: "DEF", points: [FakePoint(x: 124, y: 342), FakePoint(x: 243, y: 406)]),
    FakeOcrResult(text: "6%+4%", points: [FakePoint(x: 578, y: 344), FakePoint(x: 788, y: 408)]),
    FakeOcrResult(text: "SPD(3)", points: [FakePoint(x: 120, y: 468), FakePoint(x: 327, y: 543)]),
    FakeOcrResult(text: "23+5", points: [FakePoint(x: 575, y: 469), FakePoint(x: 735, y: 536)]),
  ];
  final res1 = ArtifactParser.parse(perception);
  print('MAIN: ${res1['main_stat']}');
  print('GLYPHS: ${res1['glyphs']}');
  print('GLYPH PERCENTS: ${res1['glyph_percents']}');
  if (res1['glyph_percents']['DEF'] == true) print('[✅] Perception: % у глифа DEF сохранен!');
  else print('[❌] Perception: % у глифа DEF потерян!');

  // --- ТЕСТ 2: Protection (два числа) ---
  print('\n--- ТЕСТ 2: Protection (два числа) ---');
  final protection = [
    FakeOcrResult(text: "ATK 143 ATK 11", points: [FakePoint(x: 356, y: 274), FakePoint(x: 860, y: 330)]),
    FakeOcrResult(text: "HP 378", points: [FakePoint(x: 124, y: 343), FakePoint(x: 696, y: 408)]),
  ];
  final res2 = ArtifactParser.parse(protection);
  print('MAIN: ${res2['main_stat']}');
  print('DOP: ${res2['dop_stats']}');
  print('GLYPHS: ${res2['glyphs']}');
  if (res2['main_stat']['value'] == 143) print('[✅] Protection: MAIN найден (ATK 143)!');
  else print('[❌] Protection: MAIN не найден!');
  if (res2['glyphs']['ATK']?.contains(11) == true) print('[✅] Protection: Глиф ATK 11 найден!');

  // --- ТЕСТ 3: Speed (числа < 10) ---
  print('\n--- ТЕСТ 3: Speed (числа < 10) ---');
  final speed = [
    FakeOcrResult(text: "HP 3480", points: [FakePoint(x: 355, y: 274), FakePoint(x: 597, y: 332)]),
    FakeOcrResult(text: "SPD(1)", points: [FakePoint(x: 121, y: 405), FakePoint(x: 322, y: 477)]),
    FakeOcrResult(text: "9", points: [FakePoint(x: 574, y: 408), FakePoint(x: 629, y: 473)]),
  ];
  final res3 = ArtifactParser.parse(speed);
  print('MAIN: ${res3['main_stat']}');
  print('STATS: ${res3['stats']}');
  if (res3['stats']['SPD']?.contains(9) == true) print('[✅] Speed: SPD 9 найден!');
  else print('[❌] Speed: SPD 9 потерян!');
}

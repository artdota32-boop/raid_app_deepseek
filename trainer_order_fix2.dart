// ТРЕНАЖЕР ПОРЯДКА v10.0 (сборка в один список)
// Запуск: dart run trainer_order_fix2.dart

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
      if (val == 0) continue;
      if (best == null || val > best) best = val;
    }
    return best;
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> mainBlocks) {
    final stats = <String, List<int>>{};
    final percents = <String, List<int>>{};
    final dopStats = <String, List<int>>{};
    final mainStat = <String, dynamic>{};
    final leftBlocks = <FakeOcrResult>[];
    final rightBlocks = <FakeOcrResult>[];

    // 🔥 Общий список для сохранения порядка
    final orderedDop = <String>[];

    for (final r in mainBlocks) {
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = _cleanText(r.text);
      final statName = _findStatName(r);
      final isMainZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;

      if (isMainZone && statName != null && _isStatWithNumber(r.text)) {
        final val = _extractNumber(r);
        if (val != null) {
          mainStat['name'] = statName;
          mainStat['value'] = val;
          mainStat['isPercent'] = text.contains('%');
          continue;
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
        if (statName != mainStat['name'] || selfValue != mainStat['value']) {
          orderedDop.add('$statName|$selfValue');
        }
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
      if (statName != mainStat['name'] || value != mainStat['value']) {
        if (bestNum.text.contains('%')) {
          orderedDop.add('$statName|$value%');
        } else {
          orderedDop.add('$statName|$value');
        }
      }
    }

    return {
      'ordered_dop': orderedDop,
      'main_stat': mainStat,
    };
  }
}

void main() {
  print('=== ТРЕНАЖЕР ПОРЯДКА v10.0 ===');

  // --- ТЕСТ: Speed ---
  print('\n--- ТЕСТ: Speed ---');
  final speed = [
    FakeOcrResult(text: "HP 3480", points: [FakePoint(x: 355, y: 274), FakePoint(x: 597, y: 332)]),
    FakeOcrResult(text: "ACC", points: [FakePoint(x: 123, y: 344), FakePoint(x: 253, y: 406)]),
    FakeOcrResult(text: "11", points: [FakePoint(x: 576, y: 344), FakePoint(x: 657, y: 409)]),
    FakeOcrResult(text: "SPD(1)", points: [FakePoint(x: 121, y: 405), FakePoint(x: 322, y: 477)]),
    FakeOcrResult(text: "9", points: [FakePoint(x: 574, y: 408), FakePoint(x: 629, y: 473)]),
    FakeOcrResult(text: "ATK(1)", points: [FakePoint(x: 119, y: 467), FakePoint(x: 322, y: 541)]),
    FakeOcrResult(text: "10%", points: [FakePoint(x: 579, y: 470), FakePoint(x: 705, y: 535)]),
    FakeOcrResult(text: "C. RÀE(2)", points: [FakePoint(x: 119, y: 529), FakePoint(x: 428, y: 613)]),
    FakeOcrResult(text: "15%", points: [FakePoint(x: 577, y: 534), FakePoint(x: 707, y: 602)]),
  ];
  final res = ArtifactParser.parse(speed);

  final orderedDop = res['ordered_dop'] as List<String>;

  print('\n=== DOP НА ЭКРАНЕ (как в игре) ===');
  for (final line in orderedDop) {
    print(line);
  }

  print('\n=== ПРОВЕРКА ===');
  if (orderedDop.isNotEmpty && orderedDop.first == 'ACC|11') print('[✅] Порядок совпадает с игрой (ACC первый)!');
  if (orderedDop.contains('SPD|9')) print('[✅] SPD 9 найден!');
  if (orderedDop.contains('C.RATE|15%')) print('[✅] C.RATE 15% найден!');
}

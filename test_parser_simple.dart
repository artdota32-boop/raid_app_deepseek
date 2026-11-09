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
  static double isMainStatY1 = 250.0;
  static double isMainStatY2 = 340.0;
  static double isMainStatX1 = 180.0;
  static double isMainStatX2 = 600.0;
  static double xSplit = 250.0;
  static double yThreshold = 15.0;

  static const List<String> statNames = [
    'Метк', 'Крит. ш', 'Крит. ур', 'Атк', 'Здр', 'Скр', 'Зщт', 'Сопр',
    'ACC', 'C.RATE', 'C.RAT', 'C. RATE', 'C. RAT', 'C RATE', 'CRATE',
    'C.DMG', 'C. DMG', 'C DMG', 'CDMG', 'ATK', 'HP', 'SPD', 'DEF', 'RES',
  ];

  static double _centerY(FakeOcrResult r) {
    final ys = r.points.map((p) => p.y).toList();
    return (ys.reduce((a, b) => a < b ? a : b) + ys.reduce((a, b) => a > b ? a : b)) / 2;
  }

  static double _centerX(FakeOcrResult r) {
    final xs = r.points.map((p) => p.x).toList();
    return (xs.reduce((a, b) => a < b ? a : b) + xs.reduce((a, b) => a > b ? a : b)) / 2;
  }

  static String _cleanText(String text) => text.trim();

  static String? _findStatName(FakeOcrResult r) {
    final text = _cleanText(r.text).toUpperCase();
    for (final stat in statNames) {
      if (text.contains(stat.toUpperCase())) return stat;
    }
    return null;
  }

  static bool _isStatWithNumber(String text) {
    final cleaned = _cleanText(text).toUpperCase();
    for (final stat in statNames) {
      if (cleaned.startsWith(stat.toUpperCase())) {
        final rest = cleaned.substring(stat.length).trim();
        if (RegExp(r'^\d+').hasMatch(rest)) return true;
        if (RegExp(r'^\(\d+').hasMatch(rest)) return true;
      }
    }
    return false;
  }

  static int? _extractNumber(FakeOcrResult r) {
    final text = _cleanText(r.text).replaceAll(RegExp(r'\(\d+\)?'), ' ');
    final matches = RegExp(r'\d+').allMatches(text).toList();
    if (matches.isEmpty) return null;
    int? best;
    for (final m in matches) {
      final val = int.tryParse(m.group(0) ?? '');
      if (val != null && val >= 10) {
        if (best == null || val > best) best = val;
      }
    }
    return best;
  }

  static Map<String, dynamic> parse(List<FakeOcrResult> mainBlocks) {
    final result = <String, dynamic>{
      'stats': <String, List<int>>{},
      'stats_percent': <String, List<int>>{},
      'glyphs': <String, List<int>>{},
      'dop_stats': <String, List<int>>{},
      'main_stat': <String, dynamic>{},
    };

    final stats = result['stats'] as Map<String, List<int>>;
    final percent = result['stats_percent'] as Map<String, List<int>>;
    final dopStats = result['dop_stats'] as Map<String, List<int>>;
    final glyphs = result['glyphs'] as Map<String, List<int>>;
    final mainStatResult = result['main_stat'] as Map<String, dynamic>;

    for (int idx = 0; idx < mainBlocks.length; idx++) {
      final r = mainBlocks[idx];
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = _cleanText(r.text);

      final statName = _findStatName(r);
      final isMainZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;

      if (isMainZone && statName != null && _isStatWithNumber(r.text)) {
        final val = _extractNumber(r);
        if (val != null) {
          mainStatResult['name'] = statName;
          mainStatResult['value'] = val;
          mainStatResult['isPercent'] = text.contains('%');
          if (text.contains('%')) {
            percent.putIfAbsent(statName, () => []).add(val);
          } else {
            stats.putIfAbsent(statName, () => []).add(val);
          }
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

      if (statName != null && cx < xSplit) {
        final val = _extractNumber(r);
        if (val != null) {
          stats.putIfAbsent(statName, () => []).add(val);
        }
      }
    }
    return result;
  }
}

void main() {
  final blocks = <FakeOcrResult>[
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

  final parsed = ArtifactParser.parse(blocks);

  print("=== РЕЗУЛЬТАТ ПАРСЕРА ===");
  print("MAIN: ${parsed['main_stat']}");
  print("DOP (из dop_stats): ${parsed['dop_stats']}");
  print("STATS (из stats): ${parsed['stats']}");
  print("PERCENT (из stats_percent): ${parsed['stats_percent']}");
}

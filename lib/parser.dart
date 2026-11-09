import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:ui' as ui;
import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;

/// v3.4.0 — parser под paddle_ocr_native (PP-OCRv6)
class ArtifactParser {
  static Map<String, dynamic> setsDb = {'sets': []};
  static bool _setsDbLoaded = false;
  static List<String> setsLog = [];
  static int currentRank = 0;

  static Future<void> loadSetsDb() async {
    if (_setsDbLoaded) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/sets.json');
      setsDb = json.decode(jsonStr);
      _setsDbLoaded = true;
      setsLog.add('[SETS] ✅ Loaded ${(setsDb['sets'] as List).length} sets');
    } catch (e) {
      setsDb = {'sets': []};
      setsLog.add('[SETS] ❌ Failed: $e');
    }
  }

  static Map<String, dynamic>? _findSetByName(String text) {
    final norm = text.toLowerCase().trim();
    final count = (setsDb['sets'] as List).length;
    setsLog.add('[SETS] Search "$norm" in $count sets');
    final sets = (setsDb['sets'] as List).toList();
    sets.sort((a, b) =>
      (b['name_en'] as String).length.compareTo((a['name_en'] as String).length)
    );
    for (final set in sets) {
      final nameEn = (set['name_en'] as String).toLowerCase();
      final nameRu = (set['name_ru'] as String).toLowerCase();
      final id = (set['id'] as String).toLowerCase();
      if (norm.contains(nameEn) || norm.contains(nameRu) || norm.contains(id)) {
        setsLog.add('[SETS] ✅ Found: $id');
        return set as Map<String, dynamic>;
      }
    }
    setsLog.add('[SETS] ❌ Not found');
    return null;
  }

  static String _formatSetBonuses(Map<String, dynamic> set) {
    final bonuses = set['bonuses'] as Map<String, dynamic>;
    final parts = <String>[];
    final keys = bonuses.keys.toList()..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
    for (final k in keys) {
      parts.add('${k}pc ${bonuses[k]}');
    }
    return parts.join(', ');
  }

  static double yThreshold = 15.0;
  static double xGapThreshold = 25.0;
  static double xSplit = 250.0;
  static double yMaxForSet = 700.0;
  static double yMinForStats = 900.0;
  static double isMainStatY1 = 250.0;
  static double isMainStatY2 = 340.0;
  static double isMainStatX1 = 180.0;
  static double isMainStatX2 = 600.0;
  static double setDescCy = 550.0;
  static double xMaxForSet = 700.0;

  static Future<void> loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    xSplit = (p.getInt('xSplit') ?? 250).toDouble();
    yThreshold = (p.getInt('yThreshold') ?? 15).toDouble();
    yMaxForSet = (p.getInt('yMaxForSet') ?? 700).toDouble();
    yMinForStats = (p.getInt('yMinForStats') ?? 900).toDouble();
    xMaxForSet = (p.getInt('xMaxForSet') ?? 700).toDouble();
    isMainStatY1 = 250.0;
    isMainStatY2 = 340.0;
    isMainStatX1 = (p.getInt('isMainStatX1') ?? 180).toDouble();
    isMainStatX2 = (p.getInt('isMainStatX2') ?? 600).toDouble();
    setDescCy = (p.getInt('setDescCy') ?? 700).toDouble();
    currentRank = p.getInt('rank') ?? 0;
    await loadSetsDb();
  }

  static const Map<String, String> latinToCyrillic = {
    'M': 'М', 'e': 'е', 'E': 'Е', 'T': 'Т',
    'y': 'у', 'x': 'х', 'c': 'с', 'p': 'р',
    'A': 'А', 'B': 'В', 'H': 'Н', 'K': 'К',
    'O': 'О', 'P': 'Р', 'C': 'С', 'k': 'к',
    'o': 'о', 'a': 'а', 't': 'т', 'r': 'р',
    'n': 'п', 'u': 'и',
  };

  static const List<List<String>> replacementPairs = [
    ['cYYlowb', 'Скр'], ['cYlowb', 'Скр'], ['cnmaYlowb', 'Скр'], ['cnmYlowb', 'Скр'],
    ['cmYlowb', 'Скр'], ['cmnlowbl', 'Скр'], ['cnmlowbl', 'Скр'], ['caYlowbl', 'Скр'],
    ['cYlow', 'Скр'], ['calowb', 'Скр'], ['cYlwb', 'Скр'], ['cYlob', 'Зщт'], ['cYwb', 'Скр'],
    ['Скb(', 'Скр('], ['Скb', 'Скр'], ['Скp', 'Скр'], ['Скв', 'Скр'], ['Ск(', 'Скр('],
    ['Cwb', 'Скр'], ['cowb', 'Зщт'], ['3др', 'Здр'], ['3Д', 'Здр'], ['Здр(1w', 'Здр(1)'],
    ['Здр(1', 'Здр(1)'], ['Метw', 'Метк'], ['Метv', 'Метк'], ['Метв', 'Метк'], ['МеТ', 'Метк'],
    ['Мет(', 'Метк('], ['Атк(1w', 'Атк(1)'], ['Атк(1', 'Атк(1)'], ['Атк1', 'Атк'],
    ['АТк', 'Атк'], ['Ат 1', 'Атк 1'], ['A (1', 'Атк(1)'], ['A (', 'Атк('],
    ['Урит. шw', 'Крит. ш'], ['Урит. ш', 'Крит. ш'], ['Урит. ш(1', 'Крит. ш(1)'],
    ['Крит. ш(1', 'Крит. ш(1)'], ['Крит. у(1', 'Крит. ур(1)'], ['Крит. (1w', 'Крит. ш(1)'],
    ['Крит. (1', 'Крит. ш(1)'], ['Крит. (', 'Крит. ш('], ['сКрит', 'Крит'],
    ['Суровостьw', 'Суровость'], ['Небеснаяскорость', 'Небесная скорость'],
    ['ИТ.Ш', ''], ['ИТЛ', ''],
  ];

  static const List<String> types = [
    'Доспех', 'Оружие', 'Шлем', 'Перчатки', 'Сапоги', 'Щит', 'Кольцо', 'Амулет', 'Знамя',
    'Chestplate', 'Weapon', 'Helmet', 'Gloves', 'Boots', 'Shield', 'Ring', 'Amulet', 'Banner',
    'Gauntlets', 'Gauntlet',
  ];

  static const List<String> rarities = [
    'Легендарный', 'Эпический', 'Редкий', 'Обычный', 'Мифический',
    'Legendary', 'Epic', 'Rare', 'Common', 'Mythical',
  ];

  static const List<String> statNames = [
    'Метк', 'Крит. ш', 'Крит. ур', 'Атк', 'Здр', 'Скр', 'Зщт', 'Сопр', 'Точность', 'Крит. шанс', 'Крит. урон', 'Атака', 'Здоровье', 'Скорость', 'Защита', 'Сопротивление',
    'ACC', 'C.RATE', 'C.RAT', 'C. RATE', 'C. RAT', 'C RATE', 'CRATE',
    'C.DMG', 'C. DMG', 'C DMG', 'CDMG', 'ATK', 'HP', 'SPD', 'DEF', 'RES',
  ];

  static String _latinToCyr(String text) {
    String result = text;
    latinToCyrillic.forEach((lat, cyr) { result = result.replaceAll(lat, cyr); });
    return result;
  }

  static String _applyReplacements(String text) {
    String result = text;
    for (final pair in replacementPairs) { result = result.replaceAll(pair[0], pair[1]); }
    result = result.replaceAll(RegExp(r'(?<![А-Яа-яЁё])Ат(?![А-Яа-яЁё])'), 'Атк');
    return result;
  }

  static String _cleanText(String text) => _applyReplacements(text).trim();
  static String _stripGlyphMarkers(String text) => text.replaceAll(RegExp(r'\(\d+\)?'), '').trim();

  static double _minX(pn.OcrResult r) => r.points.isEmpty ? 0 : r.points.map((p) => p.x.toDouble()).reduce((a, b) => a < b ? a : b);
  static double _maxX(pn.OcrResult r) => r.points.isEmpty ? 0 : r.points.map((p) => p.x.toDouble()).reduce((a, b) => a > b ? a : b);
  static double _minY(pn.OcrResult r) => r.points.isEmpty ? 0 : r.points.map((p) => p.y.toDouble()).reduce((a, b) => a < b ? a : b);
  static double _maxY(pn.OcrResult r) => r.points.isEmpty ? 0 : r.points.map((p) => p.y.toDouble()).reduce((a, b) => a > b ? a : b);
  static double _centerY(pn.OcrResult r) => (_minY(r) + _maxY(r)) / 2;
  static double _centerX(pn.OcrResult r) => (_minX(r) + _maxX(r)) / 2;

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((v, e) => v < e ? v : e);
      }
      for (int k = 0; k <= b.length; k++) { prev[k] = curr[k]; }
    }
    return prev[b.length];
  }

  static String? _fuzzyFindStat(String normalized, [List<String>? debugOut]) {
    String? best;
    int bestDist = 3;
    for (final stat in statNames) {
      final statNorm = stat.replaceAll(RegExp(r'[\s\.]'), '').toUpperCase();
      final dist = _levenshtein(normalized, statNorm);
      if (dist < bestDist) { bestDist = dist; best = stat; }
    }
    if (best != null) { debugOut?.add('[FUZZY] "$normalized" → "$best" (dist=$bestDist)'); return best; }
    return null;
  }

  static String? _findStatName(pn.OcrResult r, [List<String>? debugOut]) {
    final text = _cleanText(r?.text ?? "");
    debugOut?.add('[FINDSTAT] input="$text"');
    if (text.isEmpty) { debugOut?.add('[FINDSTAT] → null (empty)'); return null; }
    final cleaned = _stripGlyphMarkers(text);
    if (cleaned.isEmpty) { debugOut?.add('[FINDSTAT] → null (cleaned empty)'); return null; }

    String norm(String s) => s
        .replaceAll('Á', 'A').replaceAll('á', 'a').replaceAll('É', 'E').replaceAll('é', 'e')
        .replaceAll('Í', 'I').replaceAll('í', 'i').replaceAll('Ó', 'O').replaceAll('ó', 'o')
        .replaceAll('Ú', 'U').replaceAll('ú', 'u').replaceAll('À', 'A').replaceAll('à', 'a')
        .replaceAll('È', 'E').replaceAll('è', 'e').replaceAll('Ì', 'I').replaceAll('ì', 'i')
        .replaceAll('Ò', 'O').replaceAll('ò', 'o').replaceAll('Ù', 'U').replaceAll('ù', 'u')
        .replaceAll('Â', 'A').replaceAll('â', 'a').replaceAll('Ê', 'E').replaceAll('ê', 'e')
        .replaceAll('Î', 'I').replaceAll('î', 'i').replaceAll('Ô', 'O').replaceAll('ô', 'o')
        .replaceAll('Û', 'U').replaceAll('û', 'u').replaceAll(RegExp(r'[\s\.]'), '').toUpperCase();

    final normalized = norm(cleaned);
    debugOut?.add('[FINDSTAT] cleaned="$cleaned" normalized="$normalized"');

    for (final stat in statNames) {
      final statNorm = norm(stat);
      if (normalized.contains(statNorm)) { debugOut?.add('[FINDSTAT] → MATCH "$stat"'); return stat; }
    }
    final fuzzy = _fuzzyFindStat(normalized, debugOut);
    if (fuzzy != null) { debugOut?.add('[FINDSTAT] → FUZZY "$fuzzy"'); return fuzzy; }
    debugOut?.add('[FINDSTAT] → null (no match)');
    return null;
  }

  static String _normForIsStat(String s) {
    return s.replaceAll('À', 'A').replaceAll('Á', 'A').replaceAll('Â', 'A')
        .replaceAll('È', 'E').replaceAll('É', 'E').replaceAll('Ê', 'E')
        .replaceAll('Ì', 'I').replaceAll('Í', 'I').replaceAll('Î', 'I')
        .replaceAll('Ò', 'O').replaceAll('Ó', 'O').replaceAll('Ô', 'O')
        .replaceAll('Ù', 'U').replaceAll('Ú', 'U').replaceAll('Û', 'U')
        .replaceAll('Ġ', 'G').replaceAll('ġ', 'g').replaceAll(RegExp(r'[\s\.]'), '').toUpperCase();
  }

  static bool _hasPercent(pn.OcrResult r, [List<String>? debugOut]) {
    final t = _cleanText(r?.text ?? "");
    final result = t.contains('%') || t.endsWith(',');
    debugOut?.add('[HASPERCENT] text="$t" → $result');
    return result;
  }

  static int? _extractNumber(pn.OcrResult r, [List<String>? debugOut]) {
    String text = _cleanText(r?.text ?? "");
    final original = text;
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
      if (val == 0) continue;
      if (best == null || val > best) best = val;
    }
    return best;
  }

  static void _parseStats(
    List<pn.OcrResult> mainBlocks,
    Map<String, List<int>> statsOut,
    Map<String, List<int>> percentOut,
    Map<String, List<int>> dopStatsOut,
    Map<String, List<int>> glyphsOut,
    List<String> debugOut,
    Map<String, dynamic> mainStatResult,
    Map<String, bool> glyphPercentsOut,
  ) {
    debugOut.add('[PARSER] _parseStats START, mainBlocks=${mainBlocks.length}');

    final leftBlocks = <pn.OcrResult>[];
    final rightBlocks = <pn.OcrResult>[];

    for (int idx = 0; idx < mainBlocks.length; idx++) {
      final r = mainBlocks[idx];
      if (r.points.isEmpty) continue;
      final cy = _centerY(r);
      final cx = _centerX(r);
      final text = _cleanText(r?.text ?? "");

      if (cy > yMinForStats) continue;
      if (cy > setDescCy) continue;

      final statName = _findStatName(r);
      final isMainZone = cy > isMainStatY1 && cy < isMainStatY2 && cx > isMainStatX1 && cx < isMainStatX2;

      // 🔥 ФИКС PROTECTION: Правило двух чисел
      final matches = RegExp(r'\d+').allMatches(text).toList();
      if (matches.length >= 2 && text.toUpperCase().contains('ATK')) {
        final nums = matches.map((m) => int.parse(m.group(0)!)).toList();
        mainStatResult['name'] = 'ATK';
        mainStatResult['value'] = nums[0];
        mainStatResult['isPercent'] = false;
        glyphsOut.putIfAbsent('ATK', () => []).add(nums[1]);
        debugOut.add('[ITER] #$idx → TWO-NUM: ATK = ${nums[0]} (glyph=${nums[1]})');
        continue;
      }

      if (isMainZone && statName != null && _isStatWithNumber(r.text, debugOut)) {
        final val = _extractNumber(r, debugOut);
        if (val != null) {
          mainStatResult['name'] = statName;
          mainStatResult['value'] = val;
          mainStatResult['isPercent'] = _hasPercent(r, debugOut);
          if (_hasPercent(r, debugOut)) {
            percentOut.putIfAbsent(statName, () => []).add(val);
          } else {
            statsOut.putIfAbsent(statName, () => []).add(val);
          }
          debugOut.add('[ITER] #$idx → MAIN-STAT $statName = $val');
          continue;
        }
      }

      if (_hasGlyphPattern(r.text, debugOut) && cx >= xSplit) {
        final pair = _extractBaseAndGlyph(r.text, debugOut);
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
            if (_hasPercent(r, debugOut)) {
              percentOut.putIfAbsent(glyphStat, () => []).add(baseVal);
            } else {
              statsOut.putIfAbsent(glyphStat, () => []).add(baseVal);
            }
            glyphsOut.putIfAbsent(glyphStat, () => []).add(glyphVal);
            glyphPercentsOut[glyphStat] = pair['glyphPercent']!;
            debugOut.add('[ITER] #$idx → GLYPH $glyphStat base=$baseVal glyph=$glyphVal');
            continue;
          }
        }
      }

      if (statName != null && cx >= xSplit && _isStatWithNumber(r.text, debugOut)) {
        final val = _extractNumber(r, debugOut);
        if (val != null) {
          dopStatsOut.putIfAbsent(statName, () => []).add(val);
          debugOut.add('[ITER] #$idx → DOP-STAT $statName = $val');
          continue;
        }
      }

      if (_isStatWithNumber(r.text, debugOut) && cx < xSplit) {
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
      final selfValue = _extractNumber(left, debugOut);
      if (_isStatWithNumber(left.text, debugOut) && selfValue != null) {
        statsOut.putIfAbsent(statName, () => []).add(selfValue);
        debugOut.add('[PARSER] MATCH (self): $statName = $selfValue');
        continue;
      }
      pn.OcrResult? bestNum;
      double bestDist = double.infinity;
      for (final right in rightBlocks) {
        final dy = (_centerY(right) - leftY).abs();
        if (dy < yThreshold && dy < bestDist) {
          bestNum = right;
          bestDist = dy;
        }
      }
      if (bestNum == null) continue;
      final value = _extractNumber(bestNum, debugOut);
      if (value == null) continue;
      if (_hasPercent(bestNum, debugOut)) {
        percentOut.putIfAbsent(statName, () => []).add(value);
      } else {
        statsOut.putIfAbsent(statName, () => []).add(value);
      }
      debugOut.add('[PARSER] MATCH: $statName = $value (from "${bestNum.text}")');
    }
    debugOut.add('[PARSER] _parseStats END');
  }

  static Map<String, dynamic> parse(
    List<pn.OcrResult> mainBlocks, {
    List<pn.OcrResult> rightBlocks = const [],
    List<pn.OcrResult> iconBlocks = const [],
  }) {
    final result = <String, dynamic>{
      'set': null, 'type': null, 'rarity': null, 'level': null, 'rank': null,
      'stats': <String, List<int>>{}, 'stats_percent': <String, List<int>>{},
      'glyphs': <String, List<int>>{}, 'dop_stats': <String, List<int>>{},
      'glyph_percents': <String, bool>{},
      'set_bonus': null, 'worn': null, 'debug': <String>[],
      'main_stat': <String, dynamic>{},
    };

    try {
      final stats = result['stats'] as Map<String, List<int>>;
      final percents = result['stats_percent'] as Map<String, List<int>>;
      final dopStats = result['dop_stats'] as Map<String, List<int>>;
      final glyphs = result['glyphs'] as Map<String, List<int>>;
      final glyphPercents = result['glyph_percents'] as Map<String, bool>;
      final debug = result['debug'] as List<String>;
      final mainStatResult = result['main_stat'] as Map<String, dynamic>;

      final allText = mainBlocks.map((r) => _cleanText(r?.text ?? "")).join(" | ");

      for (final r in mainBlocks) {
        if (r.points.isEmpty) continue;
        final cy = _centerY(r);
        if (cy > 700) continue;
        final text = _cleanText(r?.text ?? "");
        for (final t in types) { if (text.contains(t)) { result['type'] = t; break; } }
        if (result['type'] != null) break;
      }
      for (final r in rarities) { if (allText.contains(r)) { result['rarity'] = r; break; } }

      final cleanAllText = allText.replaceAll('.', '');
      final lvlMatch = RegExp(r'\+(\d{1,2})').firstMatch(cleanAllText);
      if (lvlMatch != null) {
        final lvl = int.tryParse(lvlMatch.group(1) ?? '');
        if (lvl != null && [4, 8, 12, 16].contains(lvl)) { result['level'] = lvl; }
      }
      if (currentRank >= 1 && currentRank <= 6) { result['rank'] = currentRank; }

      final wornMatch = RegExp(r'Надето[:\s]*(\d+/\d+)').firstMatch(allText);
      if (wornMatch != null) { result['worn'] = wornMatch.group(1); }
      else { final wornEn = RegExp(r'(\d+/\d+)\s*Artifacts Equipped').firstMatch(allText); if (wornEn != null) result['worn'] = wornEn.group(1); }

      pn.OcrResult? topBlock;
      double minY = double.infinity;
      for (final r in mainBlocks) {
        if (r.points.isEmpty) continue;
        final cy = _centerY(r); final cx = _centerX(r);
        if (cy > yMaxForSet) continue; if (cx > xMaxForSet) continue;
        final text = _cleanText(r?.text ?? "");
        if (text.length < 5) continue; if (text.isEmpty) continue;
        if (types.contains(text)) continue; if (rarities.contains(text)) continue;
        if (text.contains('Улучшить') || text.contains('Надеть')) continue;
        if (cy < minY) { minY = cy; topBlock = r; }
      }
      if (topBlock != null) {
        String setName = _cleanText(topBlock.text);
        setName = setName.replaceFirst(RegExp(r'^\s*(Set|Сет)\s*[:\.]?\s*', caseSensitive: false), '');
        setName = setName.trim();
        result['set'] = setName.isEmpty ? null : setName;
      }

      final setName2 = result['set'] as String?;
      if (setName2 != null) {
        final setInfo = _findSetByName(setName2);
        if (setInfo != null) {
          result['set_bonus'] = _formatSetBonuses(setInfo);
          result['set_id'] = setInfo['id'];
        } else {
          final bonusPieces = RegExp(r'(\d+)\s+Artifacts per Set').firstMatch(allText);
          if (bonusPieces != null) { result['set_bonus'] = '${bonusPieces.group(1)} pcs'; }
        }
      }

      debug.addAll(setsLog);
      _parseStats(mainBlocks, stats, percents, dopStats, glyphs, debug, mainStatResult, glyphPercents);

      if (result['level'] == null && iconBlocks.isNotEmpty) {
        for (final r in iconBlocks) {
          if (r.points.isEmpty) continue;
          final m = RegExp(r'\+?(\d{1,2})').firstMatch(_cleanText(r?.text ?? ""));
          if (m != null) {
            final lvl = int.tryParse(m.group(1) ?? '');
            if (lvl != null && [4, 8, 12, 16].contains(lvl)) { result['level'] = lvl; break; }
          }
        }
      }
    } catch (e) { result['error'] = 'parse error: $e'; }
    return result;
  }

  static bool _isStatWithNumber(String text, [List<String>? debugOut]) {
    final cleaned = _cleanText(text);
    final normCleaned = _normForIsStat(cleaned);
    for (final stat in statNames) {
      final normStat = _normForIsStat(stat);
      if (normCleaned.startsWith(normStat)) {
        final rest = normCleaned.substring(normStat.length).trim();
        final stripped = rest.replaceAll(RegExp(r'\(\d+\)?'), '').trim();
        if (RegExp(r'^\d+$').hasMatch(stripped)) {
          final num = int.tryParse(stripped);
          if (num != null && num <= 9) return false;
          return true;
        }
        if (rest.isNotEmpty && RegExp(r'^\(\d+\)?$').hasMatch(rest)) return true;
        if (RegExp(r'^\d+\%').hasMatch(stripped)) return true;
      }
    }
    return false;
  }

  static bool _hasGlyphPattern(String text, [List<String>? debugOut]) {
    final t = _cleanText(text).trim();
    return RegExp(r'^(\d+%?)\+(\d+%?)$').hasMatch(t);
  }

  static Map<String, dynamic> _extractBaseAndGlyph(String text, [List<String>? debugOut]) {
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
      'glyphPercent': m.group(4) == '%',
    };
  }
}

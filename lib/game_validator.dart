class GameValidator {
  /// Проверяет структуру результата ArtifactParser.
  /// Не изменяет parsed. Пустой список означает отсутствие замечаний.
  static List<String> validate(Map<String, dynamic> parsed) {
    final notes = <String>[];

    if (parsed['error'] != null) {
      notes.add('Ошибка парсера: ${parsed['error']}');
      return notes;
    }

    _checkOptionalString(parsed, 'type', notes);
    _checkOptionalString(parsed, 'rarity', notes);

    for (final field in [
      'stats',
      'stats_percent',
      'dop_stats',
      'glyphs',
    ]) {
      final value = parsed[field];

      if (value is! Map) {
        notes.add('$field: ожидалась Map');
        continue;
      }

      for (final entry in value.entries) {
        if (entry.key is! String) {
          notes.add('$field: ключ должен быть String');
        }
        if (entry.value is! List<int>) {
          notes.add('$field["${entry.key}"]: ожидался List<int>');
        } else if ((entry.value as List<int>).isEmpty) {
          notes.add('$field["${entry.key}"]: пустой список');
        }
      }
    }

    final mainStat = parsed['main_stat'];

    if (mainStat is! Map) {
      notes.add('main_stat: ожидалась Map');
    } else {
      final name = mainStat['name'];
      final value = mainStat['value'];
      final isPercent = mainStat['isPercent'];

      if (name != null && name is! String) {
        notes.add('main_stat.name: ожидалась String');
      }
      if (value != null && value is! int) {
        notes.add('main_stat.value: ожидался int');
      }
      if (isPercent != null && isPercent is! bool) {
        notes.add('main_stat.isPercent: ожидался bool');
      }
      if (name != null && value == null) {
        notes.add('У главного стата отсутствует значение');
      }
    }

    return notes;
  }

  static void _checkOptionalString(
    Map<String, dynamic> parsed,
    String field,
    List<String> notes,
  ) {
    final value = parsed[field];

    if (value != null && value is! String) {
      notes.add('$field: ожидалась String');
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import '../lib/game_validator.dart';

void main() {
  group('GameValidator', () {
    Map<String, dynamic> validData() => {
          'error': null,
          'type': 'Шлем',
          'rarity': 'Легендарный',
          'main_stat': {
            'name': 'Здоровье',
            'value': 1000,
            'isPercent': false,
          },
          'stats': <String, List<int>>{},
          'stats_percent': <String, List<int>>{},
          'dop_stats': <String, List<int>>{},
          'glyphs': <String, List<int>>{},
        };

    test('корректные данные и пустые карты не дают замечаний', () {
      expect(GameValidator.validate(validData()), isEmpty);
    });

    test('отсутствующий main_stat вызывает замечание', () {
      final parsed = validData()..remove('main_stat');

      expect(
        GameValidator.validate(parsed),
        contains('main_stat: ожидалась Map'),
      );
    });

    test('неправильный тип stats вызывает замечание', () {
      final parsed = validData()..['stats'] = 'не карта';

      expect(
        GameValidator.validate(parsed),
        contains('stats: ожидалась Map'),
      );
    });

    test('неправильные типы type и rarity обнаруживаются', () {
      final parsed = validData()
        ..['type'] = 123
        ..['rarity'] = false;

      final notes = GameValidator.validate(parsed);

      expect(notes, contains('type: ожидалась String'));
      expect(notes, contains('rarity: ожидалась String'));
    });

    test('неправильные типы полей main_stat обнаруживаются', () {
      final parsed = validData()
        ..['main_stat'] = {
          'name': 123,
          'value': 'тысяча',
          'isPercent': 'да',
        };

      final notes = GameValidator.validate(parsed);

      expect(notes, contains('main_stat.name: ожидалась String'));
      expect(notes, contains('main_stat.value: ожидался int'));
      expect(notes, contains('main_stat.isPercent: ожидался bool'));
    });

    test('неправильные ключи и значения карт обнаруживаются', () {
      final parsed = validData()
        ..['stats'] = <dynamic, dynamic>{
          123: <int>[10],
          'Здоровье': 'не список',
        };

      final notes = GameValidator.validate(parsed);

      expect(notes, contains('stats: ключ должен быть String'));
      expect(
        notes,
        contains('stats["Здоровье"]: ожидался List<int>'),
      );
    });

    test('ошибка парсера обнаруживается', () {
      final parsed = validData()..['error'] = 'test error';

      final notes = GameValidator.validate(parsed);

      expect(notes, contains('Ошибка парсера: test error'));
    });
  });
}

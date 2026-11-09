from pathlib import Path

path = Path("lib/main.dart")
source = path.read_text()

old = """      final validationNotes = GameValidator.validate(parsed);"""
new = """      final validationNotes = GameValidator.validate(parsed);
      _dprint('[GameValidator] DONE');"""

if source.count(old) != 1:
    raise SystemExit("СТОП: блок validate(parsed) не найден ровно один раз. Файл не изменён.")

source = source.replace(old, new, 1)
path.write_text(source)
print("Готово: DONE добавлен в main.dart после валидатора.")

# 1. Чиним parser.dart (добавляем ?? '')
with open('lib/parser.dart', 'r') as f:
    p = f.read()
p = p.replace("_cleanText(r.text)).join(", "_cleanText(r.text ?? '')).join(")
with open('lib/parser.dart', 'w') as f:
    f.write(p)

# 2. Чиним main.dart (убираем кривую кнопку и ставим ровную)
with open('lib/main.dart', 'r') as f:
    m = f.read()

# Находим сломанный кусок, который вставил прошлый скрипт
broken_part = """label: const Text('REPL'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _testOnnx,
                  icon: const Icon(Icons.memory),
                  label: const Text('Тест ONNX'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),"""

# Возвращаем как было
m = m.replace(broken_part, "label: const Text('REPL'),")

# Теперь вставляем кнопку ПРАВИЛЬНО (после блока REPL)
target = """label: const Text('REPL'),
                ),"""

good_button = """label: const Text('REPL'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _testOnnx,
                  icon: const Icon(Icons.memory),
                  label: const Text('Тест ONNX'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),"""

m = m.replace(target, good_button, 1)

with open('lib/main.dart', 'w') as f:
    f.write(m)

print("✅ Все скобки и null-safety ИСПРАВЛЕНЫ!")

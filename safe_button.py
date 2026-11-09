with open('lib/main.dart', 'r') as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    # Если нашли конец кнопки REPL
    if "label: const Text('REPL')," in line:
        new_lines.append("""                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _testOnnx,
                  icon: const Icon(Icons.memory),
                  label: const Text('Тест ONNX'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),\n""")

with open('lib/main.dart', 'w') as f:
    f.writelines(new_lines)
print("✅ Кнопка ТЕСТ ONNX вставлена безопасно!")

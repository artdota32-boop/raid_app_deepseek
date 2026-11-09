import re

with open('lib/main.dart', 'r') as f:
    code = f.read()

# 1. Удаляем все следы старых кривых вставок кнопки
code = re.sub(r"label: const Text\('REPL'\),\s*\),\s*const SizedBox\(height: 10\),\s*ElevatedButton\.icon\(\s*onPressed: _testOnnx,.*?\),", "label: const Text('REPL'),\n                ),", code, flags=re.DOTALL)
code = re.sub(r"ElevatedButton\.icon\(\s*onPressed: _testOnnx,.*?\),", "", code, flags=re.DOTALL)

# 2. Удаляем старую функцию _testOnnx, если она есть
code = re.sub(r"Future<void> _testOnnx\(\) async \{.*?\n  \}", "", code, flags=re.DOTALL)

# 3. Вставляем чистую функцию _testOnnx
func = """
  Future<void> _testOnnx() async {
    setState(() => _status = 'Загрузка ONNX модели...');
    try {
      final ort = OnnxRuntime();
      final session = await ort.createSessionFromAsset('assets/inference.onnx');
      setState(() => _status = '✅ ONNX Модель УСПЕШНО загружена!');
    } catch (e) {
      setState(() => _status = '❌ Ошибка ONNX: $e');
    }
  }

  void _dprint(String line) {"""
code = code.replace("  void _dprint(String line) {", func, 1)

# 4. Вставляем кнопку в 100% безопасное место (сразу после Выбрать видео)
target = "label: const Text('Выбрать видео'),"
new_button = """label: const Text('Выбрать видео'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _testOnnx,
                      icon: const Icon(Icons.memory),
                      label: const Text('Тест ONNX'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                    ),"""
code = code.replace(target, new_button, 1)

with open('lib/main.dart', 'w') as f:
    f.write(code)
print("✅ Файл main.dart полностью очищен и починен!")

with open('lib/main.dart', 'r') as f:
    code = f.read()

# 1. Добавляем импорт
if "flutter_onnxruntime" not in code:
    code = code.replace("import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;",
                        "import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;\nimport 'package:flutter_onnxruntime/flutter_onnxruntime.dart';")

# 2. Вставляем функцию ВНУТРЬ класса _HomePageState (перед _dprint)
if "_testOnnx" not in code:
    func = """
  Future<void> _testOnnx() async {
    setState(() => _status = 'Загрузка ONNX модели...');
    try {
      final ort = OnnxRuntime();
      final session = await ort.createSessionFromAsset('assets/inference.onnx');
      setState(() => _status = '✅ ONNX Модель УСПЕШНО загружена!');
      // session.dispose(); // В v1.9.0 этого метода нет
    } catch (e) {
      setState(() => _status = '❌ Ошибка ONNX: $e');
    }
  }

  void _dprint(String line) {"""
    code = code.replace("  void _dprint(String line) {", func)

# 3. Добавляем кнопку (оставляем как было)
if "Тест ONNX" not in code:
    btn = """
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _testOnnx,
                  icon: const Icon(Icons.memory),
                  label: const Text('Тест ONNX'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),"""
    code = code.replace("const SizedBox(height: 10),\n                ElevatedButton.icon(\n                  onPressed: _exportDataset,", btn + "\n                const SizedBox(height: 10),\n                ElevatedButton.icon(\n                  onPressed: _exportDataset,")

with open('lib/main.dart', 'w') as f:
    f.write(code)
print("✅ Код ONNX ИСПРАВЛЕН и добавлен в main.dart!")

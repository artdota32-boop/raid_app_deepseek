with open('lib/main.dart', 'r') as f:
    code = f.read()

# 1. Добавляем импорт библиотеки
if "flutter_onnxruntime" not in code:
    code = code.replace("import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;",
                        "import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;\nimport 'package:flutter_onnxruntime/flutter_onnxruntime.dart';")

# 2. Добавляем функцию теста перед @override build
if "_testOnnx" not in code:
    func = """
  Future<void> _testOnnx() async {
    setState(() => _status = 'Загрузка ONNX модели...');
    try {
      final ort = OnnxRuntime();
      final session = await ort.createSessionFromAsset('assets/inference.onnx');
      setState(() => _status = '✅ ONNX Модель УСПЕШНО загружена!');
      await session.dispose();
    } catch (e) {
      setState(() => _status = '❌ Ошибка ONNX: $e');
    }
  }

  @override
  Widget build(BuildContext context) {"""
    code = code.replace("  @override\n  Widget build(BuildContext context) {", func)

# 3. Добавляем кнопку в UI (после кнопки REPL)
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
print("✅ Код ONNX успешно добавлен в main.dart!")

with open('lib/main.dart', 'r') as f:
    code = f.read()

old_func = """  Future<void> _testOnnx() async {
    setState(() => _status = 'Загрузка ONNX модели...');
    try {
      final ort = OnnxRuntime();
      final session = await ort.createSessionFromAsset('assets/inference.onnx');
      setState(() => _status = '✅ ONNX Модель УСПЕШНО загружена!');
    } catch (e) {
      setState(() => _status = '❌ Ошибка ONNX: $e');
    }
  }"""

new_func = """  Future<void> _testOnnx() async {
    if (_croppedBytes == null) {
      setState(() => _status = '❌ Сначала выбери видео, чтобы получить кроп!');
      return;
    }
    setState(() => _status = 'Чтение текста через ONNX...');
    try {
      final result = await OnnxOcr.recognize(_croppedBytes!);
      setState(() => _status = 'Результат: $result');
    } catch (e) {
      setState(() => _status = '❌ Ошибка OCR: $e');
    }
  }"""

code = code.replace(old_func, new_func)

# Добавляем импорт, если его нет
if "onnx_ocr.dart" not in code:
    code = code.replace("import 'about_screen.dart';", "import 'about_screen.dart';\nimport 'onnx_ocr.dart';")

with open('lib/main.dart', 'w') as f:
    f.write(code)
print("✅ Функция _testOnnx обновлена для чтения картинки!")

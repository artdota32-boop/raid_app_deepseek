with open('lib/main.dart', 'r') as f:
    code = f.read()

if "Тест ONNX" not in code:
    # Ищем конец кнопки REPL
    target = "label: const Text('REPL'),"
    
    # Наша новая кнопка
    btn = """label: const Text('REPL'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _testOnnx,
                  icon: const Icon(Icons.memory),
                  label: const Text('Тест ONNX'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),
                ),"""
    
    if target in code:
        code = code.replace(target, btn, 1)
        with open('lib/main.dart', 'w') as f:
            f.write(code)
        print("✅ Кнопка ТЕСТ ONNX успешно добавлена в интерфейс!")
    else:
        print("❌ Не нашли кнопку REPL. Скинь скрин кода вокруг кнопки REPL.")
else:
    print("✅ Кнопка уже есть в коде.")

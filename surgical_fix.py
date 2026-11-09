import re

with open('lib/main.dart', 'r') as f:
    code = f.read()

# 1. Убираем лишнюю скобку у первой кнопки ONNX
code = re.sub(r"style: ElevatedButton\.styleFrom\(backgroundColor: Colors\.orange\.shade100\),\s*\),\s*\),", "style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade100),\n                    ),", code)

# 2. Убираем "осиротевший" кусок кода после кнопки REPL
code = re.sub(r"label: const Text\('REPL'\),\s*\),\s*label: const Text\('Тест ONNX'\),\s*style: ElevatedButton\.styleFrom\(backgroundColor: Colors\.orange\.shade100\),", "label: const Text('REPL'),\n                    ),", code)

# 3. Возвращаем забытую скобку кнопке "Экспорт датасета"
code = re.sub(r"style: ElevatedButton\.styleFrom\(backgroundColor: Colors\.green\.shade100\),\s*const SizedBox\(height: 10\),", "style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade100),\n                    ),\n                    const SizedBox(height: 10),", code)

with open('lib/main.dart', 'w') as f:
    f.write(code)
print("✅ Хирургический фикс применен! Мусор удален.")

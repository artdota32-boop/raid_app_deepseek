with open('lib/main.dart', 'r') as f:
    lines = f.readlines()

out = []
for i, line in enumerate(lines):
    if line.strip() == "),":
        # Проверяем, что это лишняя скобка после нашей кнопки
        prev_text = "".join(lines[max(0, i-10):i])
        if "Тест ONNX" in prev_text and "ElevatedButton.icon" in prev_text:
            continue # Пропускаем (удаляем) эту лишнюю скобку
    out.append(line)

with open('lib/main.dart', 'w') as f:
    f.writelines(out)
print("✅ Лишняя скобка в main.dart удалена!")

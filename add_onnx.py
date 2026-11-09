with open('pubspec.yaml', 'r') as f:
    lines = f.readlines()

new_lines = []
added = False
for line in lines:
    new_lines.append(line)
    if line.strip() == 'dependencies:' and not added:
        new_lines.append('  flutter_onnxruntime: ^1.4.1\n')
        added = True

with open('pubspec.yaml', 'w') as f:
    f.writelines(new_lines)

if added:
    print("✅ Успешно добавили flutter_onnxruntime в pubspec.yaml")
else:
    print("❌ Не нашли 'dependencies:' в pubspec.yaml")

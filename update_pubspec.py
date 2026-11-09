with open('pubspec.yaml', 'r') as f:
    lines = f.readlines()

new_lines = []
in_assets = False
for line in lines:
    new_lines.append(line)
    if 'assets:' in line and not line.strip().startswith('#'):
        in_assets = True
        indent = line[:len(line) - len(line.lstrip())] + '  '

if in_assets:
    content = "".join(new_lines)
    if 'assets/inference.onnx' not in content:
        final_lines = []
        for line in new_lines:
            final_lines.append(line)
            if 'assets:' in line and not line.strip().startswith('#'):
                final_lines.append(f"{indent}- assets/inference.onnx\n")
                final_lines.append(f"{indent}- assets/dict.txt\n")
        with open('pubspec.yaml', 'w') as f:
            f.writelines(final_lines)
        print("✅ Успешно добавили onnx и dict в pubspec.yaml")
    else:
        print("✅ Файлы уже прописаны в pubspec.yaml")
else:
    print("❌ Не нашли 'assets:' в pubspec.yaml. Скинь скрин pubspec.yaml.")

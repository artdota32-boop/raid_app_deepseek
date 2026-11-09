import os

path = 'android/app/src/main/AndroidManifest.xml'

if not os.path.exists(path):
    print("❌ Файл не найден по пути:", path)
else:
    with open(path, 'r') as f:
        code = f.read()

    # 1. Меняем старую систему на новую
    code = code.replace('android:name="io.flutter.app.FlutterApplication"', 'android:name="${applicationName}"')
    
    # 2. Добавляем мету v2 embedding, если её нет
    if 'flutterEmbedding' not in code:
        code = code.replace('</application>', '    <meta-data android:name="flutterEmbedding" android:value="2" />\n    </application>')

    with open(path, 'w') as f:
        f.write(code)
    print("✅ AndroidManifest.xml успешно обновлен!")

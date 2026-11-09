with open('lib/main.dart', 'r') as f:
    code = f.read()

old_appbar = """appBar: AppBar(title: Text('Raid Scanner $_version')),"""

new_appbar = """appBar: AppBar(
        title: const Text('Raid Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
            },
          ),
        ],
      ),"""

code = code.replace(old_appbar, new_appbar)

# Добавляем импорт
if "about_screen.dart" not in code:
    code = code.replace("import 'parser.dart';", "import 'parser.dart';\nimport 'about_screen.dart';")

with open('lib/main.dart', 'w') as f:
    f.write(code)
print("✅ Кнопка 'О программе' и новый AppBar добавлены!")

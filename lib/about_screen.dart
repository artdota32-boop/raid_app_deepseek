import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('О приложении'),
        backgroundColor: Colors.deepPurple,
      ),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final info = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 30),
              // Иконка (заглушка, потом заменим)
              const Icon(Icons.shield, size: 100, color: Colors.deepPurple),
              const SizedBox(height: 20),
              // Название и версия
              Center(
                child: Text(
                  'Raid Scanner',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  'Версия ${info.version} (${info.buildNumber})',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 40),
              const Divider(),
              // Лог изменений
              const ListTile(
                leading: Icon(Icons.new_releases, color: Colors.amber),
                title: Text('Что нового в этой версии'),
                subtitle: Text('✅ Добавлена кнопка Тест ONNX\n✅ Настроена сборка через GitHub Actions\n✅ Исправлены ошибки Gradle и Kotlin'),
              ),
              const Divider(),
              // Разработчики
              const ListTile(
                leading: Icon(Icons.code, color: Colors.blue),
                title: Text('Разработчики'),
                subtitle: Text('Артурик (идеи, тесты) и Дип (код, логика)'),
              ),
              const Divider(),
              // Кодовое слово (пасхалка)
              const ListTile(
                leading: Icon(Icons.lock, color: Colors.green),
                title: Text('Кодовое слово'),
                subtitle: Text('«братик»'),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class RoboflowApi {
  static const String apiKey = String.fromEnvironment('ROBOFLOW_API_KEY');
  static const String modelId = "raid_stars-1-resnet18-t2";
  static const String endpoint = "https://classify.roboflow.com/$modelId";

  static Future<String?> classifyImage(File imageFile) async {
    if (apiKey.isEmpty) {
      print('Roboflow API key is not configured. Set --dart-define=ROBOFLOW_API_KEY=...');
      return null;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$endpoint?api_key=$apiKey'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        body: base64Image,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['top']; // возвращает '5star' или '6star'
      } else {
        print('Ошибка API: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Ошибка запроса: $e');
      return null;
    }
  }
}

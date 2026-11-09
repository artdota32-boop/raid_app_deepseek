import 'dart:io';
import 'package:image/image.dart' as img;
import '../lib/polygon/polygon_detector.dart';

void main(List<String> args) {
  final inputPath = args.isNotEmpty
      ? args[0]
      : 'screenshots/speed_ru_frame.png';

  final input = File(inputPath);

  if (!input.existsSync()) {
    print('ERROR: source image not found: $inputPath');
    exitCode = 2;
    return;
  }

  final source = img.decodeImage(input.readAsBytesSync());

  if (source == null) {
    print('ERROR: cannot decode source image');
    exitCode = 2;
    return;
  }

  print('===== POLYGON RAW PROBE =====');
  print('SOURCE: $inputPath');
  print('IMAGE: ${source.width}x${source.height}');

  const detector = PolygonDetector();
  final detection = detector.detect(source);

  if (detection == null) {
    print('RESULT: PANEL NOT FOUND');
    exitCode = 2;
    return;
  }

  final b = detection.bounds;

  print('RESULT: PANEL FOUND');
  print('RAW BBOX: x=${b.left}, y=${b.top}, '
      'w=${b.width}, h=${b.height}');
  print('CONFIDENCE: ${detection.confidence.toStringAsFixed(3)}');

  if (b.left < 0 || b.top < 0 ||
      b.width <= 0 || b.height <= 0 ||
      b.left + b.width > source.width ||
      b.top + b.height > source.height) {
    print('ERROR: invalid crop coordinates');
    exitCode = 2;
    return;
  }

  final crop = img.copyCrop(
    source,
    x: b.left,
    y: b.top,
    width: b.width,
    height: b.height,
  );

  final outputDir = Directory('screenshots/outputs');
  outputDir.createSync(recursive: true);

  const cropPath = 'screenshots/outputs/polygon_raw_crop.png';
  const debugPath = 'screenshots/outputs/polygon_raw_debug.png';

  File(cropPath).writeAsBytesSync(img.encodePng(crop));

  final debug = detector.drawDebug(source, detection);
  File(debugPath).writeAsBytesSync(img.encodePng(debug));

  print('RAW CROP: ${crop.width}x${crop.height}');
  print('SAVED: $cropPath');
  print('SAVED: $debugPath');
  print('===== DONE =====');
}

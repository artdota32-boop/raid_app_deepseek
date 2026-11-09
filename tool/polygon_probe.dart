import 'dart:io';
import 'package:image/image.dart' as img;
import '../lib/polygon/polygon_detector.dart';

void main(List<String> args) {
  final inputPath =
      args.isNotEmpty ? args[0] : 'screenshots/speed_ru_frame.png';

  final bytes = File(inputPath).readAsBytesSync();
  final source = img.decodeImage(bytes);

  if (source == null) {
    stderr.writeln('ERROR: cannot decode');
    exitCode = 2;
    return;
  }

  print('===== POLYGON PROBE =====');
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
  print('BBOX: x=${b.left}, y=${b.top}, w=${b.width}, h=${b.height}');
  print('CONFIDENCE: ${detection.confidence.toStringAsFixed(3)}');
  print('TOP LINE: ${detection.topLineStartX} - ${detection.topLineEndX}');
  print('LEFT: ${detection.leftVerticalCoverage.toStringAsFixed(3)}');
  print('RIGHT: ${detection.rightVerticalCoverage.toStringAsFixed(3)}');

  final debug = detector.drawDebug(source, detection);
  const out = 'screenshots/outputs/polygon_debug.png';
  File(out).writeAsBytesSync(img.encodePng(debug));
  print('SAVED: $out');
  print('===== DONE =====');
}

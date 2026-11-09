import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import '../lib/polygon/polygon_detector.dart';

void main(List<String> args) {
  final inputPath =
      args.isNotEmpty ? args[0] : 'screenshots/speed_ru_frame.png';

  final input = File(inputPath);

  if (!input.existsSync()) {
    print('ERROR: SOURCE NOT FOUND: $inputPath');
    exitCode = 2;
    return;
  }

  final source = img.decodeImage(input.readAsBytesSync());

  if (source == null) {
    print('ERROR: IMAGE DECODE FAILED');
    exitCode = 2;
    return;
  }

  const detector = PolygonDetector();
  final detection = detector.detect(source);

  print('===== POLYGON DIAGNOSTICS =====');
  print('SOURCE: $inputPath');
  print('IMAGE: ${source.width}x${source.height}');

  if (detection == null) {
    print('RESULT: PANEL NOT FOUND');
    exitCode = 2;
    return;
  }

  final b = detection.bounds;

  print('RESULT: PANEL FOUND');
  print('BBOX: x=${b.left}, y=${b.top}, '
      'w=${b.width}, h=${b.height}');
  print('CONFIDENCE: ${detection.confidence.toStringAsFixed(3)}');

  print('BOTTOM_BOUNDARY_FOUND: ${detection.bottomBoundaryFound}');
  print('BOTTOM_LINE_Y: ${detection.bottomLineY ?? "NOT FOUND"}');
  print('BOTTOM_FALLBACK: ${detection.usedBottomFallback}');

  print('LEFT_COVERAGE: ${detection.leftVerticalCoverage.toStringAsFixed(3)}');
  print(
      'RIGHT_COVERAGE: ${detection.rightVerticalCoverage.toStringAsFixed(3)}');

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
  const reportPath = 'screenshots/outputs/polygon_diagnostics.json';

  File(cropPath).writeAsBytesSync(img.encodePng(crop));

  final debug = detector.drawDebug(source, detection);
  File(debugPath).writeAsBytesSync(img.encodePng(debug));

  final report = {
    'source': inputPath,
    'image': {
      'width': source.width,
      'height': source.height,
    },
    'result': 'found',
    'bbox': b.toJson(),
    'confidence': detection.confidence,
    'confidence_note':
        'Heuristic score for top and side detection; it does not measure bottom-boundary certainty.',
    'bottom_boundary_found': detection.bottomBoundaryFound,
    'bottom_line_y': detection.bottomLineY,
    'bottom_fallback_used': detection.usedBottomFallback,
    'left_vertical_coverage': detection.leftVerticalCoverage,
    'right_vertical_coverage': detection.rightVerticalCoverage,
    'raw_crop': {
      'width': crop.width,
      'height': crop.height,
      'path': cropPath,
    },
  };

  File(reportPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );

  print('RAW CROP: ${crop.width}x${crop.height}');
  print('SAVED: $cropPath');
  print('SAVED: $debugPath');
  print('REPORT: $reportPath');
  print('===== DONE =====');
}

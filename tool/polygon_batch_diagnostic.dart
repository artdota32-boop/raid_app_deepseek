import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;

import '../lib/polygon/polygon_detector.dart';

Future<void> main(List<String> args) async {
  final inputPath =
      args.isNotEmpty ? args[0] : 'experiments/polygon_test_frames';
  final outputPath = args.length > 1
      ? args[1]
      : inputPath + Platform.pathSeparator + 'debug';

  final inputDir = Directory(inputPath);
  if (!await inputDir.exists()) {
    stderr.writeln('Input directory does not exist: $inputPath');
    exitCode = 2;
    return;
  }

  final files = (await inputDir
          .list(followLinks: false)
          .where((entry) => entry is File)
          .cast<File>()
          .where((file) {
            final name = file.uri.pathSegments.last.toLowerCase();
            return name.endsWith('.png') ||
                name.endsWith('.jpg') ||
                name.endsWith('.jpeg');
          })
          .toList())
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('No PNG/JPG images found in: $inputPath');
    exitCode = 2;
    return;
  }

  await Directory(outputPath).create(recursive: true);

  const detector = PolygonDetector();
  final results = <Map<String, dynamic>>[];

  for (final file in files) {
    final name = file.uri.pathSegments.last;

    try {
      final source = img.decodeImage(await file.readAsBytes());

      if (source == null) {
        stderr.writeln('DECODE_FAILED  $name');
        results.add({'file': name, 'status': 'decode_failed'});
        continue;
      }

      final detection = detector.detect(source);

      if (detection == null) {
        stdout.writeln(
          'NOT_FOUND      $name  ' +
              source.width.toString() +
              'x' +
              source.height.toString(),
        );
        results.add({
          'file': name,
          'status': 'not_found',
          'width': source.width,
          'height': source.height,
        });
        continue;
      }

      final debugImage = detector.drawDebug(source, detection);
      final debugName = name.replaceFirst(
        RegExp(r'\.(png|jpe?g)$', caseSensitive: false),
        '_debug.png',
      );
      final debugPath = outputPath + Platform.pathSeparator + debugName;
      await File(debugPath).writeAsBytes(img.encodePng(debugImage));

      final box = detection.bounds;
      final bottomText = detection.bottomBoundaryFound
          ? detection.bottomLineY.toString()
          : 'fallback';

      stdout.writeln(
        'FOUND          ' +
            name +
            '  ' +
            source.width.toString() +
            'x' +
            source.height.toString() +
            ' confidence=' +
            detection.confidence.toStringAsFixed(3) +
            ' box=(' +
            box.left.toString() +
            ',' +
            box.top.toString() +
            ',' +
            box.width.toString() +
            ',' +
            box.height.toString() +
            ') bottom=' +
            bottomText +
            ' bottomTouchesImageEdge=' +
            detection.bottomTouchesImageEdge.toString(),
      );

      results.add({
        'file': name,
        'status': 'found',
        'width': source.width,
        'height': source.height,
        'confidence': detection.confidence,
        'bbox': box.toJson(),
        'top_line': {
          'start_x': detection.topLineStartX,
          'end_x': detection.topLineEndX,
        },
        'left_vertical_coverage': detection.leftVerticalCoverage,
        'right_vertical_coverage': detection.rightVerticalCoverage,
        'bottom_boundary_found': detection.bottomBoundaryFound,
        'bottom_line_y': detection.bottomLineY,
        'bottom_touches_image_edge': detection.bottomTouchesImageEdge,
        'used_bottom_fallback': detection.usedBottomFallback,
        'debug_image': debugPath,
      });
    } catch (error, stackTrace) {
      stderr.writeln('ERROR          $name  $error');
      stderr.writeln(stackTrace);
      results.add({
        'file': name,
        'status': 'error',
        'error': error.toString(),
      });
    }
  }

  final foundCount =
      results.where((result) => result['status'] == 'found').length;
  final summary = {
    'input_directory': inputPath,
    'output_directory': outputPath,
    'total_files': files.length,
    'found': foundCount,
    'not_found': results.where((r) => r['status'] == 'not_found').length,
    'decode_failed':
        results.where((r) => r['status'] == 'decode_failed').length,
    'errors': results.where((r) => r['status'] == 'error').length,
    'results': results,
  };

  final summaryPath =
      outputPath + Platform.pathSeparator + 'polygon_batch_results.json';
  await File(summaryPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(summary),
  );

  stdout.writeln('');
  stdout.writeln('Processed: ' + files.length.toString());
  stdout.writeln('Detected:  ' + foundCount.toString());
  stdout.writeln('Report:    ' + summaryPath);
  stdout.writeln('Debug PNGs: ' + outputPath);
}

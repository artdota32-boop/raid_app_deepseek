import 'dart:io';

import 'package:image/image.dart' as img;

import '../lib/polygon/polygon_detector.dart';

class _Run {
  final int start;
  final int end;

  const _Run(this.start, this.end);

  int get length => end - start + 1;

  @override
  String toString() => '$start..$end (len=$length)';
}

Future<void> main(List<String> args) async {
  final inputPath =
      args.isNotEmpty ? args[0] : 'experiments/polygon_test_frames';
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

  const detector = PolygonDetector();

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final image = img.decodeImage(await file.readAsBytes());

    if (image == null) {
      stdout.writeln('$name: DECODE_FAILED');
      continue;
    }

    final detection = detector.detect(image);
    if (detection == null) {
      stdout.writeln('$name: NOT_FOUND');
      continue;
    }

    final left = detection.bounds.left;
    final right = detection.bounds.right - 1;
    final width = right - left + 1;
    final minRunLength = (width * 0.70).round();
    final tolerance = (width * 0.05).round() < 10
        ? 10
        : (width * 0.05).round();
    final xFrom = (left - tolerance).clamp(0, image.width - 1).toInt();
    final xTo = (right + tolerance).clamp(0, image.width - 1).toInt();

    stdout.writeln('');
    stdout.writeln(
      '$name  box=(${detection.bounds.left},${detection.bounds.top},'
      '${detection.bounds.width},${detection.bounds.height}) '
      'bottomY=${detection.bottomLineY}',
    );
    stdout.writeln(
      '  bottom scan x=$xFrom..$xTo, minRun=$minRunLength, '
      'endpoint tolerance=$tolerance',
    );

    var candidateCount = 0;
    final scanStart = detection.bounds.top + 20;

    for (var y = scanStart; y < image.height; y++) {
      final run = _longestCyanRun(image, y, xFrom, xTo);
      if (run == null || run.length < minRunLength) continue;

      final leftMatch = (run.start - left).abs() <= tolerance;
      final rightMatch = (run.end - right).abs() <= tolerance;
      if (!leftMatch || !rightMatch) continue;

      final neighborRows = <String>[];
      var neighborHits = 0;

      for (final dy in [-1, 1]) {
        final neighborY = y + dy;
        if (neighborY < 0 || neighborY >= image.height) continue;

        final neighborRun =
            _longestCyanRun(image, neighborY, xFrom, xTo);
        final matches = neighborRun != null &&
            neighborRun.length >= minRunLength &&
            (neighborRun.start - left).abs() <= tolerance &&
            (neighborRun.end - right).abs() <= tolerance;

        if (matches) neighborHits++;
        neighborRows.add(
          '$neighborY=${matches ? neighborRun : 'no-match'}',
        );
      }

      if (neighborHits == 0) continue;
      candidateCount++;

      final probeFrom = y + 4;
      if (probeFrom >= image.height) {
        stdout.writeln(
          '  MATCH y=$y run=$run neighbors={${neighborRows.join(', ')}} '
          'below-probe=UNAVAILABLE (starts at $probeFrom, '
          'image ends at ${image.height - 1})',
        );
      } else {
        final probeTo =
            (probeFrom + 11).clamp(0, image.height - 1).toInt();
        final leftHits =
            _verticalHits(image, left, probeFrom, probeTo);
        final rightHits =
            _verticalHits(image, right, probeFrom, probeTo);
        final total = probeTo - probeFrom + 1;
        stdout.writeln(
          '  MATCH y=$y run=$run neighbors={${neighborRows.join(', ')}} '
          'below-probe=$probeFrom..$probeTo '
          'left=$leftHits/$total right=$rightHits/$total',
        );
      }
    }

    stdout.writeln('  aligned candidates with neighbor: $candidateCount');

    final tailStart = image.height - 20;
    final leftTail = _verticalHits(
      image,
      left,
      tailStart,
      image.height - 1,
    );
    final rightTail = _verticalHits(
      image,
      right,
      tailStart,
      image.height - 1,
    );
    stdout.writeln(
      '  cyan side hits in last 20 rows: left=$leftTail/20 '
      'right=$rightTail/20',
    );
  }

  stdout.writeln('');
  stdout.writeln('Probe complete. No source images were modified.');
}

_Run? _longestCyanRun(img.Image image, int y, int xFrom, int xTo) {
  _Run? best;
  int? start;

  for (var x = xFrom; x <= xTo; x++) {
    if (_isCyan(image, x, y)) {
      start ??= x;
    } else if (start != null) {
      final candidate = _Run(start, x - 1);
      if (best == null || candidate.length > best.length) {
        best = candidate;
      }
      start = null;
    }
  }

  if (start != null) {
    final candidate = _Run(start, xTo);
    if (best == null || candidate.length > best.length) {
      best = candidate;
    }
  }

  return best;
}

int _verticalHits(img.Image image, int x, int fromY, int toY) {
  var hits = 0;

  for (var y = fromY; y <= toY; y++) {
    var found = false;

    for (var dx = -2; dx <= 2; dx++) {
      final px = x + dx;
      if (px < 0 || px >= image.width) continue;

      if (_isCyan(image, px, y)) {
        found = true;
        break;
      }
    }

    if (found) hits++;
  }

  return hits;
}

bool _isCyan(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  final r = pixel.r.toDouble();
  final g = pixel.g.toDouble();
  final b = pixel.b.toDouble();

  return g > 100 &&
      b > 120 &&
      g > r * 1.35 &&
      b > r * 1.35 &&
      (g - b).abs() < 100;
}

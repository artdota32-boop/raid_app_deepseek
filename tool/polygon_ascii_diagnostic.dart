import 'dart:io';

import 'package:image/image.dart' as img;

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

class _Run {
  final int start;
  final int end;

  const _Run(this.start, this.end);

  int get length => end - start + 1;
}

_Run? _longestRun(img.Image image, int y, int xFrom, int xTo) {
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
      if (px >= 0 && px < image.width && _isCyan(image, px, y)) {
        found = true;
        break;
      }
    }
    if (found) hits++;
  }

  return hits;
}

String _buildReport(img.Image image, String fileName, int imageCount) {
  final out = StringBuffer();
  out.writeln('POLYGON ASCII DIAGNOSTIC');
  out.writeln('Files scanned: $imageCount');
  out.writeln('Map source: $fileName');
  out.writeln('Image: ${image.width}x${image.height}');
  out.writeln('Color rule: same cyan threshold as PolygonDetector');
  out.writeln('Map ROI: x=40..479, y=336..719; each symbol = 8x8 pixels');
  out.writeln('Legend: space=0 cyan, .=1-2, +=3-7, #=8 or more');
  out.writeln('');

  const x0 = 40;
  const y0 = 336;
  const cell = 8;
  final x1 = image.width < 480 ? image.width - 1 : 479;
  final y1 = image.height - 1;

  final columns = ((x1 - x0 + 1) / cell).ceil();
  final rows = ((y1 - y0 + 1) / cell).ceil();

  out.writeln('ASCII MAP (row labels are source-image Y coordinates):');
  for (var row = 0; row < rows; row++) {
    final yStart = y0 + row * cell;
    final yEnd = (yStart + cell - 1).clamp(0, y1).toInt();
    final symbols = StringBuffer();

    for (var col = 0; col < columns; col++) {
      final xStart = x0 + col * cell;
      final xEnd = (xStart + cell - 1).clamp(0, x1).toInt();
      var count = 0;

      for (var y = yStart; y <= yEnd; y++) {
        for (var x = xStart; x <= xEnd; x++) {
          if (_isCyan(image, x, y)) count++;
        }
      }

      symbols.write(
        count == 0 ? ' ' : count <= 2 ? '.' : count <= 7 ? '+' : '#',
      );
    }

    out.writeln('${yStart.toString().padLeft(3)} |$symbols|');
  }

  out.writeln('');
  out.writeln('BOTTOM EDGE ROW SCAN (x=50..475; rows with cyan run >=100px):');
  final scanX1 = image.width < 476 ? image.width - 1 : 475;
  for (var y = image.height - 40; y < image.height; y++) {
    final run = _longestRun(image, y, 50, scanX1);
    if (run != null && run.length >= 100) {
      out.writeln('y=$y  run=${run.start}..${run.end}  length=${run.length}');
    }
  }

  out.writeln('');
  out.writeln('SIDE PIXEL CHECK (last 20 rows):');
  final leftX = 76;
  final rightX = 447;
  final fromY = image.height - 20;
  out.writeln('left x=$leftX: ${_verticalHits(image, leftX, fromY, image.height - 1)}/20');
  out.writeln('right x=$rightX: ${_verticalHits(image, rightX, fromY, image.height - 1)}/20');

  return out.toString();
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

  if (files.isEmpty) {
    stderr.writeln('No PNG/JPG frames found.');
    exitCode = 2;
    return;
  }

  File? selected;
  for (final file in files) {
    if (file.uri.pathSegments.last.toLowerCase() == 'speed_ru.png') {
      selected = file;
      break;
    }
  }
  selected ??= files.first;

  final decoded = img.decodeImage(await selected.readAsBytes());
  if (decoded == null) {
    stderr.writeln('Cannot decode ${selected.path}');
    exitCode = 2;
    return;
  }

  final report = _buildReport(
    decoded,
    selected.uri.pathSegments.last,
    files.length,
  );

  final output = File(
    '$inputPath/polygon_ascii_diagnostic.txt',
  );
  await output.writeAsString(report);

  stdout.writeln('TXT report created: ${output.path}');
  stdout.writeln('Source frames scanned: ${files.length}');
  stdout.writeln('Map source: ${selected.uri.pathSegments.last}');
  stdout.writeln('Report size: ${await output.length()} bytes');
  stdout.writeln('');
  stdout.writeln('Preview:');
  stdout.write(report);
}

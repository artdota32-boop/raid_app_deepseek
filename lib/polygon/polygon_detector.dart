import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'polygon_models.dart';

class PolygonDetection {
  final PolygonBox bounds;
  final double confidence;
  final int topLineStartX;
  final int topLineEndX;
  final double leftVerticalCoverage;
  final double rightVerticalCoverage;

  final bool bottomBoundaryFound;
  final int? bottomLineY;
  final bool bottomTouchesImageEdge;
  final bool usedBottomFallback;

  const PolygonDetection({
    required this.bounds,
    required this.confidence,
    required this.topLineStartX,
    required this.topLineEndX,
    required this.leftVerticalCoverage,
    required this.rightVerticalCoverage,
    required this.bottomBoundaryFound,
    required this.bottomLineY,
    required this.bottomTouchesImageEdge,
    required this.usedBottomFallback,
  });
}

class _VerticalMatch {
  final int x;
  final double coverage;

  const _VerticalMatch(this.x, this.coverage);
}

class _HorizontalMatch {
  final int startX;
  final int endX;

  int get length => endX - startX + 1;

  const _HorizontalMatch(this.startX, this.endX);
}

/// First POLYGON prototype:
/// detects the turquoise upper border, side edges and bottom border
/// of the known artifact-details panel.
class PolygonDetector {
  const PolygonDetector();

  PolygonDetection? detect(img.Image image) {
    if (image.width < 200 || image.height < 150) return null;

    final minLineLength = (image.width * 0.16).round();
    final maxStartX = (image.width * 0.50).round();
    final maxRightGap = (image.width * 0.10).round();

    PolygonDetection? best;

    final minY = (image.height * 0.12).round();
    final maxY = (image.height * 0.85).round();

    for (var y = minY; y < maxY; y++) {
      var x = 0;

      while (x < image.width) {
        if (!_isCyan(image, x, y)) {
          x++;
          continue;
        }

        final startX = x;

        while (x < image.width && _isCyan(image, x, y)) {
          x++;
        }

        final endX = x - 1;
        final lineLength = endX - startX + 1;

        if (lineLength < minLineLength || startX > maxStartX) {
          continue;
        }

        final left = _bestVertical(
          image,
          startX - 3,
          startX + 3,
          y + 4,
        );

        if (left == null || left.coverage < 0.45) continue;

        final right = _bestVertical(
          image,
          endX - 2,
          math.min(image.width - 1, endX + maxRightGap).toInt(),
          y + 4,
        );

        if (right == null || right.coverage < 0.45) continue;
        if (right.x <= left.x) continue;

        final panelWidth = right.x - left.x + 1;

        if (panelWidth < image.width * 0.18 ||
            panelWidth > image.width * 0.50) {
          continue;
        }

        // A panel's true top edge is where both side edges begin.
        // If both vertical edges already continue above this line, this
        // horizontal run is an interior separator, not the panel top.
        if (_hasVerticalContinuationAbove(image, left.x, right.x, y)) {
          continue;
        }

        final lineScore =
            (lineLength / (image.width * 0.22)).clamp(0.0, 1.0).toDouble();

        final gap = right.x - endX;

        final gapScore =
            (1.0 - gap / math.max(1, maxRightGap)).clamp(0.0, 1.0).toDouble();

        final confidence = 0.35 * lineScore +
            0.30 * left.coverage +
            0.30 * right.coverage +
            0.05 * gapScore;

        if (confidence < 0.62) continue;

        // Search for the real bottom border.
        final bottomLineY = _findBottomLine(
          image,
          left.x,
          right.x,
          y,
        );

        // Bottom line occupies at least two rows in our current test.
        // If not found, use the image edge but mark the fallback.
        final rawBottom = bottomLineY != null
            ? math.min(image.height, bottomLineY + 2).toInt()
            : image.height;

        final boxHeight = rawBottom - y;
        if (boxHeight <= 0) continue;

        final detection = PolygonDetection(
          bounds: PolygonBox(
            left: left.x,
            top: y,
            width: panelWidth,
            height: boxHeight,
          ),
          confidence: confidence,
          topLineStartX: startX,
          topLineEndX: endX,
          leftVerticalCoverage: left.coverage,
          rightVerticalCoverage: right.coverage,
          bottomBoundaryFound: bottomLineY != null,
          bottomLineY: bottomLineY,
          // A detected line can still be cut off by the image boundary.
          // Keep that uncertainty separate from whether a cyan line matched.
          bottomTouchesImageEdge:
              bottomLineY != null && bottomLineY + 2 >= image.height,
          usedBottomFallback: bottomLineY == null,
        );

        if (best == null || detection.confidence > best.confidence) {
          best = detection;
        }
      }
    }

    return best;
  }

  /// Finds a horizontal cyan line aligned with both panel side edges.
  /// Returns the first valid line from top to bottom.
  int? _findBottomLine(
    img.Image image,
    int panelLeft,
    int panelRight,
    int startY,
  ) {
    final panelWidth = panelRight - panelLeft + 1;
    if (panelWidth <= 0) return null;

    final minLineLength = (panelWidth * 0.70).round();

    final edgeTolerance = math.max(10, (panelWidth * 0.05).round()).toInt();

    final xFrom = math.max(0, panelLeft - edgeTolerance).toInt();
    final xTo = math.min(image.width - 1, panelRight + edgeTolerance).toInt();

    if (xFrom > xTo) return null;

    final scanStart = math.min(image.height - 1, startY + 20).toInt();

    for (var y = scanStart; y < image.height; y++) {
      final currentRun = _longestCyanRun(
        image,
        y,
        xFrom,
        xTo,
      );

      if (!_matchesBottomLine(
        currentRun,
        panelLeft,
        panelRight,
        minLineLength,
        edgeTolerance,
      )) {
        continue;
      }

      // Check the adjacent rows.
      // A neighboring row must also match both side edges.
      var neighborHits = 0;

      for (final dy in [-1, 1]) {
        final neighborY = y + dy;

        if (neighborY < 0 || neighborY >= image.height) {
          continue;
        }

        final neighborRun = _longestCyanRun(
          image,
          neighborY,
          xFrom,
          xTo,
        );

        if (_matchesBottomLine(
          neighborRun,
          panelLeft,
          panelRight,
          minLineLength,
          edgeTolerance,
        )) {
          neighborHits++;
        }
      }

      if (neighborHits >= 1) {
        // An interior separator can align perfectly with both side edges.
        // It is not the panel bottom if those edges continue below it.
        if (_hasVerticalContinuationBelow(image, panelLeft, panelRight, y)) {
          continue;
        }
        return y;
      }
    }

    return null;
  }

  bool _hasVerticalContinuationAbove(
    img.Image image,
    int panelLeft,
    int panelRight,
    int topY,
  ) {
    const probeRows = 8;
    final fromY = math.max(0, topY - probeRows).toInt();
    final toY = topY - 1;

    if (fromY > toY) return false;

    final leftCoverage =
        _verticalCoverageInRange(image, panelLeft, fromY, toY);
    final rightCoverage =
        _verticalCoverageInRange(image, panelRight, fromY, toY);

    // Require both sides to continue above the candidate to avoid rejecting
    // a true top edge because of an isolated cyan mark.
    return leftCoverage >= 0.40 && rightCoverage >= 0.40;
  }

  bool _hasVerticalContinuationBelow(
    img.Image image,
    int panelLeft,
    int panelRight,
    int bottomLineY,
  ) {
    const borderThicknessAllowance = 4;
    const probeRows = 12;

    final fromY = bottomLineY + borderThicknessAllowance;
    if (fromY >= image.height) return false;

    final toY = math.min(image.height - 1, fromY + probeRows - 1).toInt();

    final leftCoverage =
        _verticalCoverageInRange(image, panelLeft, fromY, toY);
    final rightCoverage =
        _verticalCoverageInRange(image, panelRight, fromY, toY);

    // Either side continuing below the horizontal run means that run is
    // an interior divider rather than a closed bottom edge.
    return leftCoverage >= 0.40 || rightCoverage >= 0.40;
  }

  double _verticalCoverageInRange(
    img.Image image,
    int x,
    int fromY,
    int toY,
  ) {
    if (fromY > toY) return 0.0;

    final totalRows = toY - fromY + 1;
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

    return hits / totalRows;
  }

  bool _matchesBottomLine(
    _HorizontalMatch? run,
    int panelLeft,
    int panelRight,
    int minLineLength,
    int edgeTolerance,
  ) {
    if (run == null || run.length < minLineLength) {
      return false;
    }

    final leftMatch = (run.startX - panelLeft).abs() <= edgeTolerance;

    final rightMatch = (run.endX - panelRight).abs() <= edgeTolerance;

    return leftMatch && rightMatch;
  }

  _HorizontalMatch? _longestCyanRun(
    img.Image image,
    int y,
    int xFrom,
    int xTo,
  ) {
    _HorizontalMatch? best;
    int? runStart;

    for (var x = xFrom; x <= xTo; x++) {
      if (_isCyan(image, x, y)) {
        runStart ??= x;
      } else if (runStart != null) {
        final candidate = _HorizontalMatch(runStart, x - 1);

        if (best == null || candidate.length > best.length) {
          best = candidate;
        }

        runStart = null;
      }
    }

    if (runStart != null) {
      final candidate = _HorizontalMatch(runStart, xTo);

      if (best == null || candidate.length > best.length) {
        best = candidate;
      }
    }

    return best;
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

  _VerticalMatch? _bestVertical(
    img.Image image,
    int firstX,
    int lastX,
    int startY,
  ) {
    final fromX = math.max(0, firstX).toInt();
    final toX = math.min(image.width - 1, lastX).toInt();

    if (fromX > toX) return null;

    final y0 = math.min(image.height, startY).toInt();
    final totalRows = image.height - y0;

    if (totalRows <= 0) return null;

    _VerticalMatch? best;

    for (var x = fromX; x <= toX; x++) {
      var hits = 0;

      for (var y = y0; y < image.height; y++) {
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

      final coverage = hits / totalRows;

      if (best == null || coverage > best.coverage) {
        best = _VerticalMatch(x, coverage);
      }
    }

    return best;
  }

  img.Image drawDebug(
    img.Image source,
    PolygonDetection detection,
  ) {
    final result = img.Image(
      width: source.width,
      height: source.height,
      numChannels: 3,
    );

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        result.setPixel(x, y, source.getPixel(x, y));
      }
    }

    final box = detection.bounds;
    final red = img.ColorRgb8(255, 40, 40);
    const thickness = 3;

    for (var t = 0; t < thickness; t++) {
      final top = box.top + t;
      final bottom = box.bottom - 1 - t;
      final left = box.left + t;
      final right = box.right - 1 - t;

      for (var x = box.left; x < box.right; x++) {
        if (top >= 0 && top < result.height) {
          result.setPixel(x, top, red);
        }

        if (bottom >= 0 && bottom < result.height) {
          result.setPixel(x, bottom, red);
        }
      }

      for (var y = box.top; y < box.bottom; y++) {
        if (left >= 0 && left < result.width) {
          result.setPixel(left, y, red);
        }

        if (right >= 0 && right < result.width) {
          result.setPixel(right, y, red);
        }
      }
    }

    return result;
  }
}

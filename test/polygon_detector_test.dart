import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../lib/polygon/polygon_detector.dart';

void main() {
  group('PolygonDetector — synthetic frame characterization', () {
    const detector = PolygonDetector();

    img.Image makeFrame({
      bool drawBottom = false,
      bool bottomAtImageEdge = false,
      bool fragmentedSides = false,
      bool interiorStripe = false,
    }) {
      final image = img.Image(width: 800, height: 600, numChannels: 3);
      final cyan = img.ColorRgb8(0, 180, 220);

      // Synthetic artifact panel: top edge, left/right edges.
      for (var x = 120; x <= 320; x++) {
        image.setPixel(x, 150, cyan);
      }
      // For a complete panel, side edges stop where the bottom border
      // begins. For the clipped-panel case, they continue to the frame edge.
      final sideBottom = drawBottom ? 400 : image.height;
      for (var y = 154; y < sideBottom; y++) {
        if (fragmentedSides && (y - 154).isOdd) continue;
        image.setPixel(120, y, cyan);
        image.setPixel(350, y, cyan);
      }

      if (interiorStripe) {
        // An interior separator aligned with both side edges.
        for (var y = 260; y <= 262; y++) {
          for (var x = 118; x <= 348; x++) {
            image.setPixel(x, y, cyan);
          }
        }
      }

      if (drawBottom) {
        for (var y = 400; y <= 402; y++) {
          for (var x = 120; x <= 350; x++) {
            image.setPixel(x, y, cyan);
          }
        }
      }

      if (bottomAtImageEdge) {
        for (var y = image.height - 2; y < image.height; y++) {
          for (var x = 120; x <= 350; x++) {
            image.setPixel(x, y, cyan);
          }
        }
      }

      return image;
    }

    test('detects a synthetic panel with a complete bottom border', () {
      final result = detector.detect(makeFrame(drawBottom: true));

      expect(result, isNotNull);
      expect(result!.bottomBoundaryFound, isTrue);
      expect(result.bottomTouchesImageEdge, isFalse);
      expect(result.usedBottomFallback, isFalse);
      expect(result.bottomLineY, 400);
      expect(result.bounds.left, 118);
      expect(result.bounds.top, 150);
      expect(result.bounds.width, 231);
    });

    test('marks a detected bottom border that reaches the image edge', () {
      final result = detector.detect(makeFrame(bottomAtImageEdge: true));

      expect(result, isNotNull);
      expect(result!.bottomBoundaryFound, isTrue);
      expect(result.bottomLineY, 598);
      expect(result.bottomTouchesImageEdge, isTrue);
      expect(result.usedBottomFallback, isFalse);
      expect(result.bounds.bottom, 600);
    });

    test('characterizes current behavior: missing bottom border still returns high confidence',
        () {
      final result = detector.detect(makeFrame());

      // This test intentionally records the current defect. It should be
      // changed when the detector distinguishes a clipped/incomplete panel
      // from a fully confirmed panel.
      expect(result, isNotNull);
      expect(result!.bottomBoundaryFound, isFalse);
      expect(result.usedBottomFallback, isTrue);
      expect(result.bounds.bottom, 600);
      expect(result.confidence, greaterThan(0.95));
    });

    test('characterizes current behavior: dashed side edges are accepted', () {
      final result = detector.detect(makeFrame(fragmentedSides: true));

      // _bestVertical counts cyan hits per row rather than requiring a
      // continuous vertical edge. Every second row still exceeds coverage.
      expect(result, isNotNull);
      expect(result!.leftVerticalCoverage, greaterThanOrEqualTo(0.45));
      expect(result.rightVerticalCoverage, greaterThanOrEqualTo(0.45));
      expect(result.usedBottomFallback, isTrue);
    });

    test(
      'characterizes current behavior: an interior cyan stripe is selected as a false top edge',
      () {
        final result = detector.detect(makeFrame(interiorStripe: true));

        // The stripe is also considered as a top-edge candidate. Its longer
        // run gives it a higher confidence than the real top edge, so it wins.
        // Bottom-line search then starts below the stripe and falls back
        // to the image edge.
        expect(result, isNotNull);
        expect(result!.bounds.top, 260);
        expect(result.bounds.bottom, 600);
        expect(result.topLineStartX, 118);
        expect(result.topLineEndX, 348);
        expect(result.bottomBoundaryFound, isFalse);
        expect(result.usedBottomFallback, isTrue);
        expect(result.confidence, 1.0);
      },
      skip: 'Known bug POLY-1: an interior cyan stripe is incorrectly selected as the panel top edge.',
    );

    test(
      'regression: an interior cyan stripe must not be selected as the panel top or bottom',
      () {
        final result = detector.detect(makeFrame(interiorStripe: true));

        expect(result, isNotNull);

        // The real top edge must be selected.
        expect(result!.bounds.top, 150);
        expect(result.topLineStartX, 120);
        expect(result.topLineEndX, 320);

        // The interior stripe is not a real bottom border.
        expect(result.bottomBoundaryFound, isFalse);
        expect(result.bottomLineY, isNull);
        expect(result.usedBottomFallback, isTrue);
        expect(result.bounds.bottom, 600);
      },
    );

    test('returns null for a frame without cyan panel edges', () {
      final image = img.Image(width: 800, height: 600, numChannels: 3);

      expect(detector.detect(image), isNull);
    });
  });
}

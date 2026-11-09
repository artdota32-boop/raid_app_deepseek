import 'package:paddle_ocr_native/paddle_ocr_native.dart' as pn;
import 'parser.dart';

void main() {
  // Фейковые блоки OCR (имитация Perception)
  final fakeMainBlocks = <pn.OcrResult>[
    pn.OcrResult(text: "Set: Perception", points: [pn.Point(x: 120, y: 40), pn.Point(x: 600, y: 120)]),
    pn.OcrResult(text: "C. RATE 60%", points: [pn.Point(x: 356, y: 273), pn.Point(x: 709, y: 332)]),
    pn.OcrResult(text: "DEF", points: [pn.Point(x: 124, y: 342), pn.Point(x: 243, y: 406)]),
    pn.OcrResult(text: "6%+4%", points: [pn.Point(x: 578, y: 344), pn.Point(x: 788, y: 408)]),
    pn.OcrResult(text: "DEF", points: [pn.Point(x: 122, y: 406), pn.Point(x: 244, y: 473)]),
    pn.OcrResult(text: "23", points: [pn.Point(x: 575, y: 407), pn.Point(x: 662, y: 472)]),
    pn.OcrResult(text: "SPD(3)", points: [pn.Point(x: 120, y: 468), pn.Point(x: 327, y: 543)]),
    pn.OcrResult(text: "23+5", points: [pn.Point(x: 575, y: 469), pn.Point(x: 735, y: 536)]),
    pn.OcrResult(text: "ATK", points: [pn.Point(x: 121, y: 534), pn.Point(x: 253, y: 600)]),
    pn.OcrResult(text: "6%", points: [pn.Point(x: 575, y: 533), pn.Point(x: 674, y: 602)]),
  ];

  final parsed = ArtifactParser.parse(fakeMainBlocks);
  
  print("=== RESULT ===");
  print("MAIN: ${parsed['main_stat']}");
  print("DOP: ${parsed['dop_stats']}");
  print("GLYPHS: ${parsed['glyphs']}");
  print("STATS: ${parsed['stats']}");
  print("PERCENTS: ${parsed['stats_percent']}");
}

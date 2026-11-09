/// RAID POLYGON — модели данных v0.1

enum PolygonStatus { found, notFound, notConfident, error }

enum PolygonStage {
  frame,
  detection,
  crop,
  imageQuality,
  ocr,
  parser,
  comparison,
  report
}

enum PolygonErrorCode {
  frameError,
  detectEmpty,
  detectLowConfidence,
  cropError,
  cropIncomplete,
  imageQuality,
  ocrEmpty,
  ocrPartial,
  parserError,
  noMatch,
  multipleMatches,
}

extension PolygonErrorCodeExt on PolygonErrorCode {
  String get code => switch (this) {
        PolygonErrorCode.frameError => "E01",
        PolygonErrorCode.detectEmpty => "E02",
        PolygonErrorCode.detectLowConfidence => "E03",
        PolygonErrorCode.cropError => "E04",
        PolygonErrorCode.cropIncomplete => "E05",
        PolygonErrorCode.imageQuality => "E06",
        PolygonErrorCode.ocrEmpty => "E07",
        PolygonErrorCode.ocrPartial => "E08",
        PolygonErrorCode.parserError => "E09",
        PolygonErrorCode.noMatch => "E10",
        PolygonErrorCode.multipleMatches => "E11",
      };
  String get label =>
      name.replaceAllMapped(RegExp(r"[A-Z]"), (m) => "_${m[0]}").toUpperCase();
}

class PolygonBox {
  final int left, top, width, height;
  const PolygonBox(
      {required this.left,
      required this.top,
      required this.width,
      required this.height});
  int get right => left + width;
  int get bottom => top + height;
  bool get isValid => left >= 0 && top >= 0 && width > 0 && height > 0;
  Map<String, dynamic> toJson() => {
        "left": left,
        "top": top,
        "width": width,
        "height": height,
        "right": right,
        "bottom": bottom
      };
}

class PolygonStat {
  final String name;
  final num? value;
  final String unit;
  final int? position;
  final String? rawValue;
  const PolygonStat(
      {required this.name,
      this.value,
      this.unit = "flat",
      this.position,
      this.rawValue});
  Map<String, dynamic> toJson() => {
        "name": name,
        "value": value,
        "unit": unit,
        "position": position,
        "raw_value": rawValue
      };
}

class PolygonArtifact {
  final String? set, type, rarity;
  final int? rankStars, level;
  final PolygonStat? mainStat;
  final List<PolygonStat> substatsOrdered;
  final PolygonStat? setBonus;
  const PolygonArtifact(
      {this.set,
      this.type,
      this.rarity,
      this.rankStars,
      this.level,
      this.mainStat,
      this.substatsOrdered = const [],
      this.setBonus});
  Map<String, dynamic> toJson() => {
        "set": set,
        "type": type,
        "rarity": rarity,
        "rank_stars": rankStars,
        "level": level,
        "main_stat": mainStat?.toJson(),
        "substats_ordered": substatsOrdered.map((s) => s.toJson()).toList(),
        "set_bonus": setBonus?.toJson()
      };
}

class PolygonDiagnostic {
  final PolygonStage stage;
  final String message;
  final PolygonErrorCode? errorCode;
  final bool confirmed;
  final int? candidateId, timestampMs;
  const PolygonDiagnostic(
      {required this.stage,
      required this.message,
      this.errorCode,
      this.confirmed = false,
      this.candidateId,
      this.timestampMs});
  Map<String, dynamic> toJson() => {
        "stage": stage.name,
        "error_code": errorCode?.code,
        "error_label": errorCode?.label,
        "message": message,
        "confirmed": confirmed,
        "candidate_id": candidateId,
        "timestamp_ms": timestampMs
      };
}

class PolygonCandidate {
  final int id;
  final PolygonBox bounds;
  final double? detectorConfidence;
  final String detectorMethod;
  final int? frameIndex, timestampMs;
  final String? sourceFramePath, cropPath, ocrInputPath;
  final String? ocrText;
  final PolygonArtifact? artifact;
  final double? matchScore;
  final Map<String, dynamic>? imageMetadata;
  final List<PolygonDiagnostic> diagnostics;
  const PolygonCandidate(
      {required this.id,
      required this.bounds,
      required this.detectorMethod,
      this.detectorConfidence,
      this.frameIndex,
      this.timestampMs,
      this.sourceFramePath,
      this.cropPath,
      this.ocrInputPath,
      this.ocrText,
      this.artifact,
      this.matchScore,
      this.imageMetadata,
      this.diagnostics = const []});
  Map<String, dynamic> toJson() => {
        "id": id,
        "bbox": bounds.toJson(),
        "detector_confidence": detectorConfidence,
        "detector_method": detectorMethod,
        "frame_index": frameIndex,
        "timestamp_ms": timestampMs,
        "source_frame_path": sourceFramePath,
        "crop_path": cropPath,
        "ocr_input_path": ocrInputPath,
        "ocr_text": ocrText,
        "parsed_artifact": artifact?.toJson(),
        "match_score": matchScore,
        "image_metadata": imageMetadata,
        "diagnostics": diagnostics.map((d) => d.toJson()).toList()
      };
}

class PolygonResult {
  final PolygonStatus status;
  final PolygonArtifact reference;
  final List<PolygonCandidate> candidates;
  final List<PolygonDiagnostic> diagnostics;
  final int? bestCandidateId, processedFrames, durationMs;
  final String? reportPath;
  const PolygonResult(
      {required this.status,
      required this.reference,
      this.candidates = const [],
      this.diagnostics = const [],
      this.bestCandidateId,
      this.processedFrames,
      this.durationMs,
      this.reportPath});
  Map<String, dynamic> toJson() => {
        "status": status.name,
        "reference": reference.toJson(),
        "candidates": candidates.map((c) => c.toJson()).toList(),
        "diagnostics": diagnostics.map((d) => d.toJson()).toList(),
        "best_candidate_id": bestCandidateId,
        "processed_frames": processedFrames,
        "duration_ms": durationMs,
        "report_path": reportPath
      };
}

/// How a [PaddleOcr] instance locates its models.
///
/// The native (Android/iOS) backends need on-device paths to `.onnx` files plus
/// a character dictionary — use [ModelSource.filePaths]. The web backend uses
/// `@paddleocr/paddleocr-js`, which fetches `.onnx` models from a CDN by
/// language + version, or explicit model names — use [ModelSource.bundled].
sealed class ModelSource {
  const ModelSource();

  /// Supply your own `.onnx` files + character dictionary.
  ///
  /// Works on Android and iOS. Paths must be absolute on-device paths —
  /// typically obtained by extracting bundled assets into the app's documents
  /// directory, or downloading at first launch.
  const factory ModelSource.filePaths({
    required String det,
    required String rec,
    required String dict,
    String? cls,
  }) = FilePathsModelSource;

  /// Let the backend fetch models itself by language + version.
  ///
  /// Web only — throws [UnsupportedError] on Android/iOS. Defaults to the
  /// PP-OCRv6 model family supported by paddleocr-js.
  const factory ModelSource.bundled({
    String lang,
    String version,
    String? textDetectionModelName,
    String? textRecognitionModelName,
  }) = BundledModelSource;
}

class FilePathsModelSource extends ModelSource {
  const FilePathsModelSource({
    required this.det,
    required this.rec,
    required this.dict,
    this.cls,
  });

  final String det;
  final String rec;
  final String dict;
  final String? cls;
}

class BundledModelSource extends ModelSource {
  const BundledModelSource({
    this.lang = 'ch',
    this.version = 'PP-OCRv6',
    this.textDetectionModelName,
    this.textRecognitionModelName,
  });

  final String lang;
  final String version;
  final String? textDetectionModelName;
  final String? textRecognitionModelName;
}

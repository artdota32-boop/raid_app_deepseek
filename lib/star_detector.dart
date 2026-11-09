import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:image/image.dart' as img;

int? detectStarsOpenCV(Uint8List imageBytes) {
  try {
    final image = img.decodeImage(imageBytes);
    if (image == null) return null;

    final mat = cv.Mat.fromList(
      image.height, image.width, cv.MatType.CV_8UC3,
      image.getBytes(order: img.ChannelOrder.bgr),
    );
    final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
    final (_, thresh) = cv.threshold(gray, 150, 255, cv.THRESH_BINARY);
    final (contours, _) = cv.findContours(thresh, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

    int starCount = 0;
    for (final contour in contours) {
      final area = cv.contourArea(contour);
      if (area > 3000 && area < 20000) {
        starCount++;
      }
    }
    mat.dispose(); gray.dispose(); thresh.dispose();
    return starCount;
  } catch (e) {
    print("Ошибка OpenCV: $e");
    return null;
  }
}

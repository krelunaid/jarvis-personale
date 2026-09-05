import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'vision.dart';

// Serializable frame copy: converted on an isolate, never written to disk.
class VideoFrame {
  final int width, height, rotation;
  final bool bgra;
  final List<Uint8List> planes;
  final List<int> rows, pixels;
  VideoFrame(
    this.width,
    this.height,
    this.bgra,
    this.planes,
    this.rows,
    this.pixels, {
    this.rotation = 0,
  });
}

class EncodedVision {
  final Uint8List jpeg;
  final List<double> hint;
  EncodedVision(this.jpeg, this.hint);
}

Uint8List encodeVideoFrame(VideoFrame frame) => encodeVisionFrame(frame).jpeg;

EncodedVision encodeVisionFrame(VideoFrame frame) {
  if (frame.width <= 0 ||
      frame.height <= 0 ||
      frame.planes.length < (frame.bgra ? 1 : 3)) {
    throw const FormatException('Formato video non supportato');
  }
  final scale =
      VisionPace.maxEdge /
      (frame.width > frame.height ? frame.width : frame.height);
  final w = scale < 1 ? (frame.width * scale).round() : frame.width;
  final h = scale < 1 ? (frame.height * scale).round() : frame.height;
  var output = img.Image(width: w, height: h);
  final planes = frame.planes;
  final rows = frame.rows;
  final pixels = frame.pixels;
  for (var y = 0; y < h; y++) {
    final sy = y * frame.height ~/ h;
    for (var x = 0; x < w; x++) {
      final sx = x * frame.width ~/ w;
      if (frame.bgra) {
        final offset = sy * rows[0] + sx * pixels[0];
        final p = planes[0];
        output.setPixelRgb(x, y, p[offset + 2], p[offset + 1], p[offset]);
      } else {
        final l = planes[0][sy * rows[0] + sx * pixels[0]].toDouble();
        final u = planes[1][(sy ~/ 2) * rows[1] + (sx ~/ 2) * pixels[1]] - 128;
        final v = planes[2][(sy ~/ 2) * rows[2] + (sx ~/ 2) * pixels[2]] - 128;
        output.setPixelRgb(
          x,
          y,
          (l + 1.402 * v).round().clamp(0, 255),
          (l - .344136 * u - .714136 * v).round().clamp(0, 255),
          (l + 1.772 * u).round().clamp(0, 255),
        );
      }
    }
  }
  if (frame.rotation != 0) {
    output = img.copyRotate(output, angle: frame.rotation);
  }
  return EncodedVision(
    Uint8List.fromList(img.encodeJpg(output, quality: VisionPace.jpegQuality)),
    luminanceHint(output),
  );
}

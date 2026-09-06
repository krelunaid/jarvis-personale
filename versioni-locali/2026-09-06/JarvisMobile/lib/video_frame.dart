import 'dart:typed_data';
import 'package:image/image.dart' as img;

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

Uint8List encodeVideoFrame(VideoFrame frame) {
  if (frame.width <= 0 ||
      frame.height <= 0 ||
      frame.planes.length < (frame.bgra ? 1 : 3)) {
    throw const FormatException('Formato video non supportato');
  }
  final scale = 768 / (frame.width > frame.height ? frame.width : frame.height);
  final w = scale < 1 ? (frame.width * scale).round() : frame.width;
  final h = scale < 1 ? (frame.height * scale).round() : frame.height;
  var output = img.Image(width: w, height: h);
  int byte(int plane, int x, int y) =>
      frame.planes[plane][y * frame.rows[plane] + x * frame.pixels[plane]];
  int clamp(double value) => value.round().clamp(0, 255);
  for (var y = 0; y < h; y++) {
    final sy = y * frame.height ~/ h;
    for (var x = 0; x < w; x++) {
      final sx = x * frame.width ~/ w;
      if (frame.bgra) {
        final offset = sy * frame.rows[0] + sx * frame.pixels[0];
        final p = frame.planes[0];
        output.setPixelRgb(x, y, p[offset + 2], p[offset + 1], p[offset]);
      } else {
        final l = byte(0, sx, sy).toDouble();
        final u = byte(1, sx ~/ 2, sy ~/ 2) - 128;
        final v = byte(2, sx ~/ 2, sy ~/ 2) - 128;
        output.setPixelRgb(
          x,
          y,
          clamp(l + 1.402 * v),
          clamp(l - .344136 * u - .714136 * v),
          clamp(l + 1.772 * u),
        );
      }
    }
  }
  if (frame.rotation != 0) {
    output = img.copyRotate(output, angle: frame.rotation);
  }
  return Uint8List.fromList(img.encodeJpg(output, quality: 72));
}

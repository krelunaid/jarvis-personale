import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jarvis_mobile/video_frame.dart';

void main() {
  test('BGRA preserves colors with padded rows', () {
    final bytes = Uint8List.fromList([
      0,
      0,
      255,
      255,
      0,
      0,
      255,
      255,
      99,
      99,
      99,
      99,
      0,
      0,
      255,
      255,
      0,
      0,
      255,
      255,
      99,
      99,
      99,
      99,
    ]);
    final image = img.decodeJpg(
      encodeVideoFrame(VideoFrame(2, 2, true, [bytes], [12], [4])),
    )!;
    expect(image.width, 2);
    expect(image.getPixel(1, 1).r, greaterThan(230));
    expect(image.getPixel(1, 1).b, lessThan(20));
  });
  test('YUV preserves chroma strides and rotates portrait', () {
    final image = img.decodeJpg(
      encodeVideoFrame(
        VideoFrame(
          4,
          2,
          false,
          [
            Uint8List.fromList([
              128,
              128,
              128,
              128,
              0,
              0,
              128,
              128,
              128,
              128,
              0,
              0,
            ]),
            Uint8List.fromList([128, 0, 128, 0]),
            Uint8List.fromList([128, 0, 128, 0]),
          ],
          [6, 4, 4],
          [1, 2, 2],
          rotation: 90,
        ),
      ),
    )!;
    expect(image.width, 2);
    expect(image.height, 4);
    expect(image.getPixel(0, 0).r, closeTo(128, 4));
    expect(image.getPixel(0, 0).b, closeTo(128, 4));
  });
  test('Malformed frames fail without emitting images', () {
    expect(
      () => encodeVideoFrame(VideoFrame(2, 2, false, [Uint8List(4)], [2], [1])),
      throwsFormatException,
    );
    expect(
      () => encodeVideoFrame(VideoFrame(2, 2, true, [Uint8List(1)], [8], [4])),
      throwsRangeError,
    );
  });
}

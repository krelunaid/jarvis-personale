import 'package:image/image.dart' as img;

class VisionPace {
  static const acceptGap = Duration(milliseconds: 250);
  static const liveSendGap = Duration(milliseconds: 250);
  static const chatSendGap = Duration(milliseconds: 400);
  static const liveStableRefresh = Duration(seconds: 2);
  static const chatStableRefresh = Duration(seconds: 30);
  static const snapshotFreshness = Duration(seconds: 3);
  static const changeThreshold = 7.0;

  static bool readyToSend({
    required bool live,
    required DateTime last,
    required DateTime now,
  }) {
    return now.difference(last) >= (live ? liveSendGap : chatSendGap);
  }

  static bool sceneMoved(
    double difference, {
    required bool live,
    required DateTime last,
    required DateTime now,
  }) {
    if (difference >= changeThreshold) return true;
    return now.difference(last) >=
        (live ? liveStableRefresh : chatStableRefresh);
  }
}

double sceneDifference(img.Image? previous, img.Image current) {
  final tiny = current.width == 16 && current.height == 16
      ? current
      : img.copyResize(current, width: 16, height: 16);
  if (previous == null) return 255;
  final prior = previous.width == 16 && previous.height == 16
      ? previous
      : img.copyResize(previous, width: 16, height: 16);
  var sum = 0.0;
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      sum += (tiny.getPixel(x, y).luminance - prior.getPixel(x, y).luminance)
          .abs();
    }
  }
  return sum / 256;
}

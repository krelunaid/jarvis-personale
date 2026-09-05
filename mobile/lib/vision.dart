import 'package:image/image.dart' as img;

class VisionPace {
  static const acceptGap = Duration(milliseconds: 200);
  static const liveSendGap = Duration(milliseconds: 200);
  static const chatSendGap = Duration(milliseconds: 400);
  static const liveStableRefresh = Duration(milliseconds: 500);
  static const chatStableRefresh = Duration(seconds: 30);
  static const snapshotFreshness = Duration(seconds: 2);
  static const changeThreshold = 3.5;
  static const peakThreshold = 28.0;
  static const maxEdge = 768;
  static const jpegQuality = 82;

  static bool readyToSend({
    required bool live,
    required DateTime last,
    required DateTime now,
  }) {
    return now.difference(last) >= (live ? liveSendGap : chatSendGap);
  }

  static bool sceneMoved(
    double difference, {
    double peak = 0,
    required bool live,
    required DateTime last,
    required DateTime now,
  }) {
    if (difference >= changeThreshold || peak >= peakThreshold) return true;
    return now.difference(last) >=
        (live ? liveStableRefresh : chatStableRefresh);
  }
}

class SceneDelta {
  final double mean, peak;
  const SceneDelta(this.mean, this.peak);
}

List<double> luminanceHint(img.Image image) {
  final tiny = image.width == 16 && image.height == 16
      ? image
      : img.copyResize(image, width: 16, height: 16);
  final hint = List<double>.filled(256, 0);
  var i = 0;
  for (var y = 0; y < 16; y++) {
    for (var x = 0; x < 16; x++) {
      hint[i++] = tiny.getPixel(x, y).luminance.toDouble();
    }
  }
  return hint;
}

SceneDelta compareHints(List<double>? previous, List<double> current) {
  if (previous == null || previous.length != current.length) {
    return const SceneDelta(255, 255);
  }
  var sum = 0.0;
  var peak = 0.0;
  for (var i = 0; i < current.length; i++) {
    final d = (current[i] - previous[i]).abs();
    sum += d;
    if (d > peak) peak = d;
  }
  return SceneDelta(sum / current.length, peak);
}

double sceneDifference(img.Image? previous, img.Image current) {
  return compareHints(
    previous == null ? null : luminanceHint(previous),
    luminanceHint(current),
  ).mean;
}

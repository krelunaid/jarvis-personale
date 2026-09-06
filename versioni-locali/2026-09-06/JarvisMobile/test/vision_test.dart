import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jarvis_mobile/app_model.dart';
import 'package:jarvis_mobile/vision.dart';
import 'core_test.dart' show FakeStore;

void main() {
  test('accept and send gaps stay in the 2–5 Hz band', () {
    expect(VisionPace.acceptGap, const Duration(milliseconds: 250));
    expect(VisionPace.liveSendGap, const Duration(milliseconds: 250));
    expect(VisionPace.chatSendGap, const Duration(milliseconds: 400));
    expect(
      const Duration(seconds: 1).inMilliseconds /
          VisionPace.acceptGap.inMilliseconds,
      closeTo(4, 0.1),
    );
    expect(
      const Duration(seconds: 1).inMilliseconds /
          VisionPace.liveSendGap.inMilliseconds,
      inInclusiveRange(2, 5),
    );
    expect(
      const Duration(seconds: 1).inMilliseconds /
          VisionPace.chatSendGap.inMilliseconds,
      inInclusiveRange(2, 5),
    );
  });

  test('stable scenes skip until the refresh window, moving scenes send', () {
    final now = DateTime(2026, 9, 5, 16, 30);
    expect(
      VisionPace.readyToSend(
        live: true,
        last: now.subtract(const Duration(milliseconds: 100)),
        now: now,
      ),
      isFalse,
    );
    expect(
      VisionPace.readyToSend(
        live: true,
        last: now.subtract(const Duration(milliseconds: 250)),
        now: now,
      ),
      isTrue,
    );
    expect(
      VisionPace.readyToSend(
        live: false,
        last: now.subtract(const Duration(seconds: 1)),
        now: now,
      ),
      isTrue,
    );
    expect(
      VisionPace.sceneMoved(
        1,
        live: true,
        last: now.subtract(const Duration(milliseconds: 400)),
        now: now,
      ),
      isFalse,
    );
    expect(
      VisionPace.sceneMoved(
        8,
        live: true,
        last: now.subtract(const Duration(milliseconds: 400)),
        now: now,
      ),
      isTrue,
    );
    expect(
      VisionPace.sceneMoved(
        1,
        live: true,
        last: now.subtract(const Duration(seconds: 2)),
        now: now,
      ),
      isTrue,
    );
    expect(
      VisionPace.sceneMoved(
        1,
        live: false,
        last: now.subtract(const Duration(seconds: 8)),
        now: now,
      ),
      isFalse,
    );
    expect(
      VisionPace.sceneMoved(
        1,
        live: false,
        last: now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      isTrue,
    );
  });

  test('luminance fingerprint ignores identical tiles and notices a shift', () {
    final dark = img.Image(width: 16, height: 16);
    img.fill(dark, color: img.ColorRgb8(10, 10, 10));
    final copy = img.Image.from(dark);
    final bright = img.Image(width: 16, height: 16);
    img.fill(bright, color: img.ColorRgb8(200, 200, 200));
    expect(sceneDifference(null, dark), 255);
    expect(sceneDifference(dark, copy), 0);
    expect(
      sceneDifference(dark, bright),
      greaterThan(VisionPace.changeThreshold),
    );
  });

  test('observe stays silent without camera or when watching is off', () async {
    final model = AppModel(storage: FakeStore())
      ..api.key = 'test-not-a-real-key';
    await model.observe();
    expect(model.messages, isEmpty);
    expect(model.visionStatus, 'Fotocamera spenta');
    model.watching = true;
    await model.observe();
    expect(model.messages, isEmpty);
    model.setWatching(false);
    expect(model.visionStatus, 'Solo anteprima locale');
    await model.observe();
    expect(model.messages, isEmpty);
    await model.stopCamera();
    expect(model.visionStatus, 'Fotocamera spenta');
    expect(model.camera, isNull);
    model.dispose();
  });
}

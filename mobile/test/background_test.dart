import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/app_model.dart';
import 'core_test.dart' show FakeStore;

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'iOS keeps only an already active voice session, and stops camera setup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final model = AppModel(storage: FakeStore());
      model.live.active = true;
      model.add('user', 'Continuiamo questa conversazione');
      model.cameraStarting = true;
      await model.enterBackground();
      expect(model.live.active, isTrue);
      expect(model.messages.single.text, 'Continuiamo questa conversazione');
      expect(model.cameraStarting, isFalse);
      expect(model.camera, isNull);
      await model.shutdown();
      expect(model.live.active, isFalse);
      expect(model.messages, isEmpty);
      model.dispose();
    },
  );
  test(
    'Termina clears conversation but retains saved memory and settings',
    () async {
      final model = AppModel(storage: FakeStore());
      await model.memory.remember('Preferisco risposte brevi');
      await model.saveSettings('test-key', 'ash');
      model.add('user', 'Parliamo della domanda precedente');
      model.live.active = true;
      model.cameraStarting = true;
      await model.startStop();
      expect(model.messages, isEmpty);
      expect(model.memory.notes, ['Preferisco risposte brevi']);
      expect(model.api.key, 'test-key');
      expect(model.voice, 'ash');
      expect(model.live.active, isFalse);
      expect(model.cameraStarting, isFalse);
      model.dispose();
    },
  );
  test('leaving an inactive chat clears it before reopening', () async {
    final model = AppModel(storage: FakeStore());
    model.add('user', 'Vecchio messaggio');
    await model.enterBackground();
    expect(model.messages, isEmpty);
    model.dispose();
  });
  test('opt-out survives reload and stops voice when backgrounded', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final store = FakeStore();
    final first = AppModel(storage: store);
    await first.saveSettings('', 'cedar', backgroundVoice: false);
    first.dispose();
    final model = AppModel(storage: store);
    await model.load();
    model.live.active = true;
    await model.enterBackground();
    expect(model.continueWhenLocked, isFalse);
    expect(model.live.active, isFalse);
    model.dispose();
  });
  test('pending connection and Android always stop in background', () async {
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      final model = AppModel(storage: FakeStore());
      model.live.connecting = true;
      model.live.active = platform == TargetPlatform.android;
      await model.enterBackground();
      expect(model.live.active, isFalse);
      expect(model.live.connecting, isFalse);
      model.dispose();
    }
  });
}

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jarvis_mobile/core.dart';
import 'package:jarvis_mobile/realtime.dart';
import 'core_test.dart' show FakeStore;

class RecordingVoice extends Realtime {
  final events = <Map<String, dynamic>>[];
  RecordingVoice()
    : super(
        OpenAI(http.Client()),
        Memories(FakeStore()),
        () {},
        (_, _, _) {},
        (_, _) async => 'Risultato',
      );
  @override
  void send(Map<String, dynamic> value) => events.add(value);
  void event(String type, [Map<String, dynamic> data = const {}]) =>
      handleServerEvent({'type': type, ...data});
  void words(String id, String text) => event(
    'conversation.item.input_audio_transcription.completed',
    {'item_id': id, 'transcript': text},
  );
  List<String> get types => events.map((e) => e['type'] as String).toList();
}

void main() {
  late RecordingVoice voice;
  setUp(() {
    voice = RecordingVoice()..active = true;
  });
  tearDown(() async {
    await voice.stop();
    voice.api.client.close();
  });
  test('noise does not interrupt ongoing audio', () {
    voice.event('response.created');
    voice.event('output_audio_buffer.started');
    voice.event('input_audio_buffer.speech_started', {'item_id': 'noise'});
    expect(voice.speaking, isTrue);
    expect(voice.events, isEmpty);
    voice.words('noise', '[respiro]');
    expect(voice.types, ['conversation.item.delete']);
    expect(voice.speaking, isTrue);
  });
  test('acknowledgement does not interrupt but is accepted at rest', () {
    voice.event('output_audio_buffer.started');
    voice.event('input_audio_buffer.speech_started', {'item_id': 'ack'});
    voice.words('ack', 'Sì.');
    expect(voice.types, ['conversation.item.delete']);
    voice.event('output_audio_buffer.stopped');
    voice.words('answer', 'Sì.');
    expect(voice.types.where((v) => v == 'response.create').length, 1);
  });
  test(
    'confirmed words wait for cancellation and duplicate events do not repeat',
    () {
      voice.event('response.created');
      voice.event('output_audio_buffer.started');
      voice.words('question', 'Aspetta, dimmi quanto costa');
      expect(voice.types, ['response.cancel', 'output_audio_buffer.clear']);
      voice.words('question', 'Aspetta, dimmi quanto costa');
      expect(voice.events.length, 2);
      voice.event('response.done', {
        'response': {'status': 'cancelled'},
      });
      expect(voice.types.last, 'response.create');
      expect(voice.types.where((v) => v == 'response.create').length, 1);
    },
  );
  test('one word explicit stop can interrupt', () {
    voice.event('output_audio_buffer.started');
    voice.words('stop', 'Fermati!');
    expect(voice.speaking, isFalse);
    expect(voice.types, ['output_audio_buffer.clear', 'response.create']);
  });
  test('muted and stopped sessions ignore late speech', () async {
    voice.muted = true;
    voice.words('muted', 'Una domanda');
    expect(voice.types, ['conversation.item.delete']);
    await voice.stop();
    voice.events.clear();
    voice.words('late', 'Una domanda');
    expect(voice.events, isEmpty);
  });
  test('transcription failure preserves audio and permits retry', () {
    voice.event('output_audio_buffer.started');
    voice.event('conversation.item.input_audio_transcription.failed', {
      'item_id': 'bad',
    });
    expect(voice.speaking, isTrue);
    expect(voice.types, ['conversation.item.delete']);
    expect(voice.error, contains('Riprova'));
    voice.words('retry', 'Ho una domanda');
    expect(voice.types.last, 'response.create');
  });
  test('confirmed speech pins the latest camera frame before answering', () {
    voice.latestPhoto = Uint8List.fromList([1, 2, 3]);
    voice.words('look', 'Cosa vedi adesso?');
    expect(voice.types, [
      'output_audio_buffer.clear',
      'conversation.item.create',
      'response.create',
    ]);
    final item = voice.events.first['item'] as Map<String, dynamic>;
    final content = item['content'] as List;
    expect(content[0]['text'], contains('Scena attuale'));
    expect(content[1]['type'], 'input_image');
  });
}

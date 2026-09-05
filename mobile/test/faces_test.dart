import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jarvis_mobile/core.dart';
import 'package:jarvis_mobile/faces.dart';
import 'core_test.dart' show FakeStore;

img.Image patternFace(
  int seed, {
  int noise = 0,
  int eyeGap = 32,
  int mouth = 62,
}) {
  final image = img.Image(width: 96, height: 96);
  final skin = 90 + (seed % 80);
  img.fill(image, color: img.ColorRgb8(skin, 70 + seed % 40, 55));
  for (var y = 0; y < 96; y++) {
    for (var x = 0; x < 96; x++) {
      final shade = ((x - 48) * (seed % 7) + (y - 40) * ((seed ~/ 3) % 5) + noise * ((x + y) % 3)).clamp(-30, 30);
      final p = image.getPixel(x, y);
      image.setPixelRgb(
        x,
        y,
        (p.r.toInt() + shade).clamp(20, 240),
        (p.g.toInt() + shade ~/ 2).clamp(20, 240),
        p.b.toInt(),
      );
    }
  }
  img.fillCircle(
    image,
    x: 48 - eyeGap ~/ 2,
    y: 34,
    radius: 7,
    color: img.ColorRgb8(15, 15, 20),
  );
  img.fillCircle(
    image,
    x: 48 + eyeGap ~/ 2,
    y: 34 + (seed % 4),
    radius: 7,
    color: img.ColorRgb8(15, 15, 20),
  );
  img.fillRect(
    image,
    x1: 36,
    y1: mouth,
    x2: 60,
    y2: mouth + 5,
    color: img.ColorRgb8(40, 20, 20),
  );
  return image;
}

const box = FaceBox(left: 8, top: 8, width: 80, height: 80);

void main() {
  test('Face roster persists, lists, adds a second sample and forgets', () async {
    final store = FakeStore();
    final first = FaceBook(store);
    final print = FacePrint.fromImage(patternFace(1), box);
    expect(await first.enroll('Marco', print), contains('Marco'));
    expect(await first.enroll('Marco', print), contains('altro scatto'));
    expect(first.listText(), contains('Marco'));
    final reopened = FaceBook(store);
    await reopened.load();
    expect(reopened.people.single.name, 'Marco');
    expect(reopened.people.single.prints.length, 2);
    expect(await reopened.forget('marco'), contains('rimosso'));
    await first.load();
    expect(first.people, isEmpty);
    expect(first.listText(), 'Nessun volto in rubrica.');
  });

  test('Corrupt roster is not overwritten', () async {
    final store = FakeStore()..data['faces'] = '{"people":1}';
    await expectLater(FaceBook(store).load(), throwsA(isA<JarvisError>()));
    expect(store.data['faces'], '{"people":1}');
  });

  test('Matcher names only a clear enrolled match', () {
    final book = FaceBook(FakeStore());
    final marco = FacePrint.fromImage(patternFace(3, eyeGap: 28, mouth: 64), box);
    final marcoAgain = FacePrint.fromImage(
      patternFace(3, noise: 1, eyeGap: 28, mouth: 64),
      box,
    );
    final anna = FacePrint.fromImage(patternFace(90, eyeGap: 48, mouth: 70), box);
    book.people = [
      FacePerson('1', 'Marco', [marco]),
      FacePerson('2', 'Anna', [anna]),
    ];
    expect(book.match(marcoAgain), 'Marco');
    expect(
      book.match(FacePrint.fromImage(patternFace(200, eyeGap: 20, mouth: 50), box)),
      isNull,
    );
    expect(FaceBook(FakeStore()).match(marco), isNull);
  });

  test('Unknown faces stay unnamed in the vision caption', () {
    final book = FaceBook(FakeStore());
    book.people = [
      FacePerson('1', 'Marco', [
        FacePrint.fromImage(patternFace(3, eyeGap: 28, mouth: 64), box),
      ]),
    ];
    final stranger = book.identify(patternFace(200, eyeGap: 20, mouth: 50), [
      box,
    ]);
    expect(stranger.known, isEmpty);
    expect(stranger.unknown, 1);
    expect(stranger.note, contains('non in rubrica volti'));
    expect(stranger.note.toLowerCase(), isNot(contains('marco')));
    final hit = book.identify(patternFace(3, eyeGap: 28, mouth: 64), [box]);
    expect(hit.known, ['Marco']);
    expect(hit.note, contains('Marco'));
  });

  test('Face commands require explicit wording', () {
    expect(
      FaceBook.command('Jarvis, ricorda questo volto come Marco')?.name,
      'Marco',
    );
    expect(FaceBook.command('Ricorda questo viso come Anna Rossi')?.action, 'enroll');
    expect(FaceBook.command('Elenca i volti')?.action, 'list');
    expect(FaceBook.command('Chi hai in rubrica volti')?.action, 'list');
    expect(FaceBook.command('Dimentica il volto di Marco')?.name, 'Marco');
    expect(
      FaceBook.command('Togli Anna dalla rubrica volti')?.action,
      'forget',
    );
    expect(FaceBook.command('Ricorda che preferisco esempi'), isNull);
    expect(FaceBook.command('Dimentica la spesa'), isNull);
    expect(FaceBook.command('Chi è quella persona?'), isNull);
  });

  test('Instructions allow only enrolled names', () {
    final text = instructions('Nota');
    expect(text, contains('persona non in rubrica volti'));
    expect(text, contains('SOLO le persone'));
    expect(text, isNot(contains('Non identificare persone.')));
    final session = liveSession('Nota', 'cedar');
    expect(
      (session['tools'] as List).map((t) => t['name']),
      containsAll([
        'enroll_face',
        'list_faces',
        'forget_face',
        'remember_memory',
      ]),
    );
  });

  test('Respond keeps the photo last and can attach a face note', () async {
    late Map<String, dynamic> body;
    final api = OpenAI(
      MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'output': [
              {
                'content': [
                  {'text': 'Vedo Marco'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    )..key = 'test';
    expect(
      await api.respond(
        'Chi vedi?',
        '',
        photo: Uint8List.fromList([1, 2]),
        faceNote: 'Persone iscritte nel riquadro: Marco.',
      ),
      'Vedo Marco',
    );
    final content = body['input'].last['content'] as List;
    expect(content[1]['text'], contains('Marco'));
    expect(content.last['type'], 'input_image');
  });
}

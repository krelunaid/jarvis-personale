import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jarvis_mobile/app_model.dart';
import 'package:jarvis_mobile/faces.dart';
import 'package:jarvis_mobile/main.dart';
import 'core_test.dart' show FakeStore;

void main() {
  testWidgets('Memory screen saves and displays a note without sensors', (
    tester,
  ) async {
    final model = AppModel(storage: FakeStore());
    await tester.pumpWidget(MaterialApp(home: JarvisHome(model: model)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Memoria'));
    await tester.pumpAndSettle();
    expect(find.text('Ti tengo a mente.'), findsOneWidget);
    await tester.tap(find.text('Aggiungi un ricordo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Preferisco risposte brevi');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(model.memory.notes, ['Preferisco risposte brevi']);
    expect(find.text('Preferisco risposte brevi'), findsOneWidget);
    expect(model.live.active, false);
    expect(model.camera, isNull);
  });

  testWidgets('Settings lists and deletes an enrolled face', (tester) async {
    final store = FakeStore();
    final book = FaceBook(store);
    final image = img.Image(width: 80, height: 80);
    for (var y = 0; y < 80; y++) {
      for (var x = 0; x < 80; x++) {
        image.setPixelRgb(x, y, 70 + x, 50 + y ~/ 2, 40);
      }
    }
    await book.enroll(
      'Marco',
      FacePrint.fromImage(
        image,
        const FaceBox(left: 4, top: 4, width: 72, height: 72),
      ),
    );
    final model = AppModel(storage: store);
    await tester.pumpWidget(MaterialApp(home: JarvisHome(model: model)));
    await tester.pumpAndSettle();
    expect(model.faces.people.single.name, 'Marco');
    await tester.tap(find.byTooltip('Impostazioni'));
    await tester.pumpAndSettle();
    expect(find.text('Rubrica volti'), findsOneWidget);
    expect(find.text('Marco'), findsOneWidget);
    await tester.tap(find.byTooltip('Dimentica Marco'));
    await tester.pumpAndSettle();
    expect(model.faces.people, isEmpty);
    expect(find.text('Nessun volto iscritto. Accendi la fotocamera e usa «Ricorda questo volto».'), findsOneWidget);
  });
}

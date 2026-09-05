import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_mobile/app_model.dart';
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
  testWidgets(
    'Voice page describes denser on-demand frames, not continuous video',
    (tester) async {
      final model = AppModel(storage: FakeStore());
      await tester.pumpWidget(MaterialApp(home: JarvisHome(model: model)));
      await tester.pumpAndSettle();
      final copy = find.textContaining(
        'circa 5 fotogrammi al secondo',
        skipOffstage: false,
      );
      expect(copy, findsOneWidget);
      expect(
        tester.widget<Text>(copy).data,
        contains('Non è un video continuo'),
      );
      expect(
        find.text('Fotocamera spenta', skipOffstage: false),
        findsOneWidget,
      );
      expect(model.camera, isNull);
    },
  );
}

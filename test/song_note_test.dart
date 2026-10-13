import 'package:appli_gdc/widgets/song_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _open(WidgetTester tester, {String? notePath, required bool canEdit}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSongNote(context,
              songId: 's', songTitle: 'Alléluia', notePath: notePath, canEdit: canEdit, onChanged: (_) {}),
          child: const Text('ouvrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sans note : on propose de l\'enregistrer', (tester) async {
    await _open(tester, canEdit: true);
    expect(find.text('Note du chant'), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record_rounded), findsOneWidget);
  });

  testWidgets('avec une note : écouter, et modifier pour les référents', (tester) async {
    await _open(tester, notePath: 'note.m4a', canEdit: true);
    expect(find.text('Touche pour écouter la note'), findsOneWidget);
    expect(find.text('Modifier'), findsOneWidget);
  });

  testWidgets('un membre peut seulement écouter', (tester) async {
    await _open(tester, notePath: 'note.m4a', canEdit: false);
    expect(find.text('Touche pour écouter la note'), findsOneWidget);
    expect(find.text('Modifier'), findsNothing);
  });
}

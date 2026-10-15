import 'package:appli_gdc/widgets/storage_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('jauge : total, détail par espace et alerte au-delà de 70 %', (tester) async {
    const mo = 1024 * 1024;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StorageCard(usage: () async => {'enregistrements': 700 * mo, 'booklets': 45 * mo, 'audio': 0}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('745 Mo utilisés sur 1 Go (73 %)'), findsOneWidget);
    expect(find.text('Enregistrements et notes'), findsOneWidget);
    expect(find.text('Audios des chants'), findsNothing);
    expect(find.textContaining('L\'espace se remplit'), findsOneWidget);
  });
}

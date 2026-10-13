import 'package:appli_gdc/widgets/swipe_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('une carte à la fois, on glisse pour voir la suivante', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          SwipeCards(
            count: 3,
            itemBuilder: (_, i) => SizedBox(height: 80 + 20.0 * i, child: Text('Carte $i')),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Carte 0'), findsOneWidget);
    expect(find.text('Carte 1'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Carte 1'), findsOneWidget);
    expect(find.text('Carte 0'), findsNothing);
    // La hauteur suit la carte affichée (100 + marge du bas 12).
    expect(tester.getSize(find.byType(PageView)).height, 112);
  });
}

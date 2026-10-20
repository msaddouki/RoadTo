import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/browse_panels.dart';
import 'package:roadto_core/roadto_core.dart';

Place _p(String name) => Place(name: name, position: const LatLon(45.75, 4.83));

void main() {
  testWidgets('destination bar: one line, simulation as a badge, both taps', (tester) async {
    var search = 0, settings = 0;
    tester.view.physicalSize = const Size(320, 200) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DestinationBar(onSearch: () => search++, onSettings: () => settings++, routing: false, simulate: true),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Où allez-vous ?')).maxLines, 1);
    expect(find.text('Conduite simulée'), findsOneWidget);
    await tester.tap(find.text('Où allez-vous ?'));
    await tester.tap(find.byTooltip('Réglages'));
    expect((search, settings), (1, 1));
  });

  test('shortcuts: Maison and Travail first, four at most', () {
    final all = [_p('Salle de sport'), _p('Travail'), _p('Chez Léa'), _p('Maison'), _p('Gare')];
    expect(FavoriteShortcuts.ordered(all).map((p) => p.name), ['Maison', 'Travail', 'Salle de sport', 'Chez Léa']);
  });

  testWidgets('a shortcut starts the trip', (tester) async {
    Place? went;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoriteShortcuts(favorites: [_p('Maison')], onGo: (p) => went = p),
        ),
      ),
    );
    await tester.tap(find.text('Maison'));
    expect(went?.name, 'Maison');
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/search_screen.dart';
import 'package:roadto_core/roadto_core.dart';

const _here = LatLon(45.7578, 4.8320);

Future<Place?> _open(WidgetTester tester, List<NearbyPlace>? Function(PlaceCategory) searchCategory) async {
  Place? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await Navigator.of(context).push<Place>(
              MaterialPageRoute(
                builder: (_) =>
                    SearchScreen(search: (_) async => const [], from: _here, searchCategory: searchCategory),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('a category chip lists places along the route; tapping one picks it', (tester) async {
    PlaceCategory? asked;
    const station = Place(name: 'TotalEnergies', detail: 'Lyon', position: LatLon(45.76, 4.84));
    await _open(tester, (c) {
      asked = c;
      return const [NearbyPlace(station, 900, aheadM: 2400, offRouteM: 300)];
    });

    await tester.tap(find.text('Carburant'));
    await tester.pumpAndSettle();
    expect(asked!.id, 'fuel');
    expect(find.text('TotalEnergies'), findsOneWidget);
    expect(find.text('dans 2,4 km\nà 300 m de la route'), findsOneWidget);

    await tester.tap(find.text('TotalEnergies'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsNothing);
  });

  testWidgets('without an offline region, the chip explains what to do', (tester) async {
    await _open(tester, (_) => null);
    await tester.tap(find.text('Recharge'));
    await tester.pumpAndSettle();
    expect(find.textContaining('installez-en une dans Réglages'), findsOneWidget);
  });

  testWidgets('no result says so', (tester) async {
    await _open(tester, (_) => const []);
    await tester.tap(find.text('Parking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun résultat « Parking »'), findsOneWidget);
  });
}

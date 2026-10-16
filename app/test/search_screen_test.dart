import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/place_sheet.dart';
import 'package:roadto/ui/search_screen.dart';
import 'package:roadto_core/roadto_core.dart';

const _here = LatLon(45.7578, 4.8320);

Future<Place?> _open(
  WidgetTester tester,
  List<NearbyPlace>? Function(PlaceCategory) searchCategory, {
  ValueChanged<String>? onFuelChanged,
}) async {
  Place? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await Navigator.of(context).push<Place>(
              MaterialPageRoute(
                builder: (_) => SearchScreen(
                  search: (_) async => const [],
                  from: _here,
                  searchCategory: searchCategory,
                  onFuelChanged: onFuelChanged,
                ),
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

  group('official station data', () {
    final now = DateTime.now();
    FuelStation station(String id, Map<String, double> prices, {List<String> outOfStock = const []}) => FuelStation(
      id: id,
      position: const LatLon(45.76, 4.84),
      prices: {for (final e in prices.entries) e.key: FuelPrice(e.value, now.subtract(const Duration(hours: 2)))},
      outOfStock: outOfStock,
    );
    const a = Place(name: 'TotalEnergies', position: LatLon(45.76, 4.84));
    const b = Place(name: 'Intermarché', position: LatLon(45.77, 4.85));
    const c = Place(name: 'Station-service', position: LatLon(45.78, 4.86));

    testWidgets('fuel results show the price, switch fuel and sort cheapest first', (tester) async {
      String? chosen;
      await _open(
        tester,
        (_) => [
          NearbyPlace(a, 500, fuel: station('1', {'gazole': 1.849, 'e10': 1.799})),
          NearbyPlace(b, 900, fuel: station('2', {'gazole': 1.749}, outOfStock: ['e10'])),
          const NearbyPlace(c, 1200),
        ],
        onFuelChanged: (f) => chosen = f,
      );
      await tester.tap(find.text('Carburant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gazole 1,849 € · il y a 2 h'), findsOneWidget);
      expect(find.textContaining('Gazole 1,749 €'), findsOneWidget);
      // Only fuels some station sells are offered.
      expect(find.widgetWithText(ChoiceChip, 'SP98'), findsNothing);

      // Nearest first by default; cheapest first on demand.
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(y('TotalEnergies'), lessThan(y('Intermarché')));
      await tester.tap(find.text('Moins cher'));
      await tester.pumpAndSettle();
      expect(y('Intermarché'), lessThan(y('TotalEnergies')));
      expect(y('TotalEnergies'), lessThan(y('Station-service')));

      await tester.tap(find.widgetWithText(ChoiceChip, 'SP95-E10'));
      await tester.pumpAndSettle();
      expect(chosen, 'e10');
      expect(find.textContaining('SP95-E10 1,799 €'), findsOneWidget);
      expect(find.textContaining('SP95-E10 en rupture'), findsOneWidget);
    });

    testWidgets('charging results show their charge points', (tester) async {
      await _open(
        tester,
        (_) => const [
          NearbyPlace(
            Place(name: 'IONITY', detail: 'Aire de Solaize', position: LatLon(45.64, 4.86)),
            4000,
            charging: ChargingStation(
              id: 'FRIONE1',
              position: LatLon(45.64, 4.86),
              points: 6,
              maxKw: 350,
              connectors: ['ccs', 'type2'],
              alwaysOpen: true,
            ),
          ),
        ],
      );
      await tester.tap(find.text('Recharge'));
      await tester.pumpAndSettle();
      expect(find.text('Aire de Solaize\n6 points · 350 kW · CCS, Type 2'), findsOneWidget);
      expect(find.text('Moins cher'), findsNothing);
      // Around the position, not on a route: nothing to choose the order by.
      expect(find.text('Plus proche'), findsNothing);
    });

    test('price, age and charging summaries', () {
      final t = DateTime(2026, 10, 16, 12);
      expect(formatPrice(1.7), '1,700 €');
      expect(formatAge(t.subtract(const Duration(seconds: 30)), t), 'à l’instant');
      expect(formatAge(t.subtract(const Duration(minutes: 25)), t), 'il y a 25 min');
      expect(formatAge(t.subtract(const Duration(days: 3)), t), 'il y a 3 j');
      expect(
        chargingSummary(
          const ChargingStation(
            id: 'x',
            position: LatLon(0, 0),
            maxKw: 7.4,
            connectors: ['ef'],
            free: true,
            openToAll: false,
          ),
        ),
        '1 point · 7,4 kW · prise domestique · gratuit · accès réservé · horaires limités',
      );
    });
  });

  group('place sheet and order', () {
    final now = DateTime.now();
    const total = Place(name: 'TotalEnergies', detail: 'Lyon', position: LatLon(45.76, 4.84));
    const esso = Place(name: 'Esso', position: LatLon(45.77, 4.85));
    final totalStation = FuelStation(
      id: '1',
      position: const LatLon(45.76, 4.84),
      card24h: true,
      prices: {
        'gazole': FuelPrice(1.849, now.subtract(const Duration(hours: 2))),
        'sp98': FuelPrice(1.959, now.subtract(const Duration(days: 1))),
      },
      outOfStock: const ['e10'],
    );

    testWidgets('a station with prices opens its sheet; Y aller picks it', (tester) async {
      await _open(tester, (_) => [NearbyPlace(total, 900, aheadM: 2400, offRouteM: 300, fuel: totalStation)]);
      await tester.tap(find.text('Carburant'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TotalEnergies'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaceSheet), findsOneWidget);
      expect(find.text('1,849 €  ·  il y a 2 h'), findsOneWidget);
      expect(find.text('1,959 €  ·  il y a 1 j'), findsOneWidget);
      expect(find.text('en rupture'), findsOneWidget);
      expect(find.text('Automate carte bancaire 24h/24'), findsOneWidget);
      expect(find.text('dans 2,4 km · à 300 m de la route'), findsOneWidget);

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      await tester.tap(find.text('TotalEnergies'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Y aller'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsNothing);
    });

    testWidgets('on a route, the least detour comes first on demand', (tester) async {
      await _open(
        tester,
        (_) => const [
          NearbyPlace(total, 900, aheadM: 1000, offRouteM: 600),
          NearbyPlace(esso, 3000, aheadM: 5000, offRouteM: 40),
        ],
      );
      await tester.tap(find.text('Carburant'));
      await tester.pumpAndSettle();
      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      expect(find.text('Premier sur la route'), findsOneWidget);
      expect(y('TotalEnergies'), lessThan(y('Esso')));
      await tester.tap(find.text('Moins de détour'));
      await tester.pumpAndSettle();
      expect(y('Esso'), lessThan(y('TotalEnergies')));
    });

    testWidgets('a charging sheet shows the charge points and access', (tester) async {
      await _open(
        tester,
        (_) => const [
          NearbyPlace(
            Place(name: 'Izivia', detail: 'Place Bellecour', position: LatLon(45.75, 4.83)),
            300,
            charging: ChargingStation(
              id: 'FRIZIV1',
              position: LatLon(45.75, 4.83),
              operator: 'Izivia',
              points: 4,
              maxKw: 22,
              connectors: ['type2'],
              card: true,
              openToAll: false,
            ),
          ),
        ],
      );
      await tester.tap(find.text('Recharge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Izivia'));
      await tester.pumpAndSettle();
      expect(find.text('Payant, carte bancaire acceptée'), findsOneWidget);
      expect(find.text('Accès réservé'), findsOneWidget);
      expect(find.text('Horaires limités'), findsOneWidget);
      // The operator is the title already: not repeated.
      expect(find.widgetWithText(PlaceSheet, 'Izivia'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/state/trip_preview.dart';
import 'package:roadto/ui/route_preview.dart';
import 'package:roadto_core/roadto_core.dart';

void main() {
  final route = TripRoute(
    shape: const [LatLon(45.75, 4.83), LatLon(45.76, 4.86)],
    maneuvers: const [
      Maneuver(type: 1, instruction: 'Partez.', beginShapeIndex: 0, lengthM: 6480, timeS: 1500),
      Maneuver(type: 4, instruction: 'Vous êtes arrivé.', beginShapeIndex: 1, lengthM: 0, timeS: 0),
    ],
    lengthM: 6480,
    timeS: 1500,
  );
  const gare = Place(name: 'Gare Part-Dieu', detail: 'Lyon 3e', position: LatLon(45.76, 4.86));
  RoadAlert alert(String id, AlertType type) => RoadAlert(
    id: id,
    author: 'x',
    type: type,
    geohash: 'u05kqbz',
    createdAt: DateTime(2026, 10, 20, 8),
    expiresAt: DateTime(2026, 10, 20, 9),
  );
  final now = DateTime(2026, 10, 20, 8, 0);
  TripPreview preview(List<AlertAhead> alerts) =>
      TripPreview(place: gare, route: route, alerts: alerts, from: const LatLon(45.75, 4.83), computedAt: now);

  test('alerts on the way, by type, in the order they are met', () {
    final p = preview([
      AlertAhead(alert('a', AlertType.traffic), 900),
      AlertAhead(alert('b', AlertType.accident), 2000),
      AlertAhead(alert('c', AlertType.traffic), 4000),
    ]);
    expect(p.alertSummary.map((e) => e.$2), ['Bouchon ×2', 'Accident']);
  });

  test('stale after 10 min or 300 m away: computed again on start', () {
    final p = preview(const []);
    expect(p.fresh(const LatLon(45.7505, 4.8305), now.add(const Duration(minutes: 3))), isTrue);
    expect(p.fresh(const LatLon(45.75, 4.83), now.add(const Duration(minutes: 11))), isFalse);
    expect(p.fresh(const LatLon(45.76, 4.83), now), isFalse);
  });

  testWidgets('the sheet: destination, time, arrival, distance, alerts, and the two buttons', (tester) async {
    var go = 0, cancel = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: RoutePreviewSheet(
              preview: preview([AlertAhead(alert('a', AlertType.accident), 900)]),
              now: now,
              onGo: () => go++,
              onCancel: () => cancel++,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Gare Part-Dieu'), findsOneWidget);
    expect(find.text('Lyon 3e'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('08:25'), findsOneWidget);
    expect(find.text('6,5 km'), findsOneWidget);
    expect(find.text('Accident'), findsOneWidget);
    await tester.tap(find.text('Partir'));
    await tester.tap(find.text('Annuler'));
    expect((go, cancel), (1, 1));
  });

  testWidgets('no alert: says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutePreviewSheet(preview: preview(const []), now: now, onGo: () {}, onCancel: () {}),
        ),
      ),
    );
    expect(find.text('Aucune alerte sur le trajet'), findsOneWidget);
  });

  testWidgets('header: where to, and back', (tester) async {
    var back = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewHeader(place: gare, onBack: () => back++),
        ),
      ),
    );
    expect(find.text('Vers Gare Part-Dieu'), findsOneWidget);
    await tester.tap(find.byTooltip('Retour'));
    expect(back, 1);
  });
}

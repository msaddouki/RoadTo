import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/navigation_panels.dart';
import 'package:roadto_core/roadto_core.dart';

Future<void> _pump(WidgetTester tester, Widget w) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: w),
    ),
  ),
);

Maneuver _m(int type, String street, int at) =>
    Maneuver(type: type, instruction: street, streetNames: [street], beginShapeIndex: at, lengthM: 0, timeS: 0);

void main() {
  // A straight 1 km road, one point every ~111 m.
  final route = TripRoute(
    shape: [for (var i = 0; i < 10; i++) LatLon(45.75 + i * 0.001, 4.83)],
    maneuvers: [_m(1, 'Départ', 0), _m(10, 'Av. Jean Jaurès', 3), _m(15, 'Rue Pasteur', 5), _m(4, 'Arrivée', 9)],
    lengthM: 1000,
    timeS: 120,
  );
  GuidanceState at(double alongM) => GuidanceEngine(route).update(route.pointAt(alongM), speedMps: 13);

  group('maneuver banner', () {
    testWidgets('distance, street, and the next turn when it comes soon', (tester) async {
      final g = at(30);
      final then = ManeuverBanner.thenOf(route, g);
      expect(then!.streetNames.first, 'Rue Pasteur');
      await _pump(tester, ManeuverBanner(state: g, then: then));
      expect(find.text('Av. Jean Jaurès'), findsOneWidget);
      expect(find.text('Puis'), findsOneWidget);
      expect(find.text('Rue Pasteur'), findsOneWidget);
      expect(find.text(formatDistance(g.distanceToNextM)), findsOneWidget);
    });

    testWidgets('the light at the turn and the lanes to take', (tester) async {
      final turnM = route.maneuverStartM(1);
      final engine = GuidanceEngine(route)
        ..details = RoadDetails(
          signalsM: [turnM - 10],
          lanes: [
            LaneGuide(turnM, const [
              Lane(['left'], valid: false, arrow: 'left'),
              Lane(['straight'], valid: false, arrow: 'straight'),
              Lane(['right'], valid: true, preferred: true, arrow: 'right'),
            ]),
          ],
        );
      final g = engine.update(route.pointAt(30), speedMps: 13);
      await _pump(tester, ManeuverBanner(state: g));
      expect(find.text('Au feu'), findsOneWidget);
      expect(find.byIcon(Icons.traffic), findsOneWidget);
      expect(find.bySemanticsLabel('Voies : la première voie à droite'), findsOneWidget);
      // The banner's arrow and the lane's.
      expect(find.byIcon(Icons.turn_right), findsNWidgets(2));
      expect(find.byIcon(Icons.turn_left), findsOneWidget);
    });

    test('no "then" when the next turn is far after this one', () {
      expect(ManeuverBanner.thenOf(route, at(30), withinM: 100), isNull);
    });
  });

  group('alert ahead', () {
    final alert = RoadAlert(
      id: 'a',
      author: 'x',
      type: AlertType.accident,
      geohash: 'u05kqbz',
      createdAt: DateTime.utc(2026, 10, 1, 8),
      expiresAt: DateTime.utc(2026, 10, 1, 9),
    );
    final now = DateTime.utc(2026, 10, 1, 8, 10);

    testWidgets('type, distance and confirmations', (tester) async {
      await _pump(
        tester,
        AlertAheadCard(
          ahead: AlertAhead(alert, 1200),
          confirmations: (count: 3, latest: DateTime.utc(2026, 10, 1, 8, 6)),
          now: now,
        ),
      );
      expect(find.text('Accident · 1,2 km'), findsOneWidget);
      expect(find.text('Confirmé par 3 conducteurs · il y a 4 min'), findsOneWidget);
    });

    testWidgets('not confirmed yet: when it was reported', (tester) async {
      await _pump(
        tester,
        AlertAheadCard(ahead: AlertAhead(alert, 300), confirmations: (count: 0, latest: null), now: now),
      );
      expect(find.text('Signalé il y a 10 min'), findsOneWidget);
    });
  });

  group('speed', () {
    testWidgets('limit sign, white then red when over', (tester) async {
      await _pump(tester, const SpeedLimitSign(kph: 50, over: false));
      expect(find.bySemanticsLabel('Limitée à 50 km/h'), findsOneWidget);
      var box = tester.widget<Container>(find.byType(Container).first).decoration as BoxDecoration;
      expect(box.color, Colors.white);

      await _pump(tester, const SpeedLimitSign(kph: 30, over: true));
      expect(find.bySemanticsLabel('Limitée à 30 km/h, vitesse dépassée'), findsOneWidget);
      box = tester.widget<Container>(find.byType(Container).first).decoration as BoxDecoration;
      expect(box.color, NavColors.limitRed);
    });

    testWidgets('current speed', (tester) async {
      await _pump(tester, const SpeedReadout(kph: 47));
      expect(find.text('47'), findsOneWidget);
      expect(find.bySemanticsLabel('Vitesse : 47 km/h'), findsOneWidget);
    });
  });

  testWidgets('navigation sheet: arrival time, what is left, the three buttons', (tester) async {
    var voice = 0, report = 0, options = 0;
    final g = at(30);
    await _pump(
      tester,
      NavigationSheet(
        state: g,
        now: DateTime(2026, 10, 1, 23, 23),
        voiceOn: true,
        onToggleVoice: () => voice++,
        onReport: () => report++,
        onOptions: () => options++,
      ),
    );
    final eta = g.eta(DateTime(2026, 10, 1, 23, 23));
    expect(
      find.text('${eta.hour.toString().padLeft(2, '0')}:${eta.minute.toString().padLeft(2, '0')}'),
      findsOneWidget,
    );
    expect(find.text('arrivée'), findsOneWidget);
    expect(find.text(NavigationSheet.timeLeft(g.remaining)), findsOneWidget);
    expect(find.text(formatDistance(g.remainingM)), findsOneWidget);

    await tester.tap(find.byTooltip('Couper le guidage vocal'));
    await tester.tap(find.text('Signaler'));
    await tester.tap(find.byTooltip('Options du trajet'));
    expect((voice, report, options), (1, 1, 1));
  });

  test('time left reads in minutes, then hours', () {
    expect(NavigationSheet.timeLeft(const Duration(minutes: 18)), '18 min');
    expect(NavigationSheet.timeLeft(const Duration(minutes: 65)), '1 h 05');
  });

  testWidgets('narrow phone: nothing overflows, "Signaler" stays whole', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      NavigationSheet(
        state: GuidanceEngine(route).update(route.pointAt(30), speedMps: 13),
        now: DateTime(2026, 10, 1, 23, 23),
        voiceOn: false,
        onToggleVoice: () {},
        onReport: () {},
        onOptions: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Signaler'), findsOneWidget);
  });
}

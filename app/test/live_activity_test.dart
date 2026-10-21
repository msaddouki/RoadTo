import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/live_activity.dart';
import 'package:roadto_core/roadto_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final route = TripRoute(
    shape: const [LatLon(45.7578, 4.8320), LatLon(45.7578, 4.8420), LatLon(45.7650, 4.8420)],
    maneuvers: const [
      Maneuver(type: 1, instruction: 'Partez vers l’est.', beginShapeIndex: 0, lengthM: 778, timeS: 60),
      Maneuver(
        type: 15,
        instruction: 'Tournez à gauche dans Rue Garibaldi.',
        streetNames: ['Rue Garibaldi'],
        beginShapeIndex: 1,
        lengthM: 800,
        timeS: 60,
      ),
      Maneuver(type: 4, instruction: 'Vous êtes arrivé.', beginShapeIndex: 2, lengthM: 0, timeS: 0),
    ],
    lengthM: 1578,
    timeS: 120,
  );
  const home = Place(name: 'Maison', position: LatLon(45.7650, 4.8420));

  GuidanceState drive(LatLon to) {
    final engine = GuidanceEngine(route);
    engine.update(const LatLon(45.7578, 4.8320));
    return engine.update(to, speedMps: 13);
  }

  group('state', () {
    test('while navigating: next maneuver worded and rounded, arrival to the minute', () {
      final g = drive(const LatLon(45.7578, 4.8380));
      final now = DateTime.utc(2026, 10, 16, 8, 0, 31);
      final s = liveActivityState(guidance: g, route: route, destination: home, now: now)!;
      expect(s['destination'], 'Maison');
      expect(s['symbol'], 'arrow.turn.up.left');
      expect(s['title'], 'Rue Garibaldi');
      expect(s['instruction'], 'Tournez à gauche dans Rue Garibaldi.');
      expect(s['distance'], formatDistance(g.distanceToNextM));
      expect(s['distance'], endsWith('0 m'));
      expect(s['remaining'], formatDistance(g.remainingM));
      expect((s['arrivalEpochMs']! as int) % 60000, 0);
      expect(s['arrived'], isFalse);
      expect(s.containsKey('alert'), isFalse);

      // The estimated time left, when the app has one, sets the arrival.
      final later = liveActivityState(
        guidance: g,
        route: route,
        remaining: g.remaining + const Duration(minutes: 7),
        destination: home,
        now: now,
      )!;
      expect(
        (later['arrivalEpochMs']! as int) - (s['arrivalEpochMs']! as int),
        closeTo(const Duration(minutes: 7).inMilliseconds, 60000),
      );
    });

    test('an alert ahead is shown with its distance', () {
      final g = drive(const LatLon(45.7578, 4.8380));
      final alert = RoadAlert(
        id: 'a',
        author: 'p',
        type: AlertType.accident,
        geohash: 'u05kqt1',
        createdAt: DateTime.utc(2026, 10, 16, 8),
        expiresAt: DateTime.utc(2026, 10, 16, 9),
      );
      final s = liveActivityState(
        guidance: g,
        route: route,
        destination: home,
        ahead: AlertAhead(alert, 812),
        now: DateTime.utc(2026, 10, 16, 8),
      )!;
      expect(s['alert'], 'Accident à 810 m');
    });

    test('nothing when not navigating', () {
      expect(liveActivityState(guidance: null, route: null, destination: null, now: DateTime.now()), isNull);
    });

    test('maneuver symbols follow the phone panel families', () {
      Maneuver m(int type) => Maneuver(type: type, instruction: '', beginShapeIndex: 0, lengthM: 0, timeS: 0);
      expect(maneuverSymbol(null), 'arrow.up');
      expect(maneuverSymbol(m(10)), 'arrow.turn.up.right');
      expect(maneuverSymbol(m(16)), 'arrow.up.left');
      expect(maneuverSymbol(m(26)), 'arrow.counterclockwise.circle');
      expect(maneuverSymbol(m(5)), 'flag.checkered');
    });
  });

  group('link', () {
    late List<MethodCall> sent;
    late ChangeNotifier changes;
    late LiveActivityLink link;
    Map<String, Object?>? snapshot;

    setUp(() {
      sent = [];
      changes = ChangeNotifier();
      snapshot = null;
      messenger.setMockMethodCallHandler(LiveActivityLink.channel, (call) async {
        sent.add(call);
        return null;
      });
    });

    // Started inside each test, so its timers run on the test's fake clock.
    void startLink() => link = LiveActivityLink(
      changes: changes,
      snapshot: () => snapshot,
      minInterval: const Duration(milliseconds: 100),
    )..start(ios: true);

    tearDown(() {
      link.stop();
      messenger.setMockMethodCallHandler(LiveActivityLink.channel, null);
    });

    testWidgets('ends a leftover at start, updates only on change, ends with the trip', (tester) async {
      startLink();
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent.map((c) => c.method), ['end'], reason: 'leftover from a killed run; nothing to show yet');

      snapshot = {'distance': '250 m'};
      changes.notifyListeners();
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent.last.method, 'update');
      expect(sent.last.arguments, {'distance': '250 m'});

      // Same content, however many changes: nothing sent.
      for (var i = 0; i < 5; i++) {
        snapshot = {'distance': '250 m'};
        changes.notifyListeners();
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(sent, hasLength(2));

      snapshot = {'distance': '240 m'};
      changes.notifyListeners();
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent.last.arguments, {'distance': '240 m'});

      snapshot = null;
      changes.notifyListeners();
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent.map((c) => c.method), ['end', 'update', 'update', 'end']);
    });

    testWidgets('at most one update per interval', (tester) async {
      startLink();
      for (var i = 0; i < 10; i++) {
        snapshot = {'distance': '${300 - i * 10} m'};
        changes.notifyListeners();
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent.where((c) => c.method == 'update').length, lessThanOrEqualTo(3));
      expect(sent.last.arguments, {'distance': '210 m'});
    });
  });

  test('does nothing outside iOS', () {
    final changes = ChangeNotifier();
    var snapshots = 0;
    LiveActivityLink(
      changes: changes,
      snapshot: () {
        snapshots++;
        return null;
      },
    ).start(ios: false);
    changes.notifyListeners();
    expect(snapshots, 0);
  });
}

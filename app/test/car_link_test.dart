import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/car_link.dart';
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

  group('car state', () {
    test('while navigating: next maneuver, what is left, the route once', () {
      final engine = GuidanceEngine(route);
      engine.update(const LatLon(45.7578, 4.8320));
      final g = engine.update(const LatLon(45.7578, 4.8380), speedMps: 13);
      final now = DateTime.utc(2026, 10, 16, 8);
      final s = carState(
        guidance: g,
        route: route,
        position: const LatLon(45.7578, 4.8380),
        bearingDeg: 90,
        speedMps: 13.9,
        speedLimitKph: 50,
        mapStyle: '/data/regions/lyon/style/style.offline.json',
        now: now,
      );
      expect(s['navigating'], isTrue);
      final m = s['maneuver']! as Map;
      expect(m['type'], 15);
      expect(m['street'], 'Rue Garibaldi');
      expect(m['distanceM'] as double, closeTo(311, 10));
      expect(s['remainingS'], g.remaining.inSeconds);
      expect(s['arrivalEpochMs'], now.add(g.remaining).millisecondsSinceEpoch);
      expect(s['speedKph'], 50);
      expect((s['route']! as List).first, [4.8320, 45.7578]);
      expect(s['places'], isEmpty);
      expect(s['routing'], isFalse);
    });

    test('saved places go to the car, as many as a car list shows', () {
      final s = carState(
        guidance: null,
        route: null,
        position: const LatLon(45.75, 4.83),
        places: [for (var i = 0; i < 9; i++) Place(name: 'Lieu $i', position: LatLon(45.7, 4.8 + i / 100))],
        routing: true,
        locationDenied: true,
        now: DateTime.now(),
      );
      expect(s['places'] as List, hasLength(CarLink.maxPlaces));
      expect((s['places']! as List).first, {'name': 'Lieu 0', 'detail': null, 'lat': 45.7, 'lon': 4.8});
      expect(s['routing'], isTrue);
      expect(s['locationDenied'], isTrue);
    });

    test('not navigating: position and map only', () {
      final s = carState(guidance: null, route: null, position: const LatLon(45.75, 4.83), now: DateTime.now());
      expect(s['navigating'], isFalse);
      expect(s.containsKey('maneuver'), isFalse);
      expect(s.containsKey('route'), isFalse);
      expect(s['lat'], 45.75);
    });
  });

  group('link', () {
    late List<MethodCall> sent;
    late ChangeNotifier changes;
    late List<String> calls;
    late CarLink link;
    var snapshot = <String, Object?>{};

    setUp(() {
      sent = [];
      calls = [];
      changes = ChangeNotifier();
      snapshot = {'navigating': false, 'routeId': 'r1', 'route': const []};
      messenger.setMockMethodCallHandler(CarLink.channel, (call) async {
        sent.add(call);
        return null;
      });
      link = CarLink(
        changes: changes,
        snapshot: () => snapshot,
        onReport: (t) => calls.add('report ${t.code}'),
        onConfirm: (id, v) => calls.add('confirm $id $v'),
        onStop: () => calls.add('stop'),
        onNavigate: (p) => calls.add('navigate ${p.name} ${p.position.lat},${p.position.lon}'),
        onSearch: (q) async {
          if (q == 'panne') throw Exception('offline');
          return [
            for (var i = 0; i < 8; i++) Place(name: '$q $i', detail: 'Lyon', position: LatLon(45.75, 4.83 + i / 100)),
          ];
        },
        minInterval: const Duration(milliseconds: 100),
      )..start(android: true);
    });

    tearDown(() {
      link.stop();
      messenger.setMockMethodCallHandler(CarLink.channel, null);
    });

    Future<Object?> fromCar(String method, [Object? args]) async {
      final data = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
      final reply = await messenger.handlePlatformMessage(CarLink.channel.name, data, (_) {});
      return reply;
    }

    testWidgets('sends at start, then at most once per interval; the route only when it changes', (tester) async {
      expect(sent.single.method, 'update');
      expect((sent.single.arguments as Map).containsKey('route'), isTrue);

      for (var i = 0; i < 5; i++) {
        changes.notifyListeners();
      }
      await tester.pump(const Duration(milliseconds: 150));
      expect(sent, hasLength(2));
      expect((sent.last.arguments as Map).containsKey('route'), isFalse, reason: 'same route id');

      snapshot = {'navigating': true, 'routeId': 'r2', 'route': const []};
      changes.notifyListeners();
      await tester.pump(const Duration(milliseconds: 150));
      expect((sent.last.arguments as Map).containsKey('route'), isTrue);
    });

    testWidgets('reports, answers and stop from the car reach the app; police is refused', (tester) async {
      await fromCar('report', {'type': 'closure'});
      await fromCar('report', {'type': 'police'});
      await fromCar('report', {'type': 'nope'});
      await fromCar('confirm', {'id': 'abc', 'stillThere': false});
      await fromCar('confirm', {'id': 'abc', 'stillThere': null});
      await fromCar('stop');
      expect(calls, ['report closure', 'confirm abc false', 'confirm abc null', 'stop']);
    });

    testWidgets('destinations from the car: navigate, search (capped, errors give nothing)', (tester) async {
      final codec = const StandardMethodCodec();
      await fromCar('navigate', {'name': 'Maison', 'detail': null, 'lat': 45.76, 'lon': 4.85});
      await fromCar('navigate', {'name': 'Sans position'});
      expect(calls, ['navigate Maison 45.76,4.85']);

      final found = codec.decodeEnvelope((await fromCar('search', {'query': ' gare '}))! as ByteData) as List;
      expect(found, hasLength(CarLink.maxPlaces));
      expect(found.first, {'name': 'gare 0', 'detail': 'Lyon', 'lat': 45.75, 'lon': 4.83});
      final none = codec.decodeEnvelope((await fromCar('search', {'query': 'panne'}))! as ByteData) as List;
      expect(none, isEmpty);
    });
  });

  test('does nothing outside Android', () {
    final changes = ChangeNotifier();
    var snapshots = 0;
    CarLink(
      changes: changes,
      snapshot: () {
        snapshots++;
        return const {};
      },
      onReport: (_) {},
      onConfirm: (_, _) {},
      onStop: () {},
      onNavigate: (_) {},
      onSearch: (_) async => const [],
    ).start(android: false);
    changes.notifyListeners();
    expect(snapshots, 0);
  });
}

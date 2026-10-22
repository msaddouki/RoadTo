import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late TripRoute route;

  setUp(() => route = parseValhallaRoute(_fixture('valhalla_lyon.json')));

  RoadAlert jamAt(TripRoute r, double along, String id, {int? bearing, AlertType type = AlertType.traffic}) =>
      RoadAlert(
        id: id,
        author: 'x',
        type: type,
        geohash: geohashEncode(r.pointAt(along), precision: 7),
        createdAt: DateTime(2026),
        expiresAt: DateTime(2027),
        bearing: bearing,
      );

  /// Drives [r] from [from] to [to] metres, one fix every [stepS] seconds,
  /// taking [pace] times the engine's time.
  DateTime drive(
    EtaEstimator eta,
    GuidanceEngine engine,
    TripRoute r,
    DateTime start, {
    double from = 0,
    double? to,
    double pace = 1,
    double stepS = 2,
  }) {
    final end = to ?? r.shapeLengthM - 30;
    var at = start;
    var along = from;
    while (along < end) {
      final p = r.pointAt(along);
      eta.observe(at, engine.update(p, speedMps: 10));
      // Engine time for the next [stepS] seconds of driving at [pace].
      final kph = _plannedKph(r, along);
      along += kph / 3.6 * stepS / pace;
      at = at.add(Duration(milliseconds: (stepS * 1000).round()));
    }
    return at;
  }

  group('learned pace', () {
    test('nothing learned, or too little: the engine’s time', () {
      expect(LearnedPace.none.factor(RoadBand.town), 1);
      final little = LearnedPace.none.add({RoadBand.town: const PaceSample(300, 200)});
      expect(little.factor(RoadBand.town), 1);
      expect(little.isEmpty, isTrue);
    });

    test('an hour in town 20 % faster: about 13 % off, the other roads unchanged', () {
      final pace = LearnedPace.none.add({RoadBand.town: const PaceSample(3600, 2880)});
      expect(pace.factor(RoadBand.town), closeTo(1 - 0.2 * 3600 / 5400, 1e-9));
      expect(pace.factor(RoadBand.fast), 1);
    });

    test('bounded, old trips fade, saved and read back', () {
      final wild = LearnedPace.none.add({RoadBand.road: const PaceSample(36000, 3600)});
      expect(wild.factor(RoadBand.road), greaterThanOrEqualTo(0.7));
      expect(wild.bands[RoadBand.road]!.plannedS, LearnedPace.keptS);
      expect(wild.bands[RoadBand.road]!.actualS, closeTo(LearnedPace.keptS / 10, 1e-6));
      final back = LearnedPace.fromJson(jsonDecode(jsonEncode(wild.toJson())) as Map<String, dynamic>);
      expect(back.factor(RoadBand.road), wild.factor(RoadBand.road));
      expect(LearnedPace.fromJson({'town': 'garbage'}).bands, isEmpty);
    });

    test('kinds of road by planned speed', () {
      expect(RoadBand.ofSpeed(25), RoadBand.town);
      expect(RoadBand.ofSpeed(50), RoadBand.road);
      expect(RoadBand.ofSpeed(110), RoadBand.fast);
    });
  });

  group('estimator', () {
    test('before driving: the engine’s time, per stretch', () {
      final eta = EtaEstimator(route);
      expect(eta.plannedRemainingS(0), closeTo(route.timeS, route.timeS * 0.02));
      expect(eta.plannedRemainingS(route.shapeLengthM), 0);
      expect(eta.plannedRemainingS(route.shapeLengthM / 2), inExclusiveRange(0, route.timeS));
    });

    test('learned pace shortens the town stretches', () {
      final fast = LearnedPace.none.add({
        RoadBand.town: const PaceSample(3600, 2880),
        RoadBand.road: const PaceSample(3600, 2880),
      });
      expect(EtaEstimator(route, learned: fast).total(), lessThan(EtaEstimator(route).total()));
    });

    test('driving faster than planned brings the arrival closer, on the stretch ahead', () {
      final eta = EtaEstimator(route);
      final engine = GuidanceEngine(route);
      drive(eta, engine, route, DateTime(2026), to: route.shapeLengthM * 0.6, pace: 0.7);
      final g = engine.update(route.pointAt(route.shapeLengthM * 0.6));
      final planned = eta.plannedRemainingS(g.projection.alongM);
      expect(eta.live.ratio, closeTo(0.7, 0.08));
      expect(eta.remaining(g).inSeconds, lessThan(planned));
      expect(eta.remaining(g).inSeconds, greaterThan(planned * 0.7));
    });

    test('waiting at the start is not slow driving', () {
      final eta = EtaEstimator(route);
      final engine = GuidanceEngine(route);
      final start = DateTime(2026);
      for (var s = 0; s < 180; s += 5) {
        eta.observe(start.add(Duration(seconds: s)), engine.update(route.pointAt(0)));
      }
      drive(eta, engine, route, start.add(const Duration(seconds: 180)), to: route.shapeLengthM * 0.6);
      expect(eta.live.ratio, closeTo(1, 0.08));
    });

    test('what the trip teaches, per kind of road; nothing off route', () {
      final eta = EtaEstimator(route);
      final engine = GuidanceEngine(route);
      drive(eta, engine, route, DateTime(2026), pace: 0.8);
      final planned = eta.driven.values.fold(0.0, (s, p) => s + p.plannedS);
      final actual = eta.driven.values.fold(0.0, (s, p) => s + p.actualS);
      expect(planned, greaterThan(route.timeS * 0.8));
      expect(actual / planned, closeTo(0.8, 0.05));

      final off = EtaEstimator(route);
      final lost = GuidanceEngine(route);
      final far = const LatLon(45.8, 4.9);
      for (var s = 0; s < 60; s += 2) {
        off.observe(DateTime(2026).add(Duration(seconds: s)), lost.update(far));
      }
      expect(off.driven, isEmpty);
    });

    test('a reroute keeps the live pace', () {
      final eta = EtaEstimator(route);
      drive(eta, GuidanceEngine(route), route, DateTime(2026), to: route.shapeLengthM * 0.6, pace: 0.7);
      final next = EtaEstimator(route, carry: eta.live);
      expect(next.live.ratio, eta.live.ratio);
    });
  });

  group('jams', () {
    test('a jam on the route adds its delay, ahead only', () {
      final delays = trafficDelays(route, [jamAt(route, 1200, 'bouchon')]);
      expect(delays, hasLength(1));
      final kph = _plannedKph(route, 1200);
      expect(delays.single.delay.inSeconds, closeTo(500 / (10 / 3.6) - 500 / (kph / 3.6), 2));
      final eta = EtaEstimator(route);
      final engine = GuidanceEngine(route);
      final before = engine.update(route.pointAt(100));
      expect(eta.remaining(before, delays: delays) - eta.remaining(before), delays.single.delay);
      final after = engine.update(route.pointAt(1600));
      expect(eta.remaining(after, delays: delays), eta.remaining(after));
      expect(eta.total(delays: delays) - eta.total(), delays.single.delay);
    });

    test('other alerts, other side of the road, off the route: no delay', () {
      final along = 1200.0;
      final at = projectOnRoute(route, jamAt(route, along, 'probe').position)!;
      final heading = route.bearingAt(at.alongM).round();
      expect(trafficDelays(route, [jamAt(route, along, 'a', type: AlertType.roadworks)]), isEmpty);
      expect(trafficDelays(route, [jamAt(route, along, 'b', bearing: (heading + 180) % 360)]), isEmpty);
      expect(trafficDelays(route, [jamAt(route, along, 'c', bearing: heading)]), hasLength(1));
      final far = RoadAlert(
        id: 'far',
        author: 'x',
        type: AlertType.traffic,
        geohash: geohashEncode(const LatLon(45.8, 4.95)),
        createdAt: DateTime(2026),
        expiresAt: DateTime(2027),
      );
      expect(trafficDelays(route, [far]), isEmpty);
    });
  });

  group('alternatives', () {
    late List<TripRoute> routes;

    setUp(() => routes = parseValhallaRoutes(_fixture('valhalla_alternates.json')));

    test('the engine’s route, then its alternatives', () {
      expect(routes, hasLength(3));
      expect(routes.first.lengthM, closeTo(17407, 1));
      expect(parseValhallaRoutes(_fixture('valhalla_lyon.json')), hasLength(1));
    });

    test('the engine’s route unless another is clearly faster, jams counted', () {
      // Without jams, the third is 2 min faster: taken with the default gain, not with 3 min.
      expect(fastestWithJams(routes, const []).$1, same(routes[2]));
      expect(fastestWithJams(routes, const [], minGain: const Duration(minutes: 3)).$1, same(routes[0]));
      // Jams on the third: back to the engine's route.
      final jams = [
        for (final d in [800.0, 2000.0, 3500.0]) jamAt(routes[2], d, 'j$d'),
      ];
      final (chosen, delays) = fastestWithJams(routes, jams);
      expect(chosen, isNot(same(routes[2])));
      expect(
        EtaEstimator(chosen).total(delays: delays),
        lessThan(EtaEstimator(routes[2]).total(delays: trafficDelays(routes[2], jams))),
      );
    });

    test('asked from a server', () async {
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response.bytes(File('test/fixtures/valhalla_alternates.json').readAsBytesSync(), 200);
      });
      final router = ValhallaRouter(baseUrl: 'https://example.org/', client: client);
      final got = await router.routes(const LatLon(45.75, 4.83), const LatLon(45.77, 4.89));
      expect(sent['alternates'], 2);
      expect(got, hasLength(3));
      expect(valhallaRouteRequest(const LatLon(0, 0), const LatLon(1, 1)).containsKey('alternates'), isFalse);
    });

    test('a fallback router asks its primary, else one route', () async {
      final one = _OneRoute(routes.first);
      final several = FallbackRouter(one, one);
      expect(await several.routes(const LatLon(0, 0), const LatLon(1, 1)), [routes.first]);
    });
  });
}

double _plannedKph(TripRoute r, double along) {
  var i = 0;
  for (var k = 0; k < r.maneuvers.length; k++) {
    if (r.maneuverStartM(k) <= along) i = k;
  }
  final m = r.maneuvers[i];
  return m.timeS <= 0 ? 30 : m.lengthM / m.timeS * 3.6;
}

class _OneRoute implements RouteEngine {
  final TripRoute only;

  _OneRoute(this.only);

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async => only;
}

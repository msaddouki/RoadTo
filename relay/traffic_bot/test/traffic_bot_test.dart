import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_traffic_bot/traffic_bot.dart';
import 'package:test/test.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A TRAFICOLOR file with these states, published at [at].
({DateTime? at, Map<String, String> states}) _file(DateTime at, Map<String, String> states) => (at: at, states: states);

/// A route along [points], timed at 50 km/h.
TripRoute _routeThrough(List<LatLon> points) {
  var length = 0.0;
  for (var i = 1; i < points.length; i++) {
    length += distanceM(points[i - 1], points[i]);
  }
  return TripRoute(
    shape: points,
    maneuvers: [
      Maneuver(type: 1, instruction: 'Partez.', beginShapeIndex: 0, lengthM: length, timeS: length / 13.9),
      Maneuver(type: 4, instruction: 'Arrivée.', beginShapeIndex: points.length - 1, lengthM: 0, timeS: 0),
    ],
    lengthM: length,
    timeS: length / 13.9,
  );
}

class _FakeRouter implements RouteEngine {
  TripRoute? Function(LatLon from, LatLon to, double? heading) answer;
  int calls = 0;

  _FakeRouter(this.answer);

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async {
    calls++;
    final r = answer(from, to, headingDeg);
    if (r == null) throw RoutingException('no route');
    return r;
  }
}

void main() {
  final sites = parseReferential(_fixture('refDir.csv'));
  final robot = KeyPair.fromPrivateKey('3' * 64);
  final t0 = DateTime.utc(2026, 10, 22, 11);

  group('Lambert-93', () {
    test('the projection’s origin, and a station on the A42', () {
      final origin = lambert93ToWgs84(700000, 6600000);
      expect(origin.lat, closeTo(46.5, 1e-9));
      expect(origin.lon, closeTo(3, 1e-9));
      // Checked against the road network: on the A42 (Valhalla /locate).
      final a42 = lambert93ToWgs84(848835.0, 6523230.0);
      expect(a42.lat, closeTo(45.792439, 1e-5));
      expect(a42.lon, closeTo(4.916070, 1e-5));
    });
  });

  group('Bison Futé files', () {
    test('referential: stations with a position, in the direction of traffic', () {
      expect(sites.keys, unorderedEquals(['MUM76.h1', 'MY269.D1', 'MY269.D2', 'MY269.F3']));
      final a42 = sites['MY269.D1']!;
      expect(a42.road, 'A42');
      expect(a42.bearing, inInclusiveRange(45, 135), reason: 'OUEST_EST');
      expect(a42.lengthM, closeTo(999, 5));
      // Given north to south, measured south to north: turned round.
      final n346 = sites['MY269.D2']!;
      expect(n346.road, 'N346');
      expect(n346.bearing < 90 || n346.bearing > 270, isTrue, reason: 'SUD_NORD, ${n346.bearing}');
      expect(n346.start.lat, lessThan(n346.end.lat));
      // A point station: its direction only, no length.
      final point = sites['MY269.F3']!;
      expect(point.bearing, 0);
      expect(jamLengthOf(point), isNull);
      expect(jamLengthOf(a42), closeTo(999, 5));
    });

    test('the newest file of a feed, and the states in it', () {
      expect(latestFile(_fixture('index.html')), matches(RegExp(r'^TraficLyon_DataTRT_\d{8}_\d{6}\.xml$')));
      expect(
        latestFile(
          '<a href="TraficLyon_DataTRT_20261022_080633.xml">x</a><a href="TraficLyon_DataTRT_20261022_130235.xml">y</a>'
          '<a href="TraficLyon_DataTRT_20261022_091000.xml">z</a>',
        ),
        'TraficLyon_DataTRT_20261022_130235.xml',
      );
      expect(latestFile('<html></html>'), isNull);
      final data = parseStates(_fixture('TraficLyon_DataTRT_20261022_130235.xml'));
      expect(data.at, DateTime.utc(2026, 10, 22, 11, 2, 35, 349));
      expect(data.states, {'MQA01.E1': 'freeFlow', 'MY269.D2': 'freeFlow'});
    });

    test('DATEX II states to RoadTo levels', () {
      expect(levelOf('freeFlow'), isNull);
      expect(levelOf('heavy'), JamLevel.slow);
      expect(levelOf('congested'), JamLevel.jam);
      expect(levelOf('impossible'), JamLevel.stopped);
      expect(levelOf('unknown'), isNull);
    });
  });

  group('robot', () {
    late TrafficBot bot;
    var n = 0;
    List<NostrEvent> minute(int m, Map<String, String> states, {DateTime? published}) {
      final now = t0.add(Duration(minutes: m));
      return bot.step('TraficLyon', 'file${n++}', _file(published ?? now, states), now);
    }

    setUp(() => bot = TrafficBot(keys: robot, sites: sites));

    test('a jam is published after two readings, as an alert the apps read', () {
      expect(minute(0, {'MY269.D1': 'congested'}), isEmpty, reason: 'one reading is not enough');
      final events = minute(1, {'MY269.D1': 'congested'});
      expect(events, hasLength(1));
      final e = events.single;
      expect(checkWritePolicy(e, now: t0.add(const Duration(minutes: 1))), isNull);
      expect(e.expiration! - e.createdAt, TrafficBot.lasting.inSeconds);
      final a = RoadAlert.fromEvent(e, trustedSources: {robot.publicKey})!;
      expect(a.type, AlertType.traffic);
      expect(a.level, JamLevel.jam);
      expect(a.lengthM, closeTo(999, 5));
      expect(a.source, 'bison-fute/MY269.D1');
      expect(a.sourceLabel, 'Bison Futé');
      expect(a.bearing, inInclusiveRange(40, 140));
      expect(distanceM(a.position, sites['MY269.D1']!.middle), lessThan(120));
    });

    test('published again every five minutes while it lasts, at once when it changes', () {
      minute(0, {'MY269.D1': 'congested'});
      expect(minute(1, {'MY269.D1': 'congested'}), hasLength(1));
      for (var m = 2; m < 6; m++) {
        expect(minute(m, {'MY269.D1': 'congested'}), isEmpty, reason: 'minute $m');
      }
      expect(minute(6, {'MY269.D1': 'congested'}), hasLength(1));
      final worse = minute(7, {'MY269.D1': 'impossible'});
      expect(RoadAlert.fromEvent(worse.single)!.level, JamLevel.stopped);
    });

    test('traffic flowing again or no news: nothing more, the alert runs out', () {
      minute(0, {'MY269.D1': 'congested'});
      minute(1, {'MY269.D1': 'congested'});
      expect(minute(2, {'MY269.D1': 'freeFlow'}), isEmpty);
      expect(bot.jammed, 0);
      expect(minute(3, {'MY269.D1': 'congested'}), isEmpty, reason: 'counted again from one reading');
      minute(4, {'MY269.D2': 'heavy'});
      for (var m = 5; m < 12; m++) {
        expect(minute(m, {'MY269.D2': 'unknown'}), isEmpty);
      }
    });

    test('stations without a position, stale or repeated files: nothing', () {
      minute(0, {'MQA01.E1': 'congested'});
      expect(minute(1, {'MQA01.E1': 'congested'}), isEmpty);
      minute(2, {'MY269.D1': 'congested'});
      expect(minute(3, {'MY269.D1': 'congested'}, published: t0.add(const Duration(minutes: -20))), isEmpty);
      final now = t0.add(const Duration(minutes: 4));
      final data = _file(now, {'MY269.D1': 'congested'});
      expect(bot.step('TraficLyon', 'same.xml', data, now), hasLength(1));
      expect(bot.step('TraficLyon', 'same.xml', data, now.add(const Duration(minutes: 6))), isEmpty);
    });
  });

  group('the road of a station', () {
    final a42 = sites['MY269.D1']!;

    test('the route along the stretch, unless it strays; cut and thinned', () {
      final along = _routeThrough([a42.start, a42.middle, a42.end]);
      expect(stretchShape(a42, along), hasLength(3));
      final detour = _routeThrough([a42.start, const LatLon(45.83, 4.95), a42.end]);
      expect(stretchShape(a42, detour), isNull, reason: 'far longer than the stretch');
      expect(stretchShape(sites['MY269.F3']!, along), isNull, reason: 'a point station');
      // A long, finely drawn stretch: cut to 3 km, at most 200 points.
      final long = Site('L', 'A7', const LatLon(45.70, 4.80), const LatLon(45.70 + 4000 / 111320, 4.80), 0);
      final fine = _routeThrough([for (var i = 0; i <= 400; i++) LatLon(45.70 + i * 10 / 111320, 4.80)]);
      final cut = stretchShape(long, fine)!;
      expect(cut.length, lessThanOrEqualTo(200));
      expect(distanceM(cut.first, long.start), lessThan(1));
      expect(distanceM(cut.first, cut.last), closeTo(maxStretchM, 15));
    });

    test('asked once per station, heading with traffic; tried again an hour after a failure', () async {
      double? heading;
      final router = _FakeRouter((from, to, h) {
        heading = h;
        return _routeThrough([from, to]);
      });
      final shapes = StretchShapes(router);
      expect(shapes.wants(a42, t0), isTrue);
      await shapes.fetch(a42, t0);
      expect(heading, a42.bearing);
      expect(shapes[a42.id], hasLength(2));
      expect(shapes.wants(a42, t0), isFalse);

      final failing = StretchShapes(_FakeRouter((_, _, _) => null));
      await failing.fetch(a42, t0);
      expect(failing[a42.id], isNull);
      expect(failing.wants(a42, t0.add(const Duration(minutes: 30))), isFalse);
      expect(failing.wants(a42, t0.add(const Duration(hours: 1))), isTrue);
    });

    test('a jam carries its road once known', () async {
      final shapes = StretchShapes(_FakeRouter((from, to, _) => _routeThrough([from, to])));
      await shapes.fetch(a42, t0);
      final bot = TrafficBot(keys: robot, sites: sites, shapeOf: (id) => shapes[id]);
      bot.step('TraficLyon', 'a', _file(t0, {'MY269.D1': 'congested'}), t0);
      final e = bot.step('TraficLyon', 'b', _file(t0, {'MY269.D1': 'congested'}), t0).single;
      expect(checkWritePolicy(e, now: t0), isNull);
      final alert = RoadAlert.fromEvent(e, trustedSources: {robot.publicKey})!;
      final shape = alert.shape!;
      expect(distanceM(shape.first, a42.start), lessThan(1));
      expect(distanceM(shape.last, a42.end), lessThan(1));
      // Its pin on the road: the middle of the road, within its cell.
      expect(distanceM(alert.position, middleOf(shape)), lessThan(120));
    });

    test('the middle of a bent road is on it, not on the straight line', () {
      const bend = [LatLon(45.70, 4.80), LatLon(45.71, 4.80), LatLon(45.71, 4.81427)];
      final m = middleOf(bend);
      // 1112 m north then 1112 m east: halfway is the corner.
      expect(distanceM(m, bend[1]), lessThan(5));
      expect(middleOf(const [LatLon(45.7, 4.8), LatLon(45.7, 4.8)]), const LatLon(45.7, 4.8));
    });
  });
}

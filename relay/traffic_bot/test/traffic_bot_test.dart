import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_traffic_bot/traffic_bot.dart';
import 'package:test/test.dart';

String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// A TRAFICOLOR file with these states, published at [at].
({DateTime? at, Map<String, String> states}) _file(DateTime at, Map<String, String> states) => (at: at, states: states);

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
}

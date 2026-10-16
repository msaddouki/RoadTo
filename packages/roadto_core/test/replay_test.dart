import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

import 'support/traces.dart';

TripRoute _route(String fixture) =>
    parseValhallaRoute(jsonDecode(File('test/fixtures/$fixture').readAsStringSync()) as Map<String, dynamic>);

void main() {
  final route = _route('valhalla_lyon.json'); // Bellecour -> Cours Lafayette, 2.5 km, 2 turns

  group('GPX', () {
    test('reads track points, in any attribute order, with or without time', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1"><trk><trkseg>
  <trkpt lat="45.7578" lon="4.8320"><ele>170</ele><time>2026-10-01T08:00:00Z</time></trkpt>
  <trkpt lon='4.8330' lat='45.7578'><time>2026-10-01T08:00:10Z</time></trkpt>
  <trkpt lat="45.7579" lon="4.8340"/>
</trkseg></trk></gpx>''';
      final pts = parseGpx(gpx);
      expect(pts, hasLength(3));
      expect(pts[1].position.lon, 4.833);
      // Speed derived from time and distance: ~78 m in 10 s.
      expect(pts[1].speedMps, closeTo(7.8, 0.3));
      expect(pts[2].time, isNull);
    });

    test('round trip with speed and course', () {
      final trace = simulateDrive(route, seed: 1, noiseM: 5);
      final back = parseGpx(toGpx(trace, name: 'Bellecour <-> Lafayette'));
      expect(back, hasLength(trace.length));
      expect(distanceM(back[10].position, trace[10].position), lessThan(0.05));
      expect(back[10].speedMps, closeTo(trace[10].speedMps!, 0.01));
      expect(back[10].courseDeg, closeTo(trace[10].courseDeg!, 0.1));
      expect(back[10].time, trace[10].time);
    });
  });

  // Reference drives of the plan's J2 exit criterion: replayed in CI, none
  // may produce a guidance error (false off-route, maneuver not announced
  // before it, no arrival).
  group('reference drives, no guidance error', () {
    final drives = <String, List<TracePoint> Function()>{
      'clean, 30 km/h': () => simulateDrive(route, seed: 1, speedKmh: 30),
      'city, 50 km/h, 5 m noise': () => simulateDrive(route, seed: 2, speedKmh: 50, noiseM: 5),
      '10 m noise': () => simulateDrive(route, seed: 3, noiseM: 10),
      'noise and 40 m outliers': () => simulateDrive(route, seed: 4, noiseM: 8, spikeChance: 0.05),
      'tunnel, 150 m without fixes': () => simulateDrive(route, seed: 5, noiseM: 5, tunnel: (fromM: 500, toM: 650)),
      'red light, 25 s stop': () => simulateDrive(route, seed: 6, noiseM: 6, stop: (atM: 900, seconds: 25)),
      '2 Hz receiver': () => simulateDrive(route, seed: 7, intervalS: 0.5, noiseM: 5),
      'one fix every 2 s at 50 km/h': () => simulateDrive(route, seed: 8, speedKmh: 50, intervalS: 2, noiseM: 5),
      'traffic jam, 12 km/h': () => simulateDrive(route, seed: 9, speedKmh: 12, noiseM: 6),
      'fast, 70 km/h': () => simulateDrive(route, seed: 10, speedKmh: 70, noiseM: 8),
    };

    for (final MapEntry(key: name, value: drive) in drives.entries) {
      test(name, () {
        final report = replayTrace(route, drive());
        expect(report.offRouteAt, isEmpty, reason: 'false off-route: $report');
        expect(report.arrived, isTrue, reason: '$report');
        for (var m = 0; m < report.preAnnouncedBeforeM.length; m++) {
          final before = report.preAnnouncedBeforeM[m];
          expect(before, isNotNull, reason: 'maneuver ${m + 1} never announced: $report');
          expect(before, greaterThanOrEqualTo(0), reason: 'maneuver ${m + 1} announced after it: $report');
        }
        expect(report.clean, isTrue);
        // Each announcement is said once.
        final texts = report.announcements.map((a) => a.text).toList();
        expect(texts.toSet(), hasLength(texts.length), reason: texts.join(' | '));
      });
    }
  });

  test('a real detour is caught, within a few fixes', () {
    final trace = simulateDrive(route, seed: 11, noiseM: 5, detour: (fromM: 1400, toM: 1700, offsetM: 90));
    final report = replayTrace(route, trace);
    expect(report.offRouteAt, isNotEmpty);
    final first = report.offRouteAt.first;
    final along = projectOnRoute(route, trace[first].position)!.alongM;
    expect(along, inInclusiveRange(1400, 1500), reason: 'caught at ${along.round()} m');
  });

  test('two drifting fixes (urban canyon) are not a detour', () {
    final trace = simulateDrive(route, seed: 12, noiseM: 4, detour: (fromM: 600, toM: 615, offsetM: 60));
    expect(replayTrace(route, trace).offRouteAt, isEmpty);
  });

  // Real drives recorded with the app (or any GPS logger) go in
  // test/fixtures/gpx/<name>.gpx, next to the Valhalla route they followed
  // (<name>.route.json); each must replay without guidance error.
  group('drives in test/fixtures/gpx', () {
    final dir = Directory('test/fixtures/gpx');
    final files = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.gpx')).toList())
        : <File>[];
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final gpx in files) {
      test(gpx.uri.pathSegments.last, () {
        final routeFile = File(gpx.path.replaceFirst(RegExp(r'\.gpx$'), '.route.json'));
        final r = parseValhallaRoute(jsonDecode(routeFile.readAsStringSync()) as Map<String, dynamic>);
        final report = replayTrace(r, parseGpx(gpx.readAsStringSync()));
        expect(report.clean, isTrue, reason: '$report');
      });
    }
  });
}

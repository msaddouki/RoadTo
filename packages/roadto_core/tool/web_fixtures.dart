// Reference values for the web site's port of the alert and route logic
// (web/src), the route from a real Valhalla answer
// (web/test/fixtures/valhalla-route.json):
//   dart run tool/web_fixtures.dart > ../../web/test/fixtures/core.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:roadto_core/roadto_core.dart';

final _keys = <String, KeyPair>{};

/// A real event (mined and signed) from a fixed key per name.
NostrEvent _event(String name, int kind, int at, List<List<String>> tags) {
  final keys = _keys.putIfAbsent(
    name,
    () => KeyPair.fromPrivateKey(
      (BigInt.from(1000 + _keys.length) * BigInt.from(7919)).toRadixString(16).padLeft(64, '0'),
    ),
  );
  return NostrEvent.create(
    keys: keys,
    kind: kind,
    tags: tags,
    createdAt: DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true),
    powDifficulty: PowPolicy.forKind(kind),
  );
}

void main() {
  const t0 = 1792483200; // 2026-10-20 08:00 UTC
  final a1 = _event('author', RoadToKinds.alert, t0, [
    ['t', 'accident'],
    ['g', 'u05k'],
    ['g', 'u05kq'],
    ['g', 'u05kqt'],
    ['g', 'u05kqt1'],
    ['expiration', '${t0 + 3600}'],
    ['bearing', '90'],
  ]);
  final a2 = _event('other', RoadToKinds.alert, t0 - 1200, [
    ['t', 'traffic'],
    ['g', 'u05kqbz'],
    ['expiration', '${t0 + 600}'],
  ]);
  final events = [
    a1,
    a2,
    _event('b', RoadToKinds.confirmation, t0 + 600, [
      ['e', a1.id],
      ['still', 'yes'],
    ]),
    _event('c', RoadToKinds.confirmation, t0 + 900, [
      ['e', a1.id],
      ['still', 'no'],
    ]),
    // The author's own answer does not count.
    _event('author', RoadToKinds.confirmation, t0 + 950, [
      ['e', a1.id],
      ['still', 'yes'],
    ]),
    _event('d', RoadToKinds.confirmation, t0 + 300, [
      ['e', a2.id],
      ['still', 'no'],
    ]),
    _event('e', RoadToKinds.confirmation, t0 + 310, [
      ['e', a2.id],
      ['still', 'no'],
    ]),
  ];
  final store = AlertStore();
  for (final e in events) {
    store.ingest(e, now: DateTime.fromMillisecondsSinceEpoch((e.createdAt + 1) * 1000, isUtc: true));
  }
  final nows = [t0, t0 + 1200, t0 + 3000];
  DateTime at(int s) => DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
  final points = [(45.7578, 4.8320), (48.8566, 2.3522), (-33.8688, 151.2093)];
  final route = parseValhallaRoute(
    jsonDecode(File('../../web/test/fixtures/valhalla-route.json').readAsStringSync()) as Map<String, dynamic>,
  );
  // A drive along the route at 50 km/h, one fix a second, that leaves it
  // for a while (80 m aside) halfway and comes back.
  final engine = GuidanceEngine(route);
  final drive = <Map<String, Object?>>[];
  for (var t = 0; ; t++) {
    final d = t * 50 / 3.6;
    var p = route.pointAt(d);
    if (t >= 140 && t < 150) {
      final b = route.bearingAt(d) + 90;
      p = LatLon(
        p.lat + 80 / 111320 * math.cos(b * math.pi / 180),
        p.lon + 80 / (111320 * math.cos(p.lat * math.pi / 180)) * math.sin(b * math.pi / 180),
      );
    }
    final g = engine.update(p, speedMps: 50 / 3.6);
    drive.add({
      'lat': p.lat,
      'lon': p.lon,
      'alongM': g.projection.alongM,
      'next': g.nextManeuverIndex,
      'distanceToNextM': g.distanceToNextM,
      'remainingM': g.remainingM,
      'remainingS': g.remaining.inSeconds,
      'offRoute': g.offRoute,
      'arrived': g.arrived,
      'say': g.announcement,
    });
    if (g.arrived || d > route.shapeLengthM + 50) break;
  }
  // The time to arrival over a drive at 0.8 times the engine's time, one
  // fix every 2 s, with a learned pace and a jam ahead.
  final learned = LearnedPace.none.add({
    RoadBand.town: const PaceSample(3600, 3240),
    RoadBand.road: const PaceSample(1200, 1080),
  });
  final jam = RoadAlert(
    id: 'jam',
    author: 'x',
    type: AlertType.traffic,
    geohash: geohashEncode(route.pointAt(3000), precision: 7),
    createdAt: DateTime.utc(2026),
    expiresAt: DateTime.utc(2027),
  );
  final delays = trafficDelays(route, [jam]);
  final eta = EtaEstimator(route, learned: learned);
  final etaEngine = GuidanceEngine(route);
  final etaDrive = <Map<String, Object?>>[];
  var clock = DateTime.utc(2026, 10, 21, 8);
  for (var along = 0.0; along < route.shapeLengthM - 30;) {
    final p = route.pointAt(along);
    final g = etaEngine.update(p, speedMps: 10);
    eta.observe(clock, g);
    etaDrive.add({
      'lat': p.lat,
      'lon': p.lon,
      'atMs': clock.millisecondsSinceEpoch,
      'remainingS': eta.remaining(g, delays: delays).inSeconds,
      'ratio': eta.live.ratio,
      'weight': eta.live.weight,
    });
    var i = 0;
    for (var k = 0; k < route.maneuvers.length; k++) {
      if (route.maneuverStartM(k) <= along) i = k;
    }
    final m = route.maneuvers[i];
    final kph = m.timeS <= 0 ? 30 : m.lengthM / m.timeS * 3.6;
    along += kph / 3.6 * 2 / 0.8;
    clock = clock.add(const Duration(seconds: 2));
  }
  final alternates = parseValhallaRoutes(
    jsonDecode(File('../../web/test/fixtures/valhalla-alternates.json').readAsStringSync()) as Map<String, dynamic>,
  );
  final altJams = [
    for (final d in [800.0, 2000.0, 3500.0])
      RoadAlert(
        id: 'j$d',
        author: 'x',
        type: AlertType.traffic,
        geohash: geohashEncode(alternates[2].pointAt(d), precision: 7),
        createdAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2027),
      ),
  ];

  // Jams from the traffic robot (a test key here): level, length, source,
  // the newer replacing the older, and the delay each adds.
  final sensor = KeyPair.fromPrivateKey('5' * 64);
  NostrEvent sensorJam(DateTime at, JamLevel level, int length) => buildAlertEvent(
    keys: sensor,
    type: AlertType.traffic,
    position: route.pointAt(1500),
    bearing: route.bearingAt(1500),
    now: at,
    level: level,
    lengthM: length,
    source: 'bison-fute/MY269.D1',
    lasting: const Duration(minutes: 10),
  );
  final sensorOld = sensorJam(DateTime.utc(2026, 10, 22, 8), JamLevel.slow, 600);
  final sensorNew = sensorJam(DateTime.utc(2026, 10, 22, 8, 5), JamLevel.stopped, 1500);
  final sensorAlert = RoadAlert.fromEvent(sensorNew, trustedSources: {sensor.publicKey})!;

  // A trace_attributes answer on the route's shape: 50, 50, none, 30.
  final n = route.shape.length - 1;
  final trace = {
    'shape': encodePolyline(route.shape),
    'edges': [
      {'speed_limit': 50, 'begin_shape_index': 0, 'end_shape_index': n ~/ 4},
      {'speed_limit': 50, 'begin_shape_index': n ~/ 4, 'end_shape_index': n ~/ 2},
      {'begin_shape_index': n ~/ 2, 'end_shape_index': 3 * n ~/ 4},
      {'speed_limit': 30, 'begin_shape_index': 3 * n ~/ 4, 'end_shape_index': n},
    ],
  };
  final limits = parseSpeedLimits(trace);
  // On the route, beside it, and far from it.
  final probes = [
    route.pointAt(1000),
    route.pointAt(2500),
    const LatLon(45.7600, 4.8450),
    const LatLon(45.7400, 4.8000),
  ];
  print(
    const JsonEncoder.withIndent(' ').convert({
      'events': [for (final e in events) e.toJson()],
      'reliability': {
        for (final id in [a1.id, a2.id]) id: [for (final n in nows) store.reliability(id, now: at(n))],
      },
      'visible': {
        for (final n in nows) '$n': [for (final a in store.visible(now: at(n))) a.id]..sort(),
      },
      'stillThere': {a1.id: store.stillThere(a1.id).count},
      'nows': nows,
      'geohash': [
        for (final (lat, lon) in points)
          {'lat': lat, 'lon': lon, 'hash': geohashEncode(LatLon(lat, lon), precision: 7)},
      ],
      'route': {
        'lengthM': route.lengthM,
        'timeS': route.timeS,
        'points': route.shape.length,
        'shapeLengthM': route.shapeLengthM,
        'maneuvers': [for (final m in route.maneuvers) m.beginShapeIndex],
        'probes': [
          for (final p in probes)
            {
              'lat': p.lat,
              'lon': p.lon,
              'alongM': projectOnRoute(route, p)!.alongM,
              'offsetM': projectOnRoute(route, p)!.offsetM,
            },
        ],
        'drive': drive,
        'sensor': {
          'key': sensor.publicKey,
          'events': [sensorOld.toJson(), sensorNew.toJson()],
          'delayS': trafficDelays(route, [sensorAlert]).single.delay.inSeconds,
        },
        'eta': {
          'learned': learned.toJson(),
          'factors': {for (final b in RoadBand.values) b.name: learned.factor(b)},
          'jam': {'lat': jam.position.lat, 'lon': jam.position.lon},
          'delays': [for (final d in delays) d.delay.inSeconds],
          'totalS': eta.total(delays: delays).inSeconds,
          'plannedS': EtaEstimator(route, learned: learned).plannedRemainingS(0),
          'drive': etaDrive,
          'driven': {
            for (final e in eta.driven.entries) e.key.name: [e.value.plannedS, e.value.actualS],
          },
          'alternates': {
            'noJams': alternates.indexOf(fastestWithJams(alternates, const []).$1),
            'noJams3min': alternates.indexOf(
              fastestWithJams(alternates, const [], minGain: const Duration(minutes: 3)).$1,
            ),
            'jams': [
              for (final j in altJams) {'lat': j.position.lat, 'lon': j.position.lon},
            ],
            'withJams': alternates.indexOf(fastestWithJams(alternates, altJams).$1),
          },
        },
        'trace': trace,
        'limits': [
          for (final s in limits.spans) {'startM': s.startM, 'endM': s.endM, 'kph': s.kph},
        ],
        'formatDistance': {
          for (final m in [42.4, 856.0, 4231.0, 37400.0]) '$m': formatDistance(m),
        },
      },
    }),
  );
}

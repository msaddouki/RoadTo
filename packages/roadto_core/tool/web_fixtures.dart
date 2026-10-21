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

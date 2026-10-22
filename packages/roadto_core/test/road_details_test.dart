import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// 1 km north, one point every 10 m, then 200 m west: a turn at 1000 m of
/// [type] (15 left, 10 right, 16 slight left).
TripRoute _road({int type = 15}) {
  final shape = [
    for (var i = 0; i <= 100; i++) LatLon(45.70 + i * 10 / 111320, 4.80),
    for (var i = 1; i <= 20; i++) LatLon(45.70 + 1000 / 111320, 4.80 - i * 10 / 77900),
  ];
  return TripRoute(
    shape: shape,
    maneuvers: [
      const Maneuver(type: 1, instruction: 'Conduisez vers le nord.', beginShapeIndex: 0, lengthM: 1000, timeS: 72),
      Maneuver(
        type: type,
        instruction: 'Tournez à gauche dans Rue X.',
        verbalAlert: 'Tournez à gauche dans Rue X.',
        verbalPre: 'Tournez à gauche dans Rue X.',
        streetNames: const ['Rue X'],
        beginShapeIndex: 100,
        lengthM: 200,
        timeS: 20,
      ),
      Maneuver(type: 4, instruction: 'Vous êtes arrivé.', beginShapeIndex: shape.length - 1, lengthM: 0, timeS: 0),
    ],
    lengthM: 1200,
    timeS: 92,
  );
}

/// A trace_attributes answer for [_road]: one edge every 10 m heading
/// north, with lights and side streets where asked (metres from the start).
Map<String, dynamic> _attributes(
  TripRoute route, {
  Set<int> lights = const {},
  Map<int, List<Map<String, Object>>> side = const {},
}) => {
  'shape': encodePolyline(route.shape),
  'edges': [
    for (var i = 0; i < 100; i++)
      {
        'begin_shape_index': i,
        'end_shape_index': i + 1,
        'end_heading': 0,
        'traffic_signal': lights.contains((i + 1) * 10),
        'end_node': {'intersecting_edges': ?side[(i + 1) * 10]},
      },
  ],
};

/// Metres along the test road, to the 10 m of its points.
int _tens(double m) => (m / 10).round() * 10;

Map<String, Object> _street(int heading, {String use = 'road', String driveability = 'both'}) => {
  'begin_heading': heading,
  'use': use,
  'driveability': driveability,
};

void main() {
  group('a real answer (Part-Dieu to Bellecour)', () {
    final route = parseValhallaRoute(_fixture('valhalla_partdieu.json'));
    final details = parseRoadAttributes(
      _fixture('valhalla_partdieu_attributes.json'),
    ).withLanes(parseLanes(_fixture('valhalla_partdieu_lanes.json'), route));

    test('lights, one per junction, and side streets along the route', () {
      expect(details.signalsM, hasLength(26));
      expect(details.signalsM.first, closeTo(331, 1));
      for (var i = 1; i < details.signalsM.length; i++) {
        expect(details.signalsM[i] - details.signalsM[i - 1], greaterThan(40));
      }
      expect(details.sideRoads, hasLength(20));
      expect(details.speedLimits.at(100)?.kph, 50);
    });

    test('the lanes of the fork to Pont Wilson: the two on the left', () {
      expect(details.lanes, hasLength(1));
      final fork = lanesFor(route, details, 3)!;
      expect(route.maneuvers[3].instruction, 'Gardez la gauche pour prendre Pont Wilson.');
      expect(fork.lanes.map((l) => l.arrow), ['left', 'left', 'straight']);
      expect(fork.lanes.map((l) => l.valid), [true, true, false]);
      expect(fork.lanes.first.preferred, isTrue);
      expect(fork.hint, 'les deux voies de gauche');
      expect(lanesFor(route, details, 4), isNull);
    });

    test('the voice: lights counted, the lanes said once', () {
      final engine = GuidanceEngine(route)..details = details;
      final said = <String>[];
      LaneGuide? lanesSeen;
      for (var d = 0.0; d < route.shapeLengthM; d += 15) {
        final g = engine.update(route.pointAt(d), speedMps: 30 / 3.6);
        if (g.announcement case final a?) said.add(a);
        if (g.nextManeuverIndex == 3) lanesSeen ??= g.lanes;
      }
      expect(said, contains('Dans 600 mètres, au troisième feu, tournez à gauche dans Rue Vauban.'));
      expect(said, contains('Au feu, tournez à gauche dans Rue Vauban.'));
      expect(
        said,
        contains('Dans 600 mètres, gardez la gauche pour prendre Pont Wilson. Utilisez les deux voies de gauche.'),
      );
      expect(said.where((s) => s.contains('Utilisez')), hasLength(1));
      expect(lanesSeen?.hint, 'les deux voies de gauche');
    });
  });

  group('traffic lights', () {
    final route = _road();
    // 200 and 230 m: one junction's; 600 m; 990 m: the turn's.
    final details = parseRoadAttributes(_attributes(route, lights: {200, 230, 600, 990}));

    test('the lights of one junction count once, at the last', () {
      expect(details.signalsM.map(_tens), [230, 600, 990]);
    });

    test('the turn told with its light, counted from the car', () {
      expect(turnCue(route, details, 1, 0)!.label, 'Au 3e feu');
      expect(turnCue(route, details, 1, 300)!.label, 'Au 2e feu');
      final close = turnCue(route, details, 1, 700)!;
      expect(close.label, 'Au feu');
      expect(close.atLight, isTrue);
      expect(close.spoken('Tournez à gauche dans Rue X.'), 'Au feu, tournez à gauche dans Rue X.');
      expect(turnCue(route, details, 1, 0)!.spoken('Tournez à gauche.'), 'Au troisième feu, tournez à gauche.');
      // Past the third, or not a turn: nothing.
      final many = parseRoadAttributes(_attributes(route, lights: {100, 300, 500, 700, 990}));
      expect(turnCue(route, many, 1, 0), isNull);
      expect(turnCue(route, many, 1, 600)!.label, 'Au 2e feu');
      expect(turnCue(route, details, 2, 0), isNull, reason: 'the arrival');
    });
  });

  group('side streets', () {
    final route = _road();
    final details = parseRoadAttributes(
      _attributes(
        route,
        side: {
          300: [_street(270)],
          // The other carriageway of the same road: one junction.
          310: [_street(90, driveability: 'forward')],
          // Not counted: a car park, a one-way street towards the route,
          // a footway.
          500: [_street(270, use: 'parking_aisle')],
          600: [_street(270, driveability: 'backward')],
          650: [_street(270, use: 'footway')],
          700: [_street(265, driveability: 'forward')],
          // The turn's own junction.
          990: [_street(270), _street(90)],
        },
      ),
    );

    test('streets the car can take, on the left or the right of the way it comes', () {
      expect(details.sideRoads.map((j) => (_tens(j.alongM), j.left, j.right)), [
        (300, true, true),
        (700, true, false),
        (990, true, true),
      ]);
    });

    test('the turn counted on its side, from the car, up to the third', () {
      expect(turnCue(route, details, 1, 0)!.label, '3e à gauche');
      final second = turnCue(route, details, 1, 400)!;
      expect(second.label, '2e à gauche');
      expect(second.atLight, isFalse);
      expect(second.spoken('Tournez à gauche dans Rue X.'), 'Prenez la deuxième à gauche dans Rue X.');
      // Words it does not know stay as they are.
      expect(second.spoken('Continuez à gauche.'), 'Continuez à gauche.');
      expect(turnCue(route, details, 1, 800), isNull, reason: 'the first one: "tournez"');
      expect(turnCue(_road(type: 10), details, 1, 0)!.label, '2e à droite');
      expect(turnCue(_road(type: 16), details, 1, 0), isNull, reason: 'a slight turn is not counted');
    });

    test('a light at the turn wins over the count', () {
      final both = parseRoadAttributes(
        _attributes(
          route,
          lights: {990},
          side: {
            300: [_street(270)],
          },
        ),
      );
      expect(turnCue(route, both, 1, 0)!.label, 'Au feu');
    });
  });

  group('lanes', () {
    final route = _road();
    final turn = route.shape[100];
    Map<String, Object> intersection(LatLon at, List<(String, bool)> lanes) => {
      'location': [at.lon, at.lat],
      'lanes': [
        for (final (way, valid) in lanes)
          {
            'indications': [way],
            'valid': valid,
            'active': valid,
            if (valid) 'valid_indication': way,
          },
      ],
    };
    final answer = {
      'matchings': [
        {
          'legs': [
            {
              'steps': [
                {
                  'intersections': [
                    // Any lane will do: nothing to show.
                    intersection(route.shape[50], [('straight', true), ('straight', true)]),
                    intersection(turn, [('left', true), ('straight', false), ('right', false)]),
                    // Far from the route.
                    intersection(const LatLon(45.75, 4.85), [('left', true), ('right', false)]),
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    test('only where some lanes do not lead the right way, placed on the route', () {
      final lanes = parseLanes(answer, route);
      expect(lanes, hasLength(1));
      expect(lanes.single.alongM, closeTo(1000, 2));
      final details = const RoadDetails().withLanes(lanes);
      expect(lanesFor(route, details, 1)!.hint, 'la voie de gauche');
      expect(lanesFor(route, details, 2), isNull);
      expect(parseLanes(const {}, route), isEmpty);
    });

    test('which lanes to take, in words', () {
      LaneGuide guide(List<bool> valid) => LaneGuide(0, [
        for (final v in valid) Lane(const ['straight'], valid: v, arrow: 'straight'),
      ]);
      expect(guide([false, true]).hint, 'la voie de droite');
      expect(guide([false, true, true, false]).hint, 'les deux voies du milieu');
      expect(guide([true, true, true, false]).hint, 'les trois voies de gauche');
      expect(guide([true, false, true]).hint, isNull, reason: 'not side by side');
      expect(guide([true, true]).hint, isNull);
      expect(guide([true]).hint, isNull);
    });
  });

  test('the trip camera: close in town, further out when fast, closer before a turn', () {
    expect(navigationZoom(0), 18);
    expect(navigationZoom(50 / 3.6), 17.6);
    expect(navigationZoom(130 / 3.6), 16.2);
    expect(navigationZoom(200 / 3.6), 16.2);
    expect(navigationZoom(40 / 3.6, distanceToTurnM: 150), 18.3);
    expect(navigationZoom(80 / 3.6, distanceToTurnM: 150), navigationZoom(80 / 3.6));
  });
}

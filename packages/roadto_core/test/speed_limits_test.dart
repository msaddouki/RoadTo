import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

/// A straight road heading north from Bellecour, one point every ~111 m.
final _shape = [for (var i = 0; i < 7; i++) LatLon(45.7578 + i * 0.001, 4.8320)];
final _route = TripRoute(shape: _shape, maneuvers: const [], lengthM: 667, timeS: 60);

/// trace_attributes answer: 50, 50 (two edges), 30, unknown, unlimited.
Map<String, dynamic> _answer() => {
  'shape': encodePolyline(_shape),
  'edges': [
    {'begin_shape_index': 0, 'end_shape_index': 1, 'speed_limit': 50},
    {'begin_shape_index': 1, 'end_shape_index': 2, 'speed_limit': 50},
    {'begin_shape_index': 2, 'end_shape_index': 4, 'speed_limit': 30},
    {'begin_shape_index': 4, 'end_shape_index': 5},
    {'begin_shape_index': 5, 'end_shape_index': 6, 'speed_limit': 'unlimited'},
  ],
};

void main() {
  group('parseSpeedLimits', () {
    final limits = parseSpeedLimits(_answer());

    test('merges consecutive edges with the same limit', () {
      expect(limits.spans.map((s) => s.kph), [50, 30, null, null]);
      expect(limits.spans.first.endM, closeTo(222, 1));
      expect(limits.spans.last.unlimited, isTrue);
    });

    test('looks up the limit by distance along the route', () {
      expect(limits.at(0)!.kph, 50);
      expect(limits.at(221)!.kph, 50);
      expect(limits.at(223)!.kph, 30);
      expect(limits.at(500)!.kph, isNull);
      expect(limits.at(600)!.unlimited, isTrue);
      expect(limits.at(-1), isNull);
      expect(limits.at(10000), isNull);
    });

    test('coverage counts known and unlimited stretches', () {
      expect(limits.coverage(_route.shapeLengthM), closeTo(5 / 6, 0.01));
    });

    test('an answer without edges gives no limits', () {
      expect(parseSpeedLimits({'shape': encodePolyline(_shape)}).spans, isEmpty);
      expect(parseSpeedLimits(const {}).spans, isEmpty);
    });
  });

  test('over the limit with the usual margin', () {
    expect(isOverLimit(55, 50), isFalse);
    expect(isOverLimit(56, 50), isTrue);
    expect(isOverLimit(136, 130), isFalse);
    expect(isOverLimit(137, 130), isTrue);
  });

  test('the request walks the route shape edge by edge', () {
    final req = roadAttributesRequest(_route);
    expect(req['shape_match'], 'edge_walk');
    expect(decodePolyline(req['encoded_polyline'] as String).length, _shape.length);
    expect((req['filters'] as Map)['attributes'], containsAll(['edge.speed_limit', 'edge.traffic_signal']));
  });

  test('online: POST /trace_attributes, and /trace_route for the lanes', () async {
    final paths = <String>[];
    final client = MockClient((req) async {
      paths.add(req.url.path);
      // The lanes are a plus: without them, the limits still come.
      if (req.url.path == '/trace_route') return http.Response('{"error":"no"}', 400);
      return http.Response(jsonEncode(_answer()), 200);
    });
    final router = ValhallaRouter(baseUrl: 'https://valhalla.example/', client: client);
    final details = await router.roadDetails(_route);
    expect(paths, unorderedEquals(['/trace_attributes', '/trace_route']));
    expect(details.speedLimits.at(0)!.kph, 50);
    expect(details.lanes, isEmpty);
  });

  test('on the device, with the server as fallback', () async {
    final native = NativeValhallaRouter(
      configPath: '/region/routing.offline.json',
      call: (_, _) async => throw StateError('unused'),
      traceAttributes: (config, json) async {
        expect(config, '/region/routing.offline.json');
        expect((jsonDecode(json) as Map)['shape_match'], 'edge_walk');
        return jsonEncode(_answer());
      },
    );
    expect((await native.roadDetails(_route)).speedLimits.at(300)!.kph, 30);

    final failing = NativeValhallaRouter(
      configPath: '/x',
      call: (_, _) async => '{}',
      traceAttributes: (_, _) async => throw Exception('no graph here'),
    );
    final online = ValhallaRouter(
      baseUrl: 'https://valhalla.example/',
      client: MockClient((_) async => http.Response(jsonEncode(_answer()), 200)),
    );
    final errors = <RoutingException>[];
    final both = FallbackRouter(failing, online, onFallback: errors.add);
    expect((await both.roadDetails(_route)).speedLimits.at(0)!.kph, 50);
    expect(errors, hasLength(1));
  });

  test('without a trace callback the device has no limits', () {
    final native = NativeValhallaRouter(configPath: '/x', call: (_, _) async => '{}');
    expect(native.roadDetails(_route), throwsA(isA<RoutingException>()));
  });
}

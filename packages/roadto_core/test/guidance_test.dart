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

  group('Valhalla', () {
    test('lecture de la réponse', () {
      expect(route.shape, hasLength(51));
      expect(route.maneuvers, hasLength(4));
      expect(route.maneuvers[1].instruction, 'Tournez à gauche sur Quai Augagneur.');
      expect(route.maneuvers.last.isArrival, isTrue);
      expect(route.lengthM, closeTo(2497, 1));
      expect(route.shapeLengthM, closeTo(route.lengthM, 5));
    });

    test('requête : cap, langue et zones à éviter', () {
      final body = ValhallaRouter(baseUrl: 'https://example.org/').buildRequest(
        const LatLon(45.75, 4.83),
        const LatLon(45.76, 4.86),
        headingDeg: 92.4,
        avoid: [const LatLon(45.755, 4.84)],
      );
      expect(body['costing'], 'auto');
      expect(body['language'], 'fr-FR');
      expect((body['locations'] as List).first['heading'], 92);
      final ring = (body['exclude_polygons'] as List).single as List;
      expect(ring.first, ring.last, reason: 'polygone fermé');
    });

    test('appel HTTP', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response.bytes(utf8.encode(jsonEncode(_fixture('valhalla_lyon.json'))), 200);
      });
      final r = await ValhallaRouter(
        baseUrl: 'https://valhalla.example/',
        client: client,
      ).route(const LatLon(45.7578, 4.832), const LatLon(45.7676, 4.859));
      expect(sent.url.toString(), 'https://valhalla.example/route');
      expect(r.maneuvers, hasLength(4));
    });

    test('erreur du serveur', () {
      final client = MockClient((_) async => http.Response('{"error":"No path could be found"}', 400));
      expect(
        ValhallaRouter(baseUrl: 'https://v.example/', client: client).route(const LatLon(0, 0), const LatLon(1, 1)),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('on-device routing', () {
    final fixture = jsonEncode(_fixture('valhalla_lyon.json'));

    test('sends the Valhalla request to the platform and parses the answer', () async {
      String? sentConfig, sentRequest;
      final router = NativeValhallaRouter(
        configPath: '/regions/lyon/routing.offline.json',
        call: (config, request) async {
          sentConfig = config;
          sentRequest = request;
          return fixture;
        },
      );
      final r = await router.route(const LatLon(45.7578, 4.832), const LatLon(45.7676, 4.859), headingDeg: 90);
      expect(r.maneuvers, hasLength(4));
      expect(sentConfig, '/regions/lyon/routing.offline.json');
      final body = jsonDecode(sentRequest!) as Map<String, dynamic>;
      expect(body['costing'], 'auto');
      expect((body['locations'] as List).first['heading'], 90);
    });

    test('Valhalla errors become RoutingException', () async {
      final router = NativeValhallaRouter(
        configPath: 'x',
        call: (_, _) async => '{"error_code":171,"error":"No suitable edges near location","status_code":400}',
      );
      expect(
        router.route(const LatLon(0, 0), const LatLon(1, 1)),
        throwsA(isA<RoutingException>().having((e) => e.message, 'message', contains('No suitable edges'))),
      );
    });

    test('falls back to the online engine outside the region', () async {
      RoutingException? reason;
      final offline = NativeValhallaRouter(configPath: 'x', call: (_, _) async => throw StateError('outside'));
      final online = NativeValhallaRouter(configPath: 'y', call: (_, _) async => fixture);
      final r = await FallbackRouter(
        offline,
        online,
        onFallback: (e) => reason = e,
      ).route(const LatLon(48.85, 2.35), const LatLon(45.76, 4.86));
      expect(r.maneuvers, hasLength(4));
      expect(reason, isNotNull);
    });
  });

  group('Photon', () {
    test('lecture des résultats', () {
      final places = parsePhoton(_fixture('photon_lyon.json'));
      expect(places, hasLength(2));
      expect(places[0].label, 'Place Bellecour, 69002 Lyon');
      expect(places[1].label, '12 Cours Lafayette, 69003 Lyon');
      expect(places[1].position.lon, 4.859);
    });
  });

  group('guidage', () {
    test('trajet simulé complet : annonces dans l’ordre, puis arrivée', () {
      final engine = GuidanceEngine(route);
      final sim = RouteSimulator(route, speedKmh: 50);
      final said = <String>[];
      GuidanceState? state;
      var fix = sim.fixAt(0);
      for (var i = 0; i < 400 && !(state?.arrived ?? false); i++) {
        state = engine.update(fix.position, speedMps: fix.speedMps);
        if (state.announcement != null) said.add(state.announcement!);
        expect(state.offRoute, isFalse);
        fix = sim.step();
      }
      expect(state!.arrived, isTrue);
      expect(said.first, startsWith('Dirigez-vous vers l’est'));
      expect(said, contains('Dans 600 mètres, tournez à gauche sur Quai Augagneur.'));
      expect(said, contains('Tournez à gauche sur Quai Augagneur.'));
      expect(said, contains('Tournez à droite sur Cours Lafayette.'));
      expect(said.last, 'Vous êtes arrivé à votre destination.');
      expect(
        said.indexOf('Tournez à gauche sur Quai Augagneur.'),
        lessThan(said.indexOf('Tournez à droite sur Cours Lafayette.')),
      );
    });

    test('manœuvre suivante et distance', () {
      final engine = GuidanceEngine(route);
      final s = engine.update(route.pointAt(1000));
      expect(s.nextManeuverIndex, 1);
      expect(s.distanceToNextM, closeTo(route.maneuverStartM(1) - 1000, 2));
      expect(s.remainingM, closeTo(route.shapeLengthM - 1000, 2));
    });

    test('sortie de route après trois positions écartées', () {
      final engine = GuidanceEngine(route);
      engine.update(route.pointAt(300));
      final off = LatLon(route.pointAt(320).lat + 0.001, route.pointAt(320).lon); // ~110 m au nord
      expect(engine.update(off).offRoute, isFalse);
      expect(engine.update(off).offRoute, isFalse);
      expect(engine.update(off).offRoute, isTrue);
      expect(engine.update(route.pointAt(340)).offRoute, isFalse);
    });

    test('alertes devant sur l’itinéraire', () {
      RoadAlert alertAt(double along, String id) => RoadAlert(
        id: id,
        author: 'x',
        type: AlertType.accident,
        geohash: geohashEncode(route.pointAt(along), precision: 7),
        createdAt: DateTime(2026),
        expiresAt: DateTime(2027),
      );
      final ahead = alertsAhead(route, 500, [alertAt(200, 'derriere'), alertAt(1500, 'devant')]);
      expect(ahead.map((a) => a.alert.id), ['devant']);
      expect(ahead.single.distanceM, closeTo(1000, 120));

      final toAsk = alertsToConfirm(route.pointAt(1500), [alertAt(1500, 'devant')], alreadyAsked: {});
      expect(toAsk, hasLength(1));
      expect(alertsToConfirm(route.pointAt(1500), [alertAt(1500, 'devant')], alreadyAsked: {'devant'}), isEmpty);
    });

    test('formatage des distances', () {
      expect(formatDistance(42), '42 m');
      expect(formatDistance(347), '350 m');
      expect(formatDistance(2450), '2,5 km');
      expect(formatDistance(12400), '12 km');
    });
  });
}

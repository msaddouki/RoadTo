import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

import 'regions_test.dart' show rfc8032PublicKey, rfc8032Seed;

const _fuel = PlaceCategory('fuel', 'Carburant', {'amenity=fuel'});
const _charging = PlaceCategory('charging', 'Recharge', {'amenity=charging_station'});

/// A stations file as the pipeline writes it, around the places of
/// test/fixtures/region/places.sqlite (TotalEnergies 45.765,4.84; Station du
/// Méridien 45.77,4.78; Izivia charger 45.74,4.9).
Map<String, dynamic> _doc({String generated = '2026-10-16T08:00:00+00:00', String region = 'test'}) => {
  'format': 1,
  'region': region,
  'generated': generated,
  'sources': {},
  'fuel': [
    {
      // 90 m from the TotalEnergies of OSM: the same station.
      'id': '69003001', 'lat': 45.7658, 'lon': 4.8402, 'address': '12 Rue Garibaldi', 'city': 'LYON',
      'motorway': false, 'card_24_7': true,
      'prices': {
        'gazole': {'price': 1.789, 'updated': '2026-10-16T07:30:00+02:00'},
        'e10': {'price': 1.759, 'updated': '2026-10-15T18:00:00+02:00'},
      },
      'out_of_stock': ['sp98'],
    },
    {
      // Not in OSM.
      'id': '69960002', 'lat': 45.76, 'lon': 4.86, 'address': 'A7 aire de Solaize', 'city': 'SAINT-SYMPHORIEN-D\'OZON',
      'motorway': true, 'card_24_7': false,
      'prices': {
        'gazole': {'price': 1.999, 'updated': '2026-10-15T22:00:00+02:00'},
      },
      'out_of_stock': [],
    },
  ],
  'charging': [
    {
      // 30 m from the Izivia charger of OSM.
      'id': 'FRIZIV1', 'lat': 45.7402, 'lon': 4.9002, 'name': 'Parc Blandan', 'operator': 'Izivia',
      'address': '[37 Rue du Repos][69007][Lyon]', 'points': 4, 'max_kw': 22.0, 'connectors': ['type2'],
      'free': false, 'card': true, 'open_to_all': true, 'always_open': true,
    },
    {
      'id': 'FRIONE1',
      'lat': 45.75,
      'lon': 4.85,
      'name': 'Aire',
      'operator': 'IONITY',
      'address': '',
      'points': 6,
      'max_kw': 350.0,
      'connectors': ['ccs'],
      'free': false,
      'card': true,
      'open_to_all': true,
      'always_open': true,
    },
  ],
};

List<int> _gz(Map<String, dynamic> doc) => gzip.encode(utf8.encode(jsonEncode(doc)));

void main() {
  group('Stations file', () {
    test('decodes fuel prices and charging stations', () {
      final s = Stations.decode(_gz(_doc()));
      expect(s.regionId, 'test');
      expect(s.generated, DateTime.utc(2026, 10, 16, 8));
      final total = s.fuel.first;
      expect(total.prices['gazole']!.price, 1.789);
      expect(total.prices['gazole']!.updated, DateTime.utc(2026, 10, 16, 5, 30));
      expect(total.outOfStock, ['sp98']);
      expect(total.card24h, isTrue);
      final ionity = s.charging.last;
      expect((ionity.points, ionity.maxKw), (6, 350.0));
      expect(ionity.connectors, ['ccs']);
    });

    test('refuses what is not a stations file', () {
      expect(() => Stations.decode(utf8.encode('{}')), throwsFormatException);
      expect(() => Stations.decode(_gz({..._doc(), 'format': 2})), throwsFormatException);
    });

    test('official stations become places with a readable name and address', () {
      final s = Stations.decode(_gz(_doc()));
      final fuel = s.inBox(_fuel, 45, 46, 4, 5);
      expect(fuel.map((c) => c.place.label), [
        'Station-service, 12 Rue Garibaldi, Lyon',
        'Station-service (autoroute), A7 aire de Solaize, Saint-Symphorien-D\'ozon',
      ]);
      final charging = s.inBox(_charging, 45, 46, 4, 5);
      expect(charging.first.place.label, 'Izivia, 37 Rue du Repos, 69007, Lyon');
      expect(s.inBox(const PlaceCategory('parking', 'Parking', {}), 45, 46, 4, 5), isEmpty);
      expect(s.inBox(_fuel, 46, 47, 4, 5), isEmpty);
    });
  });

  group('merged with the offline index', () {
    late OfflineGeocoder geocoder;
    final stations = Stations.decode(_gz(_doc()));
    setUpAll(() => geocoder = OfflineGeocoder.open('test/fixtures/region/places.sqlite'));
    tearDownAll(() => geocoder.close());

    test('an OSM station keeps its name and gets the official prices', () {
      final found = geocoder.nearby(_fuel, const LatLon(45.765, 4.84), radiusM: 3000, stations: stations);
      expect(found.map((n) => n.place.name), ['TotalEnergies', 'Station-service (autoroute)']);
      expect(found.first.fuel!.prices['gazole']!.price, 1.789);
      expect(found.last.fuel!.id, '69960002');
    });

    test('without the file, only OSM places, without official data', () {
      final found = geocoder.nearby(_fuel, const LatLon(45.765, 4.84), radiusM: 3000);
      expect(found.map((n) => n.place.name), ['TotalEnergies']);
      expect(found.single.fuel, isNull);
    });

    test('charging stations missing from OSM are listed along the route', () {
      final route = TripRoute(
        shape: const [LatLon(45.745, 4.80), LatLon(45.745, 4.95)],
        maneuvers: const [],
        lengthM: 11700,
        timeS: 900,
      );
      final found = geocoder.alongRoute(_charging, route, 0, stations: stations);
      expect(found.map((n) => (n.place.name, n.charging?.id)), [('IONITY', 'FRIONE1'), ('Izivia', 'FRIZIV1')]);
    });

    test('each official station goes to the closest OSM place only', () {
      final a = (const Place(name: 'A', position: LatLon(45.7650, 4.8400)), const LatLon(45.7650, 4.8400));
      final b = (const Place(name: 'B', position: LatLon(45.7655, 4.8400)), const LatLon(45.7655, 4.8400));
      final merged = mergeStations(_fuel, [a, b], stations.inBox(_fuel, 45, 46, 4, 5));
      expect(merged.map((c) => (c.place.name, c.fuel?.id)), [
        ('A', null),
        ('B', '69003001'),
        ('Station-service (autoroute)', '69960002'),
      ]);
    });
  });

  group('StationsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('stations'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<http.Client> served(List<int> body, {List<int>? signedBytes}) async {
      final keys = await Ed25519().newKeyPairFromSeed(rfc8032Seed);
      final sig = base64.encode((await Ed25519().sign(signedBytes ?? body, keyPair: keys)).bytes);
      return MockClient(
        (req) async => req.url.path.endsWith('.sig') ? http.Response(sig, 200) : http.Response.bytes(body, 200),
      );
    }

    final url = Uri.parse('https://example.org/stations-test/stations.json.gz');

    test('downloads, checks and keeps the file; loads it back', () async {
      final store = StationsStore(dir, trustedKeys: const [rfc8032PublicKey], client: await served(_gz(_doc())));
      expect(await store.load('test'), isNull);
      final s = await store.refresh('test', url);
      expect(s.fuel, hasLength(2));
      expect((await store.load('test'))!.charging, hasLength(2));
    });

    test('refuses a file with a bad signature, and keeps the previous one', () async {
      final good = StationsStore(dir, trustedKeys: const [rfc8032PublicKey], client: await served(_gz(_doc())));
      await good.refresh('test', url);
      final tampered = StationsStore(
        dir,
        trustedKeys: const [rfc8032PublicKey],
        client: await served(_gz(_doc(generated: '2026-10-17T08:00:00+00:00')), signedBytes: [1, 2, 3]),
      );
      await expectLater(tampered.refresh('test', url), throwsFormatException);
      expect((await good.load('test'))!.generated, DateTime.utc(2026, 10, 16, 8));
    });

    test('refuses another region and keeps a newer file', () async {
      final other = StationsStore(
        dir,
        trustedKeys: const [rfc8032PublicKey],
        client: await served(_gz(_doc(region: 'paris'))),
      );
      await expectLater(other.refresh('test', url), throwsFormatException);

      final newer = StationsStore(
        dir,
        trustedKeys: const [rfc8032PublicKey],
        client: await served(_gz(_doc(generated: '2026-10-17T08:00:00+00:00'))),
      );
      await newer.refresh('test', url);
      final older = StationsStore(dir, trustedKeys: const [rfc8032PublicKey], client: await served(_gz(_doc())));
      expect((await older.refresh('test', url)).generated, DateTime.utc(2026, 10, 17, 8));
    });

    test('a server error is an error', () async {
      final store = StationsStore(
        dir,
        trustedKeys: const [rfc8032PublicKey],
        client: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(store.refresh('test', url), throwsA(isA<HttpException>()));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

/// Fixtures in test/fixtures/region were produced by the Python pipeline
/// (pipeline/roadto_pipeline) and signed with the RFC 8032 test key below,
/// so these tests check that Dart accepts exactly what the pipeline emits.
const rfc8032PublicKey = '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=';
final fixtures = Directory('test/fixtures/region');

/// Serves the fixture package over HTTP, optionally altering files.
class PackageServer {
  late HttpServer server;
  final requests = <String>[];
  final overrides = <String, List<int>>{};

  Uri get manifestUrl => Uri.parse('http://127.0.0.1:${server.port}/region-test/manifest.json');

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      requests.add(name);
      final file = File('${fixtures.path}/$name');
      final body = overrides[name] ?? (await file.exists() ? await file.readAsBytes() : null);
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  group('manifest', () {
    late List<int> bytes;
    late String sig;

    setUp(() {
      bytes = File('${fixtures.path}/manifest.json').readAsBytesSync();
      sig = File('${fixtures.path}/manifest.json.sig').readAsStringSync();
    });

    test('parses the pipeline output', () {
      final m = RegionManifest.parse(bytes);
      expect(m.regionId, 'test');
      expect(m.regionName, 'Région de test');
      expect(m.files.map((f) => f.kind), ['style', 'places', 'map']);
      expect(m.file('map')!.size, 8);
      expect(m.osmTimestamp, '2026-10-01T00:00:00Z');
    });

    test('signature from the Python pipeline verifies', () async {
      expect(await verifyManifestSignature(bytes, sig, [rfc8032PublicKey]), isTrue);
    });

    test('tampered manifest, unknown key or garbage signature are refused', () async {
      final tampered = utf8.encode(utf8.decode(bytes).replaceFirst('Région de test', 'Région piégée'));
      expect(await verifyManifestSignature(tampered, sig, [rfc8032PublicKey]), isFalse);
      final otherKey = base64.encode(List.filled(32, 7));
      expect(await verifyManifestSignature(bytes, sig, [otherKey]), isFalse);
      expect(await verifyManifestSignature(bytes, 'pas du base64 !', [rfc8032PublicKey]), isFalse);
      expect(await verifyManifestSignature(bytes, sig, const []), isFalse);
    });

    test('unsafe file names are rejected', () {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      (json['files'] as List).first['name'] = '../evil';
      expect(() => RegionManifest.parse(utf8.encode(jsonEncode(json))), throwsA(isA<RegionFormatException>()));
    });
  });

  group('region store', () {
    late Directory root;
    late PackageServer server;
    late RegionStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('regions');
      server = PackageServer();
      await server.start();
      store = RegionStore(root, trustedKeys: const [rfc8032PublicKey]);
    });

    tearDown(() async {
      await server.stop();
      await root.delete(recursive: true);
    });

    test('installs, verifies and writes the offline style', () async {
      final stages = await store.install(server.manifestUrl).map((p) => p.stage).toList();
      expect(stages.first, InstallStage.manifest);
      expect(stages.last, InstallStage.done);

      final region = (await store.load('test'))!;
      expect(region.name, 'Région de test');
      expect(File(region.mapPath).readAsStringSync(), 'fake map');
      final style = jsonDecode(File(region.stylePath).readAsStringSync()) as Map<String, dynamic>;
      final regionUrl = region.dir.absolute.uri.toString().replaceFirst(RegExp(r'/$'), '');
      expect(style['sources']['openmaptiles']['url'], 'pmtiles://$regionUrl/map.pmtiles');
      expect(style['glyphs'], '$regionUrl/style/fonts/{fontstack}/{range}.pbf');
      expect(File('${region.dir.path}/style/fonts/Noto_Sans_Regular/0-255.pbf').existsSync(), isTrue);
      expect(region.contains(45.76, 4.80), isTrue);
      expect(region.contains(48.85, 2.35), isFalse);
      expect((await store.installed()).map((r) => r.id), ['test']);
    });

    test('an update only downloads changed files', () async {
      await store.install(server.manifestUrl).drain<void>();
      server.requests.clear();
      await store.install(server.manifestUrl).drain<void>();
      expect(server.requests, ['manifest.json', 'manifest.json.sig']);
    });

    test('a corrupted file is refused and the installed version kept', () async {
      await store.install(server.manifestUrl).drain<void>();
      await File('${root.path}/test/map.pmtiles').writeAsString('fake MAP'); // forces a re-download
      server.overrides['map.pmtiles'] = utf8.encode('evil map');
      await expectLater(store.install(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));
      expect(Directory('${root.path}/.staging-test').existsSync(), isFalse);
      expect(await store.load('test'), isNotNull);
    });

    test('unsigned, mis-signed or untrusted packages are refused', () async {
      server.overrides['manifest.json'] = utf8.encode(
        File('${fixtures.path}/manifest.json').readAsStringSync().replaceFirst('2026-10-12', '2026-10-13'),
      );
      await expectLater(store.install(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));

      final untrusting = RegionStore(root, trustedKeys: [base64.encode(List.filled(32, 1))]);
      server.overrides.clear();
      await expectLater(untrusting.install(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));
      expect(await store.installed(), isEmpty);
    });

    test('a tampered install is not loaded', () async {
      await store.install(server.manifestUrl).drain<void>();
      final m = File('${root.path}/test/manifest.json');
      m.writeAsStringSync(m.readAsStringSync().replaceFirst('Région de test', 'X'));
      expect(await store.load('test'), isNull);
    });
  });

  group('offline search', () {
    late OfflineGeocoder geocoder;

    setUpAll(() => geocoder = OfflineGeocoder.open('${fixtures.path}/places.sqlite'));
    tearDownAll(() => geocoder.close());

    test('address with house number, without accents', () {
      final r = geocoder.searchSync('12 republique');
      expect(r.first.label, '12 Rue de la République, 69002 Lyon');
    });

    test('prefix search on a town', () {
      expect(geocoder.searchSync('ecul').first.label, 'Écully, Ville');
    });

    test('point of interest with its own city', () {
      final r = geocoder.searchSync('station meridien');
      expect(r.single.name, 'Station du Méridien');
      expect(r.single.detail, 'Écully');
      expect(r.single.category, 'amenity=fuel');
    });

    test('proximity breaks ties', () {
      final nearEcully = geocoder.searchSync('chemin', near: const LatLon(45.770, 4.780));
      expect(nearEcully.first.label, '3 bis Chemin des Cerisiers, Écully');
    });

    test('empty or symbol-only queries return nothing', () {
      expect(geocoder.searchSync(''), isEmpty);
      expect(geocoder.searchSync('" * -'), isEmpty);
      expect(OfflineGeocoder.ftsQuery('Rue d\'Algérie'), '"rue"* "d"* "algérie"*');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac, Sha256;
import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

/// Fixtures in test/fixtures/region were produced by the Python pipeline
/// (pipeline/roadto_pipeline) and signed with the RFC 8032 test key below,
/// so these tests check that Dart accepts exactly what the pipeline emits.
const rfc8032PublicKey = '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=';
final rfc8032Seed = [
  for (var i = 0; i < 64; i += 2)
    int.parse('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'.substring(i, i + 2), radix: 16),
];
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
      final stages = await store.installFromUrl(server.manifestUrl).map((p) => p.stage).toList();
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
      await store.installFromUrl(server.manifestUrl).drain<void>();
      server.requests.clear();
      await store.installFromUrl(server.manifestUrl).drain<void>();
      expect(server.requests, ['manifest.json', 'manifest.json.sig']);
    });

    test('a corrupted file is refused and the installed version kept', () async {
      await store.installFromUrl(server.manifestUrl).drain<void>();
      await File('${root.path}/test/map.pmtiles').writeAsString('fake MAP'); // forces a re-download
      server.overrides['map.pmtiles'] = utf8.encode('evil map');
      await expectLater(store.installFromUrl(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));
      expect(Directory('${root.path}/.staging-test').existsSync(), isFalse);
      expect(await store.load('test'), isNotNull);
    });

    test('unsigned, mis-signed or untrusted packages are refused', () async {
      server.overrides['manifest.json'] = utf8.encode(
        File('${fixtures.path}/manifest.json').readAsStringSync().replaceFirst('2026-10-12', '2026-10-13'),
      );
      await expectLater(store.installFromUrl(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));

      final untrusting = RegionStore(root, trustedKeys: [base64.encode(List.filled(32, 1))]);
      server.overrides.clear();
      await expectLater(untrusting.installFromUrl(server.manifestUrl).drain<void>(), throwsA(isA<RegionException>()));
      expect(await store.installed(), isEmpty);
    });

    test('a tampered install is not loaded', () async {
      await store.installFromUrl(server.manifestUrl).drain<void>();
      final m = File('${root.path}/test/manifest.json');
      m.writeAsStringSync(m.readAsStringSync().replaceFirst('Région de test', 'X'));
      expect(await store.load('test'), isNull);
    });
  });

  group('package sources', () {
    late Directory root;
    late RegionStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('regions');
      store = RegionStore(root, trustedKeys: const [rfc8032PublicKey]);
    });

    tearDown(() => root.delete(recursive: true));

    test('installs from a .roadto file produced by the pipeline', () async {
      await store.install(BundlePackageSource(File('test/fixtures/test.roadto'))).drain<void>();
      final region = (await store.load('test'))!;
      expect(File(region.mapPath).readAsStringSync(), 'fake map');
      expect(File(region.stylePath).existsSync(), isTrue);
    });

    test('a tampered .roadto file is refused', () async {
      final bytes = File('test/fixtures/test.roadto').readAsBytesSync();
      final i = String.fromCharCodes(bytes).indexOf('fake map');
      bytes[i] = 'F'.codeUnitAt(0);
      final copy = File('${root.path}/tampered.roadto')..writeAsBytesSync(bytes);
      await expectLater(store.install(BundlePackageSource(copy)).drain<void>(), throwsA(isA<RegionException>()));
      expect(await store.installed(), isEmpty);
    });

    test('a file that is not a region is refused with a clear message', () async {
      final junk = File('${root.path}/photo.jpg')..writeAsBytesSync(List.filled(2048, 7));
      await expectLater(
        store.install(BundlePackageSource(junk)).drain<void>(),
        throwsA(isA<RegionException>().having((e) => e.message, 'message', contains('région'))),
      );
    });

    test('installs from an unpacked folder', () async {
      await store.install(DirectoryPackageSource(fixtures)).drain<void>();
      expect((await store.installed()).single.id, 'test');
    });
  });

  group('offline routing files', () {
    late Directory root;
    late Directory pkg;

    /// The fixture package plus a routing graph and its config, re-signed
    /// with the RFC 8032 test key like the pipeline would.
    Future<Directory> packageWithRouting() async {
      final dir = Directory('${root.path}/pkg')..createSync();
      for (final f in fixtures.listSync().whereType<File>()) {
        f.copySync('${dir.path}/${f.uri.pathSegments.last}');
      }
      final extra = {
        'routing.tar': ('routing', utf8.encode('graph')),
        'routing.json': (
          'routing_config',
          utf8.encode('{"mjolnir":{"tile_extract":"@ROADTO_REGION_DIR@/routing.tar"}}'),
        ),
      };
      final manifest = jsonDecode(File('${dir.path}/manifest.json').readAsStringSync()) as Map<String, dynamic>;
      for (final MapEntry(key: name, value: (kind, bytes)) in extra.entries) {
        File('${dir.path}/$name').writeAsBytesSync(bytes);
        (manifest['files'] as List).add({
          'kind': kind,
          'name': name,
          'url': name,
          'size': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
          'required': false,
        });
      }
      final bytes = utf8.encode(jsonEncode(manifest));
      File('${dir.path}/manifest.json').writeAsBytesSync(bytes);
      final keys = await Ed25519().newKeyPairFromSeed(rfc8032Seed);
      final sig = await Ed25519().sign(bytes, keyPair: keys);
      File('${dir.path}/manifest.json.sig').writeAsStringSync(base64.encode(sig.bytes));
      return dir;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('routing');
      pkg = await packageWithRouting();
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('a platform that routes offline installs the graph and gets a local config', () async {
      final android = RegionStore(
        Directory('${root.path}/android'),
        trustedKeys: const [rfc8032PublicKey],
        wantedKinds: const {'map', 'places', 'style', 'routing', 'routing_config'},
      );
      await android.install(DirectoryPackageSource(pkg)).drain<void>();
      final region = (await android.load('test'))!;
      expect(region.hasOfflineRouting, isTrue);
      final config = jsonDecode(File(region.routingConfigPath).readAsStringSync()) as Map<String, dynamic>;
      expect(config['mjolnir']['tile_extract'], '${region.dir.absolute.path}/routing.tar');
    });

    test('other platforms skip the graph', () async {
      final ios = RegionStore(Directory('${root.path}/ios'), trustedKeys: const [rfc8032PublicKey]);
      await ios.install(DirectoryPackageSource(pkg)).drain<void>();
      final region = (await ios.load('test'))!;
      expect(region.hasOfflineRouting, isFalse);
      expect(File('${region.dir.path}/routing.tar').existsSync(), isFalse);
    });

    test('a package without the optional files still installs where they are wanted', () async {
      final android = RegionStore(
        Directory('${root.path}/android'),
        trustedKeys: const [rfc8032PublicKey],
        wantedKinds: const {'map', 'places', 'style', 'routing', 'routing_config'},
      );
      await android.install(DirectoryPackageSource(fixtures)).drain<void>();
      expect((await android.load('test'))!.hasOfflineRouting, isFalse);
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

    test('nearest fuel station, unnamed ones labelled by brand', () {
      final fuel = driverCategories.firstWhere((c) => c.id == 'fuel');
      final found = geocoder.nearby(fuel, const LatLon(45.7648, 4.8395));
      expect(found.first.place.name, 'TotalEnergies');
      expect(found.first.distanceM, lessThan(100));
      expect(found.map((n) => n.place.name), contains('Station du Méridien'));
      expect(geocoder.nearby(fuel, const LatLon(45.7648, 4.8395), radiusM: 500), hasLength(1));
    });

    test('unnamed car park: found by category with a generic label, not by text', () {
      final parking = driverCategories.firstWhere((c) => c.id == 'parking');
      expect(geocoder.nearby(parking, const LatLon(45.766, 4.841)).single.place.name, 'Parking');
      expect(geocoder.searchSync('parking'), isEmpty);
    });

    test('charging stations ahead on the route, in route order', () {
      // East-west route through Lyon, passing 1.5 km north of the Izivia station.
      final route = TripRoute(
        shape: const [LatLon(45.754, 4.80), LatLon(45.754, 4.95)],
        maneuvers: const [],
        lengthM: 11700,
        timeS: 900,
      );
      final charging = driverCategories.firstWhere((c) => c.id == 'charging');
      expect(geocoder.alongRoute(charging, route, 0, maxOffRouteM: 1000), isEmpty);
      final ahead = geocoder.alongRoute(charging, route, 0, maxOffRouteM: 2000);
      expect(ahead.single.place.name, 'Izivia');
      expect(ahead.single.aheadM, closeTo(7800, 300));
      expect(ahead.single.offRouteM, closeTo(1560, 100));
      expect(geocoder.alongRoute(charging, route, 9000, maxOffRouteM: 2000), isEmpty, reason: 'already passed');
    });

    test('empty or symbol-only queries return nothing', () {
      expect(geocoder.searchSync(''), isEmpty);
      expect(geocoder.searchSync('" * -'), isEmpty);
      expect(OfflineGeocoder.ftsQuery('Rue d\'Algérie'), '"rue"* "d"* "algérie"*');
    });
  });
}

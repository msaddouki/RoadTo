import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

// RFC 8032, section 7.1, test 1: a public test vector, never a real key.
const _seed = '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
const _public = '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=';

/// A signed region package in [dir] whose style bundle holds [styles].
Future<void> _package(Directory dir, Map<String, String> styles) async {
  final fixtures = Directory('test/fixtures/region');
  final tar = Archive();
  for (final MapEntry(key: name, value: json) in styles.entries) {
    final bytes = utf8.encode(json);
    tar.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final files = <String, List<int>>{
    'style.tar.gz': gzip.encode(TarEncoder().encode(tar)),
    'places.sqlite': File('${fixtures.path}/places.sqlite').readAsBytesSync(),
    'map.pmtiles': File('${fixtures.path}/map.pmtiles').readAsBytesSync(),
  };
  final kinds = {'style.tar.gz': 'style', 'places.sqlite': 'places', 'map.pmtiles': 'map'};
  for (final MapEntry(key: name, value: bytes) in files.entries) {
    File('${dir.path}/$name').writeAsBytesSync(bytes);
  }
  final manifest = utf8.encode(
    jsonEncode({
      'format': 1,
      'region': {
        'id': 'night',
        'name': 'Nuit',
        'bbox': [4.77, 45.75, 4.84, 45.78],
      },
      'version': '2026-10-12',
      'created_at': '2026-10-12T18:00:00Z',
      'attribution': '© OpenStreetMap contributors',
      'generator': <String, String>{},
      'files': [
        for (final MapEntry(key: name, value: bytes) in files.entries)
          {
            'kind': kinds[name],
            'name': name,
            'url': name,
            'size': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
            'required': true,
          },
      ],
    }),
  );
  File('${dir.path}/manifest.json').writeAsBytesSync(manifest);
  final seed = [for (var i = 0; i < 64; i += 2) int.parse(_seed.substring(i, i + 2), radix: 16)];
  final keys = await Ed25519().newKeyPairFromSeed(seed);
  final sig = await Ed25519().sign(manifest, keyPair: keys);
  File('${dir.path}/manifest.json.sig').writeAsStringSync('${base64.encode(sig.bytes)}\n');
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('night'));
  tearDown(() => tmp.deleteSync(recursive: true));

  const day =
      '{"sources":{"openmaptiles":{"url":"pmtiles://@ROADTO_REGION_DIR@/map.pmtiles"}},'
      '"glyphs":"@ROADTO_STYLE_DIR@/fonts/{fontstack}/{range}.pbf","layers":[]}';
  const night =
      '{"name":"night","sources":{"openmaptiles":{"url":"pmtiles://@ROADTO_REGION_DIR@/map.pmtiles"}},'
      '"glyphs":"@ROADTO_STYLE_DIR@/fonts/{fontstack}/{range}.pbf","layers":[]}';

  test('a package with a night style installs both, with this install\'s paths', () async {
    final pkg = Directory('${tmp.path}/pkg')..createSync();
    await _package(pkg, {'style.json': day, 'style-night.json': night});
    final store = RegionStore(Directory('${tmp.path}/store'), trustedKeys: const [_public]);
    await store.install(DirectoryPackageSource(pkg)).drain<void>();

    final region = (await store.load('night'))!;
    expect(region.hasNightStyle, isTrue);
    final style = jsonDecode(File(region.nightStylePath).readAsStringSync()) as Map<String, dynamic>;
    final regionUrl = region.dir.absolute.uri.toString().replaceFirst(RegExp(r'/$'), '');
    expect(style['name'], 'night');
    expect(style['sources']['openmaptiles']['url'], 'pmtiles://$regionUrl/map.pmtiles');
    expect(style['glyphs'], '$regionUrl/style/fonts/{fontstack}/{range}.pbf');
  });

  test('an older package without one has no night style', () async {
    final pkg = Directory('${tmp.path}/pkg')..createSync();
    await _package(pkg, {'style.json': day});
    final store = RegionStore(Directory('${tmp.path}/store'), trustedKeys: const [_public]);
    await store.install(DirectoryPackageSource(pkg)).drain<void>();
    final region = (await store.load('night'))!;
    expect(region.hasNightStyle, isFalse);
    expect(File(region.nightStylePath).existsSync(), isFalse);
    expect(File(region.stylePath).existsSync(), isTrue);
  });
}

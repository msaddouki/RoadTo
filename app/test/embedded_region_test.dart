import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/embedded_region.dart';
import 'package:roadto_core/roadto_core.dart';

/// Serves the package produced by the Python pipeline (core test fixture) as
/// if it were embedded under assets/regions/test/.
class _FixtureBundle extends CachingAssetBundle {
  final Map<String, List<int>> overrides;

  _FixtureBundle([this.overrides = const {}]);

  @override
  Future<ByteData> load(String key) async {
    final name = key.split('/').last;
    final bytes = overrides[name] ?? File('../packages/roadto_core/test/fixtures/region/$name').readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw FlutterError('Unable to load asset: $key');
}

const _testKey = '11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='; // RFC 8032 test vector

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('embedded'));
  tearDown(() => root.deleteSync(recursive: true));

  test('installs the embedded package with the usual checks', () async {
    final store = RegionStore(root, trustedKeys: const [_testKey]);
    final source = AssetPackageSource('test', bundle: _FixtureBundle());
    expect((await source.peekManifest())!.regionId, 'test');
    await store.install(source).drain<void>();
    expect((await store.installed()).single.name, 'Région de test');
  });

  test('a corrupted embedded file is refused', () async {
    final store = RegionStore(root, trustedKeys: const [_testKey]);
    final source = AssetPackageSource('test', bundle: _FixtureBundle({'map.pmtiles': 'evil map'.codeUnits}));
    await expectLater(store.install(source).drain<void>(), throwsA(isA<RegionException>()));
    expect(await store.installed(), isEmpty);
  });

  test('a build without embedded data has no region', () async {
    expect(await AssetPackageSource('lyon', bundle: _EmptyBundle()).peekManifest(), isNull);
  });
}

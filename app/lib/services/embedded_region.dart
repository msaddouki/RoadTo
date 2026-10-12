import 'package:flutter/services.dart';
import 'package:roadto_core/roadto_core.dart';

/// Region package shipped inside the app (`assets/regions/ID/`), copied by
/// CI from the signed release before building. Installed on first launch
/// through the same checks as a download, so the map works with no network
/// and no server.
class AssetPackageSource implements PackageSource {
  final String base;
  final AssetBundle _bundle;

  AssetPackageSource(String regionId, {AssetBundle? bundle})
    : base = 'assets/regions/$regionId',
      _bundle = bundle ?? rootBundle;

  @override
  String get label => 'app ($base)';

  Future<Uint8List?> _load(String name) async {
    try {
      final data = await _bundle.load('$base/$name');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null; // not embedded in this build
    }
  }

  /// The embedded manifest, unverified, or null when this build has none.
  /// Only used to compare versions; [RegionStore.install] verifies it.
  Future<RegionManifest?> peekManifest() async {
    final bytes = await _load('manifest.json');
    if (bytes == null) return null;
    try {
      return RegionManifest.parse(bytes);
    } on RegionFormatException {
      return null;
    }
  }

  @override
  Future<(List<int>, String)> manifest() async {
    final bytes = await _load('manifest.json');
    final sig = await _load('manifest.json.sig');
    if (bytes == null) throw RegionException('Aucune région intégrée à cette version de l’app');
    if (sig == null) throw RegionException('Région intégrée non signée : installation refusée');
    return (bytes as List<int>, String.fromCharCodes(sig));
  }

  @override
  Future<Stream<List<int>>> open(RegionFile file) async {
    final bytes = await _load(file.name);
    if (bytes == null) throw RegionException('${file.name} absent de la région intégrée');
    return _chunks(bytes);
  }

  /// Hands the asset out in 1 MB slices so the install reports progress.
  static Stream<List<int>> _chunks(Uint8List bytes) async* {
    const size = 1 << 20;
    for (var i = 0; i < bytes.length; i += size) {
      yield Uint8List.sublistView(bytes, i, i + size > bytes.length ? bytes.length : i + size);
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'manifest.dart';
import 'package_source.dart';

/// Failure while installing or loading a region. [message] is shown to the
/// user, hence in French.
class RegionException implements Exception {
  final String message;

  RegionException(this.message);

  @override
  String toString() => message;
}

enum InstallStage { manifest, download, extract, done }

class InstallProgress {
  final InstallStage stage;
  final String? file;

  /// Bytes downloaded so far over all required files (reused files count as
  /// downloaded).
  final int received;
  final int total;

  const InstallProgress(this.stage, {this.file, this.received = 0, this.total = 0});

  double get fraction => total == 0 ? 0 : received / total;
}

/// A region installed on the device.
class InstalledRegion {
  final RegionManifest manifest;
  final Directory dir;

  /// The style bundle has a night variant (packages built since it exists).
  final bool hasNightStyle;

  const InstalledRegion(this.manifest, this.dir, {this.hasNightStyle = false});

  String get id => manifest.regionId;
  String get name => manifest.regionName;
  String get version => manifest.version;

  String get mapPath => '${dir.path}/map.pmtiles';
  String get placesPath => '${dir.path}/places.sqlite';

  /// Style with absolute `file://` paths for this install, regenerated at
  /// each load because iOS may move the app's data folder on updates.
  String get stylePath => '${dir.path}/style/style.offline.json';

  /// Night variant of [stylePath], when [hasNightStyle].
  String get nightStylePath => '${dir.path}/style/style-night.offline.json';

  bool contains(double lat, double lon) {
    final b = manifest.bbox;
    return lon >= b[0] && lat >= b[1] && lon <= b[2] && lat <= b[3];
  }
}

/// Downloads, verifies and stores region packages under [root]:
///
/// ```
/// root/<id>/manifest.json, manifest.json.sig
/// root/<id>/map.pmtiles, places.sqlite, style.tar.gz
/// root/<id>/style/            extracted style bundle
/// ```
///
/// An install is staged next to the current one and swapped in only once
/// every file has the size and SHA-256 listed in a manifest signed by a
/// trusted key. A failed update leaves the installed version untouched.
class RegionStore {
  final Directory root;
  final List<String> trustedKeys;
  final http.Client _client;

  /// Kinds of files this client uses; others are skipped even if required.
  final Set<String> wantedKinds;

  RegionStore(
    this.root, {
    required this.trustedKeys,
    http.Client? client,
    this.wantedKinds = const {'map', 'places', 'style'},
  }) : _client = client ?? http.Client();

  Directory _dirOf(String id) => Directory('${root.path}/$id');

  Future<List<InstalledRegion>> installed() async {
    if (!await root.exists()) return const [];
    final out = <InstalledRegion>[];
    await for (final e in root.list()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is Directory && !name.startsWith('.')) {
        final r = await load(name);
        if (r != null) out.add(r);
      }
    }
    return out;
  }

  /// Loads an installed region, re-checking its signature, or returns null.
  Future<InstalledRegion?> load(String id) async {
    final dir = _dirOf(id);
    final manifestFile = File('${dir.path}/manifest.json');
    final sigFile = File('${dir.path}/manifest.json.sig');
    if (!await manifestFile.exists() || !await sigFile.exists()) return null;
    final bytes = await manifestFile.readAsBytes();
    if (!await verifyManifestSignature(bytes, await sigFile.readAsString(), trustedKeys)) return null;
    final manifest = RegionManifest.parse(bytes);
    for (final f in manifest.requiredFiles.where((f) => wantedKinds.contains(f.kind))) {
      if (!await File('${dir.path}/${f.name}').exists()) return null;
    }
    final region = InstalledRegion(
      manifest,
      dir,
      hasNightStyle: await File('${dir.path}/style/style-night.json').exists(),
    );
    await _writeOfflineStyle(region);
    return region;
  }

  Future<void> remove(String id) async {
    final dir = _dirOf(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Reads and verifies the manifest of [source] without installing anything.
  Future<(RegionManifest, List<int>, String)> verifiedManifest(PackageSource source) async {
    final (bytes, signature) = await source.manifest();
    if (trustedKeys.isEmpty) throw RegionException('Aucune clé de confiance configurée dans l’app');
    if (!await verifyManifestSignature(bytes, signature, trustedKeys)) {
      throw RegionException('Signature invalide : paquet refusé');
    }
    try {
      return (RegionManifest.parse(bytes), bytes, signature.trim());
    } on RegionFormatException catch (e) {
      throw RegionException('Manifeste illisible : ${e.message}');
    }
  }

  /// Installs or updates the region published at [manifestUrl].
  Stream<InstallProgress> installFromUrl(Uri manifestUrl) => install(HttpPackageSource(manifestUrl, client: _client));

  /// Installs or updates a region from any [source] (download, `.roadto`
  /// file, app assets).
  Stream<InstallProgress> install(PackageSource source) async* {
    yield const InstallProgress(InstallStage.manifest);
    final (manifest, manifestBytes, signature) = await verifiedManifest(source);
    final files = [
      for (final f in manifest.requiredFiles)
        if (wantedKinds.contains(f.kind)) f,
    ];
    final total = files.fold<int>(0, (s, f) => s + f.size);

    await root.create(recursive: true);
    final id = manifest.regionId;
    final current = _dirOf(id);
    final staging = Directory('${root.path}/.staging-$id');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create();

    try {
      var received = 0;
      for (final f in files) {
        final target = File('${staging.path}/${f.name}');
        final existing = File('${current.path}/${f.name}');
        // Unchanged files are reused: an update only copies what moved.
        if (await existing.exists() && await existing.length() == f.size && await _sha256(existing) == f.sha256) {
          await existing.copy(target.path);
          received += f.size;
          yield InstallProgress(InstallStage.download, file: f.name, received: received, total: total);
          continue;
        }
        await for (final n in _copyChecked(await source.open(f), target, f)) {
          yield InstallProgress(InstallStage.download, file: f.name, received: received + n, total: total);
        }
        received += f.size;
      }

      yield InstallProgress(InstallStage.extract, received: total, total: total);
      final style = manifest.file('style');
      if (style != null && wantedKinds.contains('style')) {
        await _extractTarGz(File('${staging.path}/${style.name}'), Directory('${staging.path}/style'));
      }
      await File('${staging.path}/manifest.json').writeAsBytes(manifestBytes);
      await File('${staging.path}/manifest.json.sig').writeAsString('$signature\n');

      final old = Directory('${root.path}/.old-$id');
      if (await old.exists()) await old.delete(recursive: true);
      if (await current.exists()) await current.rename(old.path);
      await staging.rename(current.path);
      if (await old.exists()) await old.delete(recursive: true);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }

    final region = await load(id);
    if (region == null) throw RegionException('Région installée mais illisible');
    yield InstallProgress(InstallStage.done, received: total, total: total);
  }

  /// Writes [data] to [target], yielding bytes written, then checks its size
  /// and SHA-256 against the manifest.
  Stream<int> _copyChecked(Stream<List<int>> data, File target, RegionFile f) async* {
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    final sink = target.openWrite();
    var n = 0, lastReport = 0;
    try {
      await for (final chunk in data) {
        n += chunk.length;
        if (n > f.size) throw RegionException('${f.name} plus gros qu’annoncé');
        hasher.add(chunk);
        sink.add(chunk);
        if (n - lastReport >= 256 * 1024) {
          lastReport = n;
          yield n;
        }
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (n != f.size || digest.value.toString() != f.sha256) {
      throw RegionException('${f.name} corrompu (empreinte différente)');
    }
    yield n;
  }

  static Future<String> _sha256(File f) async => (await sha256.bind(f.openRead()).first).toString();

  static Future<void> _extractTarGz(File archive, Directory into) async {
    final tar = TarDecoder().decodeBytes(gzip.decode(await archive.readAsBytes()));
    await into.create(recursive: true);
    final base = into.absolute.path;
    for (final entry in tar) {
      if (!entry.isFile) continue;
      final name = entry.name;
      if (name.startsWith('/') || name.split('/').contains('..')) {
        throw RegionException('Archive de style invalide ($name)');
      }
      final out = File('$base/$name');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content);
    }
  }

  /// Writes the styles (day, and night when present) with this install's
  /// absolute paths.
  static Future<void> _writeOfflineStyle(InstalledRegion r) async {
    final regionUrl = _fileUrl(r.dir);
    for (final (name, out) in [('style.json', r.stylePath), ('style-night.json', r.nightStylePath)]) {
      final template = File('${r.dir.path}/style/$name');
      if (!await template.exists()) continue;
      final style = (await template.readAsString())
          .replaceAll('@ROADTO_REGION_DIR@', regionUrl)
          .replaceAll('@ROADTO_STYLE_DIR@', '$regionUrl/style');
      await File(out).writeAsString(style);
    }
  }

  /// `file:///abs/path`, without trailing slash.
  static String _fileUrl(Directory d) {
    final s = d.absolute.uri.toString();
    return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

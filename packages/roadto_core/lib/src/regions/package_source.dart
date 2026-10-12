import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'manifest.dart';
import 'region_store.dart';

/// Where a region package comes from. [RegionStore.install] reads the signed
/// manifest and each file through this interface and applies the same
/// signature, size and hash checks whatever the source.
abstract interface class PackageSource {
  /// Human-readable origin, for error messages.
  String get label;

  /// Raw `manifest.json` bytes and the base64 signature from `manifest.json.sig`.
  Future<(List<int>, String)> manifest();

  /// Content of one file listed in the manifest.
  Future<Stream<List<int>>> open(RegionFile file);
}

/// Package served over HTTP(S), next to its manifest (static host, MinIO…).
class HttpPackageSource implements PackageSource {
  final Uri manifestUrl;
  final http.Client _client;

  HttpPackageSource(this.manifestUrl, {http.Client? client}) : _client = client ?? http.Client();

  @override
  String get label => manifestUrl.toString();

  @override
  Future<(List<int>, String)> manifest() async {
    final http.Response res, sig;
    try {
      res = await _client.get(manifestUrl).timeout(const Duration(seconds: 30));
      sig = await _client
          .get(manifestUrl.replace(path: '${manifestUrl.path}.sig'))
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw RegionException('Serveur des régions injoignable ($e)');
    }
    if (res.statusCode != 200) throw RegionException('Manifeste introuvable (${res.statusCode})');
    if (sig.statusCode != 200) throw RegionException('Paquet non signé : installation refusée');
    return (res.bodyBytes as List<int>, sig.body);
  }

  @override
  Future<Stream<List<int>>> open(RegionFile file) async {
    final http.StreamedResponse res;
    try {
      res = await _client.send(http.Request('GET', manifestUrl.resolve(file.url))).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw RegionException('Téléchargement de ${file.name} impossible ($e)');
    }
    if (res.statusCode != 200) throw RegionException('${file.name} introuvable (${res.statusCode})');
    return res.stream;
  }
}

/// Unpacked package in a local folder (tests, development).
class DirectoryPackageSource implements PackageSource {
  final Directory dir;

  DirectoryPackageSource(this.dir);

  @override
  String get label => dir.path;

  @override
  Future<(List<int>, String)> manifest() async {
    final m = File('${dir.path}/manifest.json');
    final s = File('${dir.path}/manifest.json.sig');
    if (!await m.exists()) throw RegionException('Pas de manifest.json dans ${dir.path}');
    if (!await s.exists()) throw RegionException('Paquet non signé : installation refusée');
    return (await m.readAsBytes() as List<int>, await s.readAsString());
  }

  @override
  Future<Stream<List<int>>> open(RegionFile file) async {
    final f = File('${dir.path}/${file.name}');
    if (!await f.exists()) throw RegionException('${file.name} absent du paquet');
    return f.openRead();
  }
}

/// Single-file package (`<region>.roadto`, a ustar archive written by
/// `roadto_pipeline bundle`). Members are streamed in place: nothing is
/// extracted before the checks.
class BundlePackageSource implements PackageSource {
  final File file;
  Map<String, (int, int)>? _index;

  BundlePackageSource(this.file);

  @override
  String get label => file.path;

  /// Member name -> (data offset, size), from the 512-byte ustar headers.
  Future<Map<String, (int, int)>> _members() async {
    if (_index != null) return _index!;
    final index = <String, (int, int)>{};
    final raf = await file.open();
    try {
      final length = await raf.length();
      var pos = 0;
      while (pos + 512 <= length) {
        await raf.setPosition(pos);
        final header = await raf.read(512);
        if (header.every((b) => b == 0)) break; // end-of-archive marker
        final name = _cString(header, 0, 100);
        final prefix = _cString(header, 345, 155);
        final size = int.tryParse(_cString(header, 124, 12).trim(), radix: 8);
        final type = header[156];
        if (size == null) throw RegionException('Fichier de région illisible (${file.path})');
        // '0' or NUL: regular file. Directories and extended headers are skipped.
        if (type == 0x30 || type == 0) {
          index[prefix.isEmpty ? name : '$prefix/$name'] = (pos + 512, size);
        }
        pos += 512 + (size + 511) ~/ 512 * 512;
      }
    } on FileSystemException catch (e) {
      throw RegionException('Fichier de région illisible (${e.message})');
    } finally {
      await raf.close();
    }
    return _index = index;
  }

  static String _cString(List<int> bytes, int start, int length) {
    final end = bytes.sublist(start, start + length).indexOf(0);
    return latin1.decode(bytes.sublist(start, end < 0 ? start + length : start + end));
  }

  Future<List<int>> _readAll(String name) async {
    final entry = (await _members())[name];
    if (entry == null) throw RegionException('$name absent du fichier de région');
    final (offset, size) = entry;
    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      return await raf.read(size);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<(List<int>, String)> manifest() async {
    final members = await _members();
    if (!members.containsKey('manifest.json')) throw RegionException('Ce fichier n’est pas une région RoadTo');
    if (!members.containsKey('manifest.json.sig')) throw RegionException('Paquet non signé : installation refusée');
    return (await _readAll('manifest.json'), utf8.decode(await _readAll('manifest.json.sig')));
  }

  @override
  Future<Stream<List<int>>> open(RegionFile f) async {
    final entry = (await _members())[f.name];
    if (entry == null) throw RegionException('${f.name} absent du fichier de région');
    final (offset, size) = entry;
    return file.openRead(offset, offset + size);
  }
}

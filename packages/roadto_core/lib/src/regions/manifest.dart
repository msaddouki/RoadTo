import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// One file of a region package.
class RegionFile {
  /// `map`, `places`, `style` or `routing`.
  final String kind;
  final String name;

  /// Location relative to the manifest URL.
  final String url;
  final int size;
  final String sha256;
  final bool required;

  const RegionFile({
    required this.kind,
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
    required this.required,
  });

  factory RegionFile.fromJson(Map<String, dynamic> json) => RegionFile(
    kind: json['kind'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    size: json['size'] as int,
    sha256: json['sha256'] as String,
    required: json['required'] as bool? ?? true,
  );
}

class RegionFormatException implements Exception {
  final String message;

  RegionFormatException(this.message);

  @override
  String toString() => 'RegionFormatException: $message';
}

/// Manifest of a region package, written by `pipeline/roadto_pipeline/manifest.py`.
class RegionManifest {
  static const supportedFormat = 1;

  final int format;
  final String regionId;
  final String regionName;

  /// [minLon, minLat, maxLon, maxLat].
  final List<double> bbox;
  final String version;
  final DateTime createdAt;
  final String? osmTimestamp;
  final String attribution;
  final List<RegionFile> files;

  const RegionManifest({
    required this.format,
    required this.regionId,
    required this.regionName,
    required this.bbox,
    required this.version,
    required this.createdAt,
    required this.attribution,
    required this.files,
    this.osmTimestamp,
  });

  static final _safeName = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

  /// Parses and validates the manifest. File names and the region id end up
  /// in local paths, so anything that is not a plain name is rejected.
  factory RegionManifest.parse(List<int> bytes) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      throw RegionFormatException('invalid JSON: $e');
    }
    final format = json['format'];
    if (format != supportedFormat) throw RegionFormatException('unsupported format $format');
    final region = json['region'] as Map<String, dynamic>;
    final files = [for (final f in json['files'] as List) RegionFile.fromJson(f as Map<String, dynamic>)];
    final id = region['id'] as String;
    if (!_safeName.hasMatch(id)) throw RegionFormatException('invalid region id "$id"');
    for (final f in files) {
      if (!_safeName.hasMatch(f.name) || f.name.contains('..')) {
        throw RegionFormatException('invalid file name "${f.name}"');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(f.sha256)) throw RegionFormatException('invalid sha256 for ${f.name}');
    }
    return RegionManifest(
      format: format as int,
      regionId: id,
      regionName: region['name'] as String,
      bbox: [for (final v in region['bbox'] as List) (v as num).toDouble()],
      version: json['version'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      osmTimestamp: json['osm_timestamp'] as String?,
      attribution: json['attribution'] as String? ?? '',
      files: files,
    );
  }

  RegionFile? file(String kind) {
    for (final f in files) {
      if (f.kind == kind) return f;
    }
    return null;
  }

  Iterable<RegionFile> get requiredFiles => files.where((f) => f.required);

  int get requiredBytes => requiredFiles.fold(0, (sum, f) => sum + f.size);
}

/// Checks the detached Ed25519 signature of a manifest (`manifest.json.sig`,
/// base64 of the raw 64-byte signature) against trusted public keys (base64
/// of the raw 32-byte keys). The app only installs packages that pass.
Future<bool> verifyManifestSignature(
  List<int> manifestBytes,
  String signatureBase64,
  Iterable<String> trustedPublicKeys,
) async {
  final List<int> signature;
  try {
    signature = base64.decode(signatureBase64.trim());
  } on FormatException {
    return false;
  }
  if (signature.length != 64) return false;
  final ed25519 = Ed25519();
  for (final key in trustedPublicKeys) {
    final List<int> raw;
    try {
      raw = base64.decode(key.trim());
    } on FormatException {
      continue;
    }
    if (raw.length != 32) continue;
    final ok = await ed25519.verify(
      manifestBytes,
      signature: Signature(signature, publicKey: SimplePublicKey(raw, type: KeyPairType.ed25519)),
    );
    if (ok) return true;
  }
  return false;
}

import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../geo.dart';
import 'geocoder.dart';

/// Search in a region's `places.sqlite` (schema: `pipeline/schema/places.sql`),
/// without network.
class OfflineGeocoder implements Geocoder {
  static const supportedSchema = '1';

  final Database _db;

  OfflineGeocoder._(this._db);

  /// Opens the index read-only. Throws [StateError] on an unknown schema.
  factory OfflineGeocoder.open(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final rows = db.select("SELECT value FROM meta WHERE key = 'schema_version'");
    final version = rows.isEmpty ? null : rows.first['value'] as String;
    if (version != supportedSchema) {
      db.close();
      throw StateError('places.sqlite schema $version not supported');
    }
    return OfflineGeocoder._(db);
  }

  void close() => _db.close();

  static final _token = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// FTS5 query: every word must match, as a prefix, in any column.
  static String? ftsQuery(String input) {
    final tokens = _token.allMatches(input.toLowerCase()).map((m) => m[0]!).toList();
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '"$t"*').join(' ');
  }

  @override
  Future<List<Place>> search(String query, {LatLon? near, int limit = 8}) async =>
      searchSync(query, near: near, limit: limit);

  List<Place> searchSync(String query, {LatLon? near, int limit = 8}) {
    final fts = ftsQuery(query);
    if (fts == null) return const [];
    final numbers = _token.allMatches(query).map((m) => m[0]!).where((t) => RegExp(r'^\d').hasMatch(t)).toSet();

    final rows = _db.select(
      'SELECT p.kind, p.name, p.housenumber, p.street, p.postcode, p.city, p.lat, p.lon, p.importance,'
      ' bm25(place_fts, 10.0, 6.0, 2.0, 3.0) AS score'
      ' FROM place_fts JOIN place p ON p.id = place_fts.rowid'
      ' WHERE place_fts MATCH ? ORDER BY score LIMIT 300',
      [fts],
    );

    final scored = <(double, Place)>[];
    for (final r in rows) {
      final position = LatLon(r['lat'] as double, r['lon'] as double);
      // bm25 is negative, lower is better.
      var score = -(r['score'] as double) + (r['importance'] as int) / 25;
      if (numbers.contains(r['housenumber'])) score += 3;
      if (near != null) score -= math.log(1 + distanceM(near, position) / 1000) / 1.5;
      scored.add((score, _toPlace(r, position)));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));

    final seen = <String>{};
    return [
      for (final (_, p) in scored)
        if (seen.add(p.label)) p,
    ].take(limit).toList();
  }

  static Place _toPlace(Row r, LatLon position) {
    final kind = r['kind'] as String;
    final name = r['name'] as String?;
    final street = r['street'] as String?;
    final number = r['housenumber'] as String?;
    final city = r['city'] as String?;
    final postcode = r['postcode'] as String?;
    final locality = [postcode, city].whereType<String>().join(' ');
    String join(List<String?> parts) => parts.whereType<String>().where((s) => s.isNotEmpty).join(', ');

    return switch (kind) {
      'address' => Place(name: '$number $street', detail: locality, position: position, category: kind),
      'street' => Place(name: name ?? street ?? '', detail: city, position: position, category: kind),
      _ when kind.startsWith('place=') => Place(
        name: name ?? '',
        detail: _placeLabels[kind.substring(6)] ?? '',
        position: position,
        category: kind,
      ),
      _ => Place(
        name: name ?? '',
        detail: join([number == null || street == null ? street : '$number $street', locality]),
        position: position,
        category: kind,
      ),
    };
  }

  static const _placeLabels = {
    'city': 'Ville',
    'town': 'Ville',
    'village': 'Village',
    'suburb': 'Quartier',
    'quarter': 'Quartier',
    'neighbourhood': 'Quartier',
    'hamlet': 'Hameau',
    'locality': 'Lieu-dit',
  };
}

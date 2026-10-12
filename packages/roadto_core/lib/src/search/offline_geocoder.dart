import 'dart:math' as math;

import 'package:sqlite3/sqlite3.dart';

import '../geo.dart';
import '../routing/route.dart';
import 'categories.dart';
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
      ' WHERE place_fts MATCH ?'
      // Unnamed places (car parks, stations without a brand) are only found by category.
      " AND (p.name IS NOT NULL OR p.kind IN ('address', 'street'))"
      ' ORDER BY score LIMIT 300',
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

  static const _columns = 'kind, name, housenumber, street, postcode, city, lat, lon';

  List<(Place, LatLon)> _inBox(Set<String> kinds, double minLat, double maxLat, double minLon, double maxLon, int cap) {
    if (kinds.isEmpty) return const [];
    final marks = List.filled(kinds.length, '?').join(', ');
    final rows = _db.select(
      'SELECT $_columns FROM place WHERE kind IN ($marks) AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ? LIMIT ?',
      [...kinds, minLat, maxLat, minLon, maxLon, cap],
    );
    final out = <(Place, LatLon)>[];
    for (final r in rows) {
      final p = LatLon(r['lat'] as double, r['lon'] as double);
      out.add((_toPlace(r, p), p));
    }
    return out;
  }

  /// Places of [category] within [radiusM] of [center], nearest first.
  List<NearbyPlace> nearby(PlaceCategory category, LatLon center, {double radiusM = 5000, int limit = 30}) {
    final dLat = radiusM / 111320;
    final dLon = radiusM / (111320 * math.cos(center.lat * math.pi / 180));
    final found = [
      for (final (place, p) in _inBox(
        category.kinds,
        center.lat - dLat,
        center.lat + dLat,
        center.lon - dLon,
        center.lon + dLon,
        5000,
      ))
        NearbyPlace(place, distanceM(center, p)),
    ]..removeWhere((n) => n.distanceM > radiusM);
    found.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return found.take(limit).toList();
  }

  /// Places of [category] ahead on [route], at most [maxOffRouteM] from it,
  /// ordered by distance along the route from [alongM].
  List<NearbyPlace> alongRoute(
    PlaceCategory category,
    TripRoute route,
    double alongM, {
    double maxOffRouteM = 1000,
    double horizonM = 60000,
    int limit = 30,
  }) {
    final ahead = [
      for (var i = 0; i < route.shape.length; i++)
        if (route.cumulative[i] >= alongM - 50 && route.cumulative[i] <= alongM + horizonM) route.shape[i],
    ];
    if (ahead.isEmpty) return const [];
    final pad = maxOffRouteM / 111320;
    final lats = ahead.map((p) => p.lat), lons = ahead.map((p) => p.lon);
    final padLon = pad / math.cos(ahead.first.lat * math.pi / 180);
    final here = route.pointAt(alongM);
    final found = <NearbyPlace>[];
    for (final (place, p) in _inBox(
      category.kinds,
      lats.reduce(math.min) - pad,
      lats.reduce(math.max) + pad,
      lons.reduce(math.min) - padLon,
      lons.reduce(math.max) + padLon,
      20000,
    )) {
      final proj = projectOnRoute(route, p);
      if (proj == null || proj.offsetM > maxOffRouteM) continue;
      final aheadM = proj.alongM - alongM;
      if (aheadM < 0 || aheadM > horizonM) continue;
      found.add(NearbyPlace(place, distanceM(here, p), aheadM: aheadM, offRouteM: proj.offsetM));
    }
    found.sort((a, b) => a.aheadM!.compareTo(b.aheadM!));
    return found.take(limit).toList();
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
        name: name ?? _categoryLabel(kind),
        detail: join([number == null || street == null ? street : '$number $street', locality]),
        position: position,
        category: kind,
      ),
    };
  }

  static String _categoryLabel(String kind) {
    for (final c in driverCategories) {
      if (c.kinds.contains(kind)) return c.label;
    }
    return kind;
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

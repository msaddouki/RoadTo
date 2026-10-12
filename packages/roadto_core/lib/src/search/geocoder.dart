import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo.dart';

/// Résultat de recherche d'adresse ou de lieu.
class Place {
  final String name;
  final String? detail;
  final LatLon position;
  final String? category;

  const Place({required this.name, required this.position, this.detail, this.category});

  String get label => detail == null || detail!.isEmpty ? name : '$name, $detail';
}

/// Recherche d'adresses. Le POC interroge Photon en ligne ; l'index SQLite
/// FTS5 hors ligne du paquet région (jalon J2) implémentera la même interface.
abstract interface class Geocoder {
  Future<List<Place>> search(String query, {LatLon? near, int limit = 8});
}

class PhotonGeocoder implements Geocoder {
  final Uri baseUrl;
  final http.Client _client;
  final String language;

  PhotonGeocoder({required String baseUrl, http.Client? client, this.language = 'fr'})
    : baseUrl = Uri.parse(baseUrl),
      _client = client ?? http.Client();

  @override
  Future<List<Place>> search(String query, {LatLon? near, int limit = 8}) async {
    if (query.trim().length < 3) return const [];
    final uri = baseUrl
        .resolve('api')
        .replace(
          queryParameters: {
            'q': query.trim(),
            'limit': '$limit',
            'lang': language,
            if (near != null) 'lat': near.lat.toStringAsFixed(4),
            if (near != null) 'lon': near.lon.toStringAsFixed(4),
          },
        );
    final res = await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Recherche indisponible (${res.statusCode})');
    return parsePhoton(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }
}

List<Place> parsePhoton(Map<String, dynamic> json) {
  final out = <Place>[];
  for (final f in json['features'] as List? ?? const []) {
    final coords = f['geometry']?['coordinates'] as List?;
    final p = f['properties'] as Map<String, dynamic>? ?? const {};
    if (coords == null || coords.length < 2) continue;
    final street = [p['housenumber'], p['street']].whereType<String>().join(' ');
    final name = (p['name'] as String?) ?? (street.isNotEmpty ? street : null);
    if (name == null) continue;
    final detail = [
      if (p['name'] != null && street.isNotEmpty) street,
      [p['postcode'], p['city']].whereType<String>().join(' '),
    ].where((s) => s.isNotEmpty).join(', ');
    out.add(
      Place(
        name: name,
        detail: detail,
        position: LatLon((coords[1] as num).toDouble(), (coords[0] as num).toDouble()),
        category: p['osm_value'] as String?,
      ),
    );
  }
  return out;
}

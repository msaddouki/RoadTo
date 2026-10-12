import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo.dart';
import 'route.dart';

/// Moteur de calcul d'itinéraire. Le POC utilise Valhalla en ligne ; la
/// version hors ligne (valhalla-mobile, jalon J2) implémentera la même
/// interface.
abstract interface class RouteEngine {
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []});
}

class RoutingException implements Exception {
  final String message;

  RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}

/// Client de l'API /route de Valhalla.
class ValhallaRouter implements RouteEngine {
  final Uri baseUrl;
  final http.Client _client;
  final String language;

  ValhallaRouter({required String baseUrl, http.Client? client, this.language = 'fr-FR'})
    : baseUrl = Uri.parse(baseUrl),
      _client = client ?? http.Client();

  /// Corps de la requête, exposé pour les tests.
  Map<String, dynamic> buildRequest(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) => {
    'locations': [
      {
        'lat': from.lat,
        'lon': from.lon,
        if (headingDeg != null) 'heading': headingDeg.round(),
        if (headingDeg != null) 'heading_tolerance': 45,
      },
      {'lat': to.lat, 'lon': to.lon},
    ],
    'costing': 'auto',
    'units': 'kilometers',
    'language': language,
    'directions_options': {'units': 'kilometers', 'language': language},
    // Petits carrés de ~40 m autour des routes fermées et accidents
    // bloquants, que l'itinéraire doit contourner.
    if (avoid.isNotEmpty) 'exclude_polygons': [for (final p in avoid) _square(p, 20)],
  };

  static List<List<double>> _square(LatLon c, double halfM) {
    final dLat = halfM / 111320;
    final dLon = halfM / (111320 * math.cos(c.lat * math.pi / 180));
    return [
      [c.lon - dLon, c.lat - dLat],
      [c.lon + dLon, c.lat - dLat],
      [c.lon + dLon, c.lat + dLat],
      [c.lon - dLon, c.lat + dLat],
      [c.lon - dLon, c.lat - dLat],
    ];
  }

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async {
    final body = jsonEncode(buildRequest(from, to, headingDeg: headingDeg, avoid: avoid));
    final http.Response res;
    try {
      res = await _client
          .post(baseUrl.resolve('route'), headers: {'content-type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw RoutingException('Serveur de routage injoignable ($e)');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw RoutingException('${json['error'] ?? 'Erreur'} (${res.statusCode})');
    }
    return parseValhallaRoute(json);
  }
}

/// Convertit une réponse Valhalla en [TripRoute], en mettant bout à bout les étapes.
TripRoute parseValhallaRoute(Map<String, dynamic> json) {
  final trip = json['trip'] as Map<String, dynamic>?;
  if (trip == null) throw RoutingException('Réponse sans itinéraire');
  final shape = <LatLon>[];
  final maneuvers = <Maneuver>[];
  for (final leg in trip['legs'] as List) {
    final legShape = decodePolyline(leg['shape'] as String);
    // Les étapes partagent leur point de jonction.
    final offset = shape.isEmpty ? 0 : shape.length - 1;
    shape.addAll(shape.isEmpty ? legShape : legShape.skip(1));
    for (final m in leg['maneuvers'] as List) {
      maneuvers.add(
        Maneuver(
          type: m['type'] as int,
          instruction: m['instruction'] as String? ?? '',
          verbalAlert: m['verbal_transition_alert_instruction'] as String?,
          verbalPre: m['verbal_pre_transition_instruction'] as String?,
          verbalPost: m['verbal_post_transition_instruction'] as String?,
          streetNames: [for (final s in (m['street_names'] as List? ?? const [])) '$s'],
          beginShapeIndex: offset + (m['begin_shape_index'] as int),
          lengthM: ((m['length'] as num?) ?? 0) * 1000,
          timeS: ((m['time'] as num?) ?? 0).toDouble(),
        ),
      );
    }
  }
  final summary = trip['summary'] as Map<String, dynamic>;
  return TripRoute(
    shape: shape,
    maneuvers: maneuvers,
    lengthM: (summary['length'] as num) * 1000,
    timeS: (summary['time'] as num).toDouble(),
  );
}

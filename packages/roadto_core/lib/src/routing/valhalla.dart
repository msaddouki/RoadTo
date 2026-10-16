import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo.dart';
import 'route.dart';
import 'speed_limits.dart';

/// Route computation. Implemented online ([ValhallaRouter]), on the device
/// ([NativeValhallaRouter]), or both with a fallback ([FallbackRouter]).
abstract interface class RouteEngine {
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []});
}

/// Speed limits along a route computed by the same engine.
abstract interface class SpeedLimitSource {
  Future<SpeedLimits> speedLimits(TripRoute route);
}

class RoutingException implements Exception {
  final String message;

  RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}

/// Body of a Valhalla /route request, shared by the online and on-device
/// engines.
Map<String, dynamic> valhallaRouteRequest(
  LatLon from,
  LatLon to, {
  double? headingDeg,
  List<LatLon> avoid = const [],
  String language = 'fr-FR',
}) => {
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
  // Small squares (~40 m) around closed roads and blocking accidents, which
  // the route must avoid.
  if (avoid.isNotEmpty) 'exclude_polygons': [for (final p in avoid) _square(p, 20)],
};

List<List<double>> _square(LatLon c, double halfM) {
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

/// Client of a Valhalla server's /route and /trace_attributes APIs.
class ValhallaRouter implements RouteEngine, SpeedLimitSource {
  final Uri baseUrl;
  final http.Client _client;
  final String language;

  ValhallaRouter({required String baseUrl, http.Client? client, this.language = 'fr-FR'})
    : baseUrl = Uri.parse(baseUrl),
      _client = client ?? http.Client();

  /// Request body, exposed for tests.
  Map<String, dynamic> buildRequest(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) =>
      valhallaRouteRequest(from, to, headingDeg: headingDeg, avoid: avoid, language: language);

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async =>
      parseValhallaRoute(await _post('route', buildRequest(from, to, headingDeg: headingDeg, avoid: avoid)));

  @override
  Future<SpeedLimits> speedLimits(TripRoute route) async =>
      parseSpeedLimits(await _post('trace_attributes', speedLimitsRequest(route)));

  Future<Map<String, dynamic>> _post(String action, Map<String, dynamic> request) async {
    final http.Response res;
    try {
      res = await _client
          .post(baseUrl.resolve(action), headers: {'content-type': 'application/json'}, body: jsonEncode(request))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw RoutingException('Serveur de routage injoignable ($e)');
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw RoutingException('Réponse illisible du serveur de routage (${res.statusCode})');
    }
    if (res.statusCode != 200) {
      throw RoutingException('${json['error'] ?? 'Erreur'} (${res.statusCode})');
    }
    return json;
  }
}

/// Valhalla running on the device (valhalla-mobile), on the graph of an
/// installed region. [call] sends a /route request JSON to the platform and
/// returns the response JSON, [traceAttributes] the same for
/// /trace_attributes; the app provides them over a MethodChannel.
class NativeValhallaRouter implements RouteEngine, SpeedLimitSource {
  final String configPath;
  final Future<String> Function(String configPath, String requestJson) call;
  final Future<String> Function(String configPath, String requestJson)? traceAttributes;
  final String language;

  NativeValhallaRouter({required this.configPath, required this.call, this.traceAttributes, this.language = 'fr-FR'});

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async {
    final request = jsonEncode(
      valhallaRouteRequest(from, to, headingDeg: headingDeg, avoid: avoid, language: language),
    );
    return parseValhallaRoute(await _run(call, request));
  }

  @override
  Future<SpeedLimits> speedLimits(TripRoute route) async {
    final trace = traceAttributes;
    if (trace == null) throw RoutingException('Limitations de vitesse indisponibles hors ligne');
    return parseSpeedLimits(await _run(trace, jsonEncode(speedLimitsRequest(route))));
  }

  Future<Map<String, dynamic>> _run(
    Future<String> Function(String configPath, String requestJson) action,
    String request,
  ) async {
    final String response;
    try {
      response = await action(configPath, request);
    } catch (e) {
      throw RoutingException('Calcul hors ligne impossible ($e)');
    }
    try {
      return jsonDecode(response) as Map<String, dynamic>;
    } on FormatException {
      throw RoutingException('Réponse illisible du calcul hors ligne');
    }
  }
}

/// Tries [primary] (on the device) and falls back to [fallback] (online) when
/// it fails, e.g. for a destination outside the installed region.
class FallbackRouter implements RouteEngine, SpeedLimitSource {
  final RouteEngine primary;
  final RouteEngine fallback;

  /// Called when the fallback is used, with the primary's error.
  final void Function(RoutingException error)? onFallback;

  FallbackRouter(this.primary, this.fallback, {this.onFallback});

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async {
    try {
      return await primary.route(from, to, headingDeg: headingDeg, avoid: avoid);
    } on RoutingException catch (e) {
      onFallback?.call(e);
      return fallback.route(from, to, headingDeg: headingDeg, avoid: avoid);
    }
  }

  /// From the primary when it can, else from the fallback.
  @override
  Future<SpeedLimits> speedLimits(TripRoute route) async {
    if (primary case final SpeedLimitSource first) {
      try {
        return await first.speedLimits(route);
      } on RoutingException catch (e) {
        onFallback?.call(e);
      }
    }
    if (fallback case final SpeedLimitSource second) return second.speedLimits(route);
    throw RoutingException('Limitations de vitesse indisponibles');
  }
}

/// Converts a Valhalla response into a [TripRoute], joining the legs.
TripRoute parseValhallaRoute(Map<String, dynamic> json) {
  if (json['error'] != null) {
    throw RoutingException('${json['error']}${json['error_code'] != null ? ' (${json['error_code']})' : ''}');
  }
  final trip = json['trip'] as Map<String, dynamic>?;
  if (trip == null) throw RoutingException('Réponse sans itinéraire');
  final shape = <LatLon>[];
  final maneuvers = <Maneuver>[];
  for (final leg in trip['legs'] as List) {
    final legShape = decodePolyline(leg['shape'] as String);
    // Legs share their junction point.
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
          verbalMultiCue: m['verbal_multi_cue'] as bool? ?? false,
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

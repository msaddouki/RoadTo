import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../geo.dart';
import 'road_details.dart';
import 'route.dart';

/// Route computation. Implemented online ([ValhallaRouter]), on the device
/// ([NativeValhallaRouter]), or both with a fallback ([FallbackRouter]).
abstract interface class RouteEngine {
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []});
}

/// Several routes at once: the best one first, then up to [alternates]
/// others, to weigh the jams reported on each ([fastestWithJams]).
abstract interface class AlternativeRoutes {
  Future<List<TripRoute>> routes(
    LatLon from,
    LatLon to, {
    double? headingDeg,
    List<LatLon> avoid = const [],
    int alternates = 2,
  });
}

/// Speed limits, traffic lights, side streets and lanes along a route
/// computed by the same engine.
abstract interface class RoadDetailsSource {
  Future<RoadDetails> roadDetails(TripRoute route);
}

/// The lanes of [answer], or none: they are a plus, the rest of the
/// details stands without them.
Future<List<LaneGuide>> _lanesOr(TripRoute route, Future<Map<String, dynamic>> Function() answer) async {
  try {
    return parseLanes(await answer(), route);
  } on Object catch (_) {
    return const [];
  }
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
  int alternates = 0,
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
  if (alternates > 0) 'alternates': alternates,
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

/// Client of a Valhalla server's /route, /trace_attributes and /trace_route
/// APIs.
class ValhallaRouter implements RouteEngine, AlternativeRoutes, RoadDetailsSource {
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
  Future<List<TripRoute>> routes(
    LatLon from,
    LatLon to, {
    double? headingDeg,
    List<LatLon> avoid = const [],
    int alternates = 2,
  }) async => parseValhallaRoutes(
    await _post(
      'route',
      valhallaRouteRequest(from, to, headingDeg: headingDeg, avoid: avoid, language: language, alternates: alternates),
    ),
  );

  @override
  Future<RoadDetails> roadDetails(TripRoute route) async {
    final lanes = _lanesOr(route, () => _post('trace_route', lanesRequest(route, language: language)));
    final details = parseRoadAttributes(await _post('trace_attributes', roadAttributesRequest(route)));
    return details.withLanes(await lanes);
  }

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
/// returns the response JSON, [traceAttributes] and [traceRoute] the same
/// for /trace_attributes and /trace_route; the app provides them over a
/// MethodChannel.
class NativeValhallaRouter implements RouteEngine, AlternativeRoutes, RoadDetailsSource {
  final String configPath;
  final Future<String> Function(String configPath, String requestJson) call;
  final Future<String> Function(String configPath, String requestJson)? traceAttributes;
  final Future<String> Function(String configPath, String requestJson)? traceRoute;
  final String language;

  NativeValhallaRouter({
    required this.configPath,
    required this.call,
    this.traceAttributes,
    this.traceRoute,
    this.language = 'fr-FR',
  });

  @override
  Future<TripRoute> route(LatLon from, LatLon to, {double? headingDeg, List<LatLon> avoid = const []}) async {
    final request = jsonEncode(
      valhallaRouteRequest(from, to, headingDeg: headingDeg, avoid: avoid, language: language),
    );
    return parseValhallaRoute(await _run(call, request));
  }

  @override
  Future<List<TripRoute>> routes(
    LatLon from,
    LatLon to, {
    double? headingDeg,
    List<LatLon> avoid = const [],
    int alternates = 2,
  }) async {
    final request = jsonEncode(
      valhallaRouteRequest(from, to, headingDeg: headingDeg, avoid: avoid, language: language, alternates: alternates),
    );
    return parseValhallaRoutes(await _run(call, request));
  }

  @override
  Future<RoadDetails> roadDetails(TripRoute route) async {
    final trace = traceAttributes;
    if (trace == null) throw RoutingException('Détails de la route indisponibles hors ligne');
    final traceRoute = this.traceRoute;
    final lanes = traceRoute == null
        ? Future.value(const <LaneGuide>[])
        : _lanesOr(route, () => _run(traceRoute, jsonEncode(lanesRequest(route, language: language))));
    final details = parseRoadAttributes(await _run(trace, jsonEncode(roadAttributesRequest(route))));
    return details.withLanes(await lanes);
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
class FallbackRouter implements RouteEngine, AlternativeRoutes, RoadDetailsSource {
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

  /// From the primary when it can give several, else one route from it
  /// (alternatives are a plus), else from the fallback.
  @override
  Future<List<TripRoute>> routes(
    LatLon from,
    LatLon to, {
    double? headingDeg,
    List<LatLon> avoid = const [],
    int alternates = 2,
  }) async {
    Future<List<TripRoute>> ask(RouteEngine e) async {
      if (e case final AlternativeRoutes several) {
        return several.routes(from, to, headingDeg: headingDeg, avoid: avoid, alternates: alternates);
      }
      return [await e.route(from, to, headingDeg: headingDeg, avoid: avoid)];
    }

    try {
      return await ask(primary);
    } on RoutingException catch (e) {
      onFallback?.call(e);
      return ask(fallback);
    }
  }

  /// From the primary when it can, else from the fallback.
  @override
  Future<RoadDetails> roadDetails(TripRoute route) async {
    if (primary case final RoadDetailsSource first) {
      try {
        return await first.roadDetails(route);
      } on RoutingException catch (e) {
        onFallback?.call(e);
      }
    }
    if (fallback case final RoadDetailsSource second) return second.roadDetails(route);
    throw RoutingException('Détails de la route indisponibles');
  }
}

/// The route of a Valhalla response, then its alternatives, if any.
List<TripRoute> parseValhallaRoutes(Map<String, dynamic> json) => [
  parseValhallaRoute(json),
  for (final alt in (json['alternates'] as List? ?? const []))
    if (alt case {'trip': final Map<String, dynamic> _}) parseValhallaRoute(alt as Map<String, dynamic>),
];

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

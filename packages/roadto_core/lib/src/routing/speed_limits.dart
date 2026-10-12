import '../geo.dart';
import 'route.dart';

/// Posted speed limit over a stretch of the route, in metres from its start.
class SpeedLimitSpan {
  final double startM;
  final double endM;

  /// km/h; null when OSM has no limit for this road.
  final int? kph;

  /// No limit at all (some German motorways).
  final bool unlimited;

  const SpeedLimitSpan(this.startM, this.endM, {this.kph, this.unlimited = false});
}

/// Posted speed limits along a route, from OSM `maxspeed` through Valhalla
/// (`trace_attributes` on the route's own shape).
class SpeedLimits {
  /// Ordered, non-overlapping.
  final List<SpeedLimitSpan> spans;

  const SpeedLimits(this.spans);

  static const none = SpeedLimits([]);

  /// The span at [alongM] metres from the start of the route, if any.
  SpeedLimitSpan? at(double alongM) {
    var lo = 0, hi = spans.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final s = spans[mid];
      if (alongM < s.startM) {
        hi = mid - 1;
      } else if (alongM >= s.endM) {
        lo = mid + 1;
      } else {
        return s;
      }
    }
    return null;
  }

  /// Share of the route length with a known limit, 0 to 1.
  double coverage(double routeLengthM) {
    if (routeLengthM <= 0) return 0;
    var known = 0.0;
    for (final s in spans) {
      if (s.kph != null || s.unlimited) known += s.endM - s.startM;
    }
    return (known / routeLengthM).clamp(0, 1);
  }
}

/// Valhalla `trace_attributes` request for the speed limits along [route].
/// `edge_walk` follows the shape edge by edge, which is exact and fast for a
/// shape that Valhalla produced itself.
Map<String, dynamic> speedLimitsRequest(TripRoute route) => {
  'encoded_polyline': encodePolyline(route.shape),
  'costing': 'auto',
  'shape_match': 'edge_walk',
  'units': 'kilometers',
  'filters': {
    'attributes': ['edge.speed_limit', 'edge.begin_shape_index', 'edge.end_shape_index', 'shape'],
    'action': 'include',
  },
};

/// Reads a `trace_attributes` answer. Edge indexes point into the answer's
/// own shape, which follows the route, so distances along it are distances
/// along the route.
SpeedLimits parseSpeedLimits(Map<String, dynamic> json) {
  final encoded = json['shape'] as String?;
  final edges = json['edges'] as List?;
  if (encoded == null || edges == null) return SpeedLimits.none;
  final shape = decodePolyline(encoded);
  if (shape.length < 2) return SpeedLimits.none;
  final cumulative = List<double>.filled(shape.length, 0);
  for (var i = 1; i < shape.length; i++) {
    cumulative[i] = cumulative[i - 1] + distanceM(shape[i - 1], shape[i]);
  }
  double at(Object? index) => cumulative[((index as num?)?.toInt() ?? 0).clamp(0, shape.length - 1)];

  final spans = <SpeedLimitSpan>[];
  for (final e in edges.cast<Map<String, dynamic>>()) {
    final start = at(e['begin_shape_index']), end = at(e['end_shape_index']);
    if (end <= start) continue;
    final raw = e['speed_limit'];
    final unlimited = raw == 'unlimited';
    final kph = raw is num && raw > 0 && raw < 250 ? raw.round() : null;
    // Consecutive edges with the same limit make one span.
    final last = spans.isEmpty ? null : spans.last;
    if (last != null && last.kph == kph && last.unlimited == unlimited && (start - last.endM).abs() < 1) {
      spans[spans.length - 1] = SpeedLimitSpan(last.startM, end, kph: kph, unlimited: unlimited);
    } else {
      spans.add(SpeedLimitSpan(start, end, kph: kph, unlimited: unlimited));
    }
  }
  return SpeedLimits(spans);
}

/// Over the limit, with the usual margin: 5 km/h up to 100 km/h, 5 % above
/// (the margin French speed cameras apply).
bool isOverLimit(double speedKph, int limitKph) =>
    speedKph > (limitKph <= 100 ? limitKph + 5 : limitKph * 1.05);

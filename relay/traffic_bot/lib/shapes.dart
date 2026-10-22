import 'dart:math' as math;

import 'package:roadto_core/roadto_core.dart';

import 'bison_fute.dart';

/// The road a station measures, to draw its jams on the map: as Valhalla
/// routes it from the start of the station's stretch to its end, heading the
/// way traffic goes, so it follows the road and the right carriageway.
/// Computed once per station and kept; a failure is tried again after
/// [retryAfter].
class StretchShapes {
  final RouteEngine router;
  final Duration retryAfter;
  final _shapes = <String, List<LatLon>?>{};
  final _failedAt = <String, DateTime>{};

  StretchShapes(this.router, {this.retryAfter = const Duration(hours: 1)});

  List<LatLon>? operator [](String id) => _shapes[id];

  /// Whether [site] still needs a shape at [now].
  bool wants(Site site, DateTime now) {
    if (_shapes.containsKey(site.id) || site.lengthM < 50) return false;
    final failed = _failedAt[site.id];
    return failed == null || now.difference(failed) >= retryAfter;
  }

  Future<void> fetch(Site site, DateTime now) async {
    try {
      final route = await router.route(site.start, site.end, headingDeg: site.bearing);
      final shape = stretchShape(site, route);
      if (shape != null) {
        _shapes[site.id] = shape;
        _failedAt.remove(site.id);
        return;
      }
    } on RoutingException {
      // Tried again later.
    }
    _failedAt[site.id] = now;
  }
}

/// [route]'s shape for [site], unless the route strays (more than twice the
/// stretch, plus 600 m: a detour by an interchange), cut to [maxStretchM]
/// and to at most [maxPoints] points.
List<LatLon>? stretchShape(Site site, TripRoute route, {int maxPoints = 200}) {
  final straight = site.lengthM;
  if (straight < 50 || route.shape.length < 2) return null;
  if (route.shapeLengthM > math.max(2 * straight, straight + 600)) return null;
  final points = <LatLon>[];
  for (var i = 0; i < route.shape.length; i++) {
    if (route.cumulative[i] > maxStretchM) {
      points.add(route.pointAt(maxStretchM.toDouble()));
      break;
    }
    points.add(route.shape[i]);
  }
  if (points.length <= maxPoints) return points;
  final step = (points.length - 1) / (maxPoints - 1);
  return [for (var k = 0; k < maxPoints; k++) points[(k * step).round()]];
}

/// The point halfway along [line].
LatLon middleOf(List<LatLon> line) {
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += distanceM(line[i - 1], line[i]);
  }
  var left = total / 2;
  for (var i = 1; i < line.length; i++) {
    final d = distanceM(line[i - 1], line[i]);
    if (d >= left && d > 0) return interpolate(line[i - 1], line[i], left / d);
    left -= d;
  }
  return line.last;
}

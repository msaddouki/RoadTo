import 'dart:math' as math;

import 'package:roadto_core/roadto_core.dart';

// Lambert-93 (EPSG:2154), the French official projection the road network's
// referential uses, back to latitude and longitude (IGN, note NT/G 71,
// algorithms ALG0004 and ALG0001). RGF93 and WGS84 agree within a metre.
const _e = 0.0818191910428158; // GRS80 first eccentricity
const _n = 0.7256077650532670;
const _c = 11754255.4260960;
const _xs = 700000.0;
const _ys = 12655612.0499;
const _lambda0 = 3 * math.pi / 180;

LatLon lambert93ToWgs84(double x, double y) {
  final dx = x - _xs, dy = _ys - y;
  final r = math.sqrt(dx * dx + dy * dy);
  final gamma = math.atan(dx / dy);
  final lon = _lambda0 + gamma / _n;
  final iso = -1 / _n * math.log((r / _c).abs());
  // Latitude from the isometric latitude, by iteration.
  var lat = 2 * math.atan(math.exp(iso)) - math.pi / 2;
  for (var i = 0; i < 20; i++) {
    final s = _e * math.sin(lat);
    final next = 2 * math.atan(math.pow((1 + s) / (1 - s), _e / 2) * math.exp(iso)) - math.pi / 2;
    if ((next - lat).abs() < 1e-12) {
      lat = next;
      break;
    }
    lat = next;
  }
  return LatLon(lat * 180 / math.pi, lon * 180 / math.pi);
}

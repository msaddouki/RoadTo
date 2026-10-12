import 'dart:math' as math;

const double earthRadiusM = 6371008.8;

/// Coordonnée WGS84, en degrés.
class LatLon {
  final double lat;
  final double lon;

  const LatLon(this.lat, this.lon);

  @override
  bool operator ==(Object other) => other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLon(${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)})';
}

double _rad(double deg) => deg * math.pi / 180;
double _deg(double rad) => rad * 180 / math.pi;

/// Distance orthodromique en mètres.
double distanceM(LatLon a, LatLon b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(a.lat)) * math.cos(_rad(b.lat)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Cap initial de [a] vers [b], en degrés dans [0, 360).
double bearingDeg(LatLon a, LatLon b) {
  final la1 = _rad(a.lat), la2 = _rad(b.lat), dLon = _rad(b.lon - a.lon);
  final y = math.sin(dLon) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dLon);
  return (_deg(math.atan2(y, x)) + 360) % 360;
}

/// Point situé à [fraction] (0..1) du segment [a]–[b] (interpolation linéaire,
/// suffisante pour des segments de route de quelques centaines de mètres).
LatLon interpolate(LatLon a, LatLon b, double fraction) =>
    LatLon(a.lat + (b.lat - a.lat) * fraction, a.lon + (b.lon - a.lon) * fraction);

/// Projection de [p] sur le segment [a]–[b].
class SegmentProjection {
  /// Position du projeté le long du segment, entre 0 et 1.
  final double fraction;
  final LatLon point;
  final double distanceM;

  const SegmentProjection(this.fraction, this.point, this.distanceM);
}

/// Projette [p] sur [a]–[b] dans un plan local équirectangulaire.
SegmentProjection projectOnSegment(LatLon p, LatLon a, LatLon b) {
  final cosLat = math.cos(_rad(a.lat));
  final bx = (b.lon - a.lon) * cosLat, by = b.lat - a.lat;
  final px = (p.lon - a.lon) * cosLat, py = p.lat - a.lat;
  final len2 = bx * bx + by * by;
  var t = len2 == 0 ? 0.0 : (px * bx + py * by) / len2;
  t = t.clamp(0.0, 1.0);
  final q = interpolate(a, b, t);
  return SegmentProjection(t, q, distanceM(p, q));
}

/// Décode une polyline encodée (format Google, précision 6 par défaut,
/// celle de Valhalla).
List<LatLon> decodePolyline(String encoded, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final points = <LatLon>[];
  var index = 0, lat = 0, lon = 0;
  int next() {
    var result = 0, shift = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  while (index < encoded.length) {
    lat += next();
    lon += next();
    points.add(LatLon(lat / factor, lon / factor));
  }
  return points;
}

/// Encode une polyline (utile pour les tests et le rejeu de traces).
String encodePolyline(List<LatLon> points, {int precision = 6}) {
  final factor = math.pow(10, precision).toDouble();
  final out = StringBuffer();
  var prevLat = 0, prevLon = 0;
  void write(int v) {
    var n = v < 0 ? ~(v << 1) : (v << 1);
    while (n >= 0x20) {
      out.writeCharCode((0x20 | (n & 0x1f)) + 63);
      n >>= 5;
    }
    out.writeCharCode(n + 63);
  }

  for (final p in points) {
    final lat = (p.lat * factor).round(), lon = (p.lon * factor).round();
    write(lat - prevLat);
    write(lon - prevLon);
    prevLat = lat;
    prevLon = lon;
  }
  return out.toString();
}

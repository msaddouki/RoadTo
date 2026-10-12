import 'geo.dart';

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/// Encode une position en géohash de [precision] caractères.
String geohashEncode(LatLon p, {int precision = 7}) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  final out = StringBuffer();
  var bit = 0, ch = 0;
  var even = true;
  while (out.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (p.lon >= mid) {
        ch = (ch << 1) | 1;
        lonMin = mid;
      } else {
        ch <<= 1;
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (p.lat >= mid) {
        ch = (ch << 1) | 1;
        latMin = mid;
      } else {
        ch <<= 1;
        latMax = mid;
      }
    }
    even = !even;
    if (++bit == 5) {
      out.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return out.toString();
}

/// Emprise d'une maille géohash.
class GeohashBox {
  final double latMin, latMax, lonMin, lonMax;

  const GeohashBox(this.latMin, this.latMax, this.lonMin, this.lonMax);

  LatLon get center => LatLon((latMin + latMax) / 2, (lonMin + lonMax) / 2);
  double get latSpan => latMax - latMin;
  double get lonSpan => lonMax - lonMin;

  bool contains(LatLon p) => p.lat >= latMin && p.lat <= latMax && p.lon >= lonMin && p.lon <= lonMax;
}

GeohashBox geohashDecode(String hash) {
  var latMin = -90.0, latMax = 90.0, lonMin = -180.0, lonMax = 180.0;
  var even = true;
  for (final c in hash.toLowerCase().split('')) {
    final v = _base32.indexOf(c);
    if (v < 0) throw FormatException('Caractère géohash invalide : $c');
    for (var i = 4; i >= 0; i--) {
      final b = (v >> i) & 1;
      if (even) {
        final mid = (lonMin + lonMax) / 2;
        b == 1 ? lonMin = mid : lonMax = mid;
      } else {
        final mid = (latMin + latMax) / 2;
        b == 1 ? latMin = mid : latMax = mid;
      }
      even = !even;
    }
  }
  return GeohashBox(latMin, latMax, lonMin, lonMax);
}

bool isValidGeohash(String hash) => hash.isNotEmpty && hash.split('').every((c) => _base32.contains(c));

/// La maille et ses huit voisines.
Set<String> geohashWithNeighbors(String hash) {
  final box = geohashDecode(hash);
  final c = box.center;
  final out = <String>{};
  for (final dy in [-1, 0, 1]) {
    for (final dx in [-1, 0, 1]) {
      final lat = (c.lat + dy * box.latSpan).clamp(-89.999999, 89.999999);
      var lon = c.lon + dx * box.lonSpan;
      if (lon > 180) lon -= 360;
      if (lon < -180) lon += 360;
      out.add(geohashEncode(LatLon(lat, lon), precision: hash.length));
    }
  }
  return out;
}

/// Mailles de [precision] caractères qui couvrent un tracé, avec leurs
/// voisines, pour s'abonner aux alertes le long d'un itinéraire.
Set<String> geohashesAlong(List<LatLon> line, {int precision = 5, double stepM = 1000}) {
  final cells = <String>{};
  if (line.isEmpty) return cells;
  void add(LatLon p) => cells.add(geohashEncode(p, precision: precision));
  add(line.first);
  for (var i = 1; i < line.length; i++) {
    final a = line[i - 1], b = line[i];
    final d = distanceM(a, b);
    final steps = (d / stepM).ceil();
    for (var s = 1; s <= steps; s++) {
      add(interpolate(a, b, s / steps));
    }
  }
  return {for (final c in cells) ...geohashWithNeighbors(c)};
}

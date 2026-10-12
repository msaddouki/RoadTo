import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

void main() {
  group('geo', () {
    test('distance Bellecour – Part-Dieu ≈ 2,3 km', () {
      final d = distanceM(const LatLon(45.7578, 4.8320), const LatLon(45.7606, 4.8590));
      expect(d, closeTo(2120, 60));
    });

    test('cap vers l’est ≈ 90°', () {
      expect(bearingDeg(const LatLon(45, 4), const LatLon(45, 4.01)), closeTo(90, 0.1));
    });

    test('projection sur un segment', () {
      const a = LatLon(45, 4), b = LatLon(45, 4.01);
      final p = projectOnSegment(const LatLon(45.0005, 4.005), a, b);
      expect(p.fraction, closeTo(0.5, 0.001));
      expect(p.distanceM, closeTo(55.6, 1));
    });

    test('polyline : aller-retour', () {
      final pts = [const LatLon(45.7578, 4.832), const LatLon(45.758123, 4.834567), const LatLon(45.76, 4.8)];
      final back = decodePolyline(encodePolyline(pts));
      for (var i = 0; i < pts.length; i++) {
        expect(back[i].lat, closeTo(pts[i].lat, 1e-6));
        expect(back[i].lon, closeTo(pts[i].lon, 1e-6));
      }
    });
  });

  group('géohash', () {
    test('vecteur de référence', () {
      expect(geohashEncode(const LatLon(57.64911, 10.40744), precision: 11), 'u4pruydqqvj');
    });

    test('décodage : la maille contient le point', () {
      const p = LatLon(45.7578, 4.8320);
      final h = geohashEncode(p, precision: 7);
      expect(geohashDecode(h).contains(p), isTrue);
      expect(distanceM(geohashDecode(h).center, p), lessThan(110));
    });

    test('voisines : 9 mailles distinctes de même précision', () {
      final n = geohashWithNeighbors('u05kq');
      expect(n, hasLength(9));
      expect(n.every((h) => h.length == 5), isTrue);
      expect(n, contains('u05kq'));
    });

    test('mailles le long d’un tracé', () {
      final cells = geohashesAlong([const LatLon(45.75, 4.80), const LatLon(45.75, 4.95)]);
      expect(cells, contains(geohashEncode(const LatLon(45.75, 4.80), precision: 5)));
      expect(cells, contains(geohashEncode(const LatLon(45.75, 4.95), precision: 5)));
    });
  });
}

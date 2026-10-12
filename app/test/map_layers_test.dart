import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/map_layers.dart';
import 'package:roadto_core/roadto_core.dart';

void main() {
  final route = TripRoute(
    shape: const [LatLon(45.75, 4.83), LatLon(45.75, 4.84), LatLon(45.76, 4.84)],
    maneuvers: const [],
    lengthM: 1890,
    timeS: 200,
  );

  test('tracé coupé entre partie parcourue et restante', () {
    final fc = routeGeoJson(route, alongM: 300);
    final features = fc['features'] as List;
    expect(features.map((f) => f['properties']['part']), ['done', 'todo']);
    final done = features[0]['geometry']['coordinates'] as List;
    final todo = features[1]['geometry']['coordinates'] as List;
    expect(done.last, todo.first, reason: 'les deux parties se rejoignent');
    expect(todo.last, [4.84, 45.76]);
  });

  test('sans itinéraire, collection vide', () {
    expect(routeGeoJson(null)['features'], isEmpty);
    expect(pointGeoJson(null)['features'], isEmpty);
  });

  test('alertes : couleur et coordonnées lon/lat', () {
    final alert = RoadAlert(
      id: 'a',
      author: 'b',
      type: AlertType.accident,
      geohash: geohashEncode(const LatLon(45.7578, 4.832)),
      createdAt: DateTime(2026),
      expiresAt: DateTime(2027),
    );
    final f = (alertsGeoJson([alert])['features'] as List).single;
    expect(f['properties']['color'], '#ff5a5f');
    final c = f['geometry']['coordinates'] as List;
    expect(c[0], closeTo(4.832, 0.001));
    expect(c[1], closeTo(45.7578, 0.001));
  });
}

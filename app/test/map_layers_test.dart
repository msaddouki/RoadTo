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

  test('noms de rues : en bulles pendant un trajet, le long des routes sinon', () {
    const ids = [
      'roadto-labels',
      'street-name-main',
      'street-name-main-nav',
      'street-name-minor',
      'street-name-minor-nav',
      'place',
    ];
    expect(labelVisibility(ids, navigating: true), {
      'street-name-main': false,
      'street-name-main-nav': true,
      'street-name-minor': false,
      'street-name-minor-nav': true,
    });
    expect(labelVisibility(ids, navigating: false)['street-name-main-nav'], isFalse);
    expect(labelVisibility(ids, navigating: false)['street-name-main'], isTrue);
    // Online style without navigation labels: nothing to switch.
    expect(labelVisibility(['road_label', 'water'], navigating: true), isEmpty);
  });

  test('aperçu : un trajet court montre au moins 1,5 km autour, un long tout entier', () {
    const short = [LatLon(45.7578, 4.8320), LatLon(45.7585, 4.8330)];
    final b = routeBounds(short);
    expect(distanceM(LatLon(b.s, b.w), LatLon(b.n, b.w)), closeTo(1500, 5));
    expect(distanceM(LatLon(b.s, b.w), LatLon(b.s, b.e)), closeTo(1500, 5));
    expect((b.s + b.n) / 2, closeTo(45.75815, 1e-6));

    const long = [LatLon(45.75, 4.83), LatLon(45.99, 4.72)];
    final l = routeBounds(long);
    expect((l.s, l.w, l.n, l.e), (45.75, 4.72, 45.99, 4.83));
  });
}

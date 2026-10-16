import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/favorites.dart';
import 'package:roadto/ui/search_screen.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _here = LatLon(45.7578, 4.8320);
const _bellecour = Place(name: 'Place Bellecour', detail: '69002 Lyon', position: LatLon(45.7578, 4.8320));
const _partDieu = Place(name: 'Gare Part-Dieu', detail: 'Lyon', position: LatLon(45.7606, 4.8593));

/// Opens the search screen; the result reads the place it returned.
Future<Place? Function()> _open(WidgetTester tester, Favorites favorites, {List<Place> results = const []}) async {
  Place? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await Navigator.of(context).push<Place>(
              MaterialPageRoute(
                builder: (_) => SearchScreen(search: (_) async => results, from: _here, favorites: favorites),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return () => picked;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('store', () {
    test('saves, finds, renames and removes; kept across restarts', () async {
      final favorites = await Favorites.load();
      expect(favorites.all, isEmpty);
      await favorites.add(_bellecour, name: 'Maison');
      await favorites.add(_partDieu);

      expect(favorites.all.map((f) => f.name), ['Gare Part-Dieu', 'Maison']);
      expect(favorites.find(const LatLon(45.75785, 4.83205))!.name, 'Maison');
      expect(favorites.contains(_partDieu), isTrue);

      await favorites.rename(favorites.all.first, 'Travail');
      final reloaded = await Favorites.load();
      expect(reloaded.all.map((f) => f.name), ['Travail', 'Maison']);
      expect(reloaded.all.last.detail, '69002 Lyon');
      expect(reloaded.all.last.position.lat, 45.7578);

      await reloaded.remove(_bellecour);
      expect((await Favorites.load()).all.map((f) => f.name), ['Travail']);
    });

    test('saving the same spot again replaces it', () async {
      final favorites = await Favorites.load();
      await favorites.add(_bellecour);
      await favorites.add(_bellecour, name: 'Rendez-vous');
      expect(favorites.all.map((f) => f.name), ['Rendez-vous']);
    });

    test('unreadable entries are dropped, the others kept', () {
      final raw = '[{"name":"Maison","lat":45.7,"lon":4.8},{"name":3},"x"]';
      expect(Favorites.decode(raw).map((f) => f.name), ['Maison']);
      expect(Favorites.decode('not json'), isEmpty);
    });
  });

  group('search screen', () {
    testWidgets('favourites show before typing; tapping one picks it', (tester) async {
      final favorites = await Favorites.load();
      await favorites.add(_partDieu, name: 'Travail');
      final picked = await _open(tester, favorites);
      expect(find.text('Favoris'), findsOneWidget);
      await tester.tap(find.text('Travail'));
      await tester.pumpAndSettle();
      expect(picked()!.name, 'Travail');
    });

    testWidgets('a result is added with its star, then shown as a favourite', (tester) async {
      final favorites = await Favorites.load();
      await _open(tester, favorites, results: const [_partDieu]);
      expect(find.text('Favoris'), findsNothing);

      await tester.enterText(find.byType(TextField), 'part-dieu');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ajouter aux favoris'));
      await tester.pumpAndSettle();
      expect(favorites.contains(_partDieu), isTrue);
      expect(find.byTooltip('Retirer des favoris'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Favoris'), findsOneWidget);
      expect(find.text('Gare Part-Dieu'), findsOneWidget);
    });

    testWidgets('a favourite is renamed, then removed, from its menu', (tester) async {
      final favorites = await Favorites.load();
      await favorites.add(_bellecour);
      await _open(tester, favorites);

      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renommer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maison'));
      await tester.pump();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Maison'), findsOneWidget);
      expect(favorites.all.single.name, 'Maison');

      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer des favoris'));
      await tester.pumpAndSettle();
      expect(favorites.all, isEmpty);
      expect(find.text('Favoris'), findsNothing);
    });
  });
}

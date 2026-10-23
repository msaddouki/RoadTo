import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _bellecour = LatLon(45.7578, 4.8320);

/// An index as the pipeline writes it (pipeline/schema/places.sql), with
/// [rows] (kind, name, housenumber, street, city, lat, lon, importance).
String _index(Directory dir, List<(String, String?, String?, String?, String, double, double, int)> rows) {
  final path = '${dir.path}/places.sqlite';
  final db = sqlite3.open(path);
  db.execute(File('../../pipeline/schema/places.sql').readAsStringSync());
  db.execute("INSERT INTO meta (key, value) VALUES ('schema_version', '1')");
  final insert = db.prepare(
    'INSERT INTO place (kind, name, housenumber, street, city, lat, lon, importance) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  );
  for (final (kind, name, number, street, city, lat, lon, importance) in rows) {
    insert.execute([kind, name, number, street, city, lat, lon, importance]);
  }
  insert.close();
  db.execute(
    'INSERT INTO place_fts (rowid, name, street, housenumber, city) SELECT id, name, street, housenumber, city FROM place',
  );
  db.close();
  return path;
}

void main() {
  late Directory dir;
  late OfflineGeocoder geocoder;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('roadto_search');
    geocoder = OfflineGeocoder.open(
      _index(dir, [
        // A street name found in hundreds of towns, all far away (60 to
        // 200 km): more than the words alone let through.
        for (var i = 0; i < 400; i++)
          ('address', null, '12', 'Rue Victor Hugo', 'Bourg$i', 45.0 - (i % 20) * 0.05, 4.0 + (i ~/ 20) * 0.05, 10),
        // And the one next door, with its neighbour at number 128.
        ('address', null, '12', 'Rue Victor Hugo', 'Lyon', 45.7552, 4.8297, 10),
        ('address', null, '128', 'Rue Victor Hugo', 'Lyon', 45.7540, 4.8290, 10),
        ('street', 'Rue de Paris', null, 'Rue de Paris', 'Lyon', 45.7700, 4.8500, 30),
        ('street', 'Rue de Paris', null, 'Rue de Paris', 'Grenoble', 45.1885, 5.7245, 30),
      ]),
    );
  });
  tearDownAll(() {
    geocoder.close();
    dir.deleteSync(recursive: true);
  });

  test('the nearest address first, however many far away share its name', () {
    final found = geocoder.searchSync('12 rue victor hugo', near: _bellecour);
    expect(found.first.label, '12 Rue Victor Hugo, Lyon');
    // Number 128 matches the words too ("12" as a prefix), after the 12s nearby.
    final at128 = found.indexWhere((p) => p.name.startsWith('128 '));
    expect(at128 == -1 || at128 > 0, isTrue);
  });

  test('the same street in another town comes after the one in this town', () {
    final found = geocoder.searchSync('rue de paris', near: _bellecour);
    expect(found.map((p) => p.detail), ['Lyon', 'Grenoble']);
    // From Grenoble, the other way round.
    expect(geocoder.searchSync('rue de paris', near: const LatLon(45.19, 5.72)).map((p) => p.detail), [
      'Grenoble',
      'Lyon',
    ]);
  });

  test('without a position: the words only', () {
    expect(geocoder.searchSync('victor hugo', limit: 3), hasLength(3));
  });

  test('online answers once each: a street cut into several ways', () {
    const a = Place(name: 'Rue de la République', detail: 'Lyon', position: LatLon(45.76, 4.836));
    const b = Place(name: 'Rue de la République', detail: 'Lyon', position: LatLon(45.762, 4.836));
    const c = Place(name: 'Rue de la République', detail: 'Oullins', position: LatLon(45.71, 4.81));
    expect(distinctPlaces([a, b, c]), [a, c]);
  });
}

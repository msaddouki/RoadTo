import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Places the user saved (Maison, Travail…), kept on the phone and never
/// published. Like the other settings, Android keeps them out of cloud
/// backups (allowBackup is off) while iOS includes them in the device backup.
class Favorites extends ChangeNotifier {
  static const _key = 'favorites';

  /// Two places closer than this are the same favourite.
  static const sameM = 15.0;

  List<Place> _all;

  Favorites._(this._all);

  /// Newest first.
  List<Place> get all => List.unmodifiable(_all);

  static Future<Favorites> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      return Favorites._(raw == null ? [] : decode(raw));
    } catch (_) {
      return Favorites._([]);
    }
  }

  Place? find(LatLon at) {
    for (final f in _all) {
      if (distanceM(f.position, at) < sameM) return f;
    }
    return null;
  }

  bool contains(Place p) => find(p.position) != null;

  /// Saves [place], under [name] if given; replaces a favourite at the same spot.
  Future<void> add(Place place, {String? name}) async {
    final saved = Place(
      name: name ?? place.name,
      detail: place.detail,
      position: place.position,
      category: place.category,
    );
    _all = [saved, ..._all.where((f) => distanceM(f.position, place.position) >= sameM)];
    await _save();
  }

  Future<void> rename(Place favorite, String name) async {
    _all = [
      for (final f in _all)
        f == favorite ? Place(name: name, detail: f.detail, position: f.position, category: f.category) : f,
    ];
    await _save();
  }

  Future<void> remove(Place place) async {
    _all = _all.where((f) => distanceM(f.position, place.position) >= sameM).toList();
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, encode(_all));
  }

  static String encode(List<Place> places) => jsonEncode([
    for (final f in places)
      {
        'name': f.name,
        if (f.detail != null) 'detail': f.detail,
        'lat': f.position.lat,
        'lon': f.position.lon,
        if (f.category != null) 'category': f.category,
      },
  ]);

  /// Entries that cannot be read are dropped rather than losing them all.
  static List<Place> decode(String raw) {
    final out = <Place>[];
    try {
      for (final e in jsonDecode(raw) as List) {
        try {
          final m = e as Map<String, dynamic>;
          out.add(
            Place(
              name: m['name'] as String,
              detail: m['detail'] as String?,
              position: LatLon((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
              category: m['category'] as String?,
            ),
          );
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }
}

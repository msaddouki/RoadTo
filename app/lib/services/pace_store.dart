import 'dart:convert';

import 'package:roadto_core/roadto_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the driver's trips compare with the routing engine ([LearnedPace]),
/// kept on the phone like the other settings and never published.
abstract final class PaceStore {
  static const _key = 'learned_pace';

  static Future<LearnedPace> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null ? LearnedPace.none : LearnedPace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return LearnedPace.none;
    }
  }

  static Future<void> save(LearnedPace pace) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(pace.toJson()));
    } catch (_) {
      // Not saved: learned again from the next trips.
    }
  }

  static Future<void> clear() async {
    try {
      await (await SharedPreferences.getInstance()).remove(_key);
    } catch (_) {}
  }
}

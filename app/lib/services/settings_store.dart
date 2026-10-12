import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Réglages modifiables par l'utilisateur, stockés sur l'appareil seulement.
class AppSettings {
  final String mapStyle;
  final String routingUrl;
  final String geocoderUrl;
  final List<String> relays;
  final bool simulate;
  final double simulationSpeedKmh;
  final bool voice;

  const AppSettings({
    required this.mapStyle,
    required this.routingUrl,
    required this.geocoderUrl,
    required this.relays,
    required this.simulate,
    required this.simulationSpeedKmh,
    required this.voice,
  });

  factory AppSettings.defaults() => AppSettings(
    mapStyle: Defaults.mapStyle,
    routingUrl: Defaults.routingUrl,
    geocoderUrl: Defaults.geocoderUrl,
    relays: Defaults.relays,
    simulate: true,
    simulationSpeedKmh: Defaults.simulationSpeedKmh,
    voice: true,
  );

  AppSettings copyWith({
    String? mapStyle,
    String? routingUrl,
    String? geocoderUrl,
    List<String>? relays,
    bool? simulate,
    double? simulationSpeedKmh,
    bool? voice,
  }) => AppSettings(
    mapStyle: mapStyle ?? this.mapStyle,
    routingUrl: routingUrl ?? this.routingUrl,
    geocoderUrl: geocoderUrl ?? this.geocoderUrl,
    relays: relays ?? this.relays,
    simulate: simulate ?? this.simulate,
    simulationSpeedKmh: simulationSpeedKmh ?? this.simulationSpeedKmh,
    voice: voice ?? this.voice,
  );
}

class SettingsStore {
  static Future<AppSettings> load() async {
    final d = AppSettings.defaults();
    try {
      final p = await SharedPreferences.getInstance();
      return AppSettings(
        mapStyle: p.getString('mapStyle') ?? d.mapStyle,
        routingUrl: p.getString('routingUrl') ?? d.routingUrl,
        geocoderUrl: p.getString('geocoderUrl') ?? d.geocoderUrl,
        relays: p.getStringList('relays') ?? d.relays,
        // La simulation est active par défaut : on teste d'abord sans conduire.
        simulate: p.getBool('simulate') ?? d.simulate,
        simulationSpeedKmh: p.getDouble('simulationSpeedKmh') ?? d.simulationSpeedKmh,
        voice: p.getBool('voice') ?? d.voice,
      );
    } catch (_) {
      return d;
    }
  }

  static Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('mapStyle', s.mapStyle);
    await p.setString('routingUrl', s.routingUrl);
    await p.setString('geocoderUrl', s.geocoderUrl);
    await p.setStringList('relays', s.relays);
    await p.setBool('simulate', s.simulate);
    await p.setDouble('simulationSpeedKmh', s.simulationSpeedKmh);
    await p.setBool('voice', s.voice);
  }
}

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// When the offline map switches to its night colours.
enum NightMap {
  /// Between sunset and sunrise where the car is.
  auto,
  always,
  never;

  static NightMap parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => auto);
}

/// Réglages modifiables par l'utilisateur, stockés sur l'appareil seulement.
class AppSettings {
  final String mapStyle;
  final String routingUrl;
  final String geocoderUrl;
  final List<String> relays;
  final bool simulate;
  final double simulationSpeedKmh;
  final bool voice;

  /// Use the installed region's offline map instead of online tiles.
  final bool offlineMap;

  final NightMap nightMap;

  /// Fuel whose price is shown in the fuel search (a key of `fuelLabels`).
  final String fuel;

  const AppSettings({
    required this.mapStyle,
    required this.routingUrl,
    required this.geocoderUrl,
    required this.relays,
    required this.simulate,
    required this.simulationSpeedKmh,
    required this.voice,
    required this.offlineMap,
    this.nightMap = NightMap.auto,
    this.fuel = 'gazole',
  });

  factory AppSettings.defaults() => AppSettings(
    mapStyle: Defaults.mapStyle,
    routingUrl: Defaults.routingUrl,
    geocoderUrl: Defaults.geocoderUrl,
    relays: Defaults.relays,
    simulate: true,
    simulationSpeedKmh: Defaults.simulationSpeedKmh,
    voice: true,
    offlineMap: true,
    nightMap: NightMap.auto,
    fuel: 'gazole',
  );

  AppSettings copyWith({
    String? mapStyle,
    String? routingUrl,
    String? geocoderUrl,
    List<String>? relays,
    bool? simulate,
    double? simulationSpeedKmh,
    bool? voice,
    bool? offlineMap,
    NightMap? nightMap,
    String? fuel,
  }) => AppSettings(
    mapStyle: mapStyle ?? this.mapStyle,
    routingUrl: routingUrl ?? this.routingUrl,
    geocoderUrl: geocoderUrl ?? this.geocoderUrl,
    relays: relays ?? this.relays,
    simulate: simulate ?? this.simulate,
    simulationSpeedKmh: simulationSpeedKmh ?? this.simulationSpeedKmh,
    voice: voice ?? this.voice,
    offlineMap: offlineMap ?? this.offlineMap,
    nightMap: nightMap ?? this.nightMap,
    fuel: fuel ?? this.fuel,
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
        offlineMap: p.getBool('offlineMap') ?? d.offlineMap,
        nightMap: NightMap.parse(p.getString('nightMap')),
        fuel: p.getString('fuel') ?? d.fuel,
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
    await p.setBool('offlineMap', s.offlineMap);
    await p.setString('nightMap', s.nightMap.name);
    await p.setString('fuel', s.fuel);
  }
}

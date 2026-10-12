import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:roadto_core/roadto_core.dart';

/// Position courante, réelle ou simulée.
class Fix {
  final LatLon position;
  final double? bearingDeg;
  final double speedMps;

  const Fix(this.position, {this.bearingDeg, this.speedMps = 0});
}

enum LocationAvailability { ok, serviceDisabled, denied, deniedForever }

/// Localisation par les API standard du système. Sur Android, on force le
/// LocationManager : pas de dépendance aux services Google à l'exécution.
class DeviceLocation {
  static Future<LocationAvailability> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationAvailability.serviceDisabled;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.denied => LocationAvailability.denied,
      LocationPermission.deniedForever => LocationAvailability.deniedForever,
      _ => LocationAvailability.ok,
    };
  }

  static LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        forceLocationManager: true,
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        // Pas de localisation en arrière-plan dans le POC.
        allowBackgroundLocationUpdates: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  static Stream<Fix> stream() => Geolocator.getPositionStream(locationSettings: _settings()).map(
    (p) => Fix(
      LatLon(p.latitude, p.longitude),
      bearingDeg: p.speed > 1 && p.heading >= 0 ? p.heading : null,
      speedMps: p.speed < 0 ? 0 : p.speed,
    ),
  );
}

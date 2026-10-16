import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:geolocator_apple/geolocator_apple.dart';
import 'package:roadto_core/roadto_core.dart';

/// Current position, real or simulated.
class Fix {
  final LatLon position;
  final double? bearingDeg;
  final double speedMps;

  const Fix(this.position, {this.bearingDeg, this.speedMps = 0});
}

enum LocationAvailability { ok, serviceDisabled, denied, deniedForever }

/// Position from the system's own APIs: Android's LocationManager through
/// [AndroidLocation] (no Google Play Services), Core Location on iOS.
abstract final class DeviceLocation {
  static Future<LocationAvailability> ensurePermission() =>
      Platform.isAndroid ? AndroidLocation.ensurePermission() : _AppleLocation.ensurePermission();

  /// [background]: iOS keeps sending fixes with the app in the background
  /// (blue indicator in the status bar). Android keeps its own behaviour.
  static Stream<Fix> stream({bool background = false}) =>
      Platform.isAndroid ? AndroidLocation.stream() : _AppleLocation.stream(background: background);
}

/// Android side, implemented in MainActivity (DeviceLocation.kt).
abstract final class AndroidLocation {
  static const methods = MethodChannel('org.roadto/location');
  static const fixes = EventChannel('org.roadto/location/fixes');

  static Future<LocationAvailability> ensurePermission() async {
    final status = await methods.invokeMapMethod<String, Object?>('status') ?? const {};
    if (status['service'] != true) return LocationAvailability.serviceDisabled;
    if (status['permission'] == 'granted') return LocationAvailability.ok;
    return switch (await methods.invokeMethod<String>('request')) {
      'granted' => LocationAvailability.ok,
      'deniedForever' => LocationAvailability.deniedForever,
      _ => LocationAvailability.denied,
    };
  }

  static Stream<Fix> stream() => fixes.receiveBroadcastStream().map((e) => fixFromMap(e as Map));

  /// A fix sent by the platform. Speed, bearing and accuracy are -1 when
  /// unknown. The bearing is only trusted while moving.
  static Fix fixFromMap(Map<Object?, Object?> m) {
    final speed = (m['speed'] as num?)?.toDouble() ?? -1;
    final bearing = (m['bearing'] as num?)?.toDouble() ?? -1;
    return Fix(
      LatLon((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
      bearingDeg: speed > 1 && bearing >= 0 ? bearing : null,
      speedMps: speed < 0 ? 0 : speed,
    );
  }
}

/// iOS: geolocator's Apple implementation only, so the Android build does not
/// pull geolocator_android and Google Play Services.
abstract final class _AppleLocation {
  static final _platform = GeolocatorApple();

  static Future<LocationAvailability> ensurePermission() async {
    if (!await _platform.isLocationServiceEnabled()) return LocationAvailability.serviceDisabled;
    var p = await _platform.checkPermission();
    if (p == LocationPermission.denied) p = await _platform.requestPermission();
    return switch (p) {
      LocationPermission.denied => LocationAvailability.denied,
      LocationPermission.deniedForever => LocationAvailability.deniedForever,
      _ => LocationAvailability.ok,
    };
  }

  static Stream<Fix> stream({required bool background}) => _platform
      .getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          // Only while navigating: guidance, voice and the Live Activity go
          // on with the screen locked; the indicator shows it.
          allowBackgroundLocationUpdates: background,
          showBackgroundLocationIndicator: background,
        ),
      )
      .map(
        (p) => Fix(
          LatLon(p.latitude, p.longitude),
          bearingDeg: p.speed > 1 && p.heading >= 0 ? p.heading : null,
          speedMps: p.speed < 0 ? 0 : p.speed,
        ),
      );
}

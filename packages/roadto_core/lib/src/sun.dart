import 'dart:math' as math;

import 'geo.dart';

/// Elevation of the sun above the horizon, in degrees, at [where] and [at]
/// (NOAA's low-precision formulas, within about half a degree). Works
/// offline: the night map switches from the position alone.
double sunElevationDeg(LatLon where, DateTime at) {
  const rad = math.pi / 180;
  // Days since J2000.0 (2000-01-01 12:00 UTC).
  final n = at.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5 - 2451545.0;
  final meanLongitude = (280.460 + 0.9856474 * n) % 360;
  final meanAnomaly = ((357.528 + 0.9856003 * n) % 360) * rad;
  final eclipticLongitude = (meanLongitude + 1.915 * math.sin(meanAnomaly) + 0.020 * math.sin(2 * meanAnomaly)) * rad;
  final obliquity = (23.439 - 0.0000004 * n) * rad;
  final declination = math.asin(math.sin(obliquity) * math.sin(eclipticLongitude));
  final rightAscension = math.atan2(math.cos(obliquity) * math.sin(eclipticLongitude), math.cos(eclipticLongitude));
  final siderealDeg = (280.46061837 + 360.98564736629 * n + where.lon) % 360;
  final hourAngle = siderealDeg * rad - rightAscension;
  final lat = where.lat * rad;
  final sinElevation =
      math.sin(lat) * math.sin(declination) + math.cos(lat) * math.cos(declination) * math.cos(hourAngle);
  return math.asin(sinElevation.clamp(-1.0, 1.0)) / rad;
}

/// Between sunset and sunrise (sun's upper edge below the horizon, with
/// atmospheric refraction: -0.833°).
bool isNight(LatLon where, DateTime at) => sunElevationDeg(where, at) < -0.833;

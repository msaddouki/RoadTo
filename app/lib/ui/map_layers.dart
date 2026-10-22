import 'dart:math';

import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

/// Couleurs des alertes : teintes distinctes et luminosités différentes, pour
/// rester lisibles par les personnes daltoniennes et de nuit.
const alertColors = {
  AlertType.accident: Color(0xFFFF5A5F),
  AlertType.traffic: Color(0xFFFF9F1C),
  AlertType.hazard: Color(0xFFFFE066),
  AlertType.closure: Color(0xFFB794F6),
  AlertType.roadworks: Color(0xFF4CC9F0),
  AlertType.police: Color(0xFF6C8CFF),
};

const alertIcons = {
  AlertType.accident: Icons.car_crash,
  AlertType.traffic: Icons.traffic,
  AlertType.hazard: Icons.warning_amber_rounded,
  AlertType.closure: Icons.block,
  AlertType.roadworks: Icons.construction,
  AlertType.police: Icons.local_police,
};

String hexColor(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

List<double> _coords(LatLon p) => [p.lon, p.lat];

Map<String, dynamic> featureCollection(List<Map<String, dynamic>> features) => {
  'type': 'FeatureCollection',
  'features': features,
};

/// Tracé de l'itinéraire, découpé en partie parcourue et partie restante.
Map<String, dynamic> routeGeoJson(TripRoute? route, {double alongM = 0}) {
  if (route == null || route.shape.length < 2) return featureCollection(const []);
  final split = alongM.clamp(0.0, route.shapeLengthM);
  final done = <List<double>>[];
  final todo = <List<double>>[];
  for (var i = 0; i < route.shape.length; i++) {
    (route.cumulative[i] <= split ? done : todo).add(_coords(route.shape[i]));
  }
  final cut = _coords(route.pointAt(split));
  done.add(cut);
  todo.insert(0, cut);
  return featureCollection([
    if (done.length >= 2)
      {
        'type': 'Feature',
        'id': 1,
        'properties': {'part': 'done'},
        'geometry': {'type': 'LineString', 'coordinates': done},
      },
    if (todo.length >= 2)
      {
        'type': 'Feature',
        'id': 2,
        'properties': {'part': 'todo'},
        'geometry': {'type': 'LineString', 'coordinates': todo},
      },
  ]);
}

Map<String, dynamic> pointGeoJson(LatLon? p, {Map<String, dynamic> properties = const {}}) => featureCollection([
  if (p != null)
    {
      'type': 'Feature',
      'id': 1,
      'properties': properties,
      'geometry': {'type': 'Point', 'coordinates': _coords(p)},
    },
]);

Map<String, dynamic> alertsGeoJson(Iterable<RoadAlert> alerts) => featureCollection([
  for (final (i, a) in alerts.indexed)
    {
      'type': 'Feature',
      'id': i + 1,
      'properties': {
        'alertId': a.id,
        'type': a.type.code,
        'label': a.headline,
        'color': hexColor(alertColors[a.type]!),
      },
      'geometry': {'type': 'Point', 'coordinates': _coords(a.position)},
    },
]);

/// Jammed stretches, from the traffic robot ([RoadAlert.shape]), in their
/// level's colour: orange when slow, red when jammed, dark red when stopped.
Map<String, dynamic> jamsGeoJson(Iterable<RoadAlert> alerts) => featureCollection([
  for (final a in alerts)
    if (a.shape case final shape? when a.level != null)
      {
        'type': 'Feature',
        'properties': {'color': a.level!.color, 'level': a.level!.code},
        'geometry': {
          'type': 'LineString',
          'coordinates': [for (final p in shape) _coords(p)],
        },
      },
]);

/// Empty layer of RoadTo's style right under its labels: the route is drawn
/// under it, so it never covers a name (pipeline/roadto_pipeline/drive_style.py).
const labelsMarkerLayer = 'roadto-labels';

/// Street name layers shown during a trip only (level, in bubbles); each
/// replaces the layer of the same name without the suffix.
const navLabelSuffix = '-nav';

/// Which label layers to show or hide for [navigating], among the style's
/// [layerIds]. Empty for styles without navigation labels (online ones).
Map<String, bool> labelVisibility(Iterable<String> layerIds, {required bool navigating}) {
  final ids = layerIds.toSet();
  return {
    for (final id in ids)
      if (id.endsWith(navLabelSuffix)) id: navigating else if (ids.contains('$id$navLabelSuffix')) id: !navigating,
  };
}

/// South, west, north and east edges around [shape], widened to at least
/// [minSpanM] each way so a short trip shows its neighbourhood instead of
/// zooming in on a few streets.
({double s, double w, double n, double e}) routeBounds(List<LatLon> shape, {double minSpanM = 1500}) {
  var s = shape.first.lat, n = s, w = shape.first.lon, e = w;
  for (final p in shape) {
    if (p.lat < s) s = p.lat;
    if (p.lat > n) n = p.lat;
    if (p.lon < w) w = p.lon;
    if (p.lon > e) e = p.lon;
  }
  const mPerDegLat = 111320.0;
  final mPerDegLon = mPerDegLat * cos((s + n) / 2 * pi / 180);
  final minLat = minSpanM / mPerDegLat, minLon = minSpanM / mPerDegLon;
  if (n - s < minLat) {
    final c = (s + n) / 2;
    s = c - minLat / 2;
    n = c + minLat / 2;
  }
  if (e - w < minLon) {
    final c = (w + e) / 2;
    w = c - minLon / 2;
    e = c + minLon / 2;
  }
  return (s: s, w: w, n: n, e: e);
}

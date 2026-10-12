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
        'label': a.type.label,
        'color': hexColor(alertColors[a.type]!),
      },
      'geometry': {'type': 'Point', 'coordinates': _coords(a.position)},
    },
]);

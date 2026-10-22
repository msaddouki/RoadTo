import '../geo.dart';
import 'route.dart';
import 'speed_limits.dart';

/// What the road shows along a route besides its limits, for guidance as
/// Waze and Google Maps give it: the traffic lights ("au feu, tournez à
/// gauche"), the streets off it ("prenez la 2e à droite") and the lanes to
/// take before a turn.
///
/// From the routing engine, on the route's own shape: `trace_attributes`
/// for the limits, lights and side streets ([roadAttributesRequest]),
/// `trace_route` in OSRM form for the lanes ([lanesRequest]), which
/// Valhalla's own answers leave out.
class RoadDetails {
  final SpeedLimits speedLimits;

  /// Traffic lights, metres from the start of the route, in order. The
  /// lights of one junction (a crossing before it, each carriageway) count
  /// as one, at the last of them.
  final List<double> signalsM;

  /// Junctions with a street the car could take off the route, in order.
  final List<SideRoads> sideRoads;

  /// Lanes before the turns where only some of them lead the right way.
  final List<LaneGuide> lanes;

  const RoadDetails({
    this.speedLimits = SpeedLimits.none,
    this.signalsM = const [],
    this.sideRoads = const [],
    this.lanes = const [],
  });

  static const none = RoadDetails();

  RoadDetails withLanes(List<LaneGuide> lanes) =>
      RoadDetails(speedLimits: speedLimits, signalsM: signalsM, sideRoads: sideRoads, lanes: lanes);
}

/// A junction of the route, with streets off it on the left, the right or
/// both. A divided road's two carriageways make one junction.
class SideRoads {
  final double alongM;
  final bool left;
  final bool right;

  const SideRoads(this.alongM, {this.left = false, this.right = false});
}

/// One lane, left to right across the road: its arrows (OSRM indications:
/// "left", "slight left", "straight", "right", "uturn"…) and whether it
/// leads where the route goes.
class Lane {
  final List<String> directions;
  final bool valid;

  /// The one Valhalla recommends among the valid ones.
  final bool preferred;

  /// The arrow to draw: the way the route goes on a valid lane, else the
  /// lane's first arrow.
  final String arrow;

  const Lane(this.directions, {required this.valid, this.preferred = false, required this.arrow});
}

/// The lanes painted before a junction of the route.
class LaneGuide {
  final double alongM;
  final List<Lane> lanes;

  const LaneGuide(this.alongM, this.lanes);

  /// Which lanes to take, for the voice: "la voie de gauche", "les deux
  /// voies de droite"; null when any lane will do or the right ones are not
  /// side by side.
  String? get hint {
    final valid = [
      for (var i = 0; i < lanes.length; i++)
        if (lanes[i].valid) i,
    ];
    if (lanes.length < 2 || valid.isEmpty || valid.length == lanes.length) return null;
    if (valid.last - valid.first + 1 != valid.length) return null;
    final side = valid.first == 0
        ? 'de gauche'
        : valid.last == lanes.length - 1
        ? 'de droite'
        : 'du milieu';
    final n = valid.length;
    return n == 1 ? 'la voie $side' : 'les ${_numbers[n] ?? '$n'} voies $side';
  }

  static const _numbers = {2: 'deux', 3: 'trois', 4: 'quatre'};
}

/// Valhalla `trace_attributes` request for the speed limits, traffic lights
/// and side streets along [route]. `edge_walk` follows the shape edge by
/// edge, which is exact and fast for a shape that Valhalla produced itself.
Map<String, dynamic> roadAttributesRequest(TripRoute route) => {
  'encoded_polyline': encodePolyline(route.shape),
  'costing': 'auto',
  'shape_match': 'edge_walk',
  'units': 'kilometers',
  'filters': {
    'attributes': [
      'edge.speed_limit',
      'edge.begin_shape_index',
      'edge.end_shape_index',
      'shape',
      'edge.traffic_signal',
      'edge.end_heading',
      'node.intersecting_edge.begin_heading',
      'node.intersecting_edge.driveability',
      'node.intersecting_edge.use',
    ],
    'action': 'include',
  },
};

/// Valhalla `trace_route` request on [route]'s shape, answered in OSRM form:
/// the only one with the lanes.
Map<String, dynamic> lanesRequest(TripRoute route, {String language = 'fr-FR'}) => {
  'encoded_polyline': encodePolyline(route.shape),
  'costing': 'auto',
  'shape_match': 'edge_walk',
  'units': 'kilometers',
  'format': 'osrm',
  'language': language,
};

/// Streets a driver counts: not car parks, service roads, cycle paths or
/// pedestrian crossings.
const _streets = {'road', 'living_street'};

/// Reads a `trace_attributes` answer ([roadAttributesRequest]). A traffic
/// light on an edge is at its end.
RoadDetails parseRoadAttributes(Map<String, dynamic> json) {
  final limits = parseSpeedLimits(json);
  final encoded = json['shape'] as String?;
  final edges = json['edges'] as List?;
  if (encoded == null || edges == null) return RoadDetails(speedLimits: limits);
  final shape = decodePolyline(encoded);
  if (shape.length < 2) return RoadDetails(speedLimits: limits);
  final cumulative = List<double>.filled(shape.length, 0);
  for (var i = 1; i < shape.length; i++) {
    cumulative[i] = cumulative[i - 1] + distanceM(shape[i - 1], shape[i]);
  }
  double at(Object? index) => cumulative[((index as num?)?.toInt() ?? 0).clamp(0, shape.length - 1)];

  final signals = <double>[];
  final junctions = <SideRoads>[];
  for (final e in edges.cast<Map<String, dynamic>>()) {
    final end = at(e['end_shape_index']);
    if (e['traffic_signal'] == true) signals.add(end);
    final heading = e['end_heading'];
    final node = e['end_node'];
    if (heading is! num || node is! Map) continue;
    var left = false, right = false;
    for (final x in (node['intersecting_edges'] as List? ?? const []).whereType<Map>()) {
      final d = x['driveability'], h = x['begin_heading'];
      if (!_streets.contains(x['use']) || (d != 'forward' && d != 'both') || h is! num) continue;
      // From the way the car comes: negative to the left.
      final turn = (h - heading + 540) % 360 - 180;
      if (turn <= -30 && turn >= -150) left = true;
      if (turn >= 30 && turn <= 150) right = true;
    }
    if (left || right) junctions.add(SideRoads(end, left: left, right: right));
  }
  return RoadDetails(speedLimits: limits, signalsM: _mergeSignals(signals), sideRoads: _mergeJunctions(junctions));
}

/// Lights less than this apart are the same junction's.
const _signalSpanM = 40.0;

/// Nodes less than this apart are one junction (a divided road).
const _junctionSpanM = 30.0;

List<double> _mergeSignals(List<double> along) {
  final sorted = [...along]..sort();
  final out = <double>[];
  double? first;
  for (final d in sorted) {
    if (first != null && d - first <= _signalSpanM) {
      out[out.length - 1] = d;
    } else {
      first = d;
      out.add(d);
    }
  }
  return out;
}

List<SideRoads> _mergeJunctions(List<SideRoads> junctions) {
  final out = <SideRoads>[];
  for (final j in junctions) {
    final last = out.isEmpty ? null : out.last;
    if (last != null && j.alongM - last.alongM <= _junctionSpanM) {
      out[out.length - 1] = SideRoads(last.alongM, left: last.left || j.left, right: last.right || j.right);
    } else {
      out.add(j);
    }
  }
  return out;
}

/// Reads a `trace_route` answer in OSRM form ([lanesRequest]): the lanes at
/// each junction where only some of them lead the right way, placed on
/// [route].
List<LaneGuide> parseLanes(Map<String, dynamic> json, TripRoute route) {
  final out = <LaneGuide>[];
  for (final matching in (json['matchings'] as List? ?? const []).whereType<Map>()) {
    for (final leg in (matching['legs'] as List? ?? const []).whereType<Map>()) {
      for (final step in (leg['steps'] as List? ?? const []).whereType<Map>()) {
        for (final x in (step['intersections'] as List? ?? const []).whereType<Map>()) {
          final raw = x['lanes'], location = x['location'];
          if (raw is! List || location is! List || location.length < 2) continue;
          final lanes = [
            for (final l in raw.whereType<Map>())
              Lane(
                [for (final d in (l['indications'] as List? ?? const [])) '$d'],
                valid: l['valid'] == true,
                preferred: l['active'] == true,
                arrow: '${l['valid'] == true ? (l['valid_indication'] ?? _first(l)) : _first(l)}',
              ),
          ];
          if (lanes.length < 2 || lanes.every((l) => l.valid) || !lanes.any((l) => l.valid)) continue;
          final p = projectOnRoute(route, LatLon((location[1] as num).toDouble(), (location[0] as num).toDouble()));
          if (p == null || p.offsetM > 20) continue;
          out.add(LaneGuide(p.alongM, lanes));
        }
      }
    }
  }
  out.sort((a, b) => a.alongM.compareTo(b.alongM));
  return out;
}

Object _first(Map<dynamic, dynamic> lane) => (lane['indications'] as List?)?.firstOrNull ?? 'straight';

/// How a turn is told with the road's landmarks: "Au feu", "2e à gauche".
class TurnCue {
  /// For the banner: "Au feu", "Au 2e feu", "2e à gauche".
  final String label;

  /// Said before the maneuver's words: "Au feu", "Au deuxième feu".
  final String? _lead;

  /// The ordinal that replaces "Tournez" for a street count ("deuxième").
  final String? _nth;

  const TurnCue._(this.label, this._lead, this._nth);

  /// Told with a traffic light rather than a count of streets.
  bool get atLight => _lead != null;

  /// [text] (Valhalla's words for the turn) with the cue: "Au feu, tournez
  /// à gauche dans Rue X." or "Prenez la deuxième à gauche dans Rue X.".
  String spoken(String text) {
    if (_lead case final lead?) return '$lead, ${text.isEmpty ? text : text[0].toLowerCase() + text.substring(1)}';
    return text.replaceFirstMapped(RegExp(r'^Tournez à (gauche|droite)'), (m) => 'Prenez la $_nth à ${m[1]}');
  }
}

const _ordinals = {2: ('2e', 'deuxième'), 3: ('3e', 'troisième')};

/// Turns told with a traffic light: left and right, slight, sharp, U-turns.
const _turns = {9, 10, 11, 12, 13, 14, 15, 16};

/// The cue for maneuver [index] of [route] seen from [alongM]: the light at
/// the turn, counted from here ("Au 2e feu"), else the street, counted
/// from here on the side of the turn ("2e à gauche"). Up to the third
/// only: past that a driver counts wrong, and so might the map.
TurnCue? turnCue(TripRoute route, RoadDetails details, int index, double alongM) {
  if (index < 0 || index >= route.maneuvers.length) return null;
  final type = route.maneuvers[index].type;
  if (!_turns.contains(type)) return null;
  final turnM = route.maneuverStartM(index);

  // The turn's light: at the junction or just before it (the stop line).
  final light = details.signalsM.indexWhere((s) => s >= turnM - 50 && s <= turnM + 10);
  if (light >= 0) {
    final before = details.signalsM.take(light).where((s) => s > alongM).length;
    if (before == 0) return const TurnCue._('Au feu', 'Au feu', null);
    if (_ordinals[before + 1] case (final short, final long)) return TurnCue._('Au $short feu', 'Au $long feu', null);
    return null;
  }

  // Plain left and right only: a slight turn is not "the 2nd".
  if (type != 10 && type != 15) return null;
  final left = type == 15;
  final before = details.sideRoads
      .where((j) => j.alongM > alongM + 5 && j.alongM < turnM - _junctionSpanM - 5 && (left ? j.left : j.right))
      .length;
  if (_ordinals[before + 1] case (final short, final long)) {
    return TurnCue._('$short à ${left ? 'gauche' : 'droite'}', null, long);
  }
  return null;
}

/// The lanes to take for maneuver [index]: those painted at its junction.
LaneGuide? lanesFor(TripRoute route, RoadDetails details, int index) {
  if (index < 0 || index >= route.maneuvers.length || route.maneuvers[index].isArrival) return null;
  final turnM = route.maneuverStartM(index);
  LaneGuide? best;
  for (final g in details.lanes) {
    final gap = (g.alongM - turnM).abs();
    if (gap <= 20 && (best == null || gap < (best.alongM - turnM).abs())) best = g;
  }
  return best;
}

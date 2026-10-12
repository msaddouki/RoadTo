import '../geo.dart';

/// Une manœuvre de l'itinéraire (tourner, sortir, arriver…).
class Maneuver {
  /// Type Valhalla (4 = arrivée, 1–3 = départ, etc.).
  final int type;
  final String instruction;

  /// Annonce vocale longue, à quelques centaines de mètres.
  final String? verbalAlert;

  /// Annonce vocale juste avant la manœuvre.
  final String? verbalPre;

  /// Annonce vocale après la manœuvre (« continuez sur 2 km »).
  final String? verbalPost;
  final List<String> streetNames;

  /// Indice, dans la géométrie de l'itinéraire, du point où commence la manœuvre.
  final int beginShapeIndex;
  final double lengthM;
  final double timeS;

  const Maneuver({
    required this.type,
    required this.instruction,
    required this.beginShapeIndex,
    required this.lengthM,
    required this.timeS,
    this.verbalAlert,
    this.verbalPre,
    this.verbalPost,
    this.streetNames = const [],
  });

  bool get isArrival => type >= 4 && type <= 6;
}

/// Itinéraire calculé, indépendant du moteur de routage.
class TripRoute {
  final List<LatLon> shape;
  final List<Maneuver> maneuvers;
  final double lengthM;
  final double timeS;

  /// Distance cumulée depuis le départ, pour chaque point de [shape].
  late final List<double> cumulative = _cumulative(shape);

  TripRoute({required this.shape, required this.maneuvers, required this.lengthM, required this.timeS});

  static List<double> _cumulative(List<LatLon> shape) {
    final out = List<double>.filled(shape.length, 0);
    for (var i = 1; i < shape.length; i++) {
      out[i] = out[i - 1] + distanceM(shape[i - 1], shape[i]);
    }
    return out;
  }

  /// Longueur géométrique de la trace (peut différer de [lengthM] de
  /// quelques mètres).
  double get shapeLengthM => cumulative.isEmpty ? 0 : cumulative.last;

  /// Distance depuis le départ du début de la manœuvre [i].
  double maneuverStartM(int i) => cumulative[maneuvers[i].beginShapeIndex.clamp(0, shape.length - 1)];

  /// Point situé à [d] mètres du départ le long de la trace.
  LatLon pointAt(double d) {
    if (shape.isEmpty) throw StateError('Itinéraire vide');
    if (d <= 0) return shape.first;
    if (d >= shapeLengthM) return shape.last;
    var lo = 0, hi = cumulative.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      cumulative[mid] <= d ? lo = mid : hi = mid;
    }
    final seg = cumulative[hi] - cumulative[lo];
    return interpolate(shape[lo], shape[hi], seg == 0 ? 0 : (d - cumulative[lo]) / seg);
  }

  /// Cap de la route à [d] mètres du départ.
  double bearingAt(double d) {
    final a = pointAt(d);
    final b = pointAt(d + 15);
    return a == b ? bearingDeg(pointAt(d - 15), a) : bearingDeg(a, b);
  }
}

/// Projection d'une position sur un itinéraire.
class RouteProjection {
  final int segmentIndex;
  final LatLon point;

  /// Distance depuis le départ du point projeté.
  final double alongM;

  /// Écart latéral entre la position et la route.
  final double offsetM;

  const RouteProjection(this.segmentIndex, this.point, this.alongM, this.offsetM);
}

/// Projette [p] sur les segments [from]..[to] (exclu) de [route].
RouteProjection? projectOnRoute(TripRoute route, LatLon p, {int from = 0, int? to}) {
  final shape = route.shape;
  if (shape.length < 2) return null;
  final end = (to ?? shape.length - 1).clamp(1, shape.length - 1);
  RouteProjection? best;
  for (var i = from.clamp(0, shape.length - 2); i < end; i++) {
    final proj = projectOnSegment(p, shape[i], shape[i + 1]);
    if (best == null || proj.distanceM < best.offsetM) {
      final segLen = route.cumulative[i + 1] - route.cumulative[i];
      best = RouteProjection(i, proj.point, route.cumulative[i] + proj.fraction * segLen, proj.distanceM);
    }
  }
  return best;
}

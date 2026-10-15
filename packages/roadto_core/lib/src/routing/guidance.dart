import '../alerts.dart';
import '../geo.dart';
import 'route.dart';

/// État du guidage après une nouvelle position.
class GuidanceState {
  final RouteProjection projection;

  /// Manœuvre à venir (la prochaine action du conducteur).
  final Maneuver? nextManeuver;
  final int? nextManeuverIndex;
  final double distanceToNextM;
  final double remainingM;
  final Duration remaining;
  final bool offRoute;
  final bool arrived;

  /// Phrase à prononcer maintenant, s'il y en a une.
  final String? announcement;

  const GuidanceState({
    required this.projection,
    required this.nextManeuver,
    required this.nextManeuverIndex,
    required this.distanceToNextM,
    required this.remainingM,
    required this.remaining,
    required this.offRoute,
    required this.arrived,
    this.announcement,
  });

  DateTime eta(DateTime now) => now.add(remaining);
}

/// Suit la progression sur un itinéraire : manœuvre suivante, distance,
/// temps restant, sortie de route et annonces vocales.
///
/// Remplaçable par Ferrostar au jalon J2 ; l'interface côté app restera
/// la même.
class GuidanceEngine {
  final TripRoute route;

  /// Écart au-delà duquel une position compte comme hors route.
  final double offRouteThresholdM;

  /// Positions hors route consécutives avant de déclarer la sortie de route.
  final int offRouteConfirmations;
  final double arrivalThresholdM;

  int _segmentHint = 0;
  int _offRouteCount = 0;
  bool _started = false;
  final _announced = <String>{};

  GuidanceEngine(
    this.route, {
    this.offRouteThresholdM = 40,
    this.offRouteConfirmations = 3,
    this.arrivalThresholdM = 25,
  });

  GuidanceState update(LatLon position, {double speedMps = 0}) {
    // On cherche d'abord près du dernier segment connu, pour ne pas sauter
    // sur une portion parallèle ou repassant au même endroit.
    var proj = projectOnRoute(route, position, from: _segmentHint - 2, to: _segmentHint + 60);
    if (proj == null || proj.offsetM > offRouteThresholdM) {
      final global = projectOnRoute(route, position);
      if (global != null && (proj == null || global.offsetM < proj.offsetM)) proj = global;
    }
    if (proj == null) throw StateError('Itinéraire vide');

    final off = proj.offsetM > offRouteThresholdM;
    _offRouteCount = off ? _offRouteCount + 1 : 0;
    if (!off) _segmentHint = proj.segmentIndex;

    final along = proj.alongM;
    final remainingM = (route.shapeLengthM - along).clamp(0.0, double.infinity);
    final arrived = remainingM <= arrivalThresholdM && !off;

    int? nextIdx;
    for (var i = 0; i < route.maneuvers.length; i++) {
      if (route.maneuverStartM(i) > along + 3) {
        nextIdx = i;
        break;
      }
    }
    final next = nextIdx == null ? null : route.maneuvers[nextIdx];
    final distanceToNext = nextIdx == null ? remainingM : route.maneuverStartM(nextIdx) - along;

    // Temps restant : au prorata de la distance, avec la vitesse prévue par
    // le moteur de routage.
    final ratio = route.shapeLengthM == 0 ? 0 : remainingM / route.shapeLengthM;
    final remaining = Duration(seconds: (route.timeS * ratio).round());

    String? say;
    if (!_started) {
      _started = true;
      final first = route.maneuvers.isEmpty ? null : route.maneuvers.first;
      say = first?.verbalPre ?? first?.instruction;
      _announced.add('0:pre');
    } else if (arrived) {
      if (_announced.add('arrived')) {
        say = route.maneuvers.isNotEmpty && route.maneuvers.last.isArrival
            ? (route.maneuvers.last.verbalPre ?? route.maneuvers.last.instruction)
            : 'Vous êtes arrivé.';
      }
    } else if (next != null && nextIdx != null && !off) {
      // Annonce proche : ~8 s avant, au moins 60 m, au plus 250 m.
      final nearM = (speedMps * 8).clamp(60.0, 250.0);
      if (distanceToNext <= nearM) {
        // The arrival is said once, when the car is there (above), not also
        // as the close announcement of the arrival maneuver.
        if (!next.isArrival && _announced.add('$nextIdx:pre')) say = next.verbalPre ?? next.instruction;
      } else if (distanceToNext <= 600 && distanceToNext > nearM + 150) {
        if (_announced.add('$nextIdx:alert')) {
          // Valhalla often has no alert text for the arrival, and its
          // instruction ("Vous êtes arrivé") would read wrong after "Dans 500 m".
          final text = next.verbalAlert ?? (next.isArrival ? 'vous arrivez à destination' : next.instruction);
          say = 'Dans ${_roundDistance(distanceToNext)}, ${_lowerFirst(text)}';
        }
      }
    }

    return GuidanceState(
      projection: proj,
      nextManeuver: next,
      nextManeuverIndex: nextIdx,
      distanceToNextM: distanceToNext,
      remainingM: remainingM,
      remaining: remaining,
      offRoute: _offRouteCount >= offRouteConfirmations,
      arrived: arrived,
      announcement: say,
    );
  }
}

String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

String _roundDistance(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} kilomètres';
  final step = m >= 200 ? 100 : 50;
  return '${((m / step).round() * step)} mètres';
}

/// Format court d'une distance pour l'affichage (« 350 m », « 2,4 km »).
String formatDistance(double m) {
  if (m >= 10000) return '${(m / 1000).round()} km';
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  if (m >= 100) return '${((m / 10).round() * 10)} m';
  return '${m.round()} m';
}

/// Alerte située sur l'itinéraire, devant le conducteur.
class AlertAhead {
  final RoadAlert alert;
  final double distanceM;

  const AlertAhead(this.alert, this.distanceM);
}

/// Alertes à moins de [maxOffsetM] de la route et devant [alongM], triées par
/// distance.
List<AlertAhead> alertsAhead(
  TripRoute route,
  double alongM,
  Iterable<RoadAlert> alerts, {
  double maxOffsetM = 120,
  double horizonM = 5000,
}) {
  final out = <AlertAhead>[];
  for (final a in alerts) {
    final p = projectOnRoute(route, a.position);
    if (p == null || p.offsetM > maxOffsetM) continue;
    final d = p.alongM - alongM;
    if (d >= -20 && d <= horizonM) out.add(AlertAhead(a, d < 0 ? 0 : d));
  }
  out.sort((x, y) => x.distanceM.compareTo(y.distanceM));
  return out;
}

/// Alertes que le conducteur vient de croiser, à qui demander « toujours là ? ».
/// Une alerte n'est proposée qu'une fois ([alreadyAsked]) et jamais à son
/// auteur ([ownKeys]).
List<RoadAlert> alertsToConfirm(
  LatLon position,
  Iterable<RoadAlert> alerts, {
  required Set<String> alreadyAsked,
  Set<String> ownKeys = const {},
  double radiusM = 150,
}) => [
  for (final a in alerts)
    if (!alreadyAsked.contains(a.id) && !ownKeys.contains(a.author) && distanceM(position, a.position) <= radiusM) a,
];

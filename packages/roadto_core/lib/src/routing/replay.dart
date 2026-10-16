import 'gpx.dart';
import 'guidance.dart';
import 'route.dart';

/// A spoken announcement during a replay, with where it was said.
class ReplayAnnouncement {
  final int fixIndex;
  final double alongM;
  final String text;

  const ReplayAnnouncement(this.fixIndex, this.alongM, this.text);

  @override
  String toString() => '#$fixIndex @${alongM.round()} m: $text';
}

/// What the guidance did over a trace.
class ReplayReport {
  final int fixes;
  final List<ReplayAnnouncement> announcements;

  /// Fix indexes where the guidance declared the car off route.
  final List<int> offRouteAt;

  /// Fix index of the arrival, if reached.
  final int? arrivedAt;

  /// For each maneuver after the departure, how far before it its close
  /// announcement was said (metres), or null if it never was.
  final List<double?> preAnnouncedBeforeM;

  const ReplayReport({
    required this.fixes,
    required this.announcements,
    required this.offRouteAt,
    required this.arrivedAt,
    required this.preAnnouncedBeforeM,
  });

  bool get arrived => arrivedAt != null;

  /// Every maneuver announced before reaching it, the arrival reached, and
  /// never off route: a trip without guidance error.
  bool get clean => offRouteAt.isEmpty && arrived && preAnnouncedBeforeM.every((d) => d != null && d >= 0);

  @override
  String toString() =>
      'ReplayReport($fixes fixes, ${announcements.length} announcements, '
      'off route at $offRouteAt, arrived at $arrivedAt, announced before (m) '
      '${preAnnouncedBeforeM.map((d) => d?.round()).toList()})';
}

/// Runs [GuidanceEngine] over a recorded or simulated trace of [route], as
/// the app does with live fixes (no rerouting: an off-route trace stays on
/// the original route).
ReplayReport replayTrace(TripRoute route, List<TracePoint> trace, {GuidanceEngine? engine}) {
  final guidance = engine ?? GuidanceEngine(route);
  final announcements = <ReplayAnnouncement>[];
  final offRouteAt = <int>[];
  int? arrivedAt;
  var wasOff = false;
  final preAt = <int, double>{};
  final last = route.maneuvers.length - 1;

  for (var i = 0; i < trace.length; i++) {
    final fix = trace[i];
    final state = guidance.update(fix.position, speedMps: fix.speedMps ?? 0);
    final text = state.announcement;
    if (text != null) {
      announcements.add(ReplayAnnouncement(i, state.projection.alongM, text));
      // Attributed to the maneuver the guidance is heading for, not by text:
      // two maneuvers can read the same ("Tournez à droite.").
      final m = state.nextManeuverIndex;
      if (state.arrived && last > 0 && route.maneuvers[last].isArrival) {
        preAt.putIfAbsent(last, () => state.remainingM);
      } else if (m != null && m > 0 && text == (route.maneuvers[m].verbalPre ?? route.maneuvers[m].instruction)) {
        preAt.putIfAbsent(m, () => state.distanceToNextM);
      }
      // A multi-cue announcement ("Turn right. Then take the exit") also
      // announces the maneuver right after the one it is about: the departure
      // (said before the car reaches maneuver 1) or the next maneuver [m].
      for (final k in [?m, if (m != null) m - 1]) {
        final said = route.maneuvers[k];
        if (k + 1 > last || !said.verbalMultiCue || text != (said.verbalPre ?? said.instruction)) continue;
        if (!route.maneuvers[k + 1].isArrival) {
          preAt.putIfAbsent(k + 1, () => route.maneuverStartM(k + 1) - state.projection.alongM);
        }
        break;
      }
    }
    if (state.offRoute && !wasOff) offRouteAt.add(i);
    wasOff = state.offRoute;
    if (state.arrived && arrivedAt == null) arrivedAt = i;
  }

  return ReplayReport(
    fixes: trace.length,
    announcements: announcements,
    offRouteAt: offRouteAt,
    arrivedAt: arrivedAt,
    preAnnouncedBeforeM: [for (var m = 1; m < route.maneuvers.length; m++) preAt[m]],
  );
}

import 'package:roadto_core/roadto_core.dart';

/// A route computed but not started yet: what the driver sees before
/// tapping "Partir" (time, distance, arrival, alerts on the way).
class TripPreview {
  final Place place;
  final TripRoute route;

  /// Alerts on the route at the time it was computed, nearest first.
  final List<AlertAhead> alerts;

  /// Where the route was computed from: started much later from elsewhere,
  /// it is computed again.
  final LatLon from;
  final DateTime computedAt;

  const TripPreview({
    required this.place,
    required this.route,
    required this.alerts,
    required this.from,
    required this.computedAt,
  });

  Duration get duration => Duration(seconds: route.timeS.round());

  DateTime arrival(DateTime now) => now.add(duration);

  /// "Accident", "Bouchon ×2": the alerts on the way, by type, in the order
  /// the driver meets them.
  List<(AlertType, String)> get alertSummary {
    final counts = <AlertType, int>{};
    for (final a in alerts) {
      counts[a.alert.type] = (counts[a.alert.type] ?? 0) + 1;
    }
    return [for (final e in counts.entries) (e.key, e.value == 1 ? e.key.label : '${e.key.label} ×${e.value}')];
  }

  /// Still good to start: computed recently, from about here.
  bool fresh(LatLon position, DateTime now) =>
      now.difference(computedAt) < const Duration(minutes: 10) && distanceM(position, from) < 300;
}

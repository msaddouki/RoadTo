import 'dart:math' as math;

import '../alerts.dart';
import 'guidance.dart';
import 'route.dart';

/// Kinds of road, by the routing engine's own planned speed: its city
/// speeds are cautious, its fast roads close to the truth.
enum RoadBand {
  town('ville'),
  road('route'),
  fast('voie rapide');

  final String label;

  const RoadBand(this.label);

  static RoadBand ofSpeed(double kph) => kph < 40
      ? town
      : kph < 75
      ? road
      : fast;
}

RoadBand _bandOf(Maneuver m) => RoadBand.ofSpeed(m.timeS <= 0 ? 0 : m.lengthM / m.timeS * 3.6);

/// Planned and actual driving time on one kind of road.
class PaceSample {
  final double plannedS;
  final double actualS;

  const PaceSample(this.plannedS, this.actualS);

  static const zero = PaceSample(0, 0);

  PaceSample operator +(PaceSample o) => PaceSample(plannedS + o.plannedS, actualS + o.actualS);
}

/// How the driver's own trips compare with the routing engine, per kind of
/// road: learned on the phone from trips driven, never sent anywhere. A
/// band counts once it holds some driving, and fully after an hour of it.
class LearnedPace {
  final Map<RoadBand, PaceSample> bands;

  const LearnedPace(this.bands);

  static const none = LearnedPace({});

  /// Driving (planned time) before a band starts to count, and the weight
  /// it reaches: half after [halfWeightS], so a few trips do not swing it.
  static const minPlannedS = 600.0;
  static const halfWeightS = 1800.0;

  /// Old trips fade: past this much driving per band, the history shrinks.
  static const keptS = 4 * 3600.0;

  /// Multiplier for the engine's time on [band], 0.7 to 1.5.
  double factor(RoadBand band) {
    final s = bands[band];
    if (s == null || s.plannedS < minPlannedS) return 1;
    final ratio = (s.actualS / s.plannedS).clamp(0.7, 1.5);
    final weight = s.plannedS / (s.plannedS + halfWeightS);
    return 1 + (ratio - 1) * weight;
  }

  /// With one more trip's driving.
  LearnedPace add(Map<RoadBand, PaceSample> trip) {
    final out = Map<RoadBand, PaceSample>.of(bands);
    for (final e in trip.entries) {
      var s = (out[e.key] ?? PaceSample.zero) + e.value;
      if (s.plannedS > keptS) {
        final k = keptS / s.plannedS;
        s = PaceSample(s.plannedS * k, s.actualS * k);
      }
      out[e.key] = s;
    }
    return LearnedPace(out);
  }

  bool get isEmpty => bands.values.every((s) => s.plannedS < minPlannedS);

  Map<String, dynamic> toJson() => {
    for (final e in bands.entries) e.key.name: [e.value.plannedS, e.value.actualS],
  };

  static LearnedPace fromJson(Map<String, dynamic> json) => LearnedPace({
    for (final b in RoadBand.values)
      if (json[b.name] case [final num planned, final num actual]) b: PaceSample(planned.toDouble(), actual.toDouble()),
  });
}

/// A reported jam on the route and the time it adds.
class TrafficDelay {
  final RoadAlert alert;
  final double alongM;
  final Duration delay;

  const TrafficDelay(this.alert, this.alongM, this.delay);
}

/// Jams reported on [route]: as long and as slow as the report says
/// ([RoadAlert.lengthM], [RoadAlert.level]), else about [jamM] crawled at
/// [jamKph], instead of the planned speed there. Reports made heading the
/// other way (more than 60° off the route) are for the other side of the road.
List<TrafficDelay> trafficDelays(
  TripRoute route,
  Iterable<RoadAlert> alerts, {
  double maxOffsetM = 120,
  double jamM = 500,
  double jamKph = 10,
}) {
  final out = <TrafficDelay>[];
  for (final a in alerts) {
    if (a.type != AlertType.traffic) continue;
    final p = projectOnRoute(route, a.position);
    if (p == null || p.offsetM > maxOffsetM) continue;
    if (a.bearing case final b?) {
      final diff = ((route.bearingAt(p.alongM) - b + 540) % 360 - 180).abs();
      if (diff > 60) continue;
    }
    final planned = _plannedKphAt(route, p.alongM);
    final length = a.lengthM?.toDouble() ?? jamM;
    final crawl = a.level?.kph ?? jamKph;
    final extra = math.max(0.0, length / (crawl / 3.6) - length / (math.max(planned, crawl) / 3.6));
    out.add(TrafficDelay(a, p.alongM, Duration(seconds: extra.round())));
  }
  out.sort((x, y) => x.alongM.compareTo(y.alongM));
  return out;
}

double _plannedKphAt(TripRoute route, double alongM) {
  final i = _maneuverAt(route, alongM);
  if (i == null) return 30;
  final m = route.maneuvers[i];
  return m.timeS <= 0 ? 30 : m.lengthM / m.timeS * 3.6;
}

int? _maneuverAt(TripRoute route, double alongM) {
  int? found;
  for (var i = 0; i < route.maneuvers.length; i++) {
    if (route.maneuverStartM(i) <= alongM) {
      found = i;
    } else {
      break;
    }
  }
  return found;
}

/// The live pace of this trip: actual time over planned time, recently, and
/// how much it is trusted (0 to 1). Passed on to the next route after a
/// reroute.
class LivePace {
  final double ratio;
  final double weight;

  const LivePace(this.ratio, this.weight);

  static const none = LivePace(1, 0);
}

/// Time to arrival, better than the engine's own: its time per stretch of
/// road, corrected by what the driver's trips taught ([LearnedPace]), by
/// the pace of the last minutes for the stretch just ahead, and by the jams
/// reported on the way.
class EtaEstimator {
  final TripRoute route;
  final LearnedPace learned;

  /// Recent fixes this long count for the live pace, and its correction
  /// applies to this much of the time ahead (beyond, the jam is gone).
  static const windowS = 300.0;
  static const aheadS = 600.0;

  /// Time spent on each kind of road during this trip, to learn from.
  final Map<RoadBand, PaceSample> driven = {};

  // Per maneuver: start and end along the shape, time as corrected.
  late final List<double> _start;
  late final List<double> _end;
  late final List<double> _time;
  late final List<double> _rawTime;
  late final List<RoadBand> _band;

  final _window = <(DateTime, double, double)>[]; // when, along, raw planned from start
  LivePace _live;
  double? _startedAlongM;
  ({DateTime at, double along})? _last;

  EtaEstimator(this.route, {this.learned = LearnedPace.none, LivePace carry = LivePace.none}) : _live = carry {
    final n = route.maneuvers.length;
    _start = [for (var i = 0; i < n; i++) route.maneuverStartM(i)];
    _end = [for (var i = 0; i < n; i++) i + 1 < n ? _start[i + 1] : route.shapeLengthM];
    _band = [for (final m in route.maneuvers) _bandOf(m)];
    _rawTime = [for (final m in route.maneuvers) m.timeS];
    _time = [for (var i = 0; i < n; i++) _rawTime[i] * learned.factor(_band[i])];
  }

  LivePace get live => _live;

  /// The engine's time from [alongM] to the end, as corrected by
  /// [learned] when [corrected].
  double plannedRemainingS(double alongM, {bool corrected = true}) {
    final times = corrected ? _time : _rawTime;
    if (times.isEmpty) return route.timeS * (1 - (alongM / math.max(route.shapeLengthM, 1)).clamp(0, 1));
    var total = 0.0;
    for (var i = 0; i < times.length; i++) {
      final len = _end[i] - _start[i];
      if (alongM <= _start[i]) {
        total += times[i];
      } else if (alongM < _end[i] && len > 0) {
        total += times[i] * (_end[i] - alongM) / len;
      }
    }
    return total;
  }

  /// A new position of the trip. Fixes off the route, before the car first
  /// moves (waiting at the start is not driving) or after arrival teach
  /// nothing.
  void observe(DateTime at, GuidanceState g) {
    if (g.offRoute || g.arrived) {
      _last = null;
      return;
    }
    final along = g.projection.alongM;
    final startedAt = _startedAlongM ??= along;
    if (along - startedAt < 30) return;
    final raw = route.timeS == 0
        ? 0.0
        : plannedRemainingS(0, corrected: false) - plannedRemainingS(along, corrected: false);

    // What this stretch teaches, per kind of road (long gaps are lost fixes).
    final last = _last;
    if (last != null) {
      final dt = at.difference(last.at).inMilliseconds / 1000;
      final dPlanned = plannedRemainingS(last.along, corrected: false) - plannedRemainingS(along, corrected: false);
      if (dt > 0 && dt <= 60 && dPlanned >= 0) {
        final i = _maneuverAt(route, (last.along + along) / 2) ?? 0;
        final band = _band.isEmpty ? RoadBand.town : _band[i];
        driven[band] = (driven[band] ?? PaceSample.zero) + PaceSample(dPlanned, dt);
      }
    }
    _last = (at: at, along: along);

    _window.add((at, along, raw));
    while (_window.length > 2 && at.difference(_window[1].$1).inMilliseconds / 1000 >= windowS) {
      _window.removeAt(0);
    }
    final first = _window.first;
    final actual = at.difference(first.$1).inMilliseconds / 1000;
    final planned = raw - first.$3;
    if (planned >= 60 && actual > 0) {
      // Against the time as corrected: the learned pace is already in it.
      final i = _maneuverAt(route, along) ?? 0;
      final f = _band.isEmpty ? 1.0 : learned.factor(_band[i]);
      final ratio = (actual / (planned * f)).clamp(0.5, 2.0);
      final weight = math.min(planned / windowS, 1.0) * 0.8;
      _live = LivePace(ratio, weight);
    }
  }

  /// Time left from [g]: the corrected plan, the live pace on the next ten
  /// minutes, and the jams still ahead.
  Duration remaining(GuidanceState g, {Iterable<TrafficDelay> delays = const []}) {
    final along = g.offRoute ? (_last?.along ?? g.projection.alongM) : g.projection.alongM;
    final planned = plannedRemainingS(along);
    final near = math.min(planned, aheadS);
    final pace = 1 + (_live.ratio - 1) * _live.weight;
    var total = near * pace + (planned - near);
    for (final d in delays) {
      if (d.alongM >= along - 20) total += d.delay.inSeconds;
    }
    return Duration(seconds: total.round());
  }

  /// Before the trip: the corrected plan and the jams on the way.
  Duration total({Iterable<TrafficDelay> delays = const []}) {
    var total = plannedRemainingS(0);
    for (final d in delays) {
      total += d.delay.inSeconds;
    }
    return Duration(seconds: total.round());
  }
}

/// The route to take among [routes] (the engine's choice first, then its
/// alternatives), once the jams reported on each are counted: the engine's
/// own choice, unless another is clearly faster (by [minGain] and 5 %), so
/// the route does not change for a minute.
(TripRoute, List<TrafficDelay>) fastestWithJams(
  List<TripRoute> routes,
  Iterable<RoadAlert> alerts, {
  LearnedPace learned = LearnedPace.none,
  Duration minGain = const Duration(minutes: 2),
}) {
  if (routes.isEmpty) throw ArgumentError('no route');
  final timed = [for (final r in routes) (r, trafficDelays(r, alerts))];
  Duration time((TripRoute, List<TrafficDelay>) c) => EtaEstimator(c.$1, learned: learned).total(delays: c.$2);
  final first = timed.first;
  final firstTime = time(first);
  final margin = Duration(seconds: math.max(minGain.inSeconds, (firstTime.inSeconds * 0.05).round()));
  var best = first;
  var bestTime = firstTime;
  for (final c in timed.skip(1)) {
    final t = time(c);
    if (t <= firstTime - margin && t < bestTime) {
      best = c;
      bestTime = t;
    }
  }
  return best;
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/app_controller.dart';

/// Shows the trip on the iPhone's lock screen and in its Dynamic Island (a
/// Live Activity, ios/RoadToLiveActivity/). Updated from the phone while the
/// app runs, no push server: nothing about the trip leaves the phone.
///
/// Channel "org.roadto/live_activity": `update` {state} starts the activity
/// or updates it, `end` ends it (and any left by a previous run).
class LiveActivityLink {
  static const channel = MethodChannel('org.roadto/live_activity');

  final Listenable changes;

  /// What the activity shows, null when not navigating.
  final Map<String, Object?>? Function() snapshot;
  final MethodChannel _channel;

  /// iOS shows what it can of frequent updates; every couple of seconds is
  /// enough for distances rounded to 10 m.
  final Duration minInterval;

  Timer? _pending;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, Object?>? _last;

  LiveActivityLink({
    required this.changes,
    required this.snapshot,
    MethodChannel? methodChannel,
    this.minInterval = const Duration(seconds: 2),
  }) : _channel = methodChannel ?? channel;

  factory LiveActivityLink.forApp(AppController app) =>
      LiveActivityLink(changes: app, snapshot: () => liveActivityStateOf(app));

  /// iOS only; the activity itself needs iOS 16.2, checked on the Swift side.
  void start({bool? ios}) {
    if (!(ios ?? Platform.isIOS)) return;
    // An activity left by a run that was killed mid-trip.
    _invoke('end');
    changes.addListener(_schedule);
    _schedule();
  }

  void stop() {
    changes.removeListener(_schedule);
    _pending?.cancel();
    _pending = null;
  }

  void _schedule() {
    if (_pending != null) return;
    final wait = minInterval - DateTime.now().difference(_lastSent);
    _pending = Timer(wait.isNegative ? Duration.zero : wait, () {
      _pending = null;
      _send();
    });
  }

  void _send() {
    final state = snapshot();
    // Only what the screen would show differently.
    if (mapEquals(state, _last)) return;
    final wasActive = _last != null;
    _last = state;
    _lastSent = DateTime.now();
    if (state != null) {
      _invoke('update', state);
    } else if (wasActive) {
      _invoke('end');
    }
  }

  void _invoke(String method, [Object? args]) =>
      unawaited(_channel.invokeMethod<void>(method, args).catchError((Object _) {}));
}

Map<String, Object?>? liveActivityStateOf(AppController app) => liveActivityState(
  guidance: app.guidance,
  route: app.route,
  remaining: app.remaining,
  destination: app.destination,
  ahead: app.ahead.firstOrNull,
  now: DateTime.now(),
);

/// The activity's content, already worded and rounded: the Swift side only
/// lays it out, and the map changes only when the screen would.
@visibleForTesting
Map<String, Object?>? liveActivityState({
  required GuidanceState? guidance,
  required TripRoute? route,
  Duration? remaining,
  required Place? destination,
  AlertAhead? ahead,
  required DateTime now,
}) {
  final g = guidance;
  if (route == null || g == null) return null;
  final next = g.nextManeuver;
  final arrival = now.add(remaining ?? g.remaining);
  return {
    'destination': destination?.name ?? 'Destination',
    'symbol': maneuverSymbol(next),
    'distance': g.arrived ? '' : formatDistance(g.distanceToNextM),
    'title': switch (next) {
      _ when g.arrived => 'Vous êtes arrivé',
      null => 'Tout droit',
      final m when m.isArrival => 'Arrivée',
      final m => m.streetNames.firstOrNull ?? m.instruction,
    },
    'instruction': g.arrived ? (destination?.name ?? '') : (next?.instruction ?? ''),
    'remaining': formatDistance(g.remainingM),
    // To the minute, as shown.
    'arrivalEpochMs': arrival.millisecondsSinceEpoch ~/ 60000 * 60000,
    if (ahead != null) 'alert': '${ahead.alert.type.label} à ${formatDistance(ahead.distanceM)}',
    'arrived': g.arrived,
  };
}

/// SF Symbol of a Valhalla maneuver type, the same families as the phone's
/// panel (maneuverIcon). France drives on the right: roundabouts turn
/// counterclockwise.
@visibleForTesting
String maneuverSymbol(Maneuver? m) => switch (m?.type) {
  1 || 2 || 3 => 'location.north.fill',
  4 || 5 || 6 => 'flag.checkered',
  9 || 23 => 'arrow.up.right',
  10 || 11 || 18 || 20 => 'arrow.turn.up.right',
  12 => 'arrow.uturn.right',
  13 => 'arrow.uturn.left',
  14 || 15 || 19 || 21 => 'arrow.turn.up.left',
  16 || 24 => 'arrow.up.left',
  25 => 'arrow.merge',
  26 || 27 => 'arrow.counterclockwise.circle',
  28 || 29 => 'ferry',
  _ => 'arrow.up',
};

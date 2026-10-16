import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/app_controller.dart';

/// Shows the phone's guidance on Android Auto (android/…/car/): the car app
/// computes nothing, it draws what this sends and sends back what the driver
/// taps (reports, "Toujours là ?" answers, stop).
///
/// Channel "org.roadto/car": `update` (this state) to the car; `report`
/// {type}, `confirm` {id, stillThere}, `stop` from the car.
class CarLink {
  static const channel = MethodChannel('org.roadto/car');

  final Listenable changes;
  final Map<String, Object?> Function() snapshot;
  final void Function(AlertType type) onReport;
  final void Function(String id, bool? stillThere) onConfirm;
  final VoidCallback onStop;
  final MethodChannel _channel;

  /// The car screen does not need more than a few updates a second.
  final Duration minInterval;

  Timer? _pending;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  Object? _lastRouteId;

  CarLink({
    required this.changes,
    required this.snapshot,
    required this.onReport,
    required this.onConfirm,
    required this.onStop,
    MethodChannel? methodChannel,
    this.minInterval = const Duration(milliseconds: 500),
  }) : _channel = methodChannel ?? channel;

  factory CarLink.forApp(AppController app) => CarLink(
    changes: app,
    snapshot: () => carStateOf(app),
    onReport: (type) => app.report(type, app.position, app.fix?.bearingDeg),
    onConfirm: (id, stillThere) {
      if (app.pendingConfirmation?.id == id) app.answerConfirmation(stillThere);
    },
    onStop: app.stopNavigation,
  );

  /// Android only: Android Auto has no iOS counterpart here (CarPlay, J8).
  void start({bool? android}) {
    if (!(android ?? Platform.isAndroid)) return;
    _channel.setMethodCallHandler(_onCall);
    changes.addListener(_schedule);
    _send();
  }

  void stop() {
    changes.removeListener(_schedule);
    _pending?.cancel();
    _channel.setMethodCallHandler(null);
  }

  Future<Object?> _onCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'report':
        final type = AlertType.values.where((t) => t.code == args['type']).firstOrNull;
        // Police stays off until the L130-11 channel exists (plan, J6).
        if (type == null || type == AlertType.police) return false;
        onReport(type);
        return true;
      case 'confirm':
        onConfirm(args['id'] as String? ?? '', args['stillThere'] as bool?);
        return true;
      case 'stop':
        onStop();
        return true;
    }
    throw MissingPluginException('car: ${call.method}');
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
    _lastSent = DateTime.now();
    final state = Map<String, Object?>.of(snapshot());
    // The shape goes once per route; the car keeps it while the id stays.
    if (state['routeId'] == _lastRouteId) state.remove('route');
    _lastRouteId = state['routeId'];
    unawaited(_channel.invokeMethod<void>('update', state).catchError((Object _) {}));
  }
}

/// What the car screen shows, from the app's state.
Map<String, Object?> carStateOf(AppController app) => carState(
  guidance: app.guidance,
  route: app.route,
  position: app.position,
  bearingDeg: app.fix?.bearingDeg,
  speedMps: app.fix?.speedMps,
  speedLimitKph: app.speedLimit?.kph,
  mapStyle: app.mapStyle,
  ahead: app.ahead.firstOrNull,
  confirmations: app.ahead.isEmpty ? 0 : app.alerts.stillThere(app.ahead.first.alert.id).count,
  pending: app.pendingConfirmation,
  now: DateTime.now(),
);

@visibleForTesting
Map<String, Object?> carState({
  required GuidanceState? guidance,
  required TripRoute? route,
  required LatLon position,
  double? bearingDeg,
  double? speedMps,
  int? speedLimitKph,
  String? mapStyle,
  AlertAhead? ahead,
  int confirmations = 0,
  RoadAlert? pending,
  required DateTime now,
}) {
  final g = guidance, next = guidance?.nextManeuver;
  final navigating = route != null && g != null;
  return {
    'navigating': navigating,
    if (navigating && next != null)
      'maneuver': {
        'type': next.type,
        'instruction': next.instruction,
        'street': next.streetNames.firstOrNull,
        'distanceM': g.distanceToNextM,
      },
    if (navigating) ...{
      'remainingM': g.remainingM,
      'remainingS': g.remaining.inSeconds,
      'arrivalEpochMs': g.eta(now).millisecondsSinceEpoch,
    },
    'lat': position.lat,
    'lon': position.lon,
    'bearing': bearingDeg,
    if (speedMps != null) 'speedKph': (speedMps * 3.6).round(),
    'speedLimitKph': speedLimitKph,
    'mapStyle': mapStyle,
    if (ahead != null)
      'alert': {'label': ahead.alert.type.label, 'distanceM': ahead.distanceM, 'confirmations': confirmations},
    if (pending != null) 'confirmation': {'id': pending.id, 'label': pending.type.label},
    if (route != null) ...{
      'routeId': '${identityHashCode(route)}',
      'route': [
        for (final p in route.shape) [p.lon, p.lat],
      ],
    },
  };
}

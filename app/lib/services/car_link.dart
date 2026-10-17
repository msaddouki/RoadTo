import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/app_controller.dart';
import 'location_source.dart';

/// Shows the phone's guidance on Android Auto (android/…/car/): the car app
/// computes nothing, it draws what this sends and sends back what the driver
/// taps (reports, "Toujours là ?" answers, stop).
///
/// Channel "org.roadto/car": `update` (this state) to the car; `report`
/// {type}, `confirm` {id, stillThere}, `stop`, `navigate` {name, detail, lat,
/// lon} and `search` {query} (answered with places) from the car.
class CarLink {
  static const channel = MethodChannel('org.roadto/car');

  final Listenable changes;
  final Map<String, Object?> Function() snapshot;
  final void Function(AlertType type) onReport;
  final void Function(String id, bool? stillThere) onConfirm;
  final VoidCallback onStop;
  final void Function(Place place) onNavigate;
  final Future<List<Place>> Function(String query) onSearch;
  final MethodChannel _channel;

  /// Rows a car list shows at most.
  static const maxPlaces = 6;

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
    required this.onNavigate,
    required this.onSearch,
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
    onNavigate: (place) => unawaited(app.navigateTo(place)),
    onSearch: app.search,
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
      case 'navigate':
        final place = placeFromMap(args);
        if (place == null) return false;
        onNavigate(place);
        return true;
      case 'search':
        final query = (args['query'] as String? ?? '').trim();
        if (query.isEmpty) return const <Object?>[];
        try {
          return [for (final p in (await onSearch(query)).take(maxPlaces)) placeToMap(p)];
        } on Exception {
          return const <Object?>[]; // offline without a region: nothing found
        }
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
  places: app.favorites.all,
  routing: app.routing,
  locationDenied:
      !app.settings.simulate &&
      (app.locationStatus == LocationAvailability.denied || app.locationStatus == LocationAvailability.deniedForever),
  now: DateTime.now(),
);

Map<String, Object?> placeToMap(Place p) => {
  'name': p.name,
  'detail': p.detail,
  'lat': p.position.lat,
  'lon': p.position.lon,
};

Place? placeFromMap(Map<String, Object?> m) {
  final lat = m['lat'], lon = m['lon'];
  if (lat is! num || lon is! num) return null;
  final name = m['name'] as String? ?? '';
  return Place(
    name: name.isEmpty ? 'Destination' : name,
    detail: m['detail'] as String?,
    position: LatLon(lat.toDouble(), lon.toDouble()),
  );
}

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
  List<Place> places = const [],
  bool routing = false,
  bool locationDenied = false,
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
    'places': [for (final p in places.take(CarLink.maxPlaces)) placeToMap(p)],
    'routing': routing,
    'locationDenied': locationDenied,
    if (route != null) ...{
      'routeId': '${identityHashCode(route)}',
      'route': [
        for (final p in route.shape) [p.lon, p.lat],
      ],
    },
  };
}

import 'dart:async';

import '../geo.dart';
import 'route.dart';

/// Position simulée le long d'un itinéraire.
class SimulatedFix {
  final LatLon position;
  final double bearingDeg;
  final double speedMps;
  final double alongM;

  const SimulatedFix(this.position, this.bearingDeg, this.speedMps, this.alongM);
}

/// Rejoue un itinéraire à vitesse constante. Règle du projet : tout se teste
/// d'abord en simulation, jamais téléphone en main au volant.
class RouteSimulator {
  final TripRoute route;
  double speedKmh;
  final Duration tick;
  double _along;
  Timer? _timer;
  final _ctrl = StreamController<SimulatedFix>.broadcast();

  RouteSimulator(this.route, {this.speedKmh = 50, this.tick = const Duration(seconds: 1), double startM = 0})
    : _along = startM;

  Stream<SimulatedFix> get fixes => _ctrl.stream;
  bool get running => _timer != null;
  double get alongM => _along;

  SimulatedFix fixAt(double along) => SimulatedFix(route.pointAt(along), route.bearingAt(along), speedKmh / 3.6, along);

  /// Avance d'un pas et renvoie la nouvelle position.
  SimulatedFix step() {
    _along = (_along + speedKmh / 3.6 * tick.inMilliseconds / 1000).clamp(0, route.shapeLengthM);
    return fixAt(_along);
  }

  void start() {
    if (_timer != null) return;
    _ctrl.add(fixAt(_along));
    _timer = Timer.periodic(tick, (_) {
      final fix = step();
      _ctrl.add(fix);
      if (_along >= route.shapeLengthM) stop();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    stop();
    await _ctrl.close();
  }
}

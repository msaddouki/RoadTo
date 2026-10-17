import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';

/// Android: a foreground service runs during a trip (NavigationService.kt),
/// so the position keeps coming and the guidance goes on with the screen off
/// or RoadTo closed, as when driving with Android Auto. Nothing outside a
/// trip.
class TripService {
  static const channel = MethodChannel('org.roadto/navigation');

  final ValueListenable<bool> navigating;
  final MethodChannel _channel;
  bool _running = false;

  TripService(this.navigating, {MethodChannel? methodChannel}) : _channel = methodChannel ?? channel;

  factory TripService.forApp(AppController app) => TripService(_Navigating(app));

  void start({bool? android}) {
    if (!(android ?? Platform.isAndroid)) return;
    navigating.addListener(_sync);
    _sync();
  }

  void _sync() {
    final on = navigating.value;
    if (on == _running) return;
    _running = on;
    unawaited(_channel.invokeMethod<void>(on ? 'start' : 'stop').catchError((Object _) {}));
  }
}

/// Whether [app] is navigating, notifying only when that changes.
class _Navigating extends ValueNotifier<bool> {
  _Navigating(AppController app) : super(app.navigating) {
    app.addListener(() => value = app.navigating);
  }
}

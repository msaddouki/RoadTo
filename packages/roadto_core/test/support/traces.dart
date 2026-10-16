import 'dart:math' as math;

import 'package:roadto_core/roadto_core.dart';

/// A deterministic GPS trace of a drive along [route]: fixes every
/// [intervalS] at [speedKmh], with Gaussian noise of [noiseM] (sigma),
/// occasional single outliers, a stop, a stretch without fixes (tunnel) or a
/// lateral detour. Ends with a few fixes parked at the destination.
List<TracePoint> simulateDrive(
  TripRoute route, {
  required int seed,
  double speedKmh = 40,
  double intervalS = 1,
  double noiseM = 0,
  double spikeChance = 0,
  double spikeM = 40,
  ({double atM, double seconds})? stop,
  ({double fromM, double toM})? tunnel,
  ({double fromM, double toM, double offsetM})? detour,
}) {
  final rng = math.Random(seed);
  double gauss() {
    final u = 1 - rng.nextDouble(), v = rng.nextDouble();
    return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
  }

  LatLon offset(LatLon p, double bearing, double metres) {
    final rad = bearing * math.pi / 180;
    return LatLon(
      p.lat + metres * math.cos(rad) / 111320,
      p.lon + metres * math.sin(rad) / (111320 * math.cos(p.lat * math.pi / 180)),
    );
  }

  final speed = speedKmh / 3.6;
  final start = DateTime.utc(2026, 10, 1, 8);
  final out = <TracePoint>[];
  var t = 0.0, along = 0.0, stoppedFor = 0.0;
  var stopped = false;

  void emit(double v) {
    final heading = route.bearingAt(along);
    var p = route.pointAt(along);
    final d = detour;
    if (d != null && along >= d.fromM && along <= d.toM) p = offset(p, heading + 90, d.offsetM);
    if (noiseM > 0) p = offset(p, rng.nextDouble() * 360, (gauss() * noiseM).abs());
    if (spikeChance > 0 && rng.nextDouble() < spikeChance) p = offset(p, rng.nextDouble() * 360, spikeM);
    final tun = tunnel;
    if (tun != null && along >= tun.fromM && along <= tun.toM) return;
    out.add(
      TracePoint(
        p,
        time: start.add(Duration(milliseconds: (t * 1000).round())),
        speedMps: v == 0 ? 0 : math.max(0, v + gauss() * 0.4),
        courseDeg: v == 0 ? null : heading,
      ),
    );
  }

  final end = route.shapeLengthM;
  while (along < end) {
    final s = stop;
    if (s != null && !stopped && along >= s.atM) {
      emit(0);
      stoppedFor += intervalS;
      if (stoppedFor >= s.seconds) stopped = true;
    } else {
      along = math.min(end, along + speed * intervalS);
      emit(speed);
    }
    t += intervalS;
  }
  for (var i = 0; i < 5; i++) {
    t += intervalS;
    emit(0);
  }
  return out;
}

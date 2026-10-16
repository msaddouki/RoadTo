// Writes the synthetic-* drives of test/fixtures/gpx from their routes:
//   dart run test/support/make_synthetic_drives.dart   (in packages/roadto_core)
//
// Each route is a real Valhalla /route response for the Lyon test region,
// saved as <name>.route.json (same request as the app). The trace is
// simulated at a speed fitting the road, with GPS noise, and loses its fixes
// in the route's tunnels. Real drives recorded on the road replace these
// over time.
import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';

import 'traces.dart';

typedef _Drive = ({String label, int seed, double speedKmh, double noiseM, double spikeChance, double stopAtM});

const _drives = <String, _Drive>{
  'synthetic-perrache-saint-jean': (
    label: 'Perrache -> Saint-Jean: underpasses, a bridge, Vieux Lyon streets',
    seed: 21,
    speedKmh: 30,
    noiseM: 8,
    spikeChance: 0.03,
    stopAtM: 1200,
  ),
  'synthetic-part-dieu-confluence': (
    label: 'Part-Dieu -> Confluence: Vivier-Merle tunnel, Rhône quays',
    seed: 22,
    speedKmh: 40,
    noiseM: 6,
    spikeChance: 0,
    stopAtM: 2500,
  ),
  'synthetic-vaise-villeurbanne-periph': (
    label: 'Vaise -> Villeurbanne: Boulevard Périphérique Nord, ramps and roundabouts',
    seed: 23,
    speedKmh: 70,
    noiseM: 5,
    spikeChance: 0,
    stopAtM: 0,
  ),
  'synthetic-confluence-vienne-a7': (
    label: 'Confluence -> Vienne: A7 motorway, 29 km',
    seed: 24,
    speedKmh: 100,
    noiseM: 5,
    spikeChance: 0.01,
    stopAtM: 0,
  ),
  'synthetic-bron-saint-priest': (
    label: 'Bron -> Saint-Priest: suburbs, six roundabouts',
    seed: 25,
    speedKmh: 40,
    noiseM: 6,
    spikeChance: 0,
    stopAtM: 3000,
  ),
  'synthetic-ecully-dardilly': (
    label: 'Écully -> Dardilly: narrow lanes, three roundabouts',
    seed: 26,
    speedKmh: 35,
    noiseM: 7,
    spikeChance: 0.02,
    stopAtM: 0,
  ),
  'synthetic-terreaux-croix-rousse': (
    label: 'Terreaux -> Croix-Rousse: the climb, rue Terme tunnel',
    seed: 27,
    speedKmh: 25,
    noiseM: 10,
    spikeChance: 0.03,
    stopAtM: 600,
  ),
  'synthetic-saint-jean-tassin': (
    label: 'Saint-Jean -> Tassin: montée de Choulans, M6',
    seed: 28,
    speedKmh: 50,
    noiseM: 6,
    spikeChance: 0,
    stopAtM: 0,
  ),
  'synthetic-part-dieu-aeroport': (
    label: 'Part-Dieu -> Saint-Exupéry: périphérique, A42 and A432, 29 km',
    seed: 29,
    speedKmh: 80,
    noiseM: 5,
    spikeChance: 0.01,
    stopAtM: 0,
  ),
};

void main() {
  final dir = Directory('test/fixtures/gpx');
  for (final MapEntry(key: name, value: d) in _drives.entries) {
    final json = jsonDecode(File('${dir.path}/$name.route.json').readAsStringSync()) as Map<String, dynamic>;
    final route = parseValhallaRoute(json);
    final tunnel = _firstTunnel(route);
    final trace = simulateDrive(
      route,
      seed: d.seed,
      speedKmh: d.speedKmh,
      noiseM: d.noiseM,
      spikeChance: d.spikeChance,
      stop: d.stopAtM > 0 ? (atM: d.stopAtM, seconds: 30) : null,
      tunnel: tunnel,
    );
    final gpx = toGpx(trace, name: 'SYNTHETIC drive ${d.label} (simulateDrive seed ${d.seed})');
    File('${dir.path}/$name.gpx').writeAsStringSync(gpx);
    final km = (route.lengthM / 1000).toStringAsFixed(1);
    stdout.writeln(
      '$name: $km km, ${route.maneuvers.length} maneuvers, ${trace.length} fixes'
      '${tunnel == null ? '' : ', tunnel ${tunnel.fromM.round()}-${tunnel.toM.round()} m'}',
    );
  }
}

/// The first stretch on a street named "Tunnel…", where the receiver gets no
/// fix: at most 500 m (a maneuver can run on past the tunnel), and not in the
/// first 200 m (a trip starts with a fix).
({double fromM, double toM})? _firstTunnel(TripRoute route) {
  for (final m in route.maneuvers) {
    if (!m.streetNames.any((n) => n.toLowerCase().startsWith('tunnel'))) continue;
    final from = route.cumulative[m.beginShapeIndex];
    if (from < 200) continue;
    return (fromM: from, toM: from + (m.lengthM < 500 ? m.lengthM : 500));
  }
  return null;
}

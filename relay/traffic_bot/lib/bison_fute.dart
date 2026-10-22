// Bison Futé's open traffic data (Licence Ouverte 2.0), as published on
// tipi.bison-fute.gouv.fr for the national road network the State runs
// (transport.data.gouv.fr, "Circulation en temps réel - Réseau routier non
// concédé"):
//   - the stations' referential, refDir.csv: each station's stretch of road,
//     in Lambert-93, with its direction;
//   - "TRAFICOLOR", per area (TraficLyon, TraficMarius…): a new DATEX II
//     file every minute with each station's state (freeFlow, heavy,
//     congested, impossible, unknown).
import 'dart:math' as math;

import 'package:roadto_core/roadto_core.dart';

import 'lambert93.dart';

const tipi = 'http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR';
const referentialUrl = '$tipi/QTV-DIR/refDir.csv';
String feedIndexUrl(String feed) => '$tipi/TRAFICOLOR-DIR/$feed/';

/// A station's stretch of road, in the direction of traffic.
class Site {
  final String id;
  final String road;
  final LatLon start;
  final LatLon end;

  /// Heading of the traffic it measures, degrees.
  final double bearing;

  const Site(this.id, this.road, this.start, this.end, this.bearing);

  double get lengthM => distanceM(start, end);

  LatLon get middle => LatLon((start.lat + end.lat) / 2, (start.lon + end.lon) / 2);
}

/// Stations with a position from refDir.csv. Its header names one column more
/// than its rows hold (code_insee_commune), so rows are read by position:
/// 0 id, 3 road, 9 direction (NORD_SUD…), 14–17 start and end (Lambert-93).
Map<String, Site> parseReferential(String csv) {
  final sites = <String, Site>{};
  for (final line in csv.split(RegExp(r'\r?\n')).skip(1)) {
    final f = line.split(';');
    if (f.length < 18) continue;
    final xs = double.tryParse(f[14]), ys = double.tryParse(f[15]);
    final xe = double.tryParse(f[16]), ye = double.tryParse(f[17]);
    if (xs == null || ys == null || xe == null || ye == null) continue;
    final start = lambert93ToWgs84(xs, ys), end = lambert93ToWgs84(xe, ye);
    final cardinal = _cardinal[f[9].trim()];
    var bearing = distanceM(start, end) < 20 ? (cardinal ?? 0) : bearingDeg(start, end);
    // Stretches are sometimes given against the traffic: the direction wins.
    final turned = cardinal != null && _angle(bearing, cardinal) > 90;
    if (turned) bearing = (bearing + 180) % 360;
    sites[f[0]] = Site(f[0], f[3], turned ? end : start, turned ? start : end, bearing);
  }
  return sites;
}

const _cardinal = {'SUD_NORD': 0.0, 'OUEST_EST': 90.0, 'NORD_SUD': 180.0, 'EST_OUEST': 270.0};

double _angle(double a, double b) => ((a - b + 540) % 360 - 180).abs();

/// The newest file of a feed's index page (TraficLyon_DataTRT_20261022_130235.xml).
String? latestFile(String indexHtml) {
  final files = RegExp(
    r'href="([A-Za-z0-9_]+_DataTRT_\d{8}_\d{6}\.xml)"',
  ).allMatches(indexHtml).map((m) => m.group(1)!).toList();
  if (files.isEmpty) return null;
  String stamp(String f) => RegExp(r'_(\d{8}_\d{6})\.xml$').firstMatch(f)!.group(1)!;
  files.sort((a, b) => stamp(a).compareTo(stamp(b)));
  return files.last;
}

/// Each station's state in a TRAFICOLOR file, and when it was measured.
({DateTime? at, Map<String, String> states}) parseStates(String xml) {
  final states = <String, String>{};
  for (final block in RegExp(r'<siteMeasurements>([\s\S]*?)</siteMeasurements>').allMatches(xml)) {
    final body = block.group(1)!;
    final id = RegExp(r'measurementSiteReference[^>]*\bid="([^"]+)"').firstMatch(body)?.group(1);
    final state = RegExp(r'<trafficStatusValue>\s*([A-Za-z]+)\s*</trafficStatusValue>').firstMatch(body)?.group(1);
    if (id != null && state != null) states[id] = state;
  }
  final at = RegExp(r'<publicationTime>([^<]+)</publicationTime>').firstMatch(xml)?.group(1);
  return (at: at == null ? null : DateTime.tryParse(at), states: states);
}

/// RoadTo's level for a DATEX II traffic state; null when traffic flows or
/// nothing is known.
JamLevel? levelOf(String state) => switch (state) {
  'heavy' => JamLevel.slow,
  'congested' => JamLevel.jam,
  'impossible' => JamLevel.stopped,
  _ => null,
};

/// Longest stretch counted as one jam: past that, the station's stretch is
/// a whole section between interchanges and the jam likely is shorter.
const maxStretchM = 3000;

int? jamLengthOf(Site site) {
  final m = site.lengthM;
  if (m < 50) return null; // a point station: length unknown
  return math.min(m, maxStretchM.toDouble()).round();
}

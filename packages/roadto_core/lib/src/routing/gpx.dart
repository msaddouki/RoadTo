import '../geo.dart';

/// One GPS fix of a recorded or simulated trace.
class TracePoint {
  final LatLon position;
  final DateTime? time;

  /// m/s, when the device reported it.
  final double? speedMps;

  /// Degrees from north, when the device reported it.
  final double? courseDeg;

  const TracePoint(this.position, {this.time, this.speedMps, this.courseDeg});
}

/// Reads the track points of a GPX file (1.0 or 1.1): position, time and,
/// when present, `<speed>` and `<course>` (GPX 1.0, or as extensions). Speed
/// is derived from consecutive times and positions when absent.
List<TracePoint> parseGpx(String xml) {
  final points = <TracePoint>[];
  final pt = RegExp(r'<trkpt\b([^>]*?)(?:/>|>(.*?)</trkpt>)', dotAll: true);
  double? attr(String attrs, String name) {
    final m = RegExp('\\b$name\\s*=\\s*["\']([-+0-9.eE]+)["\']').firstMatch(attrs);
    return m == null ? null : double.tryParse(m[1]!);
  }

  String? child(String? body, String name) {
    if (body == null) return null;
    final m = RegExp('<(?:\\w+:)?$name>\\s*([^<]*?)\\s*</(?:\\w+:)?$name>').firstMatch(body);
    return m?[1];
  }

  for (final m in pt.allMatches(xml)) {
    final lat = attr(m[1]!, 'lat'), lon = attr(m[1]!, 'lon');
    if (lat == null || lon == null) continue;
    final body = m[2];
    final time = child(body, 'time');
    points.add(
      TracePoint(
        LatLon(lat, lon),
        time: time == null ? null : DateTime.tryParse(time),
        speedMps: double.tryParse(child(body, 'speed') ?? ''),
        courseDeg: double.tryParse(child(body, 'course') ?? ''),
      ),
    );
  }

  // Fill in missing speeds from the previous point.
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    if (b.speedMps != null || a.time == null || b.time == null) continue;
    final dt = b.time!.difference(a.time!).inMilliseconds / 1000;
    if (dt <= 0) continue;
    points[i] = TracePoint(
      b.position,
      time: b.time,
      speedMps: distanceM(a.position, b.position) / dt,
      courseDeg: b.courseDeg,
    );
  }
  return points;
}

/// Writes [points] as a GPX 1.1 track, speed and course as RoadTo extensions.
String toGpx(List<TracePoint> points, {String name = 'RoadTo trace'}) {
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<gpx version="1.1" creator="RoadTo" xmlns="http://www.topografix.com/GPX/1/1" '
      'xmlns:rt="urn:roadto:gpx:1">',
    )
    ..writeln('  <trk><name>${_escape(name)}</name><trkseg>');
  for (final p in points) {
    out.write('    <trkpt lat="${p.position.lat.toStringAsFixed(7)}" lon="${p.position.lon.toStringAsFixed(7)}">');
    if (p.time != null) out.write('<time>${p.time!.toUtc().toIso8601String()}</time>');
    if (p.speedMps != null || p.courseDeg != null) {
      out.write('<extensions>');
      if (p.speedMps != null) out.write('<rt:speed>${p.speedMps!.toStringAsFixed(2)}</rt:speed>');
      if (p.courseDeg != null) out.write('<rt:course>${p.courseDeg!.toStringAsFixed(1)}</rt:course>');
      out.write('</extensions>');
    }
    out.writeln('</trkpt>');
  }
  out.writeln('  </trkseg></trk>\n</gpx>');
  return out.toString();
}

String _escape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

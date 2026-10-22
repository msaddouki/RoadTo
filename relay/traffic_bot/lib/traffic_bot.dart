/// Publishes the jams of open traffic data as RoadTo alerts (see
/// docs/traffic-feed.md). The logic is here, the network in bin/.
library;

import 'package:roadto_core/roadto_core.dart';

import 'bison_fute.dart';
import 'shapes.dart';

export 'bison_fute.dart';
export 'lambert93.dart';
export 'shapes.dart';

class _SiteState {
  final JamLevel level;
  int readings;
  DateTime? publishedAt;
  JamLevel? publishedLevel;

  _SiteState(this.level) : readings = 1;
}

/// Turns each new file of station states into alerts: a station counts as
/// jammed after [confirmations] readings in a row (one a minute), its alert
/// lives [lasting] and is published again every [refreshEvery] while the
/// jam lasts, at once when it gets worse or better. When traffic flows
/// again, or the station goes silent, the last alert simply runs out.
class TrafficBot {
  final KeyPair keys;

  /// "bison-fute": the first part of the alerts' `src` tag.
  final String source;
  Map<String, Site> sites;

  static const confirmations = 2;
  static const refreshEvery = Duration(minutes: 5);
  static const lasting = Duration(minutes: 10);

  /// A file older than this is a stuck feed: nothing is published from it.
  static const staleAfter = Duration(minutes: 10);

  /// The road each station measures, when known ([StretchShapes]).
  final List<LatLon>? Function(String id) shapeOf;

  final _states = <String, _SiteState>{};
  final _lastFile = <String, String>{};

  TrafficBot({required this.keys, required this.sites, this.source = 'bison-fute', this.shapeOf = _noShape});

  static List<LatLon>? _noShape(String id) => null;

  /// Stations currently seen jammed (confirmed or not).
  int get jammed => _states.length;

  /// The alerts to publish for [file] of [feed] (each file is read once).
  List<NostrEvent> step(String feed, String file, ({DateTime? at, Map<String, String> states}) data, DateTime now) {
    if (_lastFile[feed] == file) return const [];
    _lastFile[feed] = file;
    final at = data.at;
    if (at == null || now.difference(at) > staleAfter) return const [];

    final out = <NostrEvent>[];
    for (final MapEntry(key: id, value: state) in data.states.entries) {
      final site = sites[id];
      if (site == null) continue; // no position for this station
      if (state == 'unknown') continue; // no news: the last alert runs out
      final level = levelOf(state);
      if (level == null) {
        _states.remove(id);
        continue;
      }
      var s = _states[id];
      if (s == null || s.level != level) {
        final before = s;
        s = _states[id] = _SiteState(level)
          ..publishedAt = before?.publishedAt
          ..publishedLevel = before?.publishedLevel;
        // Worse or better while a jam is already out: said at once.
        if (before?.publishedAt != null) s.readings = confirmations;
      } else {
        s.readings++;
      }
      if (s.readings < confirmations) continue;
      final last = s.publishedAt;
      if (last != null && s.publishedLevel == level && now.difference(last) < refreshEvery) continue;
      final shape = shapeOf(id);
      out.add(
        buildAlertEvent(
          keys: keys,
          type: AlertType.traffic,
          // On the road itself when its shape is known: a bend takes the
          // straight line's middle off the road.
          position: shape == null ? site.middle : middleOf(shape),
          bearing: site.bearing,
          now: now,
          level: level,
          lengthM: jamLengthOf(site),
          source: '$source/$id',
          shape: shape,
          lasting: lasting,
        ),
      );
      s
        ..publishedAt = now
        ..publishedLevel = level;
    }
    return out;
  }
}

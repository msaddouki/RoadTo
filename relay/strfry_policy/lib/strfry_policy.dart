/// strfry write-policy plugin applying the RoadTo rules.
///
/// strfry starts the plugin once and sends one JSON object per line on stdin:
///
/// ```json
/// {"type":"new","event":{...},"receivedAt":1700000000,"sourceType":"IP4","sourceInfo":"1.2.3.4"}
/// ```
///
/// and expects one line back per request:
///
/// ```json
/// {"id":"<event id>","action":"accept|reject|shadowReject","msg":"..."}
/// ```
///
/// Rules are [checkWritePolicy] from roadto_core, exactly what the dev relay
/// and the app tests enforce, plus a per-source rate limit. Client addresses
/// are only kept in memory for the rate limit and are never written out.
/// RoadTo's traffic robot ([TrafficSources.keys], relay/traffic_bot) is not
/// rate limited: it publishes a whole area's jams each minute.
library;

import 'dart:convert';

import 'package:roadto_core/roadto_core.dart';

import 'metrics.dart';

export 'metrics.dart';

class WritePolicyPlugin {
  /// Events accepted per client address and per minute.
  final int ratePerMinute;
  final bool policeAllowed;

  /// Authors not rate limited (strfry has checked their signature).
  final Set<String> unlimitedAuthors;

  final _windows = <String, (int, int)>{}; // address -> (minute, count)

  /// Decision counters, served on /metrics by the entry point.
  final PolicyMetrics metrics = PolicyMetrics();

  WritePolicyPlugin({
    this.ratePerMinute = 30,
    this.policeAllowed = FeatureFlags.policeAlerts,
    this.unlimitedAuthors = TrafficSources.keys,
  }) {
    metrics.rateLimitedSources = () => _windows.length;
  }

  /// Answers one strfry request.
  Map<String, Object?> handle(Map<String, dynamic> request, {DateTime? now}) {
    final answer = _decide(request, now: now);
    final event = request['event'];
    metrics.record(
      accepted: answer['action'] == 'accept',
      msg: answer['msg'] as String?,
      sourceType: request['sourceType'],
      kind: event is Map ? event['kind'] : null,
    );
    return answer;
  }

  Map<String, Object?> _decide(Map<String, dynamic> request, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final eventJson = request['event'];
    final id = eventJson is Map ? eventJson['id'] : null;
    if (request['type'] != 'new' || eventJson is! Map<String, dynamic> || id is! String) {
      return {'id': id ?? '', 'action': 'reject', 'msg': 'invalid: unexpected request'};
    }

    // Events replicated from our other relays (Stream, Sync) or imported by an
    // operator are not rate limited: the original relay already was.
    final source = request['sourceType'];
    if ((source == 'IP4' || source == 'IP6') && !unlimitedAuthors.contains(eventJson['pubkey'])) {
      final address = '${request['sourceInfo']}';
      final minute = t.millisecondsSinceEpoch ~/ 60000;
      final (window, count) = _windows[address] ?? (minute, 0);
      final next = window == minute ? count + 1 : 1;
      _windows[address] = (minute, next);
      if (_windows.length > 100000) _windows.removeWhere((_, w) => w.$1 != minute);
      if (next > ratePerMinute) return {'id': id, 'action': 'reject', 'msg': 'rate-limited: slow down'};
    }

    final NostrEvent event;
    try {
      event = NostrEvent.fromJson(eventJson);
    } catch (_) {
      return {'id': id, 'action': 'reject', 'msg': 'invalid: malformed event'};
    }
    // strfry has already checked the id and the signature (C++) before
    // asking the plugin; checking again in Dart (~17 ms) made the plugin the
    // relay's bottleneck under load.
    final refusal = checkWritePolicy(event, now: t, policeAllowed: policeAllowed, verifySignature: false);
    return refusal == null ? {'id': id, 'action': 'accept'} : {'id': id, 'action': 'reject', 'msg': refusal};
  }

  /// Answers one raw line; never throws, so a bad line cannot stop the relay.
  String handleLine(String line, {DateTime? now}) {
    Map<String, dynamic> request;
    try {
      request = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      request = const {};
    }
    return jsonEncode(handle(request, now: now));
  }
}

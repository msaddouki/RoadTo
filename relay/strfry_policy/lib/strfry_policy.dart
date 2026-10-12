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
library;

import 'dart:convert';

import 'package:roadto_core/roadto_core.dart';

class WritePolicyPlugin {
  /// Events accepted per client address and per minute.
  final int ratePerMinute;
  final bool policeAllowed;

  final _windows = <String, (int, int)>{}; // address -> (minute, count)

  WritePolicyPlugin({this.ratePerMinute = 30, this.policeAllowed = FeatureFlags.policeAlerts});

  /// Answers one strfry request.
  Map<String, Object?> handle(Map<String, dynamic> request, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final eventJson = request['event'];
    final id = eventJson is Map ? eventJson['id'] : null;
    if (request['type'] != 'new' || eventJson is! Map<String, dynamic> || id is! String) {
      return {'id': id ?? '', 'action': 'reject', 'msg': 'invalid: unexpected request'};
    }

    // Events replicated from our other relays (Stream, Sync) or imported by an
    // operator are not rate limited: the original relay already was.
    final source = request['sourceType'];
    if (source == 'IP4' || source == 'IP6') {
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
    final refusal = checkWritePolicy(event, now: t, policeAllowed: policeAllowed);
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

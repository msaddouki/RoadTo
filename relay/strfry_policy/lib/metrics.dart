/// Prometheus counters of the plugin's decisions.
///
/// Labels only carry classes (action, reason, source, event kind): never an
/// address, a key, an event id or a position, in line with the relay's
/// no-IP rule.
class PolicyMetrics {
  final _decisions = <String, int>{};
  final DateTime started;

  /// Client addresses currently tracked by the rate limit (a count only).
  int Function() rateLimitedSources = () => 0;

  PolicyMetrics({DateTime? started}) : started = started ?? DateTime.now();

  static const _reasons = {'blocked', 'invalid', 'pow', 'rate-limited'};

  /// Records one decision. [msg] is the refusal message (`<class>: …`).
  void record({required bool accepted, String? msg, Object? sourceType, Object? kind}) {
    final prefix = msg == null ? '' : msg.split(':').first.trim();
    final reason = accepted ? 'ok' : (_reasons.contains(prefix) ? prefix : 'other');
    final source = switch (sourceType) {
      'IP4' || 'IP6' => 'client',
      'Stream' => 'stream',
      'Sync' => 'sync',
      'Import' => 'import',
      _ => 'other',
    };
    final kindLabel = switch (kind) {
      4550 => 'alert',
      4551 => 'confirmation',
      _ => 'other',
    };
    final key = 'action="${accepted ? 'accept' : 'reject'}",reason="$reason",source="$source",kind="$kindLabel"';
    _decisions[key] = (_decisions[key] ?? 0) + 1;
  }

  int count({required String action, String? reason}) => _decisions.entries
      .where((e) => e.key.startsWith('action="$action"') && (reason == null || e.key.contains('reason="$reason"')))
      .fold(0, (sum, e) => sum + e.value);

  /// Prometheus text exposition format.
  String render() {
    final out = StringBuffer()
      ..writeln('# HELP roadto_policy_decisions_total Events judged by the RoadTo write policy.')
      ..writeln('# TYPE roadto_policy_decisions_total counter');
    final keys = _decisions.keys.toList()..sort();
    for (final k in keys) {
      out.writeln('roadto_policy_decisions_total{$k} ${_decisions[k]}');
    }
    out
      ..writeln('# HELP roadto_policy_rate_limit_sources Client addresses tracked by the rate limit this minute.')
      ..writeln('# TYPE roadto_policy_rate_limit_sources gauge')
      ..writeln('roadto_policy_rate_limit_sources ${rateLimitedSources()}')
      ..writeln('# HELP roadto_policy_start_time_seconds Start time of the plugin process.')
      ..writeln('# TYPE roadto_policy_start_time_seconds gauge')
      ..writeln('roadto_policy_start_time_seconds ${started.millisecondsSinceEpoch ~/ 1000}');
    return out.toString();
  }
}

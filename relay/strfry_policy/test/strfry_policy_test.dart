import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_strfry_policy/strfry_policy.dart';
import 'package:test/test.dart';

Map<String, dynamic> request(NostrEvent e, {String source = 'IP4', String info = '203.0.113.7'}) => {
  'type': 'new',
  'event': e.toJson(),
  'receivedAt': e.createdAt,
  'sourceType': source,
  'sourceInfo': info,
};

void main() {
  const bellecour = LatLon(45.7578, 4.8320);
  final now = DateTime.now();

  test('accepts a valid alert and a valid confirmation', () {
    final plugin = WritePolicyPlugin();
    final alert = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.closure, position: bellecour, now: now);
    expect(plugin.handle(request(alert), now: now), {'id': alert.id, 'action': 'accept'});
    final confirm = buildConfirmationEvent(
      keys: KeyPair.generate(),
      alert: RoadAlert.fromEvent(alert)!,
      stillThere: false,
      now: now,
    );
    expect(plugin.handle(request(confirm), now: now)['action'], 'accept');
  });

  test('rejects what the core policy rejects, with its reason', () {
    final plugin = WritePolicyPlugin();
    final note = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const [], content: 'spam');
    final out = plugin.handle(request(note), now: now);
    expect(out['action'], 'reject');
    expect(out['msg'], startsWith('blocked:'));
  });

  test('rate limit per client address, not for replication between relays', () {
    final plugin = WritePolicyPlugin(ratePerMinute: 2);
    final keys = KeyPair.generate();
    List<String> send(String source, String info) => [
      for (var i = 0; i < 3; i++)
        plugin.handle(
              request(
                buildAlertEvent(keys: keys, type: AlertType.hazard, position: LatLon(45.75 + i / 100, 4.83), now: now),
                source: source,
                info: info,
              ),
              now: now,
            )['action']
            as String,
    ];
    expect(send('IP4', '198.51.100.1'), ['accept', 'accept', 'reject']);
    expect(send('IP6', '2001:db8::1'), ['accept', 'accept', 'reject']);
    expect(send('Stream', ''), ['accept', 'accept', 'accept']);
    expect(send('Sync', ''), ['accept', 'accept', 'accept']);
  });

  test('the traffic robot is not rate limited; its rules still apply', () {
    final robot = KeyPair.generate();
    final plugin = WritePolicyPlugin(ratePerMinute: 2, unlimitedAuthors: {robot.publicKey});
    String send(KeyPair keys, int i, {int? length}) =>
        plugin.handle(
              request(
                buildAlertEvent(
                  keys: keys,
                  type: AlertType.traffic,
                  position: LatLon(45.75 + i / 100, 4.83),
                  now: now,
                  level: JamLevel.jam,
                  lengthM: length,
                  source: 'bison-fute/S$i',
                ),
                source: 'IP4',
                info: '127.0.0.1',
              ),
              now: now,
            )['action']
            as String;
    expect([for (var i = 0; i < 5; i++) send(robot, i, length: 800)], everyElement('accept'));
    expect(send(robot, 9, length: 99999), 'reject');
    final someone = KeyPair.generate();
    expect([for (var i = 0; i < 3; i++) send(someone, i)], ['accept', 'accept', 'reject']);
  });

  test('garbage lines are answered, never crash', () {
    final plugin = WritePolicyPlugin();
    expect(jsonDecode(plugin.handleLine('not json')), {
      'id': '',
      'action': 'reject',
      'msg': 'invalid: unexpected request',
    });
    expect(jsonDecode(plugin.handleLine('{"type":"new","event":{"id":"abc"}}'))['msg'], 'invalid: malformed event');
  });

  test('speaks the strfry line protocol as a process', () async {
    final alert = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.traffic, position: bellecour);
    final spam = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const []);
    final proc = await Process.start(Platform.resolvedExecutable, ['run', 'bin/roadto_policy.dart']);
    proc.stdin
      ..writeln(jsonEncode(request(alert)))
      ..writeln(jsonEncode(request(spam)));
    await proc.stdin.close();
    final lines = await proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).toList();
    expect(await proc.exitCode, 0);
    expect(lines.map((l) => jsonDecode(l)['action']), ['accept', 'reject']);
    expect(lines.join(), isNot(contains('203.0.113.7')), reason: 'client addresses are never written out');
  });

  group('metrics', () {
    test('count decisions by class, never by address or key', () {
      final plugin = WritePolicyPlugin(ratePerMinute: 1);
      final alert = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.closure, position: bellecour, now: now);
      final second = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.traffic, position: bellecour, now: now);
      final spam = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const [], content: 'spam');
      plugin.handle(request(alert), now: now); // accepted
      plugin.handle(request(second), now: now); // rate-limited (1/min)
      plugin.handle(request(spam, info: '198.51.100.9'), now: now); // blocked
      plugin.handle(
        request(second, source: 'Stream', info: 'ws://peer'),
        now: now,
      ); // replicated: accepted

      final m = plugin.metrics;
      expect(m.count(action: 'accept'), 2);
      expect(m.count(action: 'reject', reason: 'rate-limited'), 1);
      expect(m.count(action: 'reject', reason: 'blocked'), 1);

      final text = m.render();
      expect(
        text,
        contains('roadto_policy_decisions_total{action="accept",reason="ok",source="client",kind="alert"} 1'),
      );
      expect(
        text,
        contains('roadto_policy_decisions_total{action="accept",reason="ok",source="stream",kind="alert"} 1'),
      );
      expect(
        text,
        contains('roadto_policy_decisions_total{action="reject",reason="blocked",source="client",kind="other"} 1'),
      );
      expect(text, contains('roadto_policy_rate_limit_sources 2'));
      for (final secret in ['203.0.113.7', '198.51.100.9', 'ws://peer', alert.id, alert.pubkey]) {
        expect(text, isNot(contains(secret)));
      }
    });

    test('served over HTTP by the entry point', () async {
      final proc = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/roadto_policy.dart'],
        environment: {'ROADTO_METRICS_PORT': '19464'},
      );
      final spam = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const []);
      proc.stdin.writeln(jsonEncode(request(spam)));
      final answers = proc.stdout.transform(utf8.decoder).transform(const LineSplitter());
      expect(jsonDecode(await answers.first)['action'], 'reject');

      final client = HttpClient();
      String? body;
      for (var i = 0; i < 50 && body == null; i++) {
        try {
          final req = await client.get('127.0.0.1', 19464, '/metrics');
          body = await (await req.close()).transform(utf8.decoder).join();
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      client.close();
      await proc.stdin.close();
      proc.kill();
      expect(body, contains('reason="blocked"'));
    });
  });
}

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
}

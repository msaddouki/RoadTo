import 'dart:async';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';

/// End-to-end check of deployed RoadTo relays:
///
///   dart run tool/smoke.dart ws://localhost:7777 [ws://localhost:7778]
///
/// Publishes a valid alert to the first relay and expects it to be accepted,
/// then readable from the last one (replication when two are given); expects
/// spam and police alerts to be refused. Exits non-zero on any failure.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: smoke.dart <relay-url> [<second-relay-url>]');
    exit(64);
  }
  final failures = <String>[];
  void check(bool ok, String what) {
    stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what');
    if (!ok) failures.add(what);
  }

  const position = LatLon(45.7578, 4.8320);
  final writer = RelayPool([args.first]);
  final reader = RelayPool([args.last]);
  final alert = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.closure, position: position);

  final received = reader
      .subscribe([alertFilter(geohashWithNeighbors(geohashEncode(position, precision: subscriptionGeohashPrecision)))])
      .firstWhere((e) => e.id == alert.id)
      .timeout(const Duration(seconds: 15));
  await reader.connect();

  final accepted = await writer.publish(alert);
  check(accepted.single.accepted, 'valid alert accepted by ${args.first} (${accepted.single.message})');

  try {
    await received;
    check(true, 'alert readable from ${args.last}');
  } on TimeoutException {
    check(false, 'alert readable from ${args.last}');
  }

  final spam = await writer.publish(
    NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const [], content: 'spam'),
  );
  check(!spam.single.accepted && spam.single.message.startsWith('blocked:'), 'kind 1 refused (${spam.single.message})');

  final now = DateTime.now();
  final police = NostrEvent.create(
    keys: KeyPair.generate(),
    kind: RoadToKinds.alert,
    createdAt: now,
    powDifficulty: PowPolicy.alert,
    tags: [
      ['t', 'police'],
      ['g', geohashEncode(position, precision: 7)],
      ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 600}'],
    ],
  );
  final refused = await writer.publish(police);
  check(!refused.single.accepted, 'police alert refused (${refused.single.message})');

  await writer.close();
  await reader.close();
  if (failures.isNotEmpty) {
    stderr.writeln('${failures.length} check(s) failed');
    exit(1);
  }
  stdout.writeln('all checks passed');
}

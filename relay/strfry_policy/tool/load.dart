import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:roadto_core/roadto_core.dart';

/// Load test of two federated RoadTo relays:
///
///   dart run tool/load.dart --writer ws://localhost:7777 --reader ws://localhost:7778 \
///     --rate 20 --seconds 30 [--publishers 4] [--max-p95 5]
///
/// Publishes valid alerts (proof of work included) at a steady rate on the
/// writer, over several connections, and times how long each takes to reach
/// a subscriber on the reader: the plan's "an alert published on one phone
/// shows on the other within 5 s, through two relays", under load.
/// Exits non-zero when an alert is refused or lost, or when the 95th
/// percentile exceeds --max-p95 seconds.
///
/// Relays rate-limit each client address (30 events a minute by default):
/// raise ROADTO_RATE_PER_MINUTE on the relays under test.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('writer', mandatory: true)
    ..addOption('reader', mandatory: true)
    ..addOption('rate', defaultsTo: '20', help: 'alerts per second')
    ..addOption('seconds', defaultsTo: '30')
    ..addOption('publishers', defaultsTo: '4', help: 'connections to the writer')
    ..addOption('max-p95', defaultsTo: '5', help: 'seconds');
  final ArgResults o;
  try {
    o = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('${e.message}\n${parser.usage}');
    exit(64);
  }
  final rate = double.parse(o['rate'] as String);
  final count = (rate * double.parse(o['seconds'] as String)).round();
  final publishers = int.parse(o['publishers'] as String);
  final maxP95 = double.parse(o['max-p95'] as String);

  // Alerts are built before the run, proof of work included, so the pace is
  // the relays', not the generator's.
  stdout.writeln('building $count alerts (proof of work)…');
  final rng = Random(42);
  final types = AlertType.values.where((t) => t != AlertType.police).toList();
  final alerts = [
    for (var i = 0; i < count; i++)
      buildAlertEvent(
        keys: KeyPair.generate(),
        type: types[rng.nextInt(types.length)],
        // Spread over the Lyon test region.
        position: LatLon(45.60 + rng.nextDouble() * 0.35, 4.65 + rng.nextDouble() * 0.5),
      ),
  ];

  final reader = RelayConnection(Uri.parse(o['reader'] as String));
  final writers = [for (var i = 0; i < publishers; i++) RelayConnection(Uri.parse(o['writer'] as String))];
  final clock = Stopwatch()..start();
  final sentAt = <String, int>{};
  final latencies = <int>[];
  final pending = alerts.map((a) => a.id).toSet();
  final allIn = Completer<void>();

  reader.events.listen((pair) {
    final (_, event) = pair;
    final t0 = sentAt[event.id];
    if (t0 == null || !pending.remove(event.id)) return;
    latencies.add(clock.elapsedMilliseconds - t0);
    if (pending.isEmpty && !allIn.isCompleted) allIn.complete();
  });
  await reader.connect();
  await Future.wait(writers.map((w) => w.connect()));
  final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
  reader.subscribe('load', [
    NostrFilter(kinds: const [RoadToKinds.alert], since: since),
  ]);
  await Future<void>.delayed(const Duration(seconds: 1)); // subscription in place

  stdout.writeln('publishing $count alerts at $rate/s over $publishers connections…');
  final okLatencies = <int>[];
  final refusals = <String, int>{};
  final interval = 1000 / rate;
  final start = clock.elapsedMilliseconds;
  final publishes = <Future<void>>[];
  for (var i = 0; i < alerts.length; i++) {
    final due = start + (i * interval).round();
    final wait = due - clock.elapsedMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    final alert = alerts[i];
    sentAt[alert.id] = clock.elapsedMilliseconds;
    publishes.add(
      writers[i % publishers].publish(alert).then((r) {
        if (r.accepted) {
          okLatencies.add(clock.elapsedMilliseconds - sentAt[alert.id]!);
        } else {
          pending.remove(alert.id);
          final reason = r.message.split(':').first;
          refusals[reason] = (refusals[reason] ?? 0) + 1;
        }
      }),
    );
  }
  final publishSeconds = (clock.elapsedMilliseconds - start) / 1000;
  await Future.wait(publishes);
  if (pending.isNotEmpty) {
    await allIn.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  final refused = refusals.values.fold(0, (a, b) => a + b);
  final lost = pending.length;
  String pct(List<int> v, double p) {
    if (v.isEmpty) return '-';
    final s = [...v]..sort();
    return '${s[min(s.length - 1, (p * s.length).ceil() - 1)]} ms';
  }

  final p95 = latencies.isEmpty
      ? double.infinity
      : () {
          final s = [...latencies]..sort();
          return s[min(s.length - 1, (0.95 * s.length).ceil() - 1)] / 1000;
        }();
  stdout
    ..writeln('')
    ..writeln('sent      $count in ${publishSeconds.toStringAsFixed(1)} s')
    ..writeln('refused   $refused ${refusals.isEmpty ? '' : refusals}')
    ..writeln('received  ${latencies.length} on the other relay, lost $lost')
    ..writeln('relay OK  p50 ${pct(okLatencies, 0.5)}, p95 ${pct(okLatencies, 0.95)}')
    ..writeln(
      'delivery  p50 ${pct(latencies, 0.5)}, p95 ${pct(latencies, 0.95)}, max ${pct(latencies, 1)} '
      '(publish on one relay -> event on the other)',
    );

  await reader.close();
  for (final w in writers) {
    await w.close();
  }
  final failures = [
    if (refused > 0) '$refused alert(s) refused',
    if (lost > 0) '$lost alert(s) lost',
    if (p95 > maxP95) 'p95 ${p95.toStringAsFixed(2)} s above $maxP95 s',
  ];
  if (failures.isNotEmpty) {
    stderr.writeln('FAIL: ${failures.join(', ')}');
    exit(1);
  }
  stdout.writeln('ok');
}

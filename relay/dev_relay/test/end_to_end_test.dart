import 'dart:async';

import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_dev_relay/dev_relay.dart';
import 'package:test/test.dart';

/// Critères de sortie du J3, rejoués contre le relais de dev : une alerte
/// publiée sur un téléphone apparaît sur l'autre en moins de 5 s, via deux
/// relais, et une alerte expirée n'est plus servie.
void main() {
  const bellecour = LatLon(45.7578, 4.8320);
  late DevRelay relayA, relayB;
  late DateTime now;

  setUp(() async {
    now = DateTime.now();
    relayA = DevRelay(clock: () => now);
    relayB = DevRelay(clock: () => now);
    await relayA.start(port: 0);
    await relayB.start(port: 0);
  });

  tearDown(() async {
    await relayA.stop();
    await relayB.stop();
  });

  test('une alerte publiée par A arrive chez B en moins de 5 s', () async {
    final urls = ['${relayA.url}', '${relayB.url}'];
    final phoneA = RelayPool(urls);
    final phoneB = RelayPool(urls);
    final cells = geohashWithNeighbors(geohashEncode(bellecour, precision: subscriptionGeohashPrecision));

    final received = phoneB.subscribe([alertFilter(cells)], id: 'route').first;
    await phoneB.connect();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final event = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.accident, position: bellecour);
    final watch = Stopwatch()..start();
    final results = await phoneA.publish(event);
    expect(results.every((r) => r.accepted), isTrue, reason: '$results');

    final got = await received.timeout(const Duration(seconds: 5));
    expect(got.id, event.id);
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(relayA.storedEvents, 1);
    expect(relayB.storedEvents, 1);

    await phoneA.close();
    await phoneB.close();
  });

  test('les relais refusent ce que la politique interdit', () async {
    final pool = RelayPool(['${relayA.url}']);
    final spam = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const [], content: 'pub');
    final res = await pool.publish(spam);
    expect(res.single.accepted, isFalse);
    expect(res.single.message, startsWith('blocked:'));
    expect(relayA.storedEvents, 0);
    await pool.close();
  });

  test('une alerte expirée n’est plus servie, même à un nouvel abonné', () async {
    final pool = RelayPool(['${relayA.url}']);
    final event = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.traffic, position: bellecour, now: now);
    expect((await pool.publish(event)).single.accepted, isTrue);

    now = now.add(AlertType.traffic.ttl + const Duration(seconds: 1));
    relayA.purgeExpired();
    expect(relayA.storedEvents, 0);

    final newcomer = RelayPool(['${relayA.url}']);
    final events = <NostrEvent>[];
    newcomer
        .subscribe([
          alertFilter([geohashEncode(bellecour, precision: 5)], now: now),
        ])
        .listen(events.add);
    await newcomer.connect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(events, isEmpty);
    await pool.close();
    await newcomer.close();
  });

  test('limite de débit par connexion', () async {
    final relay = DevRelay(rateLimitPerMinute: 2);
    await relay.start(port: 0);
    final pool = RelayPool(['${relay.url}']);
    final keys = KeyPair.generate();
    final results = <PublishResult>[];
    for (var i = 0; i < 3; i++) {
      results.addAll(
        await pool.publish(
          buildAlertEvent(keys: keys, type: AlertType.hazard, position: LatLon(45.75 + i / 100, 4.83)),
        ),
      );
    }
    expect(results.map((r) => r.accepted), [true, true, false]);
    expect(results.last.message, startsWith('rate-limited:'));
    await pool.close();
    await relay.stop();
  });
}

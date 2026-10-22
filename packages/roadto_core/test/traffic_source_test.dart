import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

void main() {
  final robot = KeyPair.fromPrivateKey('1' * 64);
  final someone = KeyPair.fromPrivateKey('2' * 64);
  const here = LatLon(45.7485, 4.8467);
  final t0 = DateTime.utc(2026, 10, 22, 8);

  NostrEvent jam(
    KeyPair keys,
    DateTime at, {
    JamLevel? level = JamLevel.jam,
    int? length = 900,
    String? src = 'bison-fute/MQA01.E1',
  }) => buildAlertEvent(
    keys: keys,
    type: AlertType.traffic,
    position: here,
    now: at,
    level: level,
    lengthM: length,
    source: src,
    lasting: const Duration(minutes: 10),
  );

  test('the robot’s jam: level, length and source; shorter life asked', () {
    final e = jam(robot, t0);
    expect(e.expiration, t0.add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000);
    final a = RoadAlert.fromEvent(e, trustedSources: {robot.publicKey})!;
    expect(a.level, JamLevel.jam);
    expect(a.lengthM, 900);
    expect(a.source, 'bison-fute/MQA01.E1');
    expect(a.sourceLabel, 'Bison Futé');
    expect(checkWritePolicy(e, now: t0), isNull);
  });

  test('a source is believed from the robot only; level and length from anyone', () {
    final a = RoadAlert.fromEvent(jam(someone, t0), trustedSources: {robot.publicKey})!;
    expect(a.source, isNull);
    expect(a.sourceLabel, isNull);
    expect(a.level, JamLevel.jam);
    expect(a.lengthM, 900);
  });

  test('each site’s newest alert replaces the previous one; a late one is dropped', () {
    final store = AlertStore(trustedSources: {robot.publicKey});
    final first = jam(robot, t0);
    final second = jam(robot, t0.add(const Duration(minutes: 5)), level: JamLevel.stopped);
    final now = t0.add(const Duration(minutes: 6));
    expect(store.ingest(first, now: now), isTrue);
    expect(store.ingest(second, now: now), isTrue);
    expect(store.all.map((a) => a.id), [second.id]);
    expect(store.all.single.level, JamLevel.stopped);
    expect(store.ingest(first, now: now), isFalse, reason: 'older than what is known');
    expect(store.all.map((a) => a.id), [second.id]);
    // Another site, and anyone else's "source", stay side by side.
    store.ingest(jam(robot, t0, src: 'bison-fute/MQA01.E2'), now: now);
    store.ingest(jam(someone, t0.add(const Duration(minutes: 1))), now: now);
    store.ingest(jam(someone, t0.add(const Duration(minutes: 2))), now: now);
    expect(store.all, hasLength(4));
  });

  test('the jammed stretch: from the robot only, checked by the relays', () {
    const stretch = [LatLon(45.7485, 4.8467), LatLon(45.7510, 4.8480), LatLon(45.7540, 4.8490)];
    NostrEvent shaped(KeyPair keys) => buildAlertEvent(
      keys: keys,
      type: AlertType.traffic,
      position: here,
      now: t0,
      level: JamLevel.stopped,
      source: 'bison-fute/S1',
      shape: stretch,
    );
    final mine = RoadAlert.fromEvent(shaped(robot), trustedSources: {robot.publicKey})!;
    expect(mine.shape, hasLength(3));
    expect(distanceM(mine.shape!.last, stretch.last), lessThan(0.5));
    expect(mine.level!.color, '#8E1B1B');
    expect(RoadAlert.fromEvent(shaped(someone), trustedSources: {robot.publicKey})!.shape, isNull);
    expect(checkWritePolicy(shaped(someone), now: t0), isNull);

    NostrEvent tagged(String type, String shape) => NostrEvent.create(
      keys: someone,
      kind: RoadToKinds.alert,
      createdAt: t0,
      powDifficulty: PowPolicy.alert,
      tags: [
        ['t', type],
        ['g', 'u05k'],
        ['g', 'u05kq'],
        ['expiration', '${t0.millisecondsSinceEpoch ~/ 1000 + 600}'],
        ['shape', shape],
      ],
    );
    expect(checkWritePolicy(tagged('traffic', 'a' * 5000), now: t0), 'invalid: tracé');
    expect(checkWritePolicy(tagged('traffic', 'abc def'), now: t0), 'invalid: tracé');
    expect(checkWritePolicy(tagged('accident', encodePolyline(stretch)), now: t0), 'invalid: tracé');
    // Garbage that passes the relay is still never drawn.
    final garbage = RoadAlert.fromEvent(tagged('traffic', '~~~~'), trustedSources: {someone.publicKey})!;
    expect(garbage.shape, isNull);
  });

  test('sensor alerts are not asked about', () {
    final sensor = RoadAlert.fromEvent(jam(robot, t0), trustedSources: {robot.publicKey})!;
    final driver = RoadAlert.fromEvent(jam(someone, t0, src: null), trustedSources: {robot.publicKey})!;
    expect(alertsToConfirm(here, [sensor, driver], alreadyAsked: {}).map((a) => a.id), [driver.id]);
  });

  test('relay rules: level, length and source checked', () {
    expect(checkWritePolicy(jam(someone, t0, src: null), now: t0), isNull);
    final badLevel = NostrEvent.create(
      keys: someone,
      kind: RoadToKinds.alert,
      createdAt: t0,
      powDifficulty: PowPolicy.alert,
      tags: [
        ['t', 'traffic'],
        ['g', 'u05k'],
        ['g', 'u05kq'],
        ['expiration', '${t0.millisecondsSinceEpoch ~/ 1000 + 600}'],
        ['level', 'terrible'],
      ],
    );
    expect(checkWritePolicy(badLevel, now: t0), 'invalid: niveau de bouchon');
    expect(checkWritePolicy(jam(someone, t0, length: 50000), now: t0), 'invalid: longueur de bouchon');
    expect(checkWritePolicy(jam(someone, t0, src: 'Bison Futé!'), now: t0), 'invalid: source');
    final accident = buildAlertEvent(keys: someone, type: AlertType.accident, position: here, now: t0);
    expect(checkWritePolicy(accident, now: t0), isNull);
  });

  test('a long standstill weighs more than a short slowdown', () {
    final route = TripRoute(
      shape: [here, const LatLon(45.7575, 4.8467)],
      maneuvers: const [
        Maneuver(type: 1, instruction: 'Partez.', beginShapeIndex: 0, lengthM: 1000, timeS: 72),
        Maneuver(type: 4, instruction: 'Arrivée.', beginShapeIndex: 1, lengthM: 0, timeS: 0),
      ],
      lengthM: 1000,
      timeS: 72,
    );
    RoadAlert at(JamLevel? level, int? length) => RoadAlert.fromEvent(
      buildAlertEvent(
        keys: someone,
        type: AlertType.traffic,
        position: const LatLon(45.7530, 4.8467),
        now: t0,
        level: level,
        lengthM: length,
      ),
    )!;
    Duration delay(RoadAlert a) => trafficDelays(route, [a]).single.delay;
    final slow = delay(at(JamLevel.slow, 300));
    final stopped = delay(at(JamLevel.stopped, 1500));
    final unknown = delay(at(null, null));
    // 50 km/h planned: 300 m at 25 km/h adds ~22 s; 1500 m at 5 km/h ~16 min; unknown 500 m at 10 km/h ~2.4 min.
    expect(slow.inSeconds, closeTo(300 / (25 / 3.6) - 300 / (50 / 3.6), 1));
    expect(stopped.inSeconds, closeTo(1500 / (5 / 3.6) - 1500 / (50 / 3.6), 1));
    expect(unknown.inSeconds, closeTo(500 / (10 / 3.6) - 500 / (50 / 3.6), 1));
    expect(stopped, greaterThan(unknown));
    expect(unknown, greaterThan(slow));
  });
}

import 'dart:convert';

import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

void main() {
  const bellecour = LatLon(45.7578, 4.8320);
  final now = DateTime.utc(2026, 10, 12, 8);

  group('événements Nostr', () {
    test('signature valide, puis falsification détectée', () {
      final keys = KeyPair.generate();
      final e = NostrEvent.create(keys: keys, kind: 1, tags: const [], content: 'salut');
      expect(e.verify(), isTrue);
      final json = e.toJson()..['content'] = 'modifié';
      expect(NostrEvent.fromJson(json).verify(), isFalse);
    });

    test('aller-retour JSON', () {
      final e = NostrEvent.create(
        keys: KeyPair.generate(),
        kind: 1,
        tags: const [
          ['t', 'x'],
        ],
      );
      final back = NostrEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.id, e.id);
      expect(back.verify(), isTrue);
    });

    test('preuve de travail NIP-13', () {
      final e = NostrEvent.create(keys: KeyPair.generate(), kind: 1, tags: const [], powDifficulty: 10);
      expect(e.powBits, greaterThanOrEqualTo(10));
      expect(e.tag('nonce'), isNotNull);
      expect(leadingZeroBits('000f'), 12);
      expect(leadingZeroBits('7fff'), 1);
      expect(leadingZeroBits('8000'), 0);
    });

    test('filtre sur tags', () {
      final e = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.accident, position: bellecour, now: now);
      final h5 = geohashEncode(bellecour, precision: 5);
      expect(
        NostrFilter(
          kinds: RoadToKinds.all,
          tags: {
            'g': [h5],
          },
        ).matches(e),
        isTrue,
      );
      expect(
        const NostrFilter(
          tags: {
            'g': ['zzzzz'],
          },
        ).matches(e),
        isFalse,
      );
      expect(
        NostrFilter.fromJson(
          NostrFilter(
            kinds: [1],
            tags: {
              'g': [h5],
            },
            since: 3,
          ).toJson(),
        ).toJson(),
        {
          'kinds': [1],
          '#g': [h5],
          'since': 3,
        },
      );
    });
  });

  group('alertes', () {
    test('un signalement ne publie que la maille 7, pas la position exacte', () {
      final e = buildAlertEvent(
        keys: KeyPair.generate(),
        type: AlertType.traffic,
        position: bellecour,
        bearing: 87,
        now: now,
      );
      expect(e.tagValues('g').map((h) => h.length), [4, 5, 6, 7]);
      expect(e.tag('bearing'), '90');
      final a = RoadAlert.fromEvent(e)!;
      expect(a.type, AlertType.traffic);
      expect(a.expiresAt, now.add(AlertType.traffic.ttl));
      expect(distanceM(a.position, bellecour), lessThan(110));
      expect(checkWritePolicy(e, now: now), isNull);
    });

    test('police : désactivée par le flag', () {
      expect(AlertType.reportable, isNot(contains(AlertType.police)));
      expect(
        () => buildAlertEvent(keys: KeyPair.generate(), type: AlertType.police, position: bellecour),
        throwsStateError,
      );
    });

    test('expiration : l’alerte disparaît', () {
      final store = AlertStore();
      final e = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.traffic, position: bellecour, now: now);
      expect(store.ingest(e, now: now), isTrue);
      expect(store.visible(now: now), hasLength(1));
      final later = now.add(const Duration(minutes: 31));
      expect(store.visible(now: later), isEmpty);
      expect(store.ingest(e, now: later), isFalse, reason: 'un événement expiré est ignoré');
      store.purge(now: later);
      expect(store.all, isEmpty);
    });

    test('« toujours là ? » : deux « non » masquent, un « oui » rafraîchit', () {
      final store = AlertStore();
      final alertEvent = buildAlertEvent(
        keys: KeyPair.generate(),
        type: AlertType.hazard,
        position: bellecour,
        now: now,
      );
      store.ingest(alertEvent, now: now);
      final alert = RoadAlert.fromEvent(alertEvent)!;
      expect(store.reliability(alert.id, now: now), closeTo(1, 1e-9));

      final t = now.add(const Duration(minutes: 20));
      final aging = store.reliability(alert.id, now: t);
      store.ingest(
        buildConfirmationEvent(keys: KeyPair.generate(), alert: alert, stillThere: true, now: t),
        now: t,
      );
      expect(store.reliability(alert.id, now: t), greaterThan(aging));

      for (var i = 0; i < 3; i++) {
        store.ingest(
          buildConfirmationEvent(keys: KeyPair.generate(), alert: alert, stillThere: false, now: t),
          now: t,
        );
      }
      expect(store.visible(now: t), isEmpty);
    });

    test('résumé des « toujours là » : nombre de conducteurs et dernier « oui »', () {
      final t0 = DateTime.now().toUtc();
      final store = AlertStore();
      final e = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.accident, position: bellecour, now: t0);
      store.ingest(e, now: t0);
      final alert = store[e.id]!;
      expect(store.stillThere(alert.id), (count: 0, latest: null));
      NostrEvent answer(bool yes, int minutes) => buildConfirmationEvent(
        keys: KeyPair.generate(),
        alert: alert,
        stillThere: yes,
        now: t0.add(Duration(minutes: minutes)),
      );
      for (final c in [answer(true, 2), answer(false, 3), answer(true, 5)]) {
        store.ingest(c, now: t0.add(const Duration(minutes: 6)));
      }
      final s = store.stillThere(alert.id);
      expect(s.count, 2);
      expect(s.latest!.difference(t0).inSeconds, closeTo(300, 1)); // event times are whole seconds
    });

    test('une personne ne compte qu’une fois, l’auteur pas du tout', () {
      final store = AlertStore();
      final author = KeyPair.generate();
      final alertEvent = buildAlertEvent(keys: author, type: AlertType.hazard, position: bellecour, now: now);
      store.ingest(alertEvent, now: now);
      final alert = RoadAlert.fromEvent(alertEvent)!;
      expect(
        store.ingest(
          buildConfirmationEvent(keys: author, alert: alert, stillThere: true, now: now),
          now: now,
        ),
        isFalse,
      );
      final voter = KeyPair.generate();
      store.ingest(
        buildConfirmationEvent(keys: voter, alert: alert, stillThere: false, now: now),
        now: now,
      );
      final once = store.reliability(alert.id, now: now);
      store.ingest(
        buildConfirmationEvent(keys: voter, alert: alert, stillThere: false, now: now.add(const Duration(seconds: 5))),
        now: now,
      );
      expect(store.reliability(alert.id, now: now), closeTo(once, 0.01));
    });
  });

  group('politique d’écriture des relais', () {
    final keys = KeyPair.generate();

    test('refuse un kind hors liste', () {
      final e = NostrEvent.create(keys: keys, kind: 1, tags: const []);
      expect(checkWritePolicy(e, now: now), startsWith('blocked:'));
    });

    test('signature : vérifiée sauf si le relais l’a déjà fait', () {
      final e = buildAlertEvent(keys: KeyPair.generate(), type: AlertType.hazard, position: bellecour, now: now);
      final json = e.toJson()..['sig'] = '${'0' * 127}1';
      final forged = NostrEvent.fromJson(json);
      expect(checkWritePolicy(forged, now: now), 'invalid: identifiant ou signature');
      expect(checkWritePolicy(forged, now: now, verifySignature: false), isNull);
    });

    test('refuse une PoW insuffisante', () {
      NostrEvent e;
      var i = 0;
      // Un identifiant peut, par hasard, commencer par assez de zéros.
      do {
        e = NostrEvent.create(
          keys: keys,
          kind: RoadToKinds.alert,
          createdAt: now,
          tags: [
            ['t', 'traffic'],
            ['g', 'u05kq'],
            ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 600}'],
            ['n', '${i++}'],
          ],
        );
      } while (e.powBits >= PowPolicy.alert);
      expect(checkWritePolicy(e, now: now), startsWith('pow:'));
    });

    test('refuse un géohash incohérent', () {
      final e = NostrEvent.create(
        keys: keys,
        kind: RoadToKinds.alert,
        createdAt: now,
        powDifficulty: PowPolicy.alert,
        tags: [
          ['t', 'traffic'],
          ['g', 'u05kq3k'],
          ['g', 'gbsuv'],
          ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 600}'],
        ],
      );
      expect(checkWritePolicy(e, now: now), 'invalid: géohash incohérent');
    });

    test('refuse le kind police tant que le flag est coupé', () {
      final e = NostrEvent.create(
        keys: keys,
        kind: RoadToKinds.alert,
        createdAt: now,
        powDifficulty: PowPolicy.alert,
        tags: [
          ['t', 'police'],
          ['g', 'u05kq3k'],
          ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 600}'],
        ],
      );
      expect(checkWritePolicy(e, now: now), startsWith('blocked:'));
    });

    test('refuse une expiration trop lointaine', () {
      final e = NostrEvent.create(
        keys: keys,
        kind: RoadToKinds.alert,
        createdAt: now,
        powDifficulty: PowPolicy.alert,
        tags: [
          ['t', 'traffic'],
          ['g', 'u05kq3k'],
          ['expiration', '${now.millisecondsSinceEpoch ~/ 1000 + 86400}'],
        ],
      );
      expect(checkWritePolicy(e, now: now), 'invalid: expiration trop lointaine');
    });

    test('accepte une confirmation bien formée', () {
      final alert = RoadAlert.fromEvent(
        buildAlertEvent(keys: keys, type: AlertType.roadworks, position: bellecour, now: now),
      )!;
      final c = buildConfirmationEvent(keys: KeyPair.generate(), alert: alert, stillThere: true, now: now);
      expect(checkWritePolicy(c, now: now), isNull);
    });
  });
}

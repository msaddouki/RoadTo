import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

void main() {
  const bellecour = LatLon(45.7578, 4.8320);
  NostrEvent alert() => buildAlertEvent(keys: KeyPair.generate(), type: AlertType.traffic, position: bellecour);

  for (final background in [true, false]) {
    group(background ? 'background isolate' : 'inline', () {
      late EventVerifier verifier;
      setUp(() => verifier = EventVerifier(background: background));
      tearDown(() => verifier.close());

      test('accepts a valid event, refuses forged ones', () async {
        final e = alert();
        expect(await verifier.verify(e), isTrue);

        final badSig = NostrEvent.fromJson(e.toJson()..['sig'] = '${'0' * 127}1');
        expect(await verifier.verify(badSig), isFalse);

        // Same id and signature as a checked event, other content: the id
        // check catches it, the signature cache never vouches for it.
        final otherContent = NostrEvent.fromJson(e.toJson()..['content'] = 'forged');
        expect(await verifier.verify(otherContent), isFalse);
      });

      test('many events at once, in any order', () async {
        final events = [for (var i = 0; i < 20; i++) alert()];
        final results = await Future.wait(events.map(verifier.verify));
        expect(results, everyElement(isTrue));
      });
    });
  }

  test('a signature is checked once, even for concurrent copies', () async {
    final verifier = EventVerifier(background: false);
    final e = alert();
    final copies = await Future.wait([for (var i = 0; i < 5; i++) verifier.verify(NostrEvent.fromJson(e.toJson()))]);
    expect(copies, everyElement(isTrue));
    // Cached: a copy is answered without a new Schnorr check (fast).
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      await verifier.verify(NostrEvent.fromJson(e.toJson()));
    }
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: '200 cached checks took ${sw.elapsedMilliseconds} ms');
  });

  test('the pool closes the verifier it created', () async {
    final pool = RelayPool(const []);
    expect(await pool.verifier.verify(alert()), isTrue);
    await pool.close();
  });
}

import 'dart:math';
import 'dart:typed_data';

import 'package:roadto_core/roadto_core.dart';
import 'package:test/test.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('bech32 (BIP-173)', () {
    test('valid strings from the BIP', () {
      for (final s in ['A12UEL5L', 'abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw', '?1ezyfcl']) {
        expect(() => Bech32.decode(s), returnsNormally, reason: s);
      }
    });

    test('invalid strings from the BIP', () {
      for (final s in [
        '1nwldj5',
        'pzry9x0s0muk',
        'x1b4n0q5v',
        'li1dgmt3',
        'A1G7SGD8',
        'a1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqXw',
      ]) {
        expect(() => Bech32.decode(s), throwsFormatException, reason: s);
      }
    });

    test('round trip', () {
      final data = List<int>.generate(91, (i) => (i * 37) & 0xff);
      final (hrp, back) = Bech32.decode(Bech32.encode('ncryptsec', data));
      expect(hrp, 'ncryptsec');
      expect(back, data);
    });
  });

  group('NIP-49', () {
    test('password normalization (NIP-49 test data)', () {
      expect(EncryptedKey.normalizedPassword('ÅΩẛ̣'), [0xC3, 0x85, 0xCE, 0xA9, 0xE1, 0xB9, 0xA9]);
    });

    test('decrypts the NIP-49 test vector', () async {
      const encrypted =
          'ncryptsec1qgg9947rlpvqu76pj5ecreduf9jxhselq2nae2kghhvd5g7dgjtcxfqtd67p9m0w57lspw8gsq6yphnm8623nsl8xn9j4jdzz84zm3frztj3z7s35vpzmqf6ksu8r89qk5z2zxfmu5gv8th8wclt0h4p';
      final key = await EncryptedKey.decrypt(encrypted, 'nostr');
      expect(_hex(key), '3501454135014541350145413501453fefb02227e449e57cf4d3a3ce05378683');
    }, timeout: const Timeout(Duration(minutes: 2)));

    // Low scrypt cost: the format, not the KDF, is under test here.
    test('round trip, wrong password, damaged text', () async {
      final sk = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final enc = await EncryptedKey.encrypt(sk, 'mot de passe é', logN: 4, random: Random(1));
      expect(enc, startsWith('ncryptsec1'));
      expect(Bech32.decode(enc).$2, hasLength(91));
      expect(await EncryptedKey.decrypt(enc, 'mot de passe é'), sk);
      // The same password typed decomposed (e + combining accent) still works.
      expect(await EncryptedKey.decrypt(enc, 'mot de passe é'), sk);

      await expectLater(
        EncryptedKey.decrypt(enc, 'autre'),
        throwsA(isA<EncryptedKeyException>().having((e) => e.message, 'message', 'Mot de passe incorrect')),
      );
      final damaged = '${enc.substring(0, 30)}${enc[30] == 'q' ? 'p' : 'q'}${enc.substring(31)}';
      await expectLater(EncryptedKey.decrypt(damaged, 'mot de passe é'), throwsA(isA<EncryptedKeyException>()));
      await expectLater(EncryptedKey.decrypt('npub1xyz', 'x'), throwsA(isA<EncryptedKeyException>()));
    });

    test('the key security byte is authenticated', () async {
      final sk = Uint8List(32)..[0] = 7;
      final enc = await EncryptedKey.encrypt(sk, 'pw', logN: 4, security: KeySecurity.unknown);
      final (_, data) = Bech32.decode(enc);
      expect(data[42], 2);
      data[42] = 1; // claim the key was handled securely
      await expectLater(
        EncryptedKey.decrypt(Bech32.encode('ncryptsec', data), 'pw'),
        throwsA(isA<EncryptedKeyException>()),
      );
    });

    test('a KeyPair round-trips through hex', () async {
      final keys = KeyPair.generate();
      final enc = await EncryptedKey.encryptHex(keys.privateKey, 'pw', logN: 4);
      expect(await EncryptedKey.decryptToHex(enc, 'pw'), keys.privateKey);
      expect(() => EncryptedKey.encryptHex('zz', 'pw'), throwsArgumentError);
    });
  });
}

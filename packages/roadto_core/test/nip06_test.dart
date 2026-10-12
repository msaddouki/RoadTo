import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_core/src/nostr/bip39_english.dart';
import 'package:test/test.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('wordlist is the official BIP-39 English list', () {
    // SHA-256 of bip-0039/english.txt.
    expect(
      sha256.convert(utf8.encode('${bip39English.join('\n')}\n')).toString(),
      '2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda',
    );
  });

  group('BIP-39 (Trezor reference vectors)', () {
    test('entropy to words and seed', () {
      final p = RecoveryPhrase.fromEntropy(List.filled(16, 0));
      expect(p.toString(), List.filled(11, 'abandon').followedBy(['about']).join(' '));
      expect(
        _hex(p.seed(passphrase: 'TREZOR')),
        'c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04',
      );
    });

    test('24-word vector', () {
      final p = RecoveryPhrase.fromEntropy(List.filled(32, 0x7f));
      expect(
        p.toString(),
        'legal winner thank year wave sausage worth useful legal winner thank year wave sausage worth useful '
        'legal winner thank year wave sausage worth title',
      );
    });
  });

  group('NIP-06 vectors', () {
    test('12 words', () {
      final keys = RecoveryPhrase.parse(
        'leader monkey parrot ring guide accident before fence cannon height naive bean',
      ).keyPair();
      expect(keys.privateKey, '7f7ff03d123792d6ac594bfa67bf6d0c0ab55b6b1fdb6249303fe861f1ccba9a');
      expect(keys.publicKey, '17162c921dc4d2518f9a101db33695df1afb56ab82f5ff3e5da6eec3ca5cd917');
    });

    test('24 words', () {
      final keys = RecoveryPhrase.parse(
        'what bleak badge arrange retreat wolf trade produce cricket blur garlic valid proud rude strong '
        'choose busy staff weather area salt hollow arm fade',
      ).keyPair();
      expect(keys.privateKey, 'c15d739894c81a2fcfd3a2df85a0d2c0dbc47a280d092799f144d73d7ae78add');
      expect(keys.publicKey, 'd41b22899549e1f3d335a31002cfd382174006e166d3e658e3a5eecdb6463573');
    });
  });

  group('parsing what people type', () {
    test('case and spaces do not matter', () {
      final p = RecoveryPhrase.parse(
        '  Leader MONKEY parrot ring guide accident\nbefore fence cannon height naive bean ',
      );
      expect(p.words.first, 'leader');
    });

    test('wrong count, unknown word and bad checksum are explained', () {
      expect(() => RecoveryPhrase.parse('leader monkey'), throwsA(isA<FormatException>()));
      expect(
        () => RecoveryPhrase.parse('leader monkey parrot ring guide accident before fence cannon height naive beans'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('beans'))),
      );
      expect(
        () => RecoveryPhrase.parse('monkey leader parrot ring guide accident before fence cannon height naive bean'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('ordre'))),
      );
    });

    test('a generated phrase restores the same key', () {
      final p = RecoveryPhrase.generate();
      expect(p.words, hasLength(12));
      expect(RecoveryPhrase.parse(p.toString()).keyPair().publicKey, p.keyPair().publicKey);
      expect(RecoveryPhrase.generate(words: 24).words, hasLength(24));
    });
  });
}

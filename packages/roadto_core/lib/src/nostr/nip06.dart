import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

import 'bip39_english.dart';
import 'keys.dart';

/// Recovery phrase for the user's identity (NIP-06): a BIP-39 mnemonic whose
/// seed is derived with BIP-32 along `m/44'/1237'/<account>'/0/0`. The same
/// words restore the same key in RoadTo and in any NIP-06 Nostr client.
///
/// Only the English wordlist is used: it is the one other Nostr clients
/// expect when restoring.
class RecoveryPhrase {
  final List<String> words;

  RecoveryPhrase._(this.words);

  static final _random = math.Random.secure();
  static final _index = {for (var i = 0; i < bip39English.length; i++) bip39English[i]: i};

  /// New phrase of 12 (128-bit) or 24 (256-bit) words.
  factory RecoveryPhrase.generate({int words = 12}) {
    if (words != 12 && words != 24) throw ArgumentError('12 or 24 words');
    final entropy = Uint8List.fromList([for (var i = 0; i < words * 4 ~/ 3; i++) _random.nextInt(256)]);
    return RecoveryPhrase.fromEntropy(entropy);
  }

  /// BIP-39: entropy + checksum (first ENT/32 bits of its SHA-256), cut into
  /// 11-bit word indexes.
  factory RecoveryPhrase.fromEntropy(List<int> entropy) {
    if (entropy.length < 16 || entropy.length > 32 || entropy.length % 4 != 0) {
      throw ArgumentError('entropy must be 16 to 32 bytes, a multiple of 4');
    }
    final checksumBits = entropy.length * 8 ~/ 32;
    final hash = sha256.convert(entropy).bytes;
    final bits = StringBuffer();
    for (final b in entropy) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    bits.write(hash[0].toRadixString(2).padLeft(8, '0').substring(0, checksumBits));
    final s = bits.toString();
    return RecoveryPhrase._([
      for (var i = 0; i < s.length; i += 11) bip39English[int.parse(s.substring(i, i + 11), radix: 2)],
    ]);
  }

  /// Parses a phrase typed by the user (any case, extra spaces). Throws
  /// [FormatException] with a message for the user (in French) when it is
  /// not a valid BIP-39 phrase.
  factory RecoveryPhrase.parse(String input) {
    final words = input.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (![12, 15, 18, 21, 24].contains(words.length)) {
      throw FormatException('La phrase doit compter 12 ou 24 mots (${words.length} saisis).');
    }
    final unknown = words.where((w) => !_index.containsKey(w)).toList();
    if (unknown.isNotEmpty) throw FormatException('Mot inconnu : ${unknown.first}');
    final bits = words.map((w) => _index[w]!.toRadixString(2).padLeft(11, '0')).join();
    final checksumBits = bits.length ~/ 33;
    final entropyBits = bits.substring(0, bits.length - checksumBits);
    final entropy = [
      for (var i = 0; i < entropyBits.length; i += 8) int.parse(entropyBits.substring(i, i + 8), radix: 2),
    ];
    if (RecoveryPhrase.fromEntropy(entropy).words.join(' ') != words.join(' ')) {
      throw const FormatException('Phrase invalide : un mot est mal saisi ou dans le mauvais ordre.');
    }
    return RecoveryPhrase._(words);
  }

  @override
  String toString() => words.join(' ');

  /// BIP-39 seed: PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" + passphrase.
  Uint8List seed({String passphrase = ''}) =>
      _pbkdf2Sha512(utf8.encode(words.join(' ')), utf8.encode('mnemonic$passphrase'), 2048, 64);

  /// NIP-06 key for [account] (0 for the main identity).
  KeyPair keyPair({int account = 0, String passphrase = ''}) {
    var (key, chain) = _master(seed(passphrase: passphrase));
    for (final index in [44 | _hardened, 1237 | _hardened, account | _hardened, 0, 0]) {
      (key, chain) = _child(key, chain, index);
    }
    return KeyPair.fromPrivateKey(key.toRadixString(16).padLeft(64, '0'));
  }
}

const _hardened = 0x80000000;
final _curve = ECCurve_secp256k1();

Uint8List _pbkdf2Sha512(List<int> password, List<int> salt, int rounds, int length) {
  final hmac = Hmac(sha512, password);
  final out = BytesBuilder();
  for (var block = 1; out.length < length; block++) {
    var u = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return out.toBytes().sublist(0, length);
}

BigInt _toBig(List<int> bytes) => bytes.fold(BigInt.zero, (n, b) => (n << 8) | BigInt.from(b));

List<int> _ser256(BigInt n) {
  final hex = n.toRadixString(16).padLeft(64, '0');
  return [for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
}

/// BIP-32 master key and chain code.
(BigInt, List<int>) _master(List<int> seed) {
  final i = Hmac(sha512, utf8.encode('Bitcoin seed')).convert(seed).bytes;
  return (_toBig(i.sublist(0, 32)), i.sublist(32));
}

/// BIP-32 private child key derivation (CKDpriv).
(BigInt, List<int>) _child(BigInt key, List<int> chain, int index) {
  final data = index & _hardened != 0 ? [0, ..._ser256(key)] : (_curve.G * key)!.getEncoded(true).toList();
  data.addAll([index >> 24 & 0xff, index >> 16 & 0xff, index >> 8 & 0xff, index & 0xff]);
  final i = Hmac(sha512, chain).convert(data).bytes;
  final il = _toBig(i.sublist(0, 32));
  final child = (il + key) % _curve.n;
  if (il >= _curve.n || child == BigInt.zero) {
    // Probability below 2^-127; BIP-32 says to skip to the next index.
    return _child(key, chain, index + 1);
  }
  return (child, i.sublist(32));
}

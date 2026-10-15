import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/key_derivators/api.dart' show ScryptParameters;
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'bech32.dart';

/// How the key was handled before encryption (NIP-49 key security byte).
enum KeySecurity {
  /// Known to have been handled insecurely (shown, copied in clear…).
  insecure(0),

  /// Never known to have been handled insecurely.
  secure(1),

  /// Not tracked.
  unknown(2);

  final int byte;

  const KeySecurity(this.byte);
}

class EncryptedKeyException implements Exception {
  final String message;

  const EncryptedKeyException(this.message);

  @override
  String toString() => 'EncryptedKeyException: $message';
}

/// A private key encrypted with a password, NIP-49 (`ncryptsec1…`): scrypt
/// (r = 8, p = 1) then XChaCha20-Poly1305. Readable by any Nostr client that
/// supports NIP-49.
///
/// scrypt is deliberately slow and memory-hungry (2^[logN] × 1 KiB: 64 MiB
/// for the default 16): run it off the UI thread.
abstract final class EncryptedKey {
  static const prefix = 'ncryptsec';
  static const defaultLogN = 16;
  static const _version = 0x02;
  static const _length = 91;

  static final _aead = Xchacha20.poly1305Aead();

  static Future<String> encrypt(
    List<int> privateKey,
    String password, {
    int logN = defaultLogN,
    KeySecurity security = KeySecurity.secure,
    Random? random,
  }) async {
    if (privateKey.length != 32) throw ArgumentError('the private key is 32 bytes');
    if (logN < 1 || logN > 22) throw ArgumentError('logN out of range: $logN');
    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
    final nonce = Uint8List.fromList([for (var i = 0; i < 24; i++) rng.nextInt(256)]);
    final key = _derive(password, salt, logN);
    try {
      final box = await _aead.encrypt(privateKey, secretKey: SecretKey(key), nonce: nonce, aad: [security.byte]);
      return Bech32.encode(prefix, [
        _version,
        logN,
        ...salt,
        ...nonce,
        security.byte,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// The 32-byte private key. Throws [EncryptedKeyException] on a wrong
  /// password or a damaged text.
  static Future<Uint8List> decrypt(String encrypted, String password) async {
    final String hrp;
    final Uint8List data;
    try {
      (hrp, data) = Bech32.decode(encrypted.trim());
    } on FormatException catch (e) {
      throw EncryptedKeyException('Texte illisible (${e.message})');
    }
    if (hrp != prefix || data.length != _length) throw const EncryptedKeyException('Ce n’est pas une clé chiffrée');
    if (data[0] != _version) throw EncryptedKeyException('Version ${data[0]} non prise en charge');
    final logN = data[1];
    if (logN < 1 || logN > 22) throw EncryptedKeyException('Paramètre de dérivation invalide ($logN)');
    final salt = data.sublist(2, 18), nonce = data.sublist(18, 42), aad = data.sublist(42, 43);
    final cipherText = data.sublist(43, 75), mac = data.sublist(75, 91);
    final key = _derive(password, salt, logN);
    try {
      final clear = await _aead.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const EncryptedKeyException('Mot de passe incorrect');
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  /// [encrypt] for a key in hex, as [KeyPair.privateKey] holds it.
  static Future<String> encryptHex(String privateKeyHex, String password, {int logN = defaultLogN}) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(privateKeyHex)) throw ArgumentError('not a 32-byte hex key');
    final bytes = [for (var i = 0; i < 64; i += 2) int.parse(privateKeyHex.substring(i, i + 2), radix: 16)];
    return encrypt(bytes, password, logN: logN);
  }

  /// [decrypt] to hex, ready for [KeyPair.fromPrivateKey].
  static Future<String> decryptToHex(String encrypted, String password) async =>
      (await decrypt(encrypted, password)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Password as NFKC UTF-8, so the same password typed on another device or
  /// keyboard gives the same key.
  static Uint8List normalizedPassword(String password) => Uint8List.fromList(utf8.encode(unorm.nfkc(password)));

  static Uint8List _derive(String password, Uint8List salt, int logN) {
    final scrypt = Scrypt()..init(ScryptParameters(1 << logN, 8, 1, 32, salt));
    return scrypt.process(normalizedPassword(password));
  }
}

import 'dart:isolate';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roadto_core/roadto_core.dart';

/// Minimal key-value secret storage, so the identity logic can be tested
/// without the platform keystore.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore / iOS Keychain.
class PlatformSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  const PlatformSecretStore([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class Identity {
  final KeyPair keys;

  /// Identities created before the recovery phrase existed have none.
  final bool hasRecoveryPhrase;

  const Identity(this.keys, {required this.hasRecoveryPhrase});
}

/// The user's identity: a secp256k1 key derived from a BIP-39 recovery phrase
/// (NIP-06), both kept in the platform keystore. No account, no server; the
/// phrase restores the identity on another phone, in RoadTo or any NIP-06
/// Nostr client.
///
/// Alerts are not signed with this key but with a throwaway key per trip, so
/// trips cannot be linked together.
class IdentityStore {
  static const _keyName = 'roadto.identity.sk';
  static const _phraseName = 'roadto.identity.mnemonic';
  final SecretStore _store;

  /// scrypt cost of encrypted exports (NIP-49): 2^16, 64 MiB.
  final int exportLogN;

  IdentityStore([this._store = const PlatformSecretStore(), this.exportLogN = EncryptedKey.defaultLogN]);

  Future<Identity> loadOrCreate() async {
    final phrase = await recoveryPhrase();
    if (phrase != null) return Identity(phrase.keyPair(), hasRecoveryPhrase: true);
    final legacy = await _store.read(_keyName);
    if (legacy != null) {
      try {
        return Identity(KeyPair.fromPrivateKey(legacy), hasRecoveryPhrase: false);
      } catch (_) {
        // Unreadable key: start over with a new identity.
      }
    }
    return regenerate();
  }

  /// The stored phrase, to show it to the user, or null for a legacy identity.
  Future<RecoveryPhrase?> recoveryPhrase() async {
    final stored = await _store.read(_phraseName);
    if (stored == null) return null;
    try {
      return RecoveryPhrase.parse(stored);
    } on FormatException {
      return null;
    }
  }

  /// New identity with a new recovery phrase. The previous key is lost unless
  /// its phrase was written down.
  Future<Identity> regenerate() => restore(RecoveryPhrase.generate());

  /// Replaces the identity with the one of [phrase].
  Future<Identity> restore(RecoveryPhrase phrase) async {
    final keys = phrase.keyPair();
    await _store.write(_phraseName, phrase.toString());
    await _store.write(_keyName, keys.privateKey);
    return Identity(keys, hasRecoveryPhrase: true);
  }

  /// The private key encrypted with [password] (NIP-49, `ncryptsec1…`), a
  /// backup that does not have to be written down, readable by any Nostr
  /// client that supports NIP-49. scrypt is slow on purpose: it runs on a
  /// background isolate.
  Future<String> exportEncrypted(String password) async {
    final sk = await _store.read(_keyName) ?? (await loadOrCreate()).keys.privateKey;
    final logN = exportLogN;
    return Isolate.run(() => EncryptedKey.encryptHex(sk, password, logN: logN));
  }

  /// Replaces the identity with the key of an encrypted export. The export
  /// holds the key only, so the restored identity has no recovery phrase.
  /// Throws [EncryptedKeyException] (wrong password, damaged text).
  Future<Identity> restoreEncrypted(String encrypted, String password) async {
    final sk = await Isolate.run(() => EncryptedKey.decryptToHex(encrypted, password));
    final keys = KeyPair.fromPrivateKey(sk);
    await _store.delete(_phraseName);
    await _store.write(_keyName, keys.privateKey);
    return Identity(keys, hasRecoveryPhrase: false);
  }
}

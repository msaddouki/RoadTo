import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roadto_core/roadto_core.dart';

/// Identité de l'utilisateur : une clé secp256k1 générée sur l'appareil et
/// gardée dans le Keystore Android ou le Keychain iOS. Aucun compte, aucun
/// serveur. La phrase de récupération BIP-39 arrive au jalon J3.
///
/// Les alertes ne sont pas signées avec cette clé mais avec une clé jetable
/// par trajet, pour qu'on ne puisse pas relier les trajets entre eux.
class IdentityStore {
  static const _key = 'roadto.identity.sk';
  final FlutterSecureStorage _storage;

  IdentityStore([this._storage = const FlutterSecureStorage()]);

  Future<KeyPair> loadOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) {
      try {
        return KeyPair.fromPrivateKey(existing);
      } catch (_) {
        // Clé illisible : on en recrée une.
      }
    }
    return regenerate();
  }

  Future<KeyPair> regenerate() async {
    final keys = KeyPair.generate();
    await _storage.write(key: _key, value: keys.privateKey);
    return keys;
  }
}

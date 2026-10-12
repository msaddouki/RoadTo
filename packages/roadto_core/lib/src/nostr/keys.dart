import 'dart:math' as math;

import 'package:bip340/bip340.dart' as bip340;

/// Ordre de la courbe secp256k1.
final _curveOrder = BigInt.parse('fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141', radix: 16);

final _random = math.Random.secure();

String randomHex(int bytes) =>
    [for (var i = 0; i < bytes; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

/// Paire de clés secp256k1 (Schnorr BIP-340), en hexadécimal.
class KeyPair {
  final String privateKey;
  final String publicKey;

  KeyPair._(this.privateKey, this.publicKey);

  factory KeyPair.fromPrivateKey(String privateKeyHex) {
    final k = BigInt.parse(privateKeyHex, radix: 16);
    if (privateKeyHex.length != 64 || k == BigInt.zero || k >= _curveOrder) {
      throw ArgumentError('Clé privée invalide');
    }
    return KeyPair._(privateKeyHex, bip340.getPublicKey(privateKeyHex));
  }

  /// Nouvelle clé aléatoire. Sert aussi pour les clés d'alerte jetables, une
  /// par trajet, qui empêchent de relier les signalements d'une même personne.
  factory KeyPair.generate() {
    while (true) {
      final hex = randomHex(32);
      final k = BigInt.parse(hex, radix: 16);
      if (k > BigInt.zero && k < _curveOrder) return KeyPair.fromPrivateKey(hex);
    }
  }

  /// Forme courte pour l'affichage.
  String get shortPublicKey => '${publicKey.substring(0, 8)}…${publicKey.substring(56)}';
}

import 'dart:convert';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

import 'keys.dart';

/// Événement Nostr (NIP-01).
class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  /// Construit, mine (NIP-13 si [powDifficulty] > 0) et signe un événement.
  factory NostrEvent.create({
    required KeyPair keys,
    required int kind,
    required List<List<String>> tags,
    String content = '',
    DateTime? createdAt,
    int powDifficulty = 0,
  }) {
    final ts = (createdAt ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    var finalTags = tags;
    var id = computeId(keys.publicKey, ts, kind, tags, content);
    if (powDifficulty > 0) {
      var nonce = 0;
      final base = tags.where((t) => t.isEmpty || t.first != 'nonce').toList();
      while (true) {
        finalTags = [
          ...base,
          ['nonce', '$nonce', '$powDifficulty'],
        ];
        id = computeId(keys.publicKey, ts, kind, finalTags, content);
        if (leadingZeroBits(id) >= powDifficulty) break;
        nonce++;
      }
    }
    final sig = bip340.sign(keys.privateKey, id, randomHex(32));
    return NostrEvent(
      id: id,
      pubkey: keys.publicKey,
      createdAt: ts,
      kind: kind,
      tags: finalTags,
      content: content,
      sig: sig,
    );
  }

  factory NostrEvent.fromJson(Map<String, dynamic> json) => NostrEvent(
    id: json['id'] as String,
    pubkey: json['pubkey'] as String,
    createdAt: json['created_at'] as int,
    kind: json['kind'] as int,
    tags: [
      for (final t in json['tags'] as List) [for (final v in t as List) v.toString()],
    ],
    content: json['content'] as String,
    sig: json['sig'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  /// Première valeur du tag [name], ou null.
  String? tag(String name) {
    for (final t in tags) {
      if (t.length >= 2 && t[0] == name) return t[1];
    }
    return null;
  }

  /// Toutes les valeurs du tag [name].
  List<String> tagValues(String name) => [
    for (final t in tags)
      if (t.length >= 2 && t[0] == name) t[1],
  ];

  /// Expiration NIP-40, en secondes Unix.
  int? get expiration => int.tryParse(tag('expiration') ?? '');

  bool isExpired(DateTime now) {
    final exp = expiration;
    return exp != null && exp <= now.millisecondsSinceEpoch ~/ 1000;
  }

  /// Difficulté NIP-13 réellement atteinte par l'identifiant.
  int get powBits => leadingZeroBits(id);

  /// Vérifie l'identifiant et la signature.
  bool verify() {
    if (computeId(pubkey, createdAt, kind, tags, content) != id) return false;
    try {
      return bip340.verify(pubkey, id, sig);
    } catch (_) {
      return false;
    }
  }

  static String computeId(String pubkey, int createdAt, int kind, List<List<String>> tags, String content) {
    final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }
}

/// Nombre de bits à zéro en tête d'un identifiant hexadécimal (NIP-13).
int leadingZeroBits(String hexId) {
  var bits = 0;
  for (final c in hexId.split('')) {
    final v = int.parse(c, radix: 16);
    if (v == 0) {
      bits += 4;
      continue;
    }
    bits += v < 2 ? 3 : (v < 4 ? 2 : (v < 8 ? 1 : 0));
    break;
  }
  return bits;
}

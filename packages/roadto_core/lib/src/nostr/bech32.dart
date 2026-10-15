import 'dart:typed_data';

/// Bech32 (BIP-173), as Nostr uses it for `npub`, `nsec` and `ncryptsec`.
/// Without BIP-173's 90-character limit: an `ncryptsec` is longer.
abstract final class Bech32 {
  static const _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  static const _generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

  static String encode(String hrp, List<int> data) {
    final words = _convert(data, 8, 5, pad: true);
    final checksum = _checksum(hrp, words);
    return '${hrp}1${[...words, ...checksum].map((w) => _charset[w]).join()}';
  }

  /// Returns the human-readable part and the bytes. Throws [FormatException].
  static (String, Uint8List) decode(String input) {
    if (input != input.toLowerCase() && input != input.toUpperCase()) {
      throw const FormatException('bech32: mixed case');
    }
    final s = input.toLowerCase();
    final sep = s.lastIndexOf('1');
    if (sep < 1 || sep + 7 > s.length) throw const FormatException('bech32: no separator or too short');
    final hrp = s.substring(0, sep);
    final words = <int>[];
    for (final c in s.substring(sep + 1).split('')) {
      final v = _charset.indexOf(c);
      if (v < 0) throw FormatException('bech32: invalid character "$c"');
      words.add(v);
    }
    if (_polymod([..._expandHrp(hrp), ...words]) != 1) throw const FormatException('bech32: bad checksum');
    return (hrp, Uint8List.fromList(_convert(words.sublist(0, words.length - 6), 5, 8, pad: false)));
  }

  static List<int> _expandHrp(String hrp) => [
    for (final c in hrp.codeUnits) c >> 5,
    0,
    for (final c in hrp.codeUnits) c & 31,
  ];

  static int _polymod(List<int> values) {
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = (chk & 0x1ffffff) << 5 ^ v;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) chk ^= _generator[i];
      }
    }
    return chk;
  }

  static List<int> _checksum(String hrp, List<int> words) {
    final mod = _polymod([..._expandHrp(hrp), ...words, 0, 0, 0, 0, 0, 0]) ^ 1;
    return [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  }

  static List<int> _convert(List<int> data, int from, int to, {required bool pad}) {
    var acc = 0, bits = 0;
    final out = <int>[];
    final maxv = (1 << to) - 1;
    for (final v in data) {
      if (v < 0 || v >> from != 0) throw const FormatException('bech32: value out of range');
      acc = (acc << from) | v;
      bits += from;
      while (bits >= to) {
        bits -= to;
        out.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) out.add((acc << (to - bits)) & maxv);
    } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      throw const FormatException('bech32: bad padding');
    }
    return out;
  }
}

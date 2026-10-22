import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:roadto_core/roadto_core.dart';
import 'package:roadto_traffic_bot/traffic_bot.dart';

/// Reads Bison Futé's traffic states every minute and publishes the jams on
/// the relays (docs/traffic-feed.md).
///   ROADTO_TRAFFIC_KEY     the robot's private key (hex); its public key is
///                          in TrafficSources.keys (roadto_core)
///   ROADTO_TRAFFIC_RELAYS  relays, comma separated (ws://127.0.0.1:7777)
///   ROADTO_TRAFFIC_FEEDS   TRAFICOLOR areas, comma separated (TraficLyon)
///   ROADTO_TRAFFIC_ROUTING_URL  Valhalla server drawing each station's road
///                          once (https://valhalla1.openstreetmap.de/)
Future<void> main() async {
  final env = Platform.environment;
  final secret = env['ROADTO_TRAFFIC_KEY']?.trim() ?? '';
  final KeyPair keys;
  try {
    keys = KeyPair.fromPrivateKey(secret);
  } catch (_) {
    stderr.writeln('traffic: ROADTO_TRAFFIC_KEY must be a 64-character hex private key');
    exitCode = 64;
    return;
  }
  final relays = _list(env['ROADTO_TRAFFIC_RELAYS'], 'ws://127.0.0.1:7777');
  final feeds = _list(env['ROADTO_TRAFFIC_FEEDS'], 'TraficLyon');
  _log('robot ${keys.publicKey}, feeds ${feeds.join(', ')}, relays ${relays.length}');
  if (!TrafficSources.keys.contains(keys.publicKey)) {
    _log('warning: this key is not in TrafficSources.keys, apps will not show the source');
  }

  final client = http.Client();
  final pool = RelayPool(relays);
  final shapes = StretchShapes(
    ValhallaRouter(baseUrl: env['ROADTO_TRAFFIC_ROUTING_URL'] ?? 'https://valhalla1.openstreetmap.de/', client: client),
  );
  final bot = TrafficBot(keys: keys, sites: await _referential(client), shapeOf: (id) => shapes[id]);
  var referentialAt = DateTime.now();

  while (true) {
    final now = DateTime.now();
    if (now.difference(referentialAt) > const Duration(hours: 24)) {
      try {
        bot.sites = parseReferential(await _get(client, referentialUrl));
        referentialAt = now;
      } catch (e) {
        _log('referential not refreshed: $e');
      }
    }
    for (final feed in feeds) {
      try {
        final file = latestFile(await _get(client, feedIndexUrl(feed)));
        if (file == null) continue;
        final data = parseStates(await _get(client, '${feedIndexUrl(feed)}$file'));
        // The road of stations newly jammed, a few a minute (fair use of
        // the routing server): their jams are drawn once it is known.
        var asked = 0;
        for (final MapEntry(key: id, value: state) in data.states.entries) {
          final site = bot.sites[id];
          if (site == null || levelOf(state) == null || !shapes.wants(site, DateTime.now()) || asked >= 10) continue;
          asked++;
          await shapes.fetch(site, DateTime.now());
        }
        final events = bot.step(feed, file, data, DateTime.now());
        var accepted = 0;
        for (final e in events) {
          final results = await pool.publish(e);
          if (results.any((r) => r.accepted)) accepted++;
          for (final r in results.where((r) => !r.accepted)) {
            _log('refused by ${r.relay}: ${r.message}');
          }
        }
        if (events.isNotEmpty) {
          _log('$feed $file: ${events.length} jam(s) published, $accepted accepted; ${bot.jammed} station(s) jammed');
        }
      } catch (e) {
        _log('$feed: $e');
      }
    }
    await Future<void>.delayed(const Duration(seconds: 60));
  }
}

List<String> _list(String? raw, String fallback) => (raw == null || raw.trim().isEmpty ? fallback : raw)
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

Future<Map<String, Site>> _referential(http.Client client) async {
  while (true) {
    try {
      final sites = parseReferential(await _get(client, referentialUrl));
      _log('referential: ${sites.length} stations with a position');
      return sites;
    } catch (e) {
      _log('referential unavailable, retrying in 60 s: $e');
      await Future<void>.delayed(const Duration(seconds: 60));
    }
  }
}

Future<String> _get(http.Client client, String url) async {
  final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
  // The referential is Latin-1 in places; the states are UTF-8.
  try {
    return const Utf8Decoder().convert(res.bodyBytes);
  } on FormatException {
    return latin1.decode(res.bodyBytes);
  }
}

void _log(String message) => stdout.writeln('traffic: $message');

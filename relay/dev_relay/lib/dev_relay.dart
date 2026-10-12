/// Relais Nostr en mémoire pour le développement et les tests de bout en bout.
///
/// Ce n'est pas le relais de production (strfry + plugin, jalon J3) : il
/// n'a ni persistance ni negentropy. Il applique en revanche exactement la
/// même politique d'écriture que celle attendue en production.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:roadto_core/roadto_core.dart';

class _Client {
  final WebSocket socket;
  final subs = <String, List<NostrFilter>>{};
  int eventsThisMinute = 0;
  DateTime windowStart = DateTime.now();

  _Client(this.socket);

  void send(List<Object?> msg) => socket.add(jsonEncode(msg));
}

class DevRelay {
  final _events = <String, NostrEvent>{};
  final _clients = <_Client>{};
  HttpServer? _server;
  Timer? _purgeTimer;

  /// Nombre maximal d'événements par connexion et par minute.
  final int rateLimitPerMinute;

  /// Horloge injectable pour les tests.
  final DateTime Function() clock;

  void Function(String)? log;

  DevRelay({this.rateLimitPerMinute = 30, DateTime Function()? clock, this.log}) : clock = clock ?? DateTime.now;

  int get port => _server!.port;
  Uri get url => Uri.parse('ws://${_server!.address.host}:$port');
  int get storedEvents => _events.length;

  Future<void> start({String host = '127.0.0.1', int port = 7777}) async {
    _server = await HttpServer.bind(host, port);
    _purgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => purgeExpired());
    _server!.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        // NIP-11, réduit au minimum.
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'name': 'RoadTo dev relay',
              'description': 'Relais de développement, sans persistance.',
              'supported_nips': [1, 11, 13, 40],
            }),
          );
        await req.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(req);
      final client = _Client(socket);
      _clients.add(client);
      socket.listen(
        (raw) => _onMessage(client, raw),
        onDone: () => _clients.remove(client),
        onError: (_) => _clients.remove(client),
      );
    });
  }

  Future<void> stop() async {
    _purgeTimer?.cancel();
    for (final c in _clients.toList()) {
      await c.socket.close();
    }
    await _server?.close(force: true);
  }

  /// Supprime les événements expirés (NIP-40).
  void purgeExpired() {
    final now = clock();
    _events.removeWhere((_, e) => e.isExpired(now));
  }

  void _onMessage(_Client client, dynamic raw) {
    final List msg;
    try {
      msg = jsonDecode(raw as String) as List;
    } catch (_) {
      client.send(['NOTICE', 'invalid: JSON']);
      return;
    }
    switch (msg.firstOrNull) {
      case 'EVENT' when msg.length >= 2:
        _onEvent(client, msg[1]);
      case 'REQ' when msg.length >= 2:
        final subId = msg[1] as String;
        final filters = [for (final f in msg.skip(2)) NostrFilter.fromJson(f as Map<String, dynamic>)];
        client.subs[subId] = filters;
        final now = clock();
        final matches = _events.values.where((e) => !e.isExpired(now) && filters.any((f) => f.matches(e))).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final limit = filters
            .map((f) => f.limit)
            .whereType<int>()
            .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
        for (final e in limit == null ? matches : matches.take(limit)) {
          client.send(['EVENT', subId, e.toJson()]);
        }
        client.send(['EOSE', subId]);
      case 'CLOSE' when msg.length >= 2:
        client.subs.remove(msg[1]);
      default:
        client.send(['NOTICE', 'invalid: message inconnu']);
    }
  }

  void _onEvent(_Client client, dynamic json) {
    final NostrEvent event;
    try {
      event = NostrEvent.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      client.send(['NOTICE', 'invalid: événement mal formé']);
      return;
    }
    final now = clock();
    if (now.difference(client.windowStart) > const Duration(minutes: 1)) {
      client.windowStart = now;
      client.eventsThisMinute = 0;
    }
    if (++client.eventsThisMinute > rateLimitPerMinute) {
      client.send(['OK', event.id, false, 'rate-limited: trop de messages']);
      return;
    }
    if (_events.containsKey(event.id)) {
      client.send(['OK', event.id, true, 'duplicate: déjà connu']);
      return;
    }
    final refusal = checkWritePolicy(event, now: now);
    if (refusal != null) {
      log?.call('refus ${event.id.substring(0, 8)} : $refusal');
      client.send(['OK', event.id, false, refusal]);
      return;
    }
    _events[event.id] = event;
    // Pas d'adresse IP dans les journaux : règle vie privée du projet.
    log?.call(
      'accepté kind ${event.kind} ${event.tag('t') ?? event.tag('still') ?? ''} ${event.tagValues('g').lastOrNull ?? ''}',
    );
    client.send(['OK', event.id, true, '']);
    for (final c in _clients) {
      for (final sub in c.subs.entries) {
        if (sub.value.any((f) => f.matches(event))) c.send(['EVENT', sub.key, event.toJson()]);
      }
    }
  }
}

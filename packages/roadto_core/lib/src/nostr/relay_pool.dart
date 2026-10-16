import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'event.dart';
import 'filter.dart';
import 'keys.dart';
import 'verifier.dart';

/// Réponse d'un relais à une publication (message OK de NIP-01).
class PublishResult {
  final String relay;
  final bool accepted;
  final String message;

  const PublishResult(this.relay, this.accepted, this.message);

  @override
  String toString() => '$relay: ${accepted ? 'accepté' : 'refusé'} $message';
}

enum RelayStatus { disconnected, connecting, connected }

/// Connexion à un relais, avec reconnexion et réabonnement automatiques.
class RelayConnection {
  final Uri url;
  final Duration reconnectDelay;
  final _subs = <String, List<NostrFilter>>{};
  final _pendingOk = <String, Completer<PublishResult>>{};
  final _events = StreamController<(String, NostrEvent)>.broadcast();
  final _eose = StreamController<String>.broadcast();
  final _status = StreamController<RelayStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription? _listener;
  RelayStatus _current = RelayStatus.disconnected;
  bool _closed = false;
  Completer<void>? _connecting;

  /// Checks received events; null checks them inline, on this isolate.
  final EventVerifier? verifier;

  RelayConnection(this.url, {this.reconnectDelay = const Duration(seconds: 3), this.verifier});

  RelayStatus get status => _current;
  Stream<RelayStatus> get statusChanges => _status.stream;

  /// Événements reçus, avec l'identifiant d'abonnement.
  Stream<(String, NostrEvent)> get events => _events.stream;
  Stream<String> get endOfStoredEvents => _eose.stream;

  void _setStatus(RelayStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> connect() {
    if (_current == RelayStatus.connected) return Future.value();
    if (_connecting != null) return _connecting!.future;
    final done = _connecting = Completer<void>();
    _setStatus(RelayStatus.connecting);
    () async {
      try {
        final channel = WebSocketChannel.connect(url);
        await channel.ready;
        _channel = channel;
        _listener = channel.stream.listen(_onMessage, onDone: _onDisconnect, onError: (_) => _onDisconnect());
        _setStatus(RelayStatus.connected);
        for (final e in _subs.entries) {
          _send(['REQ', e.key, ...e.value.map((f) => f.toJson())]);
        }
        done.complete();
      } catch (e) {
        _setStatus(RelayStatus.disconnected);
        done.completeError(e);
        _scheduleReconnect();
      } finally {
        _connecting = null;
      }
    }();
    return done.future;
  }

  void _scheduleReconnect() {
    if (_closed) return;
    Timer(reconnectDelay, () {
      if (!_closed && _current == RelayStatus.disconnected) {
        connect().catchError((_) {});
      }
    });
  }

  void _onDisconnect() {
    _listener?.cancel();
    _channel = null;
    _setStatus(RelayStatus.disconnected);
    for (final c in _pendingOk.values) {
      if (!c.isCompleted) c.complete(PublishResult('$url', false, 'déconnecté'));
    }
    _pendingOk.clear();
    _scheduleReconnect();
  }

  void _onMessage(dynamic raw) {
    final List msg;
    try {
      msg = jsonDecode(raw as String) as List;
    } catch (_) {
      return;
    }
    if (msg.isEmpty) return;
    switch (msg[0]) {
      case 'EVENT' when msg.length >= 3:
        final String subId;
        final NostrEvent event;
        try {
          subId = msg[1] as String;
          event = NostrEvent.fromJson(msg[2] as Map<String, dynamic>);
        } catch (_) {
          return;
        }
        final v = verifier;
        if (v == null) {
          if (event.verify()) _events.add((subId, event));
        } else {
          v.verify(event).then((ok) {
            if (ok && !_events.isClosed) _events.add((subId, event));
          });
        }
      case 'EOSE' when msg.length >= 2:
        _eose.add(msg[1] as String);
      case 'OK' when msg.length >= 3:
        _pendingOk.remove(msg[1])?.complete(PublishResult('$url', msg[2] == true, msg.length > 3 ? '${msg[3]}' : ''));
    }
  }

  void _send(List<Object?> msg) => _channel?.sink.add(jsonEncode(msg));

  Future<PublishResult> publish(NostrEvent event, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      await connect().timeout(timeout);
    } catch (e) {
      return PublishResult('$url', false, 'connexion impossible : $e');
    }
    final c = _pendingOk[event.id] = Completer<PublishResult>();
    _send(['EVENT', event.toJson()]);
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pendingOk.remove(event.id);
        return PublishResult('$url', false, 'pas de réponse');
      },
    );
  }

  void subscribe(String id, List<NostrFilter> filters) {
    _subs[id] = filters;
    if (_current == RelayStatus.connected) {
      _send(['REQ', id, ...filters.map((f) => f.toJson())]);
    } else {
      connect().catchError((_) {});
    }
  }

  void unsubscribe(String id) {
    if (_subs.remove(id) != null && _current == RelayStatus.connected) {
      _send(['CLOSE', id]);
    }
  }

  Future<void> close() async {
    _closed = true;
    await _listener?.cancel();
    await _channel?.sink.close();
    _setStatus(RelayStatus.disconnected);
    await _events.close();
    await _eose.close();
    await _status.close();
  }
}

/// Plusieurs relais fédérés vus comme un seul : publication sur tous,
/// réception dédoublonnée.
class RelayPool {
  final Map<String, RelayConnection> _relays = {};
  final _seen = <String>{};
  final _streams = <String, StreamController<NostrEvent>>{};
  final _filters = <String, List<NostrFilter>>{};
  final _listeners = <StreamSubscription>[];
  final Duration reconnectDelay;

  /// Shared by the pool's relays, so an event sent by several of them has
  /// its signature checked once, off this isolate.
  final EventVerifier verifier;
  final bool _ownsVerifier;

  RelayPool(Iterable<String> urls, {this.reconnectDelay = const Duration(seconds: 3), EventVerifier? verifier})
    : verifier = verifier ?? EventVerifier(),
      _ownsVerifier = verifier == null {
    for (final u in urls) {
      _add(u);
    }
  }

  void _add(String url) {
    if (_relays.containsKey(url)) return;
    final r = RelayConnection(Uri.parse(url), reconnectDelay: reconnectDelay, verifier: verifier);
    _relays[url] = r;
    _listeners.add(
      r.events.listen((pair) {
        final (subId, event) = pair;
        final ctrl = _streams[subId];
        if (ctrl == null || ctrl.isClosed) return;
        if (_seen.add('$subId:${event.id}')) ctrl.add(event);
      }),
    );
    for (final e in _filters.entries) {
      r.subscribe(e.key, e.value);
    }
  }

  List<String> get urls => _relays.keys.toList();

  Map<String, RelayStatus> get statuses => {for (final e in _relays.entries) e.key: e.value.status};

  Stream<RelayStatus> statusChanges(String url) => _relays[url]!.statusChanges;

  /// Remplace la liste de relais.
  Future<void> setRelays(Iterable<String> urls) async {
    final wanted = urls.toSet();
    for (final url in _relays.keys.toList()) {
      if (!wanted.contains(url)) await _relays.remove(url)!.close();
    }
    wanted.forEach(_add);
  }

  Future<void> connect() async {
    await Future.wait(_relays.values.map((r) => r.connect().catchError((_) {})));
  }

  Future<List<PublishResult>> publish(NostrEvent event) => Future.wait(_relays.values.map((r) => r.publish(event)));

  /// Ouvre (ou remplace) l'abonnement [id] sur tous les relais.
  Stream<NostrEvent> subscribe(List<NostrFilter> filters, {String? id}) {
    final subId = id ?? 'rt-${randomHex(6)}';
    _filters[subId] = filters;
    final ctrl = _streams[subId] ??= StreamController<NostrEvent>.broadcast();
    for (final r in _relays.values) {
      r.subscribe(subId, filters);
    }
    return ctrl.stream;
  }

  void unsubscribe(String id) {
    _filters.remove(id);
    _streams.remove(id)?.close();
    for (final r in _relays.values) {
      r.unsubscribe(id);
    }
  }

  Future<void> close() async {
    for (final l in _listeners) {
      await l.cancel();
    }
    for (final s in _streams.values) {
      await s.close();
    }
    await Future.wait(_relays.values.map((r) => r.close()));
    _relays.clear();
    if (_ownsVerifier) await verifier.close();
  }
}

import 'dart:async';
import 'dart:isolate';

import 'package:bip340/bip340.dart' as bip340;

import 'event.dart';

/// Checks received events without blocking the calling isolate (the app's UI
/// thread), and each signature only once.
///
/// A Schnorr check in pure Dart costs about 17 ms on a desktop and more on a
/// phone: done inline, a burst of alerts froze the map, and an alert coming
/// from two relays was checked twice. The id (a SHA-256, cheap) is still
/// checked inline on every copy; the signature goes to a background isolate,
/// and a valid (id, signature) pair is remembered.
class EventVerifier {
  final bool background;
  final int cacheSize;

  final _verified = <String>{}; // insertion-ordered: the oldest goes first
  final _pending = <String, Future<bool>>{};
  _Worker? _worker;

  /// [background] false checks signatures inline (tests, tools).
  EventVerifier({this.background = true, this.cacheSize = 4096});

  Future<bool> verify(NostrEvent e) async {
    // The id binds the content; checked on every copy, so a cached signature
    // can never vouch for different content.
    if (!e.hasValidId()) return false;
    final key = '${e.id}:${e.sig}';
    if (_verified.contains(key)) return true;
    // A block, not an arrow: whenComplete waits for a Future its callback
    // returns, and remove() would return this very one.
    final ok = await (_pending[key] ??= _checkSignature(e).whenComplete(() {
      _pending.remove(key);
    }));
    if (ok) {
      _verified.add(key);
      if (_verified.length > cacheSize) _verified.remove(_verified.first);
    }
    return ok;
  }

  Future<bool> _checkSignature(NostrEvent e) {
    if (!background) return Future.value(e.hasValidSignature());
    return (_worker ??= _Worker()).verify(e.pubkey, e.id, e.sig);
  }

  /// Stops the background isolate. The verifier starts a new one if used again.
  Future<void> close() async {
    final w = _worker;
    _worker = null;
    await w?.close();
  }
}

/// One long-lived isolate that checks Schnorr signatures.
class _Worker {
  final _replies = <int, Completer<bool>>{};
  final _inbox = ReceivePort();
  late final Future<SendPort> _outbox = _start();
  Isolate? _isolate;
  int _next = 0;

  Future<SendPort> _start() async {
    final ready = Completer<SendPort>();
    _inbox.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m case (final int n, final bool ok)) {
        _replies.remove(n)?.complete(ok);
      }
    });
    _isolate = await Isolate.spawn(_main, _inbox.sendPort, debugName: 'roadto-verifier');
    return ready.future;
  }

  Future<bool> verify(String pubkey, String id, String sig) async {
    final out = await _outbox;
    final n = _next++;
    final reply = _replies[n] = Completer<bool>();
    out.send((n, pubkey, id, sig));
    return reply.future;
  }

  Future<void> close() async {
    _isolate?.kill(priority: Isolate.immediate);
    _inbox.close();
    for (final r in _replies.values) {
      r.complete(false);
    }
    _replies.clear();
  }

  static void _main(SendPort replies) {
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    requests.listen((m) {
      final (n, pubkey, id, sig) = m as (int, String, String, String);
      bool ok;
      try {
        ok = bip340.verify(pubkey, id, sig);
      } catch (_) {
        ok = false;
      }
      replies.send((n, ok));
    });
  }
}

import 'dart:io';

import 'package:roadto_dev_relay/dev_relay.dart';

/// Lance le relais de dev : `dart run bin/dev_relay.dart [--host 0.0.0.0] [--port 7777]`.
Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final host = arg('host', '0.0.0.0');
  final port = int.parse(arg('port', '7777'));
  final relay = DevRelay(log: (m) => stdout.writeln('[${DateTime.now().toIso8601String()}] $m'));
  await relay.start(host: host, port: port);
  stdout.writeln('Relais RoadTo de dev sur ws://$host:$port');
  stdout.writeln('Émulateur Android : ws://10.0.2.2:$port · Simulateur iOS : ws://127.0.0.1:$port');
  ProcessSignal.sigint.watch().listen((_) async {
    await relay.stop();
    exit(0);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:roadto_strfry_policy/strfry_policy.dart';

/// strfry `relay.writePolicy.plugin` entry point, compiled with
/// `dart build cli`. Reads requests on stdin, one per line, and answers
/// each on stdout. Rate limit: `ROADTO_RATE_PER_MINUTE` (default 30).
/// With `ROADTO_METRICS_PORT`, serves Prometheus counters on
/// `http://0.0.0.0:<port>/metrics`.
Future<void> main() async {
  final plugin = WritePolicyPlugin(
    ratePerMinute: int.tryParse(Platform.environment['ROADTO_RATE_PER_MINUTE'] ?? '') ?? 30,
  );
  final port = int.tryParse(Platform.environment['ROADTO_METRICS_PORT'] ?? '');
  if (port != null) await serveMetrics(plugin.metrics, port);
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    stdout.writeln(plugin.handleLine(line));
    await stdout.flush();
  }
}

/// Serves [metrics] until the process ends. A port already taken (another
/// plugin instance) only disables metrics: judging events matters more.
Future<void> serveMetrics(PolicyMetrics metrics, int port) async {
  final HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  } on SocketException catch (e) {
    stderr.writeln('roadto-policy: metrics disabled, port $port unavailable (${e.osError?.message ?? e.message})');
    return;
  }
  server.listen((request) {
    final res = request.response;
    if (request.uri.path == '/metrics') {
      res.headers.contentType = ContentType('text', 'plain', parameters: {'version': '0.0.4', 'charset': 'utf-8'});
      res.write(metrics.render());
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    res.close();
  });
}

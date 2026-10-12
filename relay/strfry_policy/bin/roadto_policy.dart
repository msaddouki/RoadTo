import 'dart:convert';
import 'dart:io';

import 'package:roadto_strfry_policy/strfry_policy.dart';

/// strfry `relay.writePolicy.plugin` entry point, compiled with
/// `dart compile exe`. Reads requests on stdin, one per line, and answers
/// each on stdout. Rate limit: `ROADTO_RATE_PER_MINUTE` (default 30).
Future<void> main() async {
  final plugin = WritePolicyPlugin(
    ratePerMinute: int.tryParse(Platform.environment['ROADTO_RATE_PER_MINUTE'] ?? '') ?? 30,
  );
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    stdout.writeln(plugin.handleLine(line));
    await stdout.flush();
  }
}

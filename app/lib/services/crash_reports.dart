import 'dart:convert';
import 'dart:io';

/// One error the app ran into, as kept on the phone.
class CrashReport {
  final File file;
  final DateTime time;
  final String error;
  final String stack;
  final String? context;
  final String platform;

  const CrashReport({
    required this.file,
    required this.time,
    required this.error,
    required this.stack,
    required this.platform,
    this.context,
  });

  String get title => error.split('\n').first;

  /// Plain text, for the user to share if they choose to.
  String get text => [
    'RoadTo error report',
    'Time: ${time.toUtc().toIso8601String()}',
    'Platform: $platform',
    if (context != null) 'Context: $context',
    '',
    error,
    '',
    stack,
  ].join('\n');
}

/// Error reports kept on the phone only (plan J7: "stored on the device
/// and sent only if the user chooses"). Nothing leaves the phone: the user
/// reads a report and shares it, through the system's own sharing, if they
/// want to.
///
/// What could identify the user or their trips is scrubbed before writing:
/// coordinates and other precise decimals, network addresses, keys and
/// other long hex strings, Nostr secrets, URL parameters. Words of a recovery
/// phrase cannot be told from ordinary text: the identity screens handle
/// their own errors, so those never reach this recorder.
class CrashReports {
  final Directory dir;
  final int keep;
  final String platform;

  CrashReports(this.dir, {this.keep = 20, String? platform})
    : platform = platform ?? '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

  static const _maxError = 4000, _maxStack = 16000;

  static final _patterns = <(RegExp, String)>[
    (RegExp(r'\b(nsec|ncryptsec)1[02-9ac-hj-np-z]+', caseSensitive: false), '[secret]'),
    (RegExp(r'\b[0-9a-fA-F]{32,}\b'), '[hex]'),
    (RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[address]'),
    // Coordinates: decimal numbers with 3+ decimals (about 100 m).
    (RegExp(r'-?\b\d{1,3}\.\d{3,}\b'), '[number]'),
    (RegExp(r'([?&][^=\s]+=)[^&\s]+'), r'$1[value]'),
  ];

  /// Removes what could identify the user or their trips.
  static String scrub(String s) {
    var out = s;
    for (final (re, replacement) in _patterns) {
      out = replacement.contains(r'$1')
          ? out.replaceAllMapped(re, (m) => replacement.replaceAll(r'$1', m[1]!))
          : out.replaceAll(re, replacement);
    }
    return out;
  }

  static String _cut(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}\n[… cut]';

  /// Records an error. Never throws: failing to record must not add a crash.
  Future<void> record(Object error, StackTrace? stack, {String? context, DateTime? now}) async {
    try {
      final t = (now ?? DateTime.now()).toUtc();
      await dir.create(recursive: true);
      final name = 'crash-${t.microsecondsSinceEpoch}.json';
      await File('${dir.path}/$name').writeAsString(
        jsonEncode({
          'time': t.toIso8601String(),
          'platform': platform,
          'error': _cut(scrub('$error'), _maxError),
          'stack': _cut(scrub('${stack ?? ''}'), _maxStack),
          if (context != null) 'context': _cut(scrub(context), 500),
        }),
      );
      final all = await _files();
      for (final old in all.skip(keep)) {
        await old.delete();
      }
    } catch (_) {}
  }

  /// Newest first.
  Future<List<File>> _files() async {
    if (!await dir.exists()) return [];
    final files = await dir.list().where((e) => e is File && e.path.endsWith('.json')).cast<File>().toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// Reports on the phone, newest first. Unreadable files are skipped.
  Future<List<CrashReport>> list() async {
    final out = <CrashReport>[];
    for (final f in await _files()) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(
          CrashReport(
            file: f,
            time: DateTime.parse(j['time'] as String),
            error: j['error'] as String,
            stack: j['stack'] as String? ?? '',
            context: j['context'] as String?,
            platform: j['platform'] as String? ?? '',
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  Future<void> delete(CrashReport r) async {
    if (await r.file.exists()) await r.file.delete();
  }

  Future<void> clear() async {
    for (final f in await _files()) {
      await f.delete();
    }
  }
}

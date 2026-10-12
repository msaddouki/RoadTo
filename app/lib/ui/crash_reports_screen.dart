import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/crash_reports.dart';

/// Errors the app ran into, kept on the phone. The user may read them and
/// share one, through a file or the clipboard, to help fix it; nothing is
/// sent otherwise.
class CrashReportsScreen extends StatefulWidget {
  final CrashReports reports;

  /// Saves a report to a file the user picks; a file picker by default.
  final Future<void> Function(CrashReport report)? save;

  const CrashReportsScreen({super.key, required this.reports, this.save});

  @override
  State<CrashReportsScreen> createState() => _CrashReportsScreenState();
}

class _CrashReportsScreenState extends State<CrashReportsScreen> {
  List<CrashReport>? _reports;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final r = await widget.reports.list();
    if (mounted) setState(() => _reports = r);
  }

  Future<void> _save(CrashReport r) async {
    final save =
        widget.save ??
        (CrashReport r) => FilePicker.saveFile(
          fileName: 'roadto-erreur-${r.time.toUtc().toIso8601String().replaceAll(':', '-')}.txt',
          bytes: Uint8List.fromList(utf8.encode(r.text)),
          mimeType: 'text/plain',
        );
    await save(r);
  }

  Future<void> _open(CrashReport r) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(
            title: const Text('Rapport d’erreur'),
            actions: [
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await widget.reports.delete(r);
                  if (c.mounted) Navigator.pop(c, true);
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SelectableText(r.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _save(r),
                icon: const Icon(Icons.save_alt),
                label: const Text('Enregistrer dans un fichier'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: r.text)),
                icon: const Icon(Icons.copy),
                label: const Text('Copier'),
              ),
            ],
          ),
        ),
      ),
    );
    if (deleted ?? false) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports d’erreur'),
        actions: [
          if (reports != null && reports.isNotEmpty)
            IconButton(
              tooltip: 'Tout supprimer',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                await widget.reports.clear();
                await _reload();
              },
            ),
        ],
      ),
      body: reports == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Ces rapports restent sur ce téléphone : rien n’est envoyé. Positions, clés et adresses en sont '
                    'retirées. Vous pouvez en partager un pour aider à corriger l’erreur.',
                  ),
                ),
                if (reports.isEmpty) const ListTile(title: Text('Aucune erreur enregistrée')),
                for (final r in reports)
                  ListTile(
                    minTileHeight: 64,
                    leading: const Icon(Icons.bug_report_outlined),
                    title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_when(r.time)),
                    onTap: () => _open(r),
                  ),
              ],
            ),
    );
  }

  static String _when(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}

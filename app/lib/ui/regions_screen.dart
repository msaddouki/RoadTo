import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import '../config.dart';
import '../state/app_controller.dart';

/// Download, update and delete offline regions.
class RegionsScreen extends StatelessWidget {
  final AppController app;
  final List<RegionSource> catalog;

  const RegionsScreen({super.key, required this.app, this.catalog = Defaults.regions});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Régions hors ligne')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Une région installée donne la carte et la recherche d’adresse sans réseau. '
              'Le calcul d’itinéraire reste en ligne pour l’instant. Téléchargez de préférence en Wi-Fi.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (app.regionError != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    app.regionError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ),
            for (final source in catalog) _RegionTile(app: app, source: source),
          ],
        ),
      ),
    );
  }
}

class _RegionTile extends StatelessWidget {
  final AppController app;
  final RegionSource source;

  const _RegionTile({required this.app, required this.source});

  @override
  Widget build(BuildContext context) {
    final installed = app.regions.where((r) => r.id == source.id).firstOrNull;
    final busy = app.installingRegion == source.id;
    final progress = busy ? app.installProgress : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              installed == null
                  ? 'Non installée'
                  : 'Installée · données du ${installed.version} · ${_size(installed.manifest.requiredBytes)}',
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress == null || progress.total == 0 ? null : progress.fraction),
              const SizedBox(height: 4),
              Text(_progressLabel(progress)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: app.installingRegion != null ? null : () => app.installRegion(source),
                  icon: Icon(installed == null ? Icons.download : Icons.refresh),
                  label: Text(installed == null ? 'Télécharger' : 'Mettre à jour'),
                ),
                const SizedBox(width: 12),
                if (installed != null && !busy)
                  TextButton(onPressed: () => app.removeRegion(source.id), child: const Text('Supprimer')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _progressLabel(InstallProgress? p) => switch (p?.stage) {
    null || InstallStage.manifest => 'Vérification du paquet…',
    InstallStage.download => '${p!.file ?? ''} · ${_size(p.received)} / ${_size(p.total)}',
    InstallStage.extract => 'Installation…',
    InstallStage.done => 'Terminé',
  };

  static String _size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1).replaceAll('.', ',')} Go';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).round()} Mo';
    return '${(bytes / 1024).ceil()} Ko';
  }
}

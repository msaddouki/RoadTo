import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import '../config.dart';
import '../state/app_controller.dart';

/// Installed offline regions, import from a `.roadto` file and, when a
/// package server is configured, downloads.
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
        builder: (context, _) {
          final busy = app.installingRegion != null;
          final downloadable = [
            for (final s in catalog)
              if (!app.regions.any((r) => r.id == s.id)) s,
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Une région installée donne la carte et la recherche d’adresse sans réseau. '
                'Le calcul d’itinéraire reste en ligne pour l’instant.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (app.regionError != null) _ErrorCard(message: app.regionError!),
              if (busy) _ProgressCard(label: app.installingRegion!, progress: app.installProgress),
              if (app.regions.isEmpty && !busy)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.map_outlined),
                    title: Text('Aucune région installée'),
                    subtitle: Text('Importez un fichier .roadto pour utiliser la carte sans réseau.'),
                  ),
                ),
              for (final r in app.regions) _InstalledTile(app: app, region: r, busy: busy),
              for (final s in downloadable) _DownloadTile(app: app, source: s, busy: busy),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: busy ? null : app.importRegionFile,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Importer un fichier .roadto'),
              ),
              const SizedBox(height: 8),
              Text(
                'Le fichier est vérifié (signature et empreinte de chaque élément) avant d’être installé.',
                style: text.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1).replaceAll('.', ',')} Go';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).round()} Mo';
  return '${(bytes / 1024).ceil()} Ko';
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final String label;
  final InstallProgress? progress;

  const _ProgressCard({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final detail = switch (p?.stage) {
      null || InstallStage.manifest => 'Vérification de la signature…',
      InstallStage.download => '${p!.file ?? ''} · ${formatBytes(p.received)} / ${formatBytes(p.total)}',
      InstallStage.extract => 'Installation…',
      InstallStage.done => 'Terminé',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Installation : $label', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: p == null || p.total == 0 ? null : p.fraction),
            const SizedBox(height: 4),
            Text(detail),
          ],
        ),
      ),
    );
  }
}

class _InstalledTile extends StatelessWidget {
  final AppController app;
  final InstalledRegion region;
  final bool busy;

  const _InstalledTile({required this.app, required this.region, required this.busy});

  @override
  Widget build(BuildContext context) {
    final embedded = Defaults.embeddedRegions.contains(region.id);
    return Card(
      child: ListTile(
        leading: Icon(app.activeRegion?.id == region.id ? Icons.check_circle : Icons.map),
        title: Text(region.name),
        subtitle: Text(
          'Données du ${region.version} · ${formatBytes(region.manifest.requiredBytes)}'
          '${embedded ? ' · intégrée à l’app' : ''}',
        ),
        trailing: busy
            ? null
            : IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text('Supprimer ${region.name} ?'),
                      content: Text(
                        embedded
                            ? 'Elle sera réinstallée depuis l’app au prochain lancement.'
                            : 'Il faudra la réimporter pour l’utiliser hors ligne.',
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
                      ],
                    ),
                  );
                  if (ok ?? false) await app.removeRegion(region.id);
                },
              ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final AppController app;
  final RegionSource source;
  final bool busy;

  const _DownloadTile({required this.app, required this.source, required this.busy});

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_download_outlined),
      title: Text(source.name),
      subtitle: const Text('Disponible au téléchargement'),
      trailing: FilledButton(
        onPressed: busy ? null : () => app.installRegion(source),
        child: const Text('Télécharger'),
      ),
    ),
  );
}

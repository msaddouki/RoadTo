import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:roadto_core/roadto_core.dart';

import '../config.dart';
import '../services/feedback.dart';
import '../services/settings_store.dart';
import '../state/app_controller.dart';
import 'crash_reports_screen.dart';
import 'feedback_screen.dart';
import 'identity_screens.dart';
import 'regions_screen.dart';

/// Relais, simulation, services et identité.
class SettingsScreen extends StatefulWidget {
  final AppController app;

  const SettingsScreen({super.key, required this.app});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _relays = TextEditingController(text: widget.app.settings.relays.join('\n'));
  late final _routing = TextEditingController(text: widget.app.settings.routingUrl);
  late final _geocoder = TextEditingController(text: widget.app.settings.geocoderUrl);
  late var _s = widget.app.settings;

  @override
  void dispose() {
    _relays.dispose();
    _routing.dispose();
    _geocoder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final relays = _relays.text
        .split(RegExp(r'[\s,]+'))
        .map((s) => s.trim())
        .where((s) => s.startsWith('ws://') || s.startsWith('wss://'))
        .toList();
    await widget.app.updateSettings(
      _s.copyWith(relays: relays, routingUrl: _routing.text.trim(), geocoderUrl: _geocoder.text.trim()),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages'),
        actions: [TextButton(onPressed: _save, child: const Text('Enregistrer'))],
      ),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Simulation', style: text.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Conduite simulée'),
              subtitle: const Text('Le trajet est rejoué le long de l’itinéraire. À utiliser pour tous les tests.'),
              value: _s.simulate,
              onChanged: (v) => setState(() => _s = _s.copyWith(simulate: v)),
            ),
            Text('Vitesse simulée : ${_s.simulationSpeedKmh.round()} km/h'),
            Slider(
              min: 20,
              max: 130,
              divisions: 11,
              value: _s.simulationSpeedKmh,
              label: '${_s.simulationSpeedKmh.round()} km/h',
              onChanged: (v) => setState(() => _s = _s.copyWith(simulationSpeedKmh: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Annonces vocales'),
              value: _s.voice,
              onChanged: (v) => setState(() => _s = _s.copyWith(voice: v)),
            ),
            const Divider(height: 32),
            Text('Relais Nostr', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Un par ligne. Sur un vrai téléphone, utilisez l’adresse IP du poste qui fait tourner le relais de dev.',
              style: text.bodySmall,
            ),
            TextField(controller: _relays, maxLines: 4, minLines: 2, keyboardType: TextInputType.url),
            const SizedBox(height: 8),
            for (final e in app.relayStatuses.entries)
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: switch (e.value) {
                      RelayStatus.connected => Colors.greenAccent,
                      RelayStatus.connecting => Colors.amber,
                      RelayStatus.disconnected => Colors.redAccent,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, style: text.bodySmall)),
                ],
              ),
            const Divider(height: 32),
            Text('Carte', style: text.titleMedium),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Régions hors ligne'),
              subtitle: Text(
                app.activeRegion == null
                    ? 'Aucune région installée : carte et recherche en ligne'
                    : '${app.activeRegion!.name} · ${app.activeRegion!.version}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegionsScreen(app: app))),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Carte hors ligne'),
              subtitle: const Text('Affiche la carte de la région installée plutôt que les tuiles en ligne.'),
              value: _s.offlineMap,
              onChanged: app.activeRegion == null ? null : (v) => setState(() => _s = _s.copyWith(offlineMap: v)),
            ),
            Text('Carte de nuit', style: text.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<NightMap>(
              segments: const [
                ButtonSegment(value: NightMap.auto, label: Text('Auto'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: NightMap.always, label: Text('Toujours'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: NightMap.never, label: Text('Jamais'), icon: Icon(Icons.light_mode)),
              ],
              selected: {_s.nightMap},
              onSelectionChanged: (v) => setState(() => _s = _s.copyWith(nightMap: v.single)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                'Auto : couleurs de nuit entre le coucher et le lever du soleil, là où vous êtes. '
                'Carte hors ligne seulement.',
                style: text.bodySmall,
              ),
            ),
            Text('Style en ligne', style: text.bodyMedium),
            RadioGroup<String>(
              groupValue: _s.mapStyle,
              onChanged: (v) => setState(() => _s = _s.copyWith(mapStyle: v)),
              child: Column(
                children: [
                  for (final e in Defaults.mapStyles.entries)
                    RadioListTile<String>(contentPadding: EdgeInsets.zero, title: Text(e.key), value: e.value),
                ],
              ),
            ),
            const Divider(height: 32),
            Text('Services en ligne (POC)', style: text.titleMedium),
            TextField(
              controller: _routing,
              decoration: const InputDecoration(labelText: 'Valhalla'),
            ),
            TextField(
              controller: _geocoder,
              decoration: const InputDecoration(labelText: 'Photon'),
            ),
            const Divider(height: 32),
            Text('Identité', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Clé générée sur ce téléphone, sans compte. Les alertes sont signées par une clé jetable propre à chaque trajet.',
              style: text.bodySmall,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Clé publique'),
              subtitle: Text(app.identity.shortPublicKey),
              trailing: IconButton(
                tooltip: 'Copier',
                icon: const Icon(Icons.copy),
                onPressed: () => Clipboard.setData(ClipboardData(text: app.identity.publicKey)),
              ),
            ),
            if (!app.hasRecoveryPhrase)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Cette identité n’a pas de phrase de récupération : elle sera perdue avec le téléphone. '
                    'Créez une nouvelle identité pour en obtenir une.',
                  ),
                ),
              ),
            if (app.hasRecoveryPhrase)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key),
                title: const Text('Afficher la phrase de récupération'),
                onTap: () async {
                  final phrase = await app.recoveryPhrase();
                  if (phrase == null || !context.mounted) return;
                  await Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => RecoveryPhraseScreen(phrase: phrase)));
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Sauvegarde chiffrée par mot de passe'),
              subtitle: const Text('Fichier ncryptsec (Nostr NIP-49)'),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => ExportIdentityScreen(export: app.exportIdentity))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore),
              title: const Text('Restaurer avec une phrase'),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => RestoreIdentityScreen(app: app))),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_open),
              title: const Text('Restaurer une sauvegarde chiffrée'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RestoreEncryptedScreen(onRestore: app.restoreEncryptedIdentity)),
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Nouvelle identité ?'),
                    content: const Text(
                      'L’identité actuelle sera perdue si vous n’avez pas noté sa phrase de récupération.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remplacer')),
                    ],
                  ),
                );
                if (ok ?? false) {
                  await app.regenerateIdentity();
                  final phrase = await app.recoveryPhrase();
                  if (phrase != null && context.mounted) {
                    await Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => RecoveryPhraseScreen(phrase: phrase)));
                  }
                }
              },
              child: const Text('Générer une nouvelle identité'),
            ),
            const Divider(height: 32),
            Text('Vie privée', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Aucune télémétrie, aucun compte. Une alerte ne publie qu’une maille d’environ 150 m, jamais votre position exacte. '
              'Les alertes expirent seules (${AlertType.traffic.ttl.inMinutes} min pour un bouchon). '
              'Alertes police : ${FeatureFlags.policeAlerts ? 'actives' : 'désactivées (jalon J6)'}.',
              style: text.bodySmall,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Envoyer un retour'),
              subtitle: const Text('Un problème, une idée : vous voyez tout ce qui part'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeedbackScreen(details: FeedbackDetails.of(app), crashReports: app.crashReports),
                ),
              ),
            ),
            if (app.crashReports != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Rapports d’erreur'),
                subtitle: const Text('Gardés sur ce téléphone, partagés seulement si vous le choisissez'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => CrashReportsScreen(reports: app.crashReports!))),
              ),
          ],
        ),
      ),
    );
  }
}

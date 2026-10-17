import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/crash_reports.dart';
import '../services/feedback.dart';

/// Réglages > Envoyer un retour: what the tester saw, with what they choose
/// to add, shared through the phone's own apps (mail, messaging). The whole
/// text is shown before it goes.
class FeedbackScreen extends StatefulWidget {
  final Future<FeedbackDetails> details;
  final CrashReports? crashReports;

  /// Replaced in tests: the system share sheet.
  final Future<void> Function(String text, String subject) share;

  const FeedbackScreen({
    super.key,
    required this.details,
    this.crashReports,
    Future<void> Function(String, String)? share,
  }) : share = share ?? _systemShare;

  static Future<void> _systemShare(String text, String subject) =>
      SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  var _kind = FeedbackKind.bug;
  var _withDetails = true;
  var _withCrash = false;
  FeedbackDetails? _details;
  String? _crash;

  @override
  void initState() {
    super.initState();
    _message.addListener(() => setState(() {}));
    widget.details.then((d) {
      if (mounted) setState(() => _details = d);
    });
    widget.crashReports?.list().then((reports) {
      if (mounted && reports.isNotEmpty) setState(() => _crash = reports.first.text);
    });
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _text => feedbackText(
    kind: _kind,
    message: _message.text,
    details: _withDetails ? _details : null,
    crashReport: _withCrash ? _crash : null,
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canSend = _message.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un retour')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('De quoi s’agit-il ?', style: text.titleSmall),
            const SizedBox(height: 4),
            RadioGroup<FeedbackKind>(
              groupValue: _kind,
              onChanged: (v) => setState(() => _kind = v ?? _kind),
              child: Column(
                children: [
                  for (final k in FeedbackKind.values)
                    RadioListTile<FeedbackKind>(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(k.label),
                      value: k,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('feedback-message'),
              controller: _message,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Ce qui s’est passé',
                hintText: 'Où, quand, ce que vous attendiez…',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Joindre les infos techniques'),
              subtitle: const Text('Version, système, réglages. Ni position, ni destination.'),
              value: _withDetails,
              onChanged: (v) => setState(() => _withDetails = v),
            ),
            if (_crash != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Joindre le dernier rapport d’erreur'),
                subtitle: const Text('Déjà nettoyé des positions, des clés et des adresses.'),
                value: _withCrash,
                onChanged: (v) => setState(() => _withCrash = v),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Voir exactement ce qui sera envoyé'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(_text, key: const Key('feedback-preview'), style: text.bodySmall),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canSend ? () => widget.share(_text, 'Retour RoadTo : ${_kind.label}') : null,
              icon: const Icon(Icons.send),
              label: const Text('Envoyer…'),
            ),
            const SizedBox(height: 8),
            Text(
              'Vous choisissez l’app (e-mail, messagerie) et le destinataire. RoadTo n’a pas de serveur qui le recevrait.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

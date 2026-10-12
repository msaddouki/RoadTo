import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/app_controller.dart';

/// Shows the recovery phrase, numbered, to be written down on paper.
class RecoveryPhraseScreen extends StatelessWidget {
  final RecoveryPhrase phrase;

  const RecoveryPhraseScreen({super.key, required this.phrase});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Phrase de récupération')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Notez ces ${phrase.words.length} mots sur papier, dans l’ordre. Ils permettent de retrouver votre '
            'identité sur un autre téléphone. Ne les photographiez pas et ne les partagez avec personne : '
            'qui les possède peut signer à votre place.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (i, w) in phrase.words.indexed)
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${i + 1}. $w', key: Key('word-$i'), style: text.titleMedium),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Je l’ai notée')),
        ],
      ),
    );
  }
}

/// Restores an identity from a recovery phrase typed by the user.
class RestoreIdentityScreen extends StatefulWidget {
  final AppController? app;

  /// Called with the validated phrase; defaults to [AppController.restoreIdentity].
  final Future<void> Function(RecoveryPhrase phrase)? onRestore;

  const RestoreIdentityScreen({super.key, this.app, this.onRestore});

  @override
  State<RestoreIdentityScreen> createState() => _RestoreIdentityScreenState();
}

class _RestoreIdentityScreenState extends State<RestoreIdentityScreen> {
  final _input = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final RecoveryPhrase phrase;
    try {
      phrase = RecoveryPhrase.parse(_input.text);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remplacer l’identité actuelle ?'),
        content: const Text('L’identité actuelle sera perdue si vous n’avez pas noté sa phrase de récupération.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurer')),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    setState(() => _busy = true);
    await (widget.onRestore ?? widget.app!.restoreIdentity)(phrase);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurer une identité')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Saisissez les 12 ou 24 mots de votre phrase de récupération, séparés par des espaces.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('phrase-input'),
            controller: _input,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(border: const OutlineInputBorder(), errorText: _error),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _restore, child: const Text('Restaurer')),
        ],
      ),
    );
  }
}

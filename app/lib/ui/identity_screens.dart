import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Encrypted backup of the key (NIP-49), protected by a password: an
/// alternative to writing the phrase down, readable by any Nostr client that
/// supports NIP-49.
class ExportIdentityScreen extends StatefulWidget {
  /// Encrypts the key with the password; [AppController.exportIdentity] by default.
  final Future<String> Function(String password) export;

  /// Saves the text to a file the user picks; a file picker by default.
  final Future<void> Function(String text)? save;

  const ExportIdentityScreen({super.key, required this.export, this.save});

  static const minLength = 10;

  @override
  State<ExportIdentityScreen> createState() => _ExportIdentityScreenState();
}

class _ExportIdentityScreenState extends State<ExportIdentityScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  String? _result;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final pw = _password.text;
    if (pw.length < ExportIdentityScreen.minLength) {
      setState(() => _error = 'Au moins ${ExportIdentityScreen.minLength} caractères');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = 'Les deux mots de passe diffèrent');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await widget.export(pw);
      if (mounted) setState(() => _result = text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String text) async {
    final save =
        widget.save ??
        (t) => FilePicker.saveFile(
          fileName: 'roadto-identite.ncryptsec',
          bytes: Uint8List.fromList(utf8.encode('$t\n')),
          mimeType: 'text/plain',
        );
    await save(text);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde chiffrée')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (result == null) ...[
            const Text(
              'Votre clé, chiffrée par un mot de passe (format Nostr NIP-49). '
              'Sans le mot de passe, la sauvegarde est inutilisable : notez-le à part. '
              'La phrase de récupération reste la sauvegarde la plus sûre.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('export-password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Mot de passe'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('export-confirm'),
              controller: _confirm,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Confirmer le mot de passe',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _export,
              child: Text(_busy ? 'Chiffrement… (quelques secondes)' : 'Chiffrer'),
            ),
          ] else ...[
            const Text('Sauvegarde prête. Gardez-la hors du téléphone, avec le mot de passe à part.'),
            const SizedBox(height: 12),
            SelectableText(
              result,
              key: const Key('export-result'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _save(result),
              icon: const Icon(Icons.save_alt),
              label: const Text('Enregistrer dans un fichier'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: result)),
              icon: const Icon(Icons.copy),
              label: const Text('Copier'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Restores the key from an encrypted backup (NIP-49), pasted or opened
/// from a file.
class RestoreEncryptedScreen extends StatefulWidget {
  final Future<void> Function(String encrypted, String password) onRestore;

  /// Reads a backup file the user picks; a file picker by default.
  final Future<String?> Function()? open;

  const RestoreEncryptedScreen({super.key, required this.onRestore, this.open});

  @override
  State<RestoreEncryptedScreen> createState() => _RestoreEncryptedScreenState();
}

class _RestoreEncryptedScreenState extends State<RestoreEncryptedScreen> {
  final _text = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final open =
        widget.open ??
        () async {
          final file = await FilePicker.pickFile(dialogTitle: 'Sauvegarde chiffrée (.ncryptsec)');
          if (file == null) return null;
          final bytes = await file.readAsBytes();
          return utf8.decode(bytes, allowMalformed: true);
        };
    final text = await open();
    if (text != null) setState(() => _text.text = text.trim());
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remplacer l’identité actuelle ?'),
        content: const Text('L’identité actuelle sera perdue si vous ne l’avez pas sauvegardée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restaurer')),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRestore(_text.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on EncryptedKeyException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restaurer une sauvegarde chiffrée')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Collez la sauvegarde (ncryptsec1…) ou ouvrez son fichier, puis saisissez son mot de passe.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('restore-text'),
            controller: _text,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'ncryptsec1…'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.file_open),
              label: const Text('Ouvrir un fichier'),
            ),
          ),
          TextField(
            key: const Key('restore-password'),
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Mot de passe',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _restore, child: Text(_busy ? 'Déchiffrement…' : 'Restaurer')),
        ],
      ),
    );
  }
}

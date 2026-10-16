import 'package:flutter/material.dart';

/// Asks for a favourite's name; null if cancelled.
Future<String?> askFavoriteName(BuildContext context, {String initial = '', String title = 'Ajouter aux favoris'}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: initial, title: title),
    );

class _NameDialog extends StatefulWidget {
  final String initial;
  final String title;

  const _NameDialog({required this.initial, required this.title});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('favorite-name'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nom'),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final s in const ['Maison', 'Travail'])
              ActionChip(label: Text(s), onPressed: () => _controller.text = s),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      ListenableBuilder(
        listenable: _controller,
        builder: (_, _) =>
            FilledButton(onPressed: _controller.text.trim().isEmpty ? null : _done, child: const Text('Enregistrer')),
      ),
    ],
  );
}

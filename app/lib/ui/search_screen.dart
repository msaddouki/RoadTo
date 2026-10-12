import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

/// Recherche d'adresse ou de lieu. Renvoie le [Place] choisi.
class SearchScreen extends StatefulWidget {
  final Future<List<Place>> Function(String query) search;
  final LatLon from;

  const SearchScreen({super.key, required this.search, required this.from});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  String? _error;
  bool _loading = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.search(q);
      if (gen != _generation || !mounted) return;
      setState(() => _results = r);
    } catch (e) {
      if (gen != _generation || !mounted) return;
      setState(() => _error = 'Recherche indisponible : $e');
    } finally {
      if (gen == _generation && mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Adresse, lieu…', border: InputBorder.none),
          onChanged: _onChanged,
          onSubmitted: _run,
        ),
        bottom: _loading
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
            : null,
      ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = _results[i];
                return ListTile(
                  minTileHeight: 64,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(p.name),
                  subtitle: p.detail == null || p.detail!.isEmpty ? null : Text(p.detail!),
                  trailing: Text(formatDistance(distanceM(widget.from, p.position))),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
    );
  }
}

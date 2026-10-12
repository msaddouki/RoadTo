import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

const _categoryIcons = {
  'fuel': Icons.local_gas_station,
  'charging': Icons.ev_station,
  'parking': Icons.local_parking,
  'rest': Icons.airline_seat_recline_normal,
  'toilets': Icons.wc,
  'food': Icons.restaurant,
};

/// Address or place search, plus one-tap categories (fuel, charging…).
/// Returns the chosen [Place].
class SearchScreen extends StatefulWidget {
  final Future<List<Place>> Function(String query) search;
  final LatLon from;

  /// Category search; returns null when no offline region is installed.
  final List<NearbyPlace>? Function(PlaceCategory category)? searchCategory;

  const SearchScreen({super.key, required this.search, required this.from, this.searchCategory});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  PlaceCategory? _category;
  List<NearbyPlace>? _nearby;
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
    if (_category != null) setState(() => _category = null);
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

  void _pickCategory(PlaceCategory c) {
    _debounce?.cancel();
    _generation++;
    _controller.clear();
    FocusScope.of(context).unfocus();
    final found = widget.searchCategory!(c);
    setState(() {
      _loading = false;
      _category = c;
      _nearby = found;
      _error = found == null
          ? 'La recherche par catégorie utilise la région hors ligne : installez-en une dans Réglages.'
          : null;
    });
  }

  static String _distanceLabel(NearbyPlace n) {
    if (n.aheadM == null) return formatDistance(n.distanceM);
    final detour = (n.offRouteM ?? 0) > 150 ? '\nà ${formatDistance(n.offRouteM!)} de la route' : '';
    return 'dans ${formatDistance(n.aheadM!)}$detour';
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    final nearby = _nearby;
    final showCategory = category != null && nearby != null;
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
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(widget.searchCategory == null ? 2 : 58),
          child: Column(
            children: [
              if (widget.searchCategory != null)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      for (final c in driverCategories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(_categoryIcons[c.id], size: 18),
                            label: Text(c.label),
                            selected: category?.id == c.id,
                            onSelected: (_) => _pickCategory(c),
                          ),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
            ],
          ),
        ),
      ),
      body: _error != null
          ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
          : showCategory && nearby.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aucun résultat « ${category.label} » à proximité dans la région installée.'),
            )
          : ListView.separated(
              itemCount: showCategory ? nearby.length : _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = showCategory ? nearby[i].place : _results[i];
                return ListTile(
                  minTileHeight: 64,
                  leading: Icon(showCategory ? _categoryIcons[category.id] : Icons.place_outlined),
                  title: Text(p.name),
                  subtitle: p.detail == null || p.detail!.isEmpty ? null : Text(p.detail!),
                  trailing: Text(
                    showCategory ? _distanceLabel(nearby[i]) : formatDistance(distanceM(widget.from, p.position)),
                    textAlign: TextAlign.end,
                  ),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
    );
  }
}

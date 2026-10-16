import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import '../services/favorites.dart';
import 'favorite_name_dialog.dart';
import 'place_sheet.dart';

const _categoryIcons = {
  'fuel': Icons.local_gas_station,
  'charging': Icons.ev_station,
  'parking': Icons.local_parking,
  'rest': Icons.airline_seat_recline_normal,
  'toilets': Icons.wc,
  'food': Icons.restaurant,
};

/// Address or place search, plus one-tap categories (fuel, charging…) and
/// the user's favourites. Returns the chosen [Place].
class SearchScreen extends StatefulWidget {
  final Future<List<Place>> Function(String query) search;
  final LatLon from;

  /// Category search; returns null when no offline region is installed.
  final List<NearbyPlace>? Function(PlaceCategory category)? searchCategory;

  /// Shown before anything is typed; results can be added to them.
  final Favorites? favorites;

  /// Fuel whose price the fuel search shows, and where a new choice goes.
  final String fuel;
  final ValueChanged<String>? onFuelChanged;

  const SearchScreen({
    super.key,
    required this.search,
    required this.from,
    this.searchCategory,
    this.favorites,
    this.fuel = 'gazole',
    this.onFuelChanged,
  });

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
  late String _fuel = widget.fuel;
  _Order _order = _Order.nearest;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    // Rebuilt on every key: favourites show while the field is empty.
    setState(() => _category = null);
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

  void _pickFuel(String fuel) {
    setState(() => _fuel = fuel);
    widget.onFuelChanged?.call(fuel);
  }

  /// Orders that make sense for these results: by price when some fuel
  /// station has the chosen fuel's price, by detour when on a route.
  List<_Order> _orders(List<NearbyPlace> nearby) => [
    _Order.nearest,
    if (_category?.id == 'fuel' && nearby.any((n) => n.fuel?.prices[_fuel] != null)) _Order.cheapest,
    if (nearby.any((n) => n.offRouteM != null)) _Order.leastDetour,
  ];

  /// Results in the chosen order. Cheapest: stations without the chosen
  /// fuel's price follow, in their order. The search returns them nearest
  /// (or first on the route) first.
  List<NearbyPlace> _ordered(List<NearbyPlace> nearby) {
    final order = _orders(nearby).contains(_order) ? _order : _Order.nearest;
    switch (order) {
      case _Order.nearest:
        return nearby;
      case _Order.cheapest:
        final priced = [
          for (final n in nearby)
            if (n.fuel?.prices[_fuel] != null) n,
        ]..sort((a, b) => a.fuel!.prices[_fuel]!.price.compareTo(b.fuel!.prices[_fuel]!.price));
        return [
          ...priced,
          for (final n in nearby)
            if (n.fuel?.prices[_fuel] == null) n,
        ];
      case _Order.leastDetour:
        // List.sort is not stable: keep the route order between equal detours.
        final indexed = [for (var i = 0; i < nearby.length; i++) (i, nearby[i])]
          ..sort((a, b) {
            final d = (a.$2.offRouteM ?? double.infinity).compareTo(b.$2.offRouteM ?? double.infinity);
            return d != 0 ? d : a.$1.compareTo(b.$1);
          });
        return [for (final (_, n) in indexed) n];
    }
  }

  Widget _orderBar(List<NearbyPlace> nearby) {
    final orders = _orders(nearby);
    final onRoute = nearby.any((n) => n.aheadM != null);
    String label(_Order o) => switch (o) {
      _Order.nearest => onRoute ? 'Premier sur la route' : 'Plus proche',
      _Order.cheapest => 'Moins cher',
      _Order.leastDetour => 'Moins de détour',
    };
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final o in orders)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(label(o)),
                selected: (orders.contains(_order) ? _order : _Order.nearest) == o,
                onSelected: (_) => setState(() => _order = o),
              ),
            ),
        ],
      ),
    );
  }

  /// A result with official data opens its sheet first; the others are
  /// picked at once.
  Future<void> _pickNearby(NearbyPlace n) async {
    if (n.fuel == null && n.charging == null) {
      Navigator.of(context).pop(n.place);
      return;
    }
    final go = await showPlaceSheet(context, n, distance: _distanceLabel(n), fuel: n.fuel == null ? null : _fuel);
    if (go && mounted) Navigator.of(context).pop(n.place);
  }

  /// Official data of a category result: the price of the chosen fuel, or
  /// the charge points.
  String? _stationInfo(NearbyPlace n) {
    final fuel = n.fuel;
    if (fuel != null) {
      final label = fuelLabels[_fuel] ?? _fuel;
      final price = fuel.prices[_fuel];
      if (price != null) return '$label ${formatPrice(price.price)} · ${formatAge(price.updated, DateTime.now())}';
      return fuel.outOfStock.contains(_fuel) ? '$label en rupture' : 'Pas de $label';
    }
    final c = n.charging;
    if (c != null) return chargingSummary(c);
    return null;
  }

  Widget _fuelBar(List<NearbyPlace> nearby) {
    final offered = {for (final n in nearby) ...?n.fuel?.prices.keys, _fuel};
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final MapEntry(key: id, value: label) in fuelLabels.entries)
            if (offered.contains(id))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(label), selected: _fuel == id, onSelected: (_) => _pickFuel(id)),
              ),
        ],
      ),
    );
  }

  static String _distanceLabel(NearbyPlace n) {
    if (n.aheadM == null) return formatDistance(n.distanceM);
    final detour = (n.offRouteM ?? 0) > 150 ? '\nà ${formatDistance(n.offRouteM!)} de la route' : '';
    return 'dans ${formatDistance(n.aheadM!)}$detour';
  }

  Future<void> _toggleFavorite(Place p) async {
    final favorites = widget.favorites!;
    if (favorites.contains(p)) {
      await favorites.remove(p);
    } else {
      await favorites.add(p);
    }
  }

  Future<void> _rename(Place f) async {
    final name = await askFavoriteName(context, initial: f.name, title: 'Renommer le favori');
    if (name != null) await widget.favorites!.rename(f, name);
  }

  Widget _favoriteList(List<Place> favorites) => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Favoris', style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final f in favorites)
        ListTile(
          minTileHeight: 64,
          leading: const Icon(Icons.star),
          title: Text(f.name),
          subtitle: f.detail == null || f.detail!.isEmpty ? null : Text(f.detail!),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(formatDistance(distanceM(widget.from, f.position))),
              PopupMenuButton<String>(
                tooltip: 'Options',
                onSelected: (v) => v == 'rename' ? _rename(f) : widget.favorites!.remove(f),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Renommer')),
                  PopupMenuItem(value: 'remove', child: Text('Retirer des favoris')),
                ],
              ),
            ],
          ),
          onTap: () => Navigator.of(context).pop(f),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final favorites = widget.favorites;
    if (favorites == null) return _build(context);
    return ListenableBuilder(listenable: favorites, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final category = _category;
    final nearby = _nearby == null ? null : _ordered(_nearby!);
    final showCategory = category != null && nearby != null;
    final showFuelBar = showCategory && category.id == 'fuel' && nearby.any((n) => n.fuel != null);
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
          : !showCategory && _controller.text.trim().isEmpty && (widget.favorites?.all.isNotEmpty ?? false)
          ? _favoriteList(widget.favorites!.all)
          : showCategory && nearby.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aucun résultat « ${category.label} » à proximité dans la région installée.'),
            )
          : Column(
              children: [
                if (showCategory && _orders(nearby).length > 1) _orderBar(nearby),
                if (showFuelBar) _fuelBar(nearby),
                Expanded(child: _resultList(category, nearby, showCategory)),
              ],
            ),
    );
  }

  Widget _resultList(PlaceCategory? category, List<NearbyPlace>? nearby, bool showCategory) => ListView.separated(
    itemCount: showCategory ? nearby!.length : _results.length,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (context, i) {
      final p = showCategory ? nearby![i].place : _results[i];
      final distance = Text(
        showCategory ? _distanceLabel(nearby![i]) : formatDistance(distanceM(widget.from, p.position)),
        textAlign: TextAlign.end,
      );
      final favorite = widget.favorites?.contains(p);
      return ListTile(
        minTileHeight: 64,
        leading: Icon(showCategory ? _categoryIcons[category!.id] : Icons.place_outlined),
        title: Text(p.name),
        subtitle: _subtitle(p, showCategory ? _stationInfo(nearby![i]) : null),
        trailing: favorite == null
            ? distance
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  distance,
                  IconButton(
                    tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                    icon: Icon(favorite ? Icons.star : Icons.star_border),
                    onPressed: () => _toggleFavorite(p),
                  ),
                ],
              ),
        onTap: () => showCategory ? _pickNearby(nearby![i]) : Navigator.of(context).pop(p),
      );
    },
  );

  Widget? _subtitle(Place p, String? info) {
    final lines = [if (p.detail != null && p.detail!.isNotEmpty) p.detail!, ?info];
    if (lines.isEmpty) return null;
    return Text(lines.join('\n'));
  }
}

enum _Order { nearest, cheapest, leastDetour }

/// "1,789 €".
String formatPrice(double euros) => '${euros.toStringAsFixed(3).replaceFirst('.', ',')} €';

/// How long ago a price was set: "à l'instant", "il y a 25 min", "il y a
/// 3 h", "il y a 2 j".
String formatAge(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 2) return 'à l’instant';
  if (d.inHours < 1) return 'il y a ${d.inMinutes} min';
  if (d.inDays < 1) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

const _connectorLabels = {
  'type2': 'Type 2',
  'ccs': 'CCS',
  'chademo': 'CHAdeMO',
  'ef': 'prise domestique',
  'other': 'autre',
};

/// "4 points · 22 kW · Type 2, CCS · gratuit · accès réservé".
String chargingSummary(ChargingStation c) {
  final kw = c.maxKw == c.maxKw.roundToDouble()
      ? c.maxKw.toStringAsFixed(0)
      : c.maxKw.toStringAsFixed(1).replaceFirst('.', ',');
  return [
    c.points > 1 ? '${c.points} points' : '1 point',
    if (c.maxKw > 0) '$kw kW',
    if (c.connectors.isNotEmpty) c.connectors.map((k) => _connectorLabels[k] ?? k).join(', '),
    if (c.free) 'gratuit',
    if (!c.openToAll) 'accès réservé',
    if (!c.alwaysOpen) 'horaires limités',
  ].join(' · ');
}

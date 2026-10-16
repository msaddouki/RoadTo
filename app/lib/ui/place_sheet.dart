import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import 'search_screen.dart' show chargingSummary, formatAge, formatPrice;

/// Details of a fuel or charging station found by category: every price
/// with its age, or the charge points, and where the data comes from.
/// Resolves to true when the driver chooses to go there.
Future<bool> showPlaceSheet(BuildContext context, NearbyPlace n, {required String distance, String? fuel}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PlaceSheet(place: n, distance: distance, fuel: fuel),
    ) ??
    false;

class PlaceSheet extends StatelessWidget {
  final NearbyPlace place;
  final String distance;

  /// The fuel chosen in the search, shown first and in bold.
  final String? fuel;

  const PlaceSheet({super.key, required this.place, required this.distance, this.fuel});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = place.place;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.name, style: text.titleLarge),
            if (p.detail != null && p.detail!.isNotEmpty) Text(p.detail!, style: text.bodyMedium),
            const SizedBox(height: 4),
            Text(distance.replaceAll('\n', ' · '), style: text.bodyMedium),
            const SizedBox(height: 16),
            if (place.fuel case final f?) ..._fuel(context, f),
            if (place.charging case final c?) ..._charging(context, c),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Fermer')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.navigation),
                    label: const Text('Y aller'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fuel(BuildContext context, FuelStation f) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    // The chosen fuel first, then the others in the usual order.
    final order = [?fuel, ...fuelLabels.keys.where((k) => k != fuel)];
    return [
      for (final id in order)
        if (f.prices[id] case final price?)
          _row(
            context,
            fuelLabels[id] ?? id,
            '${formatPrice(price.price)}  ·  ${formatAge(price.updated, now)}',
            bold: id == fuel,
          )
        else if (f.outOfStock.contains(id))
          _row(context, fuelLabels[id] ?? id, 'en rupture', bold: id == fuel),
      const SizedBox(height: 8),
      if (f.card24h) const _Fact(Icons.credit_card, 'Automate carte bancaire 24h/24'),
      if (f.motorway) const _Fact(Icons.add_road, 'Sur autoroute'),
      const SizedBox(height: 8),
      Text('Prix : prix-carburants.gouv.fr, déclarés par la station.', style: text.bodySmall),
    ];
  }

  List<Widget> _charging(BuildContext context, ChargingStation c) {
    final text = Theme.of(context).textTheme;
    return [
      if (c.operator.isNotEmpty && c.operator != place.place.name) _Fact(Icons.business, c.operator),
      _Fact(Icons.ev_station, chargingSummary(c)),
      _Fact(Icons.payments_outlined, [c.free ? 'Gratuit' : 'Payant', if (c.card) 'carte bancaire acceptée'].join(', ')),
      _Fact(Icons.lock_open, c.openToAll ? 'Accès libre' : 'Accès réservé'),
      _Fact(Icons.schedule, c.alwaysOpen ? 'Ouvert 24h/24' : 'Horaires limités'),
      const SizedBox(height: 8),
      Text('Bornes : base nationale IRVE (data.gouv.fr).', style: text.bodySmall),
    ];
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: style)),
          Expanded(child: Text(value, style: style)),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Fact(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

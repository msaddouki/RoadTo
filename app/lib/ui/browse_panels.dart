import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import 'navigation_panels.dart';

/// "Où allez-vous ?" on one line, settings at its end; the simulated drive
/// shows as a badge under it rather than squeezing the text.
class DestinationBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final bool routing;
  final bool simulate;

  const DestinationBar({
    super.key,
    required this.onSearch,
    required this.onSettings,
    required this.routing,
    required this.simulate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: NavColors.sheet,
          borderRadius: BorderRadius.circular(30),
          elevation: 6,
          shadowColor: Colors.black45,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(30)),
                    onTap: onSearch,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 8),
                      child: Row(
                        children: [
                          routing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                )
                              : const Icon(Icons.search, size: 26, color: Colors.white),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              routing ? 'Calcul de l’itinéraire…' : 'Où allez-vous ?',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Réglages',
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings, color: NavColors.muted),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
        if (simulate) ...[
          const SizedBox(height: 6),
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: NavColors.report, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              'Conduite simulée',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: NavColors.onReport),
            ),
          ),
        ],
      ],
    );
  }
}

/// Saved places one tap away (Maison, Travail, then the others), as Waze
/// puts home and work under the search.
class FavoriteShortcuts extends StatelessWidget {
  final List<Place> favorites;
  final void Function(Place place) onGo;

  /// Shortcuts shown at most; the search screen lists them all.
  static const shown = 4;

  const FavoriteShortcuts({super.key, required this.favorites, required this.onGo});

  static IconData iconOf(Place p) => switch (p.name.toLowerCase()) {
    'maison' || 'domicile' => Icons.home_rounded,
    'travail' || 'bureau' => Icons.work_rounded,
    _ => Icons.star_rounded,
  };

  /// Maison and Travail first, then the others newest first.
  static List<Place> ordered(List<Place> all) {
    int rank(Place p) => switch (iconOf(p)) {
      Icons.home_rounded => 0,
      Icons.work_rounded => 1,
      _ => 2,
    };
    final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
    indexed.sort((a, b) => rank(a.$2) != rank(b.$2) ? rank(a.$2) - rank(b.$2) : a.$1 - b.$1);
    return [for (final e in indexed.take(shown)) e.$2];
  }

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final p in ordered(favorites))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: NavColors.sheet,
                borderRadius: BorderRadius.circular(22),
                elevation: 4,
                shadowColor: Colors.black38,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onGo(p),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconOf(p), size: 20, color: const Color(0xFF8FB4FF)),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

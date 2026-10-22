import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/trip_preview.dart';
import 'map_layers.dart';
import 'navigation_panels.dart';

/// Top of the screen during the route preview: where the route goes, and
/// the way back to the map.
class PreviewHeader extends StatelessWidget {
  final Place place;
  final VoidCallback onBack;

  const PreviewHeader({super.key, required this.place, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NavColors.sheet,
      borderRadius: BorderRadius.circular(30),
      elevation: 6,
      shadowColor: Colors.black45,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Retour',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Vers ${place.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// Bottom of the screen during the route preview: the destination, time,
/// arrival and distance, the alerts on the way, and "Partir".
class RoutePreviewSheet extends StatelessWidget {
  final TripPreview preview;
  final DateTime now;
  final VoidCallback onGo;
  final VoidCallback onCancel;

  const RoutePreviewSheet({
    super.key,
    required this.preview,
    required this.now,
    required this.onGo,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final eta = p.arrival(now);
    final hh = eta.hour.toString().padLeft(2, '0'), mm = eta.minute.toString().padLeft(2, '0');
    final bottom = MediaQuery.paddingOf(context).bottom;
    final detail = p.place.detail;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
      decoration: const BoxDecoration(
        color: NavColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black38)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.place, color: Color(0xFFFF5A5F), size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    if (detail != null && detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: NavColors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TripFigure(value: NavigationSheet.timeLeft(p.duration), label: 'de trajet'),
              ),
              Expanded(
                child: TripFigure(value: '$hh:$mm', label: 'arrivée', color: NavColors.eta, big: true),
              ),
              Expanded(
                child: TripFigure(value: formatDistance(p.route.lengthM), label: 'à parcourir'),
              ),
            ],
          ),
          if (p.jamDelay >= const Duration(minutes: 1)) ...[
            const SizedBox(height: 6),
            Text(
              'dont ${p.jamDelay.inMinutes} min de bouchons signalés',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFFFF9F1C), fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 14),
          if (p.alerts.isEmpty)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: NavColors.eta, size: 20),
                SizedBox(width: 8),
                Text('Aucune alerte sur le trajet', style: TextStyle(fontSize: 15, color: NavColors.figures)),
              ],
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [for (final (type, label) in p.alertSummary) _AlertChip(type: type, label: label)],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 64,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: NavColors.panelBorder, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                  ),
                  child: const Text('Annuler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: FilledButton(
                    onPressed: onGo,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3D8BFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.navigation, size: 26),
                          SizedBox(width: 8),
                          Text('Partir', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final AlertType type;
  final String label;

  const _AlertChip({required this.type, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(color: NavColors.panel, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: alertColors[type], shape: BoxShape.circle),
            child: Icon(alertIcons[type], size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import 'map_layers.dart';

/// « Signaler en un geste » : six grandes cases, puis 5 s pour annuler.
/// La position est figée au moment du geste, pas à l'envoi.
class ReportSheet extends StatefulWidget {
  final void Function(AlertType type) onConfirmed;
  final Duration cancelDelay;

  const ReportSheet({super.key, required this.onConfirmed, this.cancelDelay = const Duration(seconds: 5)});

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  AlertType? _chosen;
  Timer? _timer;
  int _left = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _choose(AlertType t) {
    setState(() {
      _chosen = t;
      _left = widget.cancelDelay.inSeconds;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_left <= 1) {
        timer.cancel();
        widget.onConfirmed(t);
        Navigator.of(context).pop();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final types = AlertType.reportable;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: chosen == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Que voyez-vous ?',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.95,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [for (final t in types) _Tile(type: t, onTap: () => _choose(t))],
                      ),
                      if (!FeatureFlags.policeAlerts) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Alertes police désactivées tant que le canal L130-11 n’est pas en place.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The time left to cancel, as a ring around the alert.
                      SizedBox(
                        width: 112,
                        height: 112,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: _left / widget.cancelDelay.inSeconds,
                                strokeWidth: 6,
                                color: alertColors[chosen],
                                backgroundColor: alertColors[chosen]!.withValues(alpha: 0.2),
                              ),
                            ),
                            _Badge(type: chosen, size: 84),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${chosen.label} : envoi dans $_left s',
                        key: const Key('countdown'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 64,
                        child: FilledButton.tonal(
                          onPressed: () {
                            _timer?.cancel();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Annuler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// The alert's colour disc with its icon, as on the map.
class _Badge extends StatelessWidget {
  final AlertType type;
  final double size;

  const _Badge({required this.type, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: alertColors[type],
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: alertColors[type]!.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Icon(alertIcons[type], size: size * 0.5, color: Colors.white),
    );
  }
}

class _Tile extends StatelessWidget {
  final AlertType type;
  final VoidCallback onTap;

  const _Tile({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Badge(type: type, size: 68),
          const SizedBox(height: 8),
          Text(
            type.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

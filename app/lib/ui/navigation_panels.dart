import 'package:flutter/material.dart';
import 'package:roadto_core/roadto_core.dart';

import 'map_layers.dart';

/// Night palette of the navigation screen (mockup "Navigation (nuit)").
abstract final class NavColors {
  static const banner = Color(0xFF1B3A73);
  static const bannerThen = Color(0xFF12284F);
  static const thenText = Color(0xFFD5E2FF);
  static const panel = Color(0xF21A1F25);
  static const panelBorder = Color(0xFF323B45);
  static const sheet = Color(0xFF1A1F25);
  static const sheetBorder = Color(0xFF2A323B);
  static const button = Color(0xFF262D35);
  static const report = Color(0xFFF5B83D);
  static const onReport = Color(0xFF1A1300);
  static const eta = Color(0xFF7FE0A0);
  static const muted = Color(0xFFA9B3BD);
  static const figures = Color(0xFFD5DCE2);
  static const limitRed = Color(0xFFD93A3A);
}

/// Figures (distances, speeds, times) in the monospaced face, so they do not
/// jump as they change.
const _mono = 'Atkinson Hyperlegible Mono';

IconData maneuverIcon(Maneuver? m) => switch (m?.type) {
  null => Icons.straight,
  1 || 2 || 3 => Icons.navigation,
  4 || 5 || 6 => Icons.flag,
  9 || 23 => Icons.turn_slight_right,
  10 || 18 || 20 => Icons.turn_right,
  11 => Icons.turn_sharp_right,
  12 => Icons.u_turn_right,
  13 => Icons.u_turn_left,
  14 => Icons.turn_sharp_left,
  15 || 19 || 21 => Icons.turn_left,
  16 || 24 => Icons.turn_slight_left,
  25 => Icons.merge,
  26 || 27 => Icons.roundabout_right,
  28 || 29 => Icons.directions_boat,
  _ => Icons.straight,
};

String _maneuverLabel(Maneuver m) =>
    m.isArrival ? 'Arrivée' : (m.streetNames.isNotEmpty ? m.streetNames.first : m.instruction);

/// Next maneuver: distance and street, and the one after it when it comes
/// soon after ("Puis ↰ Rue Pasteur").
class ManeuverBanner extends StatelessWidget {
  final GuidanceState state;
  final Maneuver? then;

  const ManeuverBanner({super.key, required this.state, this.then});

  /// The maneuver after the next one, when it is less than [withinM] after it.
  static Maneuver? thenOf(TripRoute route, GuidanceState state, {double withinM = 800}) {
    final i = state.nextManeuverIndex;
    if (i == null || i + 1 >= route.maneuvers.length) return null;
    final gap = route.maneuverStartM(i + 1) - route.maneuverStartM(i);
    return gap <= withinM ? route.maneuvers[i + 1] : null;
  }

  @override
  Widget build(BuildContext context) {
    final m = state.nextManeuver;
    final then = this.then;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: NavColors.banner,
          borderRadius: BorderRadius.circular(20),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(maneuverIcon(m), size: 56, color: Colors.white),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.offRoute ? 'Hors itinéraire' : formatDistance(state.distanceToNextM),
                        style: TextStyle(
                          fontFamily: state.offRoute ? null : _mono,
                          fontSize: state.offRoute ? 28 : 38,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m == null ? 'Continuez' : _maneuverLabel(m),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (then != null && !state.offRoute) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
            decoration: BoxDecoration(color: NavColors.bannerThen, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Puis', style: TextStyle(fontSize: 15, color: NavColors.thenText)),
                const SizedBox(width: 8),
                Icon(maneuverIcon(then), size: 20, color: NavColors.thenText),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _maneuverLabel(then),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: NavColors.thenText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Alert on the route ahead: type, distance and how much to trust it.
class AlertAheadCard extends StatelessWidget {
  final AlertAhead ahead;
  final ({int count, DateTime? latest}) confirmations;
  final DateTime now;

  const AlertAheadCard({super.key, required this.ahead, required this.confirmations, required this.now});

  static String ago(Duration d) {
    final m = d.inMinutes;
    if (m < 1) return 'à l’instant';
    if (m < 60) return 'il y a $m min';
    return 'il y a ${d.inHours} h';
  }

  String get detail {
    final c = confirmations;
    if (c.count == 0 || c.latest == null) return 'Signalé ${ago(now.difference(ahead.alert.createdAt))}';
    final who = c.count == 1 ? '1 conducteur' : '${c.count} conducteurs';
    return 'Confirmé par $who · ${ago(now.difference(c.latest!))}';
  }

  @override
  Widget build(BuildContext context) {
    final t = ahead.alert.type;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      decoration: BoxDecoration(
        color: NavColors.panel,
        border: Border.all(color: NavColors.panelBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: alertColors[t], shape: BoxShape.circle),
            child: Icon(alertIcons[t], color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${t.label} · ${formatDistance(ahead.distanceM)}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                Text(detail, style: const TextStyle(fontSize: 13, color: NavColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round speed limit sign, as on the road; filled red when over the limit.
class SpeedLimitSign extends StatelessWidget {
  final int kph;
  final bool over;

  const SpeedLimitSign({super.key, required this.kph, required this.over});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Limitée à $kph km/h${over ? ', vitesse dépassée' : ''}',
      excludeSemantics: true,
      child: Container(
        width: 66,
        height: 66,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: over ? NavColors.limitRed : Colors.white,
          border: Border.all(color: NavColors.limitRed, width: 7),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black45)],
        ),
        child: Text(
          '$kph',
          style: TextStyle(
            fontSize: kph >= 100 ? 22 : 26,
            fontWeight: FontWeight.w800,
            color: over ? Colors.white : const Color(0xFF111111),
          ),
        ),
      ),
    );
  }
}

/// Current speed, next to the limit.
class SpeedReadout extends StatelessWidget {
  final int kph;

  const SpeedReadout({super.key, required this.kph});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vitesse : $kph km/h',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: NavColors.panel, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$kph',
              style: const TextStyle(
                fontFamily: _mono,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                height: 1,
                color: Colors.white,
              ),
            ),
            const Text('km/h', style: TextStyle(fontSize: 12, color: NavColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Bottom of the screen while navigating: arrival time, what is left, and
/// the three driving buttons (voice, report, trip options).
class NavigationSheet extends StatelessWidget {
  final GuidanceState state;
  final DateTime now;
  final bool voiceOn;
  final VoidCallback onToggleVoice;
  final VoidCallback onReport;
  final VoidCallback onOptions;

  const NavigationSheet({
    super.key,
    required this.state,
    required this.now,
    required this.voiceOn,
    required this.onToggleVoice,
    required this.onReport,
    required this.onOptions,
  });

  static String remaining(Duration d, double metres) {
    final minutes = (d.inSeconds / 60).ceil();
    final time = minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
    return '$time · ${formatDistance(metres)}';
  }

  @override
  Widget build(BuildContext context) {
    final eta = state.eta(now);
    final hh = eta.hour.toString().padLeft(2, '0'), mm = eta.minute.toString().padLeft(2, '0');
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      decoration: const BoxDecoration(
        color: NavColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: NavColors.sheetBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  state.arrived ? 'Arrivé' : '$hh:$mm',
                  style: const TextStyle(
                    fontFamily: _mono,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: NavColors.eta,
                  ),
                ),
                if (!state.arrived) ...[
                  const SizedBox(width: 8),
                  const Text('arrivée', style: TextStyle(fontSize: 14, color: NavColors.muted)),
                ],
                const Spacer(),
                // Shrinks rather than overflows on narrow phones (320 dp: the
                // sheet leaves 276 px, short of "1 h 05 · 12,3 km" at full size).
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      remaining(state.remaining, state.remainingM),
                      style: const TextStyle(fontFamily: _mono, fontSize: 18, color: NavColors.figures),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _SquareButton(
                tooltip: voiceOn ? 'Couper le guidage vocal' : 'Rétablir le guidage vocal',
                icon: voiceOn ? Icons.volume_up : Icons.volume_off,
                onPressed: onToggleVoice,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 68,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: NavColors.report,
                      foregroundColor: NavColors.onReport,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      textStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                    ),
                    onPressed: onReport,
                    icon: const Icon(Icons.warning_amber_rounded, size: 26),
                    label: const Text('Signaler'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SquareButton(tooltip: 'Options du trajet', icon: Icons.more_horiz, onPressed: onOptions),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _SquareButton({required this.tooltip, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: IconButton.filled(
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: NavColors.button,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        iconSize: 28,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

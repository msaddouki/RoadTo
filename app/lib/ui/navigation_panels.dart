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

/// Figures (distances, speeds, times) with digits of equal width, so they do
/// not jump as they change, in the app's own face (the monospaced one spread
/// "260 m" out).
const _figures = [FontFeature.tabularFigures()];

/// "260 m" as a big number and a smaller unit, the way a driver reads it.
Widget distanceText(String formatted, {required double size, Color color = Colors.white}) {
  final i = formatted.lastIndexOf(' ');
  final number = i < 0 ? formatted : formatted.substring(0, i);
  final unit = i < 0 ? '' : formatted.substring(i);
  return Text.rich(
    TextSpan(
      text: number,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, fontFeatures: _figures, height: 1),
      children: [
        TextSpan(
          text: unit,
          style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w700),
        ),
      ],
    ),
    style: TextStyle(color: color),
    maxLines: 1,
    softWrap: false,
  );
}

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

/// Next maneuver, as Waze shows it: the arrow with its distance under it,
/// the street in big letters, and the turn after it in the same card when
/// it comes soon after ("Puis ↰ Rue Pasteur").
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
    return Material(
      color: NavColors.banner,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      elevation: 8,
      shadowColor: Colors.black54,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(state.offRoute ? Icons.wrong_location : maneuverIcon(m), size: 52, color: Colors.white),
                      const SizedBox(height: 2),
                      if (!state.offRoute)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: distanceText(formatDistance(state.distanceToNextM), size: 26),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.offRoute ? 'Hors itinéraire' : (m == null ? 'Continuez' : _maneuverLabel(m)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (then != null && !state.offRoute)
            Container(
              color: NavColors.bannerThen,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  const Text('Puis', style: TextStyle(fontSize: 15, color: NavColors.thenText)),
                  const SizedBox(width: 8),
                  Icon(maneuverIcon(then), size: 22, color: Colors.white),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _maneuverLabel(then),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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
    return Material(
      color: NavColors.panel,
      borderRadius: BorderRadius.circular(22),
      elevation: 4,
      shadowColor: Colors.black45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: alertColors[t], shape: BoxShape.circle),
              child: Icon(alertIcons[t], color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${t.label} · ${formatDistance(ahead.distanceM)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      fontFeatures: _figures,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: NavColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
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
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: over ? NavColors.limitRed : Colors.white,
          border: Border.all(color: NavColors.limitRed, width: 6),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 2))],
        ),
        child: Text(
          '$kph',
          style: TextStyle(
            fontSize: kph >= 100 ? 21 : 25,
            fontWeight: FontWeight.w800,
            fontFeatures: _figures,
            color: over ? Colors.white : const Color(0xFF111111),
          ),
        ),
      ),
    );
  }
}

/// Current speed in a round dial next to the limit; red when over it.
class SpeedReadout extends StatelessWidget {
  final int kph;
  final bool over;

  const SpeedReadout({super.key, required this.kph, this.over = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vitesse : $kph km/h',
      excludeSemantics: true,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: over ? NavColors.limitRed : NavColors.panel,
          border: Border.all(color: over ? Colors.white : NavColors.panelBorder, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 2))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$kph',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                fontFeatures: _figures,
                height: 1,
                color: Colors.white,
              ),
            ),
            Text('km/h', style: TextStyle(fontSize: 11, color: over ? Colors.white : NavColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Bottom of the screen while navigating: time left, arrival time and
/// distance left side by side, readable at a glance, and the three driving
/// buttons (voice, report, trip options).
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

  /// "18 min", or "1 h 05" from an hour.
  static String timeLeft(Duration d) {
    final minutes = (d.inSeconds / 60).ceil();
    return minutes < 60 ? '$minutes min' : '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final eta = state.eta(now);
    final hh = eta.hour.toString().padLeft(2, '0'), mm = eta.minute.toString().padLeft(2, '0');
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
      decoration: const BoxDecoration(
        color: NavColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black38)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TripFigure(value: timeLeft(state.remaining), label: 'restant'),
              ),
              Expanded(
                child: TripFigure(
                  value: state.arrived ? 'Arrivé' : '$hh:$mm',
                  label: state.arrived ? '' : 'arrivée',
                  color: NavColors.eta,
                  big: true,
                ),
              ),
              Expanded(
                child: TripFigure(value: formatDistance(state.remainingM), label: 'à parcourir'),
              ),
            ],
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
                  height: 64,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: NavColors.report,
                      foregroundColor: NavColors.onReport,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onReport,
                    // Never cut in two ("Signa / ler") on a narrow phone.
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.campaign, size: 28),
                          SizedBox(width: 8),
                          Text('Signaler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
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

/// One figure of a trip (time left, arrival, distance): the value big, what
/// it is under it.
class TripFigure extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool big;

  const TripFigure({
    super.key,
    required this.value,
    required this.label,
    this.color = NavColors.figures,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same height for the three, so their labels line up.
        SizedBox(
          height: 38,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            // "9 min", "1,1 km": number and unit; "1 h 05" and the time as they are.
            child: big || !RegExp(r'^[\d,]+ \S+$').hasMatch(value)
                ? Text(
                    value,
                    style: TextStyle(
                      fontSize: big ? 30 : 22,
                      fontWeight: FontWeight.w800,
                      fontFeatures: _figures,
                      color: color,
                    ),
                  )
                : distanceText(value, size: 22, color: color),
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 13, color: NavColors.muted)),
      ],
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
      width: 64,
      height: 64,
      child: IconButton.filled(
        tooltip: tooltip,
        style: IconButton.styleFrom(backgroundColor: NavColors.button, foregroundColor: Colors.white),
        iconSize: 28,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

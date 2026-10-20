import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/browse_panels.dart';
import 'package:roadto/ui/navigation_panels.dart';
import 'package:roadto/ui/report_sheet.dart';
import 'package:roadto_core/roadto_core.dart';

import 'shots.dart';

/// A trip along the Rhône: 250 m before turning right onto Pont de la
/// Guillotière, then left soon after.
GuidanceState tripState(TripRoute route) {
  final engine = GuidanceEngine(route);
  engine.update(route.shape.first);
  return engine.update(const LatLon(45.7562, 4.8384), speedMps: 13.9);
}

final route = TripRoute(
  shape: const [LatLon(45.7540, 4.8384), LatLon(45.7585, 4.8384), LatLon(45.7585, 4.8440), LatLon(45.7620, 4.8440)],
  maneuvers: const [
    Maneuver(
      type: 1,
      instruction: 'Partez vers le nord sur Quai du Docteur Gailleton.',
      streetNames: ['Quai du Docteur Gailleton'],
      beginShapeIndex: 0,
      lengthM: 500,
      timeS: 40,
    ),
    Maneuver(
      type: 10,
      instruction: 'Tournez à droite sur Pont de la Guillotière.',
      streetNames: ['Pont de la Guillotière'],
      beginShapeIndex: 1,
      lengthM: 440,
      timeS: 40,
    ),
    Maneuver(
      type: 15,
      instruction: 'Tournez à gauche sur Quai Claude Bernard.',
      streetNames: ['Quai Claude Bernard'],
      beginShapeIndex: 2,
      lengthM: 390,
      timeS: 40,
    ),
    Maneuver(type: 4, instruction: 'Vous êtes arrivé.', beginShapeIndex: 3, lengthM: 0, timeS: 0),
  ],
  lengthM: 6480,
  timeS: 600,
);

final accident = RoadAlert(
  id: 'a',
  author: 'p',
  type: AlertType.accident,
  geohash: 'u05kqt1',
  createdAt: DateTime(2026, 10, 20, 8, 2),
  expiresAt: DateTime(2026, 10, 20, 9),
);

/// The navigation screen as MapScreen lays it out.
Widget navigation(GuidanceState g, {bool over = false}) => onMap(
  'map-nav',
  SafeArea(
    bottom: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManeuverBanner(state: g, then: ManeuverBanner.thenOf(route, g)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: AlertAheadCard(
                  ahead: AlertAhead(accident, 820),
                  confirmations: (count: 3, latest: DateTime(2026, 10, 20, 8, 10)),
                  now: DateTime(2026, 10, 20, 8, 14),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SpeedLimitSign(kph: 50, over: over),
              const SizedBox(width: 10),
              SpeedReadout(kph: over ? 63 : 48, over: over),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NavigationSheet(
          state: g,
          now: DateTime(2026, 10, 20, 8, 14),
          voiceOn: true,
          onToggleVoice: () {},
          onReport: () {},
          onOptions: () {},
        ),
      ],
    ),
  ),
);

/// The map at rest: search, shortcuts, the report button.
Widget browse() => onMap(
  'map-browse',
  SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DestinationBar(onSearch: () {}, onSettings: () {}, routing: false, simulate: true),
          const SizedBox(height: 10),
          FavoriteShortcuts(
            favorites: const [
              Place(name: 'Maison', position: LatLon(45.75, 4.83)),
              Place(name: 'Travail', position: LatLon(45.76, 4.86)),
              Place(name: 'Salle de sport', position: LatLon(45.77, 4.85)),
            ],
            onGo: (_) {},
          ),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 76,
              height: 76,
              child: FloatingActionButton(
                onPressed: () {},
                backgroundColor: NavColors.report,
                foregroundColor: NavColors.onReport,
                shape: const CircleBorder(),
                child: const Icon(Icons.campaign, size: 38),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget report() => onMap(
  'map-nav',
  Align(
    alignment: Alignment.bottomCenter,
    child: Material(
      color: const Color(0xFF1C2026),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: ReportSheet(onConfirmed: (_) {}),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadFonts);
  final g = tripState(route);

  final tag = const String.fromEnvironment('SHOTS_TAG', defaultValue: 'after');
  for (final (name, width) in [('390', 390.0), ('320', 320.0)]) {
    testWidgets('navigation $name', (t) => shoot(t, '$tag-navigation-$name', navigation(g), size: Size(width, 760)));
  }
  testWidgets('over speed', (t) => shoot(t, '$tag-overspeed', navigation(g, over: true), size: const Size(390, 760)));
  testWidgets('browse', (t) => shoot(t, '$tag-browse', browse(), size: const Size(390, 760)));
  testWidgets('report', (t) => shoot(t, '$tag-report', report(), size: const Size(390, 760)));
}

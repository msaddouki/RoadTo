import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:roadto_core/roadto_core.dart';

import '../state/app_controller.dart';
import 'favorite_name_dialog.dart';
import 'map_layers.dart';
import 'report_sheet.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Écran principal : carte, guidage, signalement.
class MapScreen extends StatefulWidget {
  final AppController app;

  const MapScreen({super.key, required this.app});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapLibreMapController? _map;
  bool _styleReady = false;
  bool _follow = true;
  StreamSubscription<String>? _messages;
  Timer? _confirmTimeout;
  String? _lastRouteKey;

  AppController get app => widget.app;

  @override
  void initState() {
    super.initState();
    app.addListener(_onAppChanged);
    _messages = app.messages.listen((m) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
    });
  }

  @override
  void dispose() {
    app.removeListener(_onAppChanged);
    _messages?.cancel();
    _confirmTimeout?.cancel();
    super.dispose();
  }

  // --- Carte ------------------------------------------------------------

  Future<void> _onStyleLoaded() async {
    final map = _map;
    if (map == null) return;
    await map.addGeoJsonSource('route', routeGeoJson(null));
    await map.addGeoJsonSource('alerts', alertsGeoJson(const []));
    await map.addGeoJsonSource('destination', pointGeoJson(null));
    await map.addGeoJsonSource('position', pointGeoJson(null));
    await map.addLineLayer(
      'route',
      'route-casing',
      const LineLayerProperties(lineColor: '#0B3D91', lineWidth: 12, lineJoin: 'round', lineCap: 'round'),
    );
    await map.addLineLayer(
      'route',
      'route-line',
      const LineLayerProperties(
        lineColor: [
          'match',
          ['get', 'part'],
          'done',
          '#7A8699',
          '#3D8BFF',
        ],
        lineWidth: 8,
        lineJoin: 'round',
        lineCap: 'round',
      ),
    );
    await map.addCircleLayer(
      'destination',
      'destination',
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: '#FF5A5F',
        circleStrokeWidth: 3,
        circleStrokeColor: '#FFFFFF',
      ),
    );
    await map.addCircleLayer(
      'alerts',
      'alerts',
      const CircleLayerProperties(
        circleRadius: 11,
        circleColor: ['get', 'color'],
        circleStrokeWidth: 3,
        circleStrokeColor: '#111418',
      ),
    );
    await map.addCircleLayer(
      'position',
      'position-halo',
      const CircleLayerProperties(circleRadius: 18, circleColor: '#3D8BFF', circleOpacity: 0.25),
    );
    await map.addCircleLayer(
      'position',
      'position',
      const CircleLayerProperties(
        circleRadius: 9,
        circleColor: '#3D8BFF',
        circleStrokeWidth: 3,
        circleStrokeColor: '#FFFFFF',
      ),
    );
    _styleReady = true;
    _lastRouteKey = null;
    await _syncMap();
  }

  Future<void> _syncMap() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final g = app.guidance;
    final routeKey = '${identityHashCode(app.route)}:${((g?.projection.alongM ?? 0) / 25).floor()}';
    if (routeKey != _lastRouteKey) {
      _lastRouteKey = routeKey;
      await map.setGeoJsonSource('route', routeGeoJson(app.route, alongM: g?.projection.alongM ?? 0));
    }
    await map.setGeoJsonSource('alerts', alertsGeoJson(app.visibleAlerts));
    await map.setGeoJsonSource('destination', pointGeoJson(app.destination?.position));
    final pos = g?.offRoute ?? true ? app.position : g!.projection.point;
    await map.setGeoJsonSource('position', pointGeoJson(pos));
    if (_follow) {
      final nav = app.navigating;
      await map.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(pos.lat, pos.lon),
            zoom: nav ? 16.5 : 14,
            bearing: nav ? (app.fix?.bearingDeg ?? (g == null ? 0 : app.route!.bearingAt(g.projection.alongM))) : 0,
            tilt: nav ? 45 : 0,
          ),
        ),
        duration: const Duration(milliseconds: 900),
      );
    }
  }

  void _onAppChanged() {
    _syncMap();
    _watchConfirmation();
    if (mounted) setState(() {});
  }

  void _watchConfirmation() {
    if (app.pendingConfirmation == null) {
      _confirmTimeout?.cancel();
      _confirmTimeout = null;
    } else {
      // Sans réponse en 12 s, on n'envoie rien.
      _confirmTimeout ??= Timer(const Duration(seconds: 12), () => app.answerConfirmation(null));
    }
  }

  // --- Actions ----------------------------------------------------------

  Future<void> _openSearch() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          search: app.search,
          from: app.position,
          searchCategory: app.searchCategory,
          favorites: app.favorites,
        ),
      ),
    );
    if (place != null) {
      setState(() => _follow = true);
      await app.navigateTo(place);
    }
  }

  Future<void> _onLongPress(LatLng at) async {
    final point = LatLon(at.latitude, at.longitude);
    final favorite = app.favorites.find(point);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(favorite?.name ?? '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}'),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  icon: const Icon(Icons.directions),
                  label: const Text('Y aller'),
                  onPressed: () => Navigator.pop(c, 'go'),
                ),
              ),
              if (favorite == null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.star_border),
                    label: const Text('Ajouter aux favoris'),
                    onPressed: () => Navigator.pop(c, 'favorite'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'go') {
      setState(() => _follow = true);
      await app.navigateTo(favorite ?? Place(name: 'Point choisi', position: point));
    } else if (choice == 'favorite') {
      final name = await askFavoriteName(context);
      if (name == null) return;
      await app.favorites.add(Place(name: name, position: point));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('« $name » ajouté aux favoris')));
    }
  }

  Future<void> _openReport() async {
    // Position et cap figés au moment du geste.
    final at = app.position;
    final bearing = app.fix?.bearingDeg;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ReportSheet(onConfirmed: (type) => app.report(type, at, bearing)),
    );
  }

  // --- Interface --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final g = app.guidance;
    return Scaffold(
      body: Stack(
        children: [
          Listener(
            onPointerDown: (_) {
              if (_follow) setState(() => _follow = false);
            },
            child: MapLibreMap(
              key: ValueKey('${app.mapStyle}@${app.activeRegion?.version}'),
              styleString: app.mapStyle,
              initialCameraPosition: CameraPosition(target: LatLng(app.position.lat, app.position.lon), zoom: 13),
              compassEnabled: false,
              onMapCreated: (c) {
                _map = c;
                _styleReady = false;
              },
              onStyleLoadedCallback: _onStyleLoaded,
              onMapLongClick: (_, at) => _onLongPress(at),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (app.navigating && g != null)
                    _ManeuverBanner(state: g)
                  else
                    _SearchBar(
                      onSearch: _openSearch,
                      onSettings: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(app: app))),
                      routing: app.routing,
                      simulate: app.settings.simulate,
                    ),
                  if (app.ahead.isNotEmpty) ...[const SizedBox(height: 8), _AlertAheadChip(ahead: app.ahead.first)],
                  const Spacer(),
                  if (app.pendingConfirmation != null) ...[
                    _StillThereCard(alert: app.pendingConfirmation!, onAnswer: app.answerConfirmation),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!_follow)
                        FloatingActionButton.small(
                          heroTag: 'recenter',
                          tooltip: 'Recentrer',
                          onPressed: () {
                            setState(() => _follow = true);
                            _syncMap();
                          },
                          child: const Icon(Icons.my_location),
                        ),
                      const Spacer(),
                      SizedBox(
                        width: 84,
                        height: 84,
                        child: FloatingActionButton(
                          heroTag: 'report',
                          tooltip: 'Signaler',
                          backgroundColor: const Color(0xFFFF9F1C),
                          foregroundColor: Colors.black,
                          shape: const CircleBorder(),
                          onPressed: _openReport,
                          child: const Icon(Icons.campaign, size: 40),
                        ),
                      ),
                    ],
                  ),
                  if (app.navigating && g != null) ...[
                    const SizedBox(height: 12),
                    _TripBar(state: g, onStop: app.stopNavigation),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

class _ManeuverBanner extends StatelessWidget {
  final GuidanceState state;

  const _ManeuverBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final m = state.nextManeuver;
    return Material(
      color: const Color(0xFF0B3D91),
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(maneuverIcon(m), size: 56, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.offRoute ? 'Hors itinéraire' : formatDistance(state.distanceToNextM),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    m == null ? 'Continuez' : (m.streetNames.isNotEmpty ? m.streetNames.first : m.instruction),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, color: Colors.white),
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

class _SearchBar extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final bool routing;
  final bool simulate;

  const _SearchBar({required this.onSearch, required this.onSettings, required this.routing, required this.simulate});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      elevation: 3,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  children: [
                    routing
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        routing ? 'Calcul de l’itinéraire…' : 'Où allez-vous ?',
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                    if (simulate) const Chip(label: Text('Simulation'), visualDensity: VisualDensity.compact),
                  ],
                ),
              ),
            ),
          ),
          IconButton(tooltip: 'Réglages', onPressed: onSettings, icon: const Icon(Icons.settings)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _AlertAheadChip extends StatelessWidget {
  final AlertAhead ahead;

  const _AlertAheadChip({required this.ahead});

  @override
  Widget build(BuildContext context) {
    final t = ahead.alert.type;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: const Color(0xFF1B1F24),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(alertIcons[t], color: alertColors[t]),
              const SizedBox(width: 8),
              Text(
                '${t.label} dans ${formatDistance(ahead.distanceM)}',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StillThereCard extends StatelessWidget {
  final RoadAlert alert;
  final Future<void> Function(bool?) onAnswer;

  const _StillThereCard({required this.alert, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final t = alert.type;
    return Material(
      color: const Color(0xFF1B1F24),
      borderRadius: BorderRadius.circular(20),
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(alertIcons[t], color: alertColors[t], size: 32),
                const SizedBox(width: 12),
                Text('${t.label} : toujours là ?', style: const TextStyle(fontSize: 20, color: Colors.white)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: FilledButton(
                      onPressed: () => onAnswer(true),
                      child: const Text('Oui', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: FilledButton.tonal(
                      onPressed: () => onAnswer(false),
                      child: const Text('Non, parti', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TripBar extends StatelessWidget {
  final GuidanceState state;
  final VoidCallback onStop;

  const _TripBar({required this.state, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final eta = state.eta(DateTime.now());
    final hh = eta.hour.toString().padLeft(2, '0'), mm = eta.minute.toString().padLeft(2, '0');
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.arrived ? 'Arrivé' : '$hh:$mm',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${state.remaining.inMinutes} min · ${formatDistance(state.remainingM)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 56,
              child: FilledButton.tonalIcon(
                onPressed: onStop,
                icon: const Icon(Icons.close),
                label: const Text('Arrêter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

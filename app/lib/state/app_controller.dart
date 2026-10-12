import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:roadto_core/roadto_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../services/device_routing.dart';
import '../services/embedded_region.dart';
import '../services/identity_store.dart';
import '../services/location_source.dart';
import '../services/settings_store.dart';
import '../services/voice.dart';

/// État de l'app et orchestration : position, itinéraire, guidage, alertes.
/// Toute la logique métier vit dans roadto_core ; ce contrôleur ne fait que
/// brancher les services de la plateforme dessus.
class AppController extends ChangeNotifier {
  AppSettings settings;
  KeyPair identity;
  bool hasRecoveryPhrase = false;
  final IdentityStore _identityStore;
  final Voice _voice = Voice();
  final AlertStore alerts = AlertStore();
  late final RelayPool pool = RelayPool(settings.relays);

  /// Clé jetable du trajet en cours, qui signe les alertes et confirmations.
  KeyPair tripKeys = KeyPair.generate();
  final Set<String> _ownKeys = {};

  Fix? fix;
  LocationAvailability? locationStatus;

  Place? destination;
  TripRoute? route;
  GuidanceEngine? _guidance;
  GuidanceState? guidance;
  RouteSimulator? _sim;
  bool routing = false;
  List<AlertAhead> ahead = const [];

  /// Posted speed limits along [route], filled in shortly after it starts.
  SpeedLimits speedLimits = SpeedLimits.none;

  /// Alerte croisée à laquelle on demande « toujours là ? ».
  RoadAlert? pendingConfirmation;
  final _asked = <String>{};

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  StreamSubscription<Fix>? _deviceSub;
  StreamSubscription<SimulatedFix>? _simSub;
  StreamSubscription<NostrEvent>? _alertSub;
  Timer? _housekeeping;
  Set<String> _cells = const {};
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  bool _rerouting = false;

  // Offline regions.
  final RegionStore regionStore;
  List<InstalledRegion> regions = const [];
  InstalledRegion? activeRegion;
  OfflineGeocoder? _offlineGeocoder;
  String? installingRegion;
  InstallProgress? installProgress;
  String? regionError;

  AppController._(this.settings, this.identity, this._identityStore, this.regionStore);

  static Future<AppController> create() async {
    final store = IdentityStore();
    final settings = await SettingsStore.load();
    final identity = await store.loadOrCreate();
    final support = await getApplicationSupportDirectory();
    final regions = RegionStore(
      Directory('${support.path}/regions'),
      trustedKeys: Defaults.trustedRegionKeys,
      wantedKinds: {'map', 'places', 'style', if (DeviceRouting.supported) ...DeviceRouting.kinds},
    );
    return AppController._(settings, identity.keys, store, regions)..hasRecoveryPhrase = identity.hasRecoveryPhrase;
  }

  bool get navigating => route != null;

  /// On the device when the installed region carries a routing graph
  /// (Android), with the online server as fallback, e.g. for a destination
  /// outside the region.
  RouteEngine get _router {
    final online = ValhallaRouter(baseUrl: settings.routingUrl);
    final region = activeRegion;
    if (region == null || !region.hasOfflineRouting || !DeviceRouting.supported) return online;
    return FallbackRouter(
      NativeValhallaRouter(
        configPath: region.routingConfigPath,
        call: DeviceRouting.route,
        traceAttributes: DeviceRouting.traceAttributes,
      ),
      online,
      onFallback: (e) => debugPrint('Offline routing failed, using the server: ${e.message}'),
    );
  }

  bool get routesOffline => DeviceRouting.supported && (activeRegion?.hasOfflineRouting ?? false);
  Geocoder get _onlineGeocoder => PhotonGeocoder(baseUrl: settings.geocoderUrl);

  /// Style to display: the installed region's offline map when there is one.
  String get mapStyle {
    final r = activeRegion;
    return r != null && settings.offlineMap ? r.stylePath : settings.mapStyle;
  }

  bool get usingOfflineMap => activeRegion != null && settings.offlineMap;

  LatLon get position => fix?.position ?? Defaults.fallbackPosition;

  Map<String, RelayStatus> get relayStatuses => pool.statuses;

  List<RoadAlert> get visibleAlerts => alerts.visible();

  Future<void> start() async {
    await _reloadRegions();
    unawaited(_installEmbeddedRegions());
    _ownKeys
      ..add(identity.publicKey)
      ..add(tripKeys.publicKey);
    await _voice.init();
    _voice.enabled = settings.voice;
    _alertSub = pool.subscribe([alertFilter(const [])], id: 'alerts').listen(_onAlertEvent);
    unawaited(pool.connect());
    _housekeeping = Timer.periodic(const Duration(seconds: 15), (_) {
      alerts.purge();
      _refreshAhead();
      notifyListeners();
    });
    await _applyLocationMode();
  }

  @override
  void dispose() {
    _housekeeping?.cancel();
    _deviceSub?.cancel();
    _simSub?.cancel();
    _alertSub?.cancel();
    _sim?.dispose();
    _offlineGeocoder?.close();
    pool.close();
    _messages.close();
    super.dispose();
  }

  // --- Position ---------------------------------------------------------

  Future<void> _applyLocationMode() async {
    await _deviceSub?.cancel();
    _deviceSub = null;
    if (settings.simulate) {
      if (navigating) {
        _startSimulator(startM: guidance?.projection.alongM ?? 0);
      } else {
        _onFix(Fix(position));
      }
      return;
    }
    _stopSimulator();
    locationStatus = await DeviceLocation.ensurePermission();
    if (locationStatus != LocationAvailability.ok) {
      _say('Localisation indisponible : réglages > simulation, ou autorisez la localisation.', speak: false);
      notifyListeners();
      return;
    }
    _deviceSub = DeviceLocation.stream().listen(_onFix, onError: (_) {});
  }

  void _startSimulator({double startM = 0}) {
    final r = route;
    if (r == null) return;
    _stopSimulator();
    _sim = RouteSimulator(r, speedKmh: settings.simulationSpeedKmh, startM: startM);
    _simSub = _sim!.fixes.listen((f) => _onFix(Fix(f.position, bearingDeg: f.bearingDeg, speedMps: f.speedMps)));
    _sim!.start();
  }

  void _stopSimulator() {
    _simSub?.cancel();
    _simSub = null;
    _sim?.dispose();
    _sim = null;
  }

  void _onFix(Fix f) {
    fix = f;
    final engine = _guidance;
    if (engine != null) {
      final g = guidance = engine.update(f.position, speedMps: f.speedMps);
      if (g.announcement != null) _voice.say(g.announcement!);
      if (g.arrived) {
        _finishTrip();
      } else if (g.offRoute) {
        _reroute('Recalcul de l’itinéraire');
      }
    }
    _refreshAhead();
    _checkConfirmations();
    _updateSubscription();
    notifyListeners();
  }

  // --- Navigation -------------------------------------------------------

  /// Offline index first when a region is installed, online search otherwise
  /// or when the region has no match.
  Future<List<Place>> search(String query) async {
    final offline = _offlineGeocoder;
    if (offline != null) {
      final found = offline.searchSync(query, near: position);
      if (found.isNotEmpty) return found;
    }
    return _onlineGeocoder.search(query, near: position);
  }

  /// Places of [category] ahead on the route when navigating, around the
  /// position otherwise. Null when no offline region is installed.
  List<NearbyPlace>? searchCategory(PlaceCategory category) {
    final offline = _offlineGeocoder;
    if (offline == null) return null;
    final r = route, g = guidance;
    if (r != null && g != null) return offline.alongRoute(category, r, g.projection.alongM);
    return offline.nearby(category, position, radiusM: 10000);
  }

  List<LatLon> get _blockedPoints => [
    for (final a in alerts.visible())
      if (a.type.blocksRoad) a.position,
  ];

  Future<void> navigateTo(Place place) async {
    routing = true;
    destination = place;
    notifyListeners();
    try {
      final r = await _router.route(position, place.position, headingDeg: fix?.bearingDeg, avoid: _blockedPoints);
      // Une clé neuve à chaque trajet : les signalements de deux trajets ne
      // peuvent pas être reliés.
      tripKeys = KeyPair.generate();
      _ownKeys.add(tripKeys.publicKey);
      _setRoute(r);
      await WakelockPlus.enable().catchError((_) {});
    } on Exception catch (e) {
      destination = null;
      _say('Itinéraire impossible : $e', speak: false);
    } finally {
      routing = false;
      notifyListeners();
    }
  }

  void _setRoute(TripRoute r) {
    route = r;
    speedLimits = SpeedLimits.none;
    unawaited(_loadSpeedLimits(r));
    _guidance = GuidanceEngine(r);
    guidance = null;
    _cells = const {};
    if (settings.simulate) {
      _startSimulator();
    } else {
      _onFix(Fix(position, bearingDeg: fix?.bearingDeg, speedMps: fix?.speedMps ?? 0));
    }
  }

  Future<void> _reroute(String reason) async {
    final dest = destination;
    if (dest == null || _rerouting) return;
    if (DateTime.now().difference(_lastReroute) < const Duration(seconds: 15)) return;
    _rerouting = true;
    _lastReroute = DateTime.now();
    try {
      final r = await _router.route(position, dest.position, headingDeg: fix?.bearingDeg, avoid: _blockedPoints);
      if (route == null) return;
      _say(reason);
      _setRoute(r);
    } on Exception catch (e) {
      _say('Recalcul impossible : $e', speak: false);
    } finally {
      _rerouting = false;
    }
  }

  /// Posted limit where the car is, when known.
  SpeedLimitSpan? get speedLimit {
    final g = guidance;
    if (route == null || g == null || g.offRoute) return null;
    return speedLimits.at(g.projection.alongM);
  }

  bool get overSpeed {
    final limit = speedLimit?.kph, f = fix;
    return limit != null && f != null && isOverLimit(f.speedMps * 3.6, limit);
  }

  Future<void> _loadSpeedLimits(TripRoute r) async {
    if (_router case final SpeedLimitSource source) {
      try {
        final limits = await source.speedLimits(r);
        if (!identical(route, r)) return; // rerouted or stopped meanwhile
        speedLimits = limits;
        notifyListeners();
      } on RoutingException catch (e) {
        debugPrint('No speed limits for this route: ${e.message}');
      }
    }
  }

  void stopNavigation() {
    _stopSimulator();
    route = null;
    speedLimits = SpeedLimits.none;
    _guidance = null;
    guidance = null;
    destination = null;
    ahead = const [];
    _cells = const {};
    WakelockPlus.disable().catchError((_) {});
    _updateSubscription();
    notifyListeners();
  }

  void _finishTrip() {
    _stopSimulator();
    Future.delayed(const Duration(seconds: 4), () {
      if (guidance?.arrived ?? false) stopNavigation();
    });
  }

  // --- Alertes ----------------------------------------------------------

  void _onAlertEvent(NostrEvent e) {
    if (!alerts.ingest(e)) return;
    final alert = alerts[e.id];
    _refreshAhead();
    // Une route fermée ou un accident bloquant apparaît devant nous :
    // on cherche un autre chemin.
    if (alert != null && alert.type.blocksRoad && ahead.any((a) => a.alert.id == alert.id)) {
      _reroute('${alert.type.label} signalé sur votre route, recalcul');
    }
    notifyListeners();
  }

  void _refreshAhead() {
    final r = route, g = guidance;
    ahead = r == null || g == null ? const [] : alertsAhead(r, g.projection.alongM, alerts.visible());
  }

  void _checkConfirmations() {
    if (pendingConfirmation != null || !navigating) return;
    final candidates = alertsToConfirm(position, alerts.visible(), alreadyAsked: _asked, ownKeys: _ownKeys);
    if (candidates.isEmpty) return;
    pendingConfirmation = candidates.first;
    _asked.add(candidates.first.id);
    _voice.say('${candidates.first.type.label} toujours là ?');
  }

  /// Réponse à « toujours là ? ». null : pas de réponse, rien n'est publié.
  Future<void> answerConfirmation(bool? stillThere) async {
    final alert = pendingConfirmation;
    pendingConfirmation = null;
    notifyListeners();
    if (alert == null || stillThere == null) return;
    final event = buildConfirmationEvent(keys: tripKeys, alert: alert, stillThere: stillThere);
    alerts.ingest(event);
    final results = await pool.publish(event);
    if (!results.any((r) => r.accepted)) _say('Réponse non transmise (relais injoignables)', speak: false);
  }

  void _updateSubscription() {
    final around = geohashWithNeighbors(geohashEncode(position, precision: subscriptionGeohashPrecision));
    final r = route;
    final cells = r == null ? around : {...around, ...geohashesAlong(r.shape)};
    if (setEquals(cells, _cells)) return;
    // On garde les anciennes mailles tant qu'on y est encore, pour éviter
    // de se réabonner à chaque changement de maille hors itinéraire.
    if (r == null && _cells.containsAll(around) && _cells.length <= 9) return;
    _cells = cells;
    pool.subscribe([alertFilter(cells)], id: 'alerts');
  }

  /// Signalement, déjà confirmé par l'utilisateur (délai d'annulation passé).
  Future<void> report(AlertType type, LatLon at, double? bearing) async {
    final event = buildAlertEvent(keys: tripKeys, type: type, position: at, bearing: bearing);
    alerts.ingest(event);
    _refreshAhead();
    notifyListeners();
    final results = await pool.publish(event);
    final ok = results.where((r) => r.accepted).length;
    _say(
      ok > 0
          ? '${type.label} signalé, merci'
          : '${type.label} non transmis : ${results.map((r) => r.message).join(', ')}',
      speak: ok > 0,
    );
  }

  // --- Offline regions --------------------------------------------------

  Future<void> _reloadRegions() async {
    try {
      regions = await regionStore.installed();
    } catch (_) {
      regions = const [];
    }
    final here = position;
    final active = regions.where((r) => r.contains(here.lat, here.lon)).firstOrNull ?? regions.firstOrNull;
    if (active?.dir.path != activeRegion?.dir.path || active?.version != activeRegion?.version) {
      _offlineGeocoder?.close();
      _offlineGeocoder = null;
      if (active != null) {
        try {
          _offlineGeocoder = OfflineGeocoder.open(active.placesPath);
        } catch (_) {
          // Unknown index schema: search stays online until the region is updated.
        }
      }
    }
    activeRegion = active;
  }

  /// Installs the regions shipped in the app when missing, or when the app
  /// carries a newer package than the installed one.
  Future<void> _installEmbeddedRegions() async {
    for (final id in Defaults.embeddedRegions) {
      final source = AssetPackageSource(id);
      final embedded = await source.peekManifest();
      if (embedded == null) continue;
      final installed = regions.where((r) => r.id == id).firstOrNull;
      if (installed != null && !embedded.createdAt.isAfter(installed.manifest.createdAt)) continue;
      await _runInstall(id, source, done: 'Carte hors ligne ${embedded.regionName} prête');
    }
  }

  Future<void> installRegion(RegionSource source) =>
      _runInstall(source.id, HttpPackageSource(Uri.parse(source.manifestUrl)), done: 'Région ${source.name} installée');

  /// Lets the user pick a `.roadto` file (USB, AirDrop, Files…) and installs it.
  Future<void> importRegionFile() async {
    final picked = await FilePicker.pickFile(dialogTitle: 'Fichier de région (.roadto)');
    if (picked == null) return;
    var path = picked.path;
    if (path == null) {
      // Content URI (Android): copy it to a file the reader can seek in.
      final tmp = File('${(await getTemporaryDirectory()).path}/import.roadto');
      final sink = tmp.openWrite();
      await sink.addStream(picked.readAsByteStream());
      await sink.close();
      path = tmp.path;
    }
    await _runInstall(picked.name, BundlePackageSource(File(path)), done: 'Région importée');
  }

  Future<void> _runInstall(String label, PackageSource source, {required String done}) async {
    if (installingRegion != null) return;
    installingRegion = label;
    installProgress = null;
    regionError = null;
    notifyListeners();
    try {
      await for (final p in regionStore.install(source)) {
        installProgress = p;
        notifyListeners();
      }
      // The map and search reopen on the new files.
      _offlineGeocoder?.close();
      _offlineGeocoder = null;
      activeRegion = null;
      await _reloadRegions();
      _say(done, speak: false);
    } on RegionException catch (e) {
      regionError = e.message;
    } catch (e) {
      regionError = 'Échec de l’installation : $e';
    } finally {
      installingRegion = null;
      installProgress = null;
      notifyListeners();
    }
  }

  Future<void> removeRegion(String id) async {
    if (activeRegion?.id == id) {
      _offlineGeocoder?.close();
      _offlineGeocoder = null;
      activeRegion = null;
    }
    await regionStore.remove(id);
    await _reloadRegions();
    notifyListeners();
  }

  // --- Réglages ---------------------------------------------------------

  Future<void> updateSettings(AppSettings s) async {
    final modeChanged = s.simulate != settings.simulate;
    final speedChanged = s.simulationSpeedKmh != settings.simulationSpeedKmh;
    settings = s;
    await SettingsStore.save(s);
    _voice.enabled = s.voice;
    await pool.setRelays(s.relays);
    _cells = const {};
    _updateSubscription();
    unawaited(pool.connect());
    if (modeChanged) {
      await _applyLocationMode();
    } else if (speedChanged && _sim != null) {
      _sim!.speedKmh = s.simulationSpeedKmh;
    }
    notifyListeners();
  }

  Future<RecoveryPhrase?> recoveryPhrase() => _identityStore.recoveryPhrase();

  Future<void> regenerateIdentity() => _setIdentity(_identityStore.regenerate());

  Future<void> restoreIdentity(RecoveryPhrase phrase) => _setIdentity(_identityStore.restore(phrase));

  Future<void> _setIdentity(Future<Identity> next) async {
    final id = await next;
    identity = id.keys;
    hasRecoveryPhrase = id.hasRecoveryPhrase;
    _ownKeys.add(identity.publicKey);
    notifyListeners();
  }

  void _say(String text, {bool speak = true}) {
    if (!_messages.isClosed) _messages.add(text);
    if (speak) _voice.say(text);
  }
}

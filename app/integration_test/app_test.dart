// End-to-end check on an Android emulator or device, with the Lyon region
// embedded (`tool/embed_region.sh lyon --with-routing`). Run it with
// `tool/run_emulator_test.sh`, which also takes screenshots; CI runs it on
// every pull request (job "Android emulator").
//
// Fresh install, default settings (simulated position at Bellecour), no
// server needed: the embedded region installs, search and routing run on
// the device, and a simulated trip follows the route.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roadto/main.dart';
import 'package:roadto/services/device_routing.dart';
import 'package:roadto/services/location_source.dart';
import 'package:roadto/state/app_controller.dart';
import 'package:roadto/ui/map_screen.dart';
import 'package:roadto_core/roadto_core.dart';

const _bellecour = LatLon(45.7578, 4.8320);
const _villefranche = LatLon(45.9875, 4.7186);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Draw every frame the app asks for, so the screenshots show the real app.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // The native side of the app's own channels is registered in MainActivity;
  // a merge once dropped the location one and nothing noticed, since the
  // default settings simulate the position.
  testWidgets('Android channels are registered', (tester) async {
    final status = await AndroidLocation.methods.invokeMapMethod<String, Object?>('status');
    expect(status, containsPair('service', isA<bool>()));
    expect(status, containsPair('permission', isA<String>()));
  });

  testWidgets('Lyon offline: install, search, route on the device, navigate', (tester) async {
    final clock = Stopwatch()..start();
    final timings = <String, int>{};
    var last = 0;
    void step(String name) {
      final now = clock.elapsedMilliseconds;
      timings[name] = now - last;
      last = now;
      debugPrint('ROADTO_STEP $name: ${timings[name]} ms');
    }

    final app = await AppController.create();
    await tester.pumpWidget(RoadToApp(app: app));
    await app.start();
    expect(find.byType(MapScreen), findsOneWidget);
    step('start');

    // First launch: the embedded package installs with the usual checks
    // (signature, sizes, SHA-256).
    await _pumpUntil(
      tester,
      () => app.regionError != null || (app.installingRegion == null && app.regions.any((r) => r.id == 'lyon')),
      timeout: const Duration(minutes: 5),
      what: 'the embedded Lyon region to install',
    );
    expect(app.regionError, isNull);
    final region = app.activeRegion!;
    expect(region.id, 'lyon');
    expect(app.usingOfflineMap, isTrue, reason: 'the map should come from the installed region');
    expect(region.hasOfflineRouting, isTrue, reason: 'the build should embed routing.tar and routing.json');
    step('install_region');
    await _pumpFor(tester, const Duration(seconds: 5)); // let the offline map draw for the screenshot

    // Offline search, straight on the region's index.
    final geocoder = OfflineGeocoder.open(region.placesPath);
    addTearDown(geocoder.close);
    final bellecour = geocoder.searchSync('Place Bellecour', near: _bellecour);
    expect(bellecour, isNotEmpty);
    expect(distanceM(bellecour.first.position, _bellecour), lessThan(1000));
    step('search_offline');

    final partDieu = await app.search('Gare Part-Dieu');
    expect(partDieu, isNotEmpty);
    final destination = partDieu.first;
    expect(distanceM(destination.position, const LatLon(45.7605, 4.8597)), lessThan(1500));
    step('search_app');

    final fuel = driverCategories.firstWhere((c) => c.id == 'fuel');
    final stations = app.searchCategory(fuel)!;
    expect(stations, isNotEmpty);
    expect(stations.first.distanceM, lessThan(5000));
    step('search_category');

    // Valhalla on the device, on the region's graph.
    final native = NativeValhallaRouter(configPath: region.routingConfigPath, call: DeviceRouting.route);
    final city = await native.route(_bellecour, destination.position);
    expect(city.lengthM, inInclusiveRange(2000, 8000));
    expect(city.maneuvers, isNotEmpty);
    step('route_device_first');

    final longer = await native.route(_bellecour, _villefranche);
    expect(longer.lengthM, inInclusiveRange(25000, 60000));
    step('route_device_long');

    // With alternatives (to weigh reported jams): the engine's own JSON.
    final several = await native.routes(_bellecour, destination.position);
    expect(several, isNotEmpty);
    expect(several.first.lengthM, closeTo(city.lengthM, city.lengthM * 0.05));
    debugPrint('On-device alternatives: ${several.length} routes');
    step('route_device_alternatives');

    // Lights, side streets and lanes on the device: trace_attributes, and
    // trace_route in OSRM form (the lanes), on the region's graph.
    final osrm = jsonDecode(await DeviceRouting.traceRoute(region.routingConfigPath, jsonEncode(lanesRequest(city))));
    expect((osrm as Map)['matchings'], isNotEmpty);
    final details = await NativeValhallaRouter(
      configPath: region.routingConfigPath,
      call: DeviceRouting.route,
      traceAttributes: DeviceRouting.traceAttributes,
      traceRoute: DeviceRouting.traceRoute,
    ).roadDetails(city);
    debugPrint(
      'On-device details: ${details.signalsM.length} lights, ${details.sideRoads.length} junctions, '
      '${details.lanes.length} lane groups',
    );
    step('route_device_details');

    // A trip in the app: the controller routes on the device too, then the
    // simulator drives along the route.
    expect(app.settings.simulate, isTrue);
    expect(app.routesOffline, isTrue);
    await app.updateSettings(app.settings.copyWith(simulationSpeedKmh: 150));
    await app.navigateTo(destination);
    expect(app.route, isNotNull, reason: 'navigation should start');
    expect(app.route!.lengthM, closeTo(city.lengthM, city.lengthM * 0.3));
    step('navigate_route');

    await _pumpUntil(
      tester,
      () => (app.guidance?.projection.alongM ?? 0) > 500,
      timeout: const Duration(minutes: 2),
      what: 'the simulated trip to move along the route',
    );
    expect(app.guidance!.offRoute, isFalse);
    step('navigate_drive');

    // While navigating, categories are searched ahead on the route.
    final ahead = app.searchCategory(driverCategories.firstWhere((c) => c.id == 'parking'))!;
    expect(ahead, isNotEmpty);
    expect(ahead.every((p) => p.aheadM != null), isTrue);
    step('search_category_ahead');
    await _pumpFor(tester, const Duration(seconds: 5));

    app.stopNavigation();
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(app.route, isNull);

    binding.reportData = {
      'timings_ms': timings,
      'region': {'id': region.id, 'version': region.version},
      'routes_m': {'city': city.lengthM.round(), 'long': longer.lengthM.round()},
    };
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required Duration timeout,
  required String what,
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out after $timeout waiting for $what');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'services/crash_reports.dart';
import 'state/app_controller.dart';
import 'ui/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Errors are kept on the phone, scrubbed; nothing is sent (plan J7).
  final crashes = CrashReports(Directory('${(await getApplicationSupportDirectory()).path}/crashes'));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crashes.record(details.exception, details.stack, context: details.context?.toDescription());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crashes.record(error, stack);
    return false;
  };
  final app = await AppController.create(crashReports: crashes);
  runApp(RoadToApp(app: app));
  await app.start();
}

class RoadToApp extends StatelessWidget {
  final AppController app;

  const RoadToApp({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    // Thème nuit par défaut, comme la maquette : moins d'éblouissement au volant.
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3D8BFF), brightness: Brightness.dark);
    return MaterialApp(
      title: 'RoadTo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: MapScreen(app: app),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/crash_reports.dart';
import 'state/app_controller.dart';
import 'ui/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Atkinson Hyperlegible'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final app = await AppController.create();
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
      theme: ThemeData(colorScheme: scheme, useMaterial3: true, fontFamily: 'Atkinson Hyperlegible Next'),
      home: MapScreen(app: app),
    );
  }
}

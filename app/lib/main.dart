import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: MapScreen(app: app),
    );
  }
}

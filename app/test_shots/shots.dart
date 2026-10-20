// Screenshots of the app's own widgets, for design reviews: real fonts,
// real widgets, a map picture behind. Not part of `flutter test` (outside
// test/): run `flutter test test_shots/ui_shots_test.dart` with
// SHOTS_OUT=<dir> and SHOTS_MAPS=<dir with map-nav.png, map-browse.png>.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await family('Atkinson Hyperlegible Next', [
    'assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf',
    'assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf',
    'assets/fonts/AtkinsonHyperlegibleNext-ExtraBold.ttf',
  ]);
  await family('Atkinson Hyperlegible Mono', ['assets/fonts/AtkinsonHyperlegibleMono-Bold.ttf']);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/sdk/flutter';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes();
  final loader = FontLoader('MaterialIcons')..addFont(icons.then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

ImageProvider mapPicture(String name) =>
    MemoryImage(File('${Platform.environment['SHOTS_MAPS']}/$name.png').readAsBytesSync());

ThemeData appTheme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D8BFF), brightness: Brightness.dark),
  useMaterial3: true,
  fontFamily: 'Atkinson Hyperlegible Next',
);

/// Pumps [child] in a phone of [size] (logical pixels) and writes it as
/// `$SHOTS_OUT/name.png` at 2x.
Future<void> shoot(WidgetTester tester, String name, Widget child, {Size size = const Size(390, 844)}) async {
  // Tests draw shadows as solid outlines by default: real ones here.
  debugDisableShadows = false;
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: appTheme(), home: child),
    ),
  );
  // Let images decode (real time, outside the test's fake clock).
  for (final e in find.byType(Image).evaluate().toList()) {
    await tester.runAsync(() => precacheImage((e.widget as Image).image, e));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    return (await image.toByteData(format: ui.ImageByteFormat.png))!;
  });
  debugDisableShadows = true; // the test checks it is back before it ends
  final out = Directory(Platform.environment['SHOTS_OUT'] ?? 'build/shots')..createSync(recursive: true);
  File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  addTearDown(tester.view.reset);
}

/// A map picture filling the screen, [overlay] on top.
Widget onMap(String map, Widget overlay) => Scaffold(
  body: Stack(
    fit: StackFit.expand,
    children: [
      Image(image: mapPicture(map), fit: BoxFit.cover, alignment: Alignment.topCenter),
      overlay,
    ],
  ),
);

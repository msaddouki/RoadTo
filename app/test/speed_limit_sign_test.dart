import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/map_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget sign) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: sign)),
    ),
  );

  testWidgets('shows the limit, white inside', (tester) async {
    await pump(tester, const SpeedLimitSign(kph: 50, over: false));
    expect(find.text('50'), findsOneWidget);
    expect(find.bySemanticsLabel('Limitée à 50 km/h'), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container)).decoration as BoxDecoration;
    expect(box.color, Colors.white);
  });

  testWidgets('turns red and says so when over the limit', (tester) async {
    await pump(tester, const SpeedLimitSign(kph: 30, over: true));
    expect(find.bySemanticsLabel('Limitée à 30 km/h, vitesse dépassée'), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container)).decoration as BoxDecoration;
    expect(box.color, isNot(Colors.white));
  });
}

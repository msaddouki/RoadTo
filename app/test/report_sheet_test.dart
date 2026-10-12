import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/ui/report_sheet.dart';
import 'package:roadto_core/roadto_core.dart';

Future<void> _open(WidgetTester tester, void Function(AlertType) onConfirmed) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => ReportSheet(onConfirmed: onConfirmed),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('six types moins la police, envoi après 5 s', (tester) async {
    AlertType? sent;
    await _open(tester, (t) => sent = t);

    expect(find.text('Police'), findsNothing);
    for (final t in AlertType.reportable) {
      expect(find.text(t.label), findsOneWidget);
    }

    await tester.tap(find.text('Bouchon'));
    await tester.pump();
    expect(find.text('Bouchon : envoi dans 5 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(sent, isNull);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sent, AlertType.traffic);
    expect(find.byKey(const Key('countdown')), findsNothing);
  });

  testWidgets('annuler pendant le délai : rien n’est envoyé', (tester) async {
    AlertType? sent;
    await _open(tester, (t) => sent = t);
    await tester.tap(find.text('Accident'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(sent, isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/feedback.dart';
import 'package:roadto/ui/feedback_screen.dart';

void main() {
  const details = FeedbackDetails(
    appVersion: '0.1.0 (42)',
    platform: 'android 15',
    simulate: false,
    offlineMap: true,
    routesOffline: true,
    region: 'lyon 2026-10-01',
    relays: 2,
  );

  test('the text: kind, message, then what the tester chose to add', () {
    final t = feedbackText(
      kind: FeedbackKind.route,
      message: '  Demi-tour demandé sur le pont Lafayette.  ',
      details: details,
      crashReport: 'RoadTo error report\nStateError',
    );
    expect(
      t,
      startsWith('Retour RoadTo : Un itinéraire ou une instruction faux\n\nDemi-tour demandé sur le pont Lafayette.\n'),
    );
    expect(t, contains('Version : 0.1.0 (42)'));
    expect(t, contains('Région : lyon 2026-10-01'));
    expect(t, contains('-- Dernier rapport d’erreur --\nRoadTo error report'));
  });

  test('nothing technical unless asked', () {
    expect(feedbackText(kind: FeedbackKind.idea, message: 'Mode moto'), 'Retour RoadTo : Une idée\n\nMode moto');
  });

  testWidgets('sends only with a message, exactly the text shown', (tester) async {
    // Tall enough for the whole form, the preview open.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shared = <(String, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FeedbackScreen(
          details: Future.value(details),
          share: (text, subject) async => shared.add((text, subject)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final send = find.widgetWithText(FilledButton, 'Envoyer…');
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('feedback-message')), 'La carte reste blanche.');
    await tester.pump();
    await tester.tap(find.text('Voir exactement ce qui sera envoyé'));
    await tester.pumpAndSettle();
    final preview = tester.widget<SelectableText>(find.byKey(const Key('feedback-preview'))).data!;
    expect(preview, contains('La carte reste blanche.'));
    expect(preview, contains('Système : android 15'));

    await tester.tap(send);
    expect(shared.single.$1, preview);
    expect(shared.single.$2, 'Retour RoadTo : Un problème');
  });
}

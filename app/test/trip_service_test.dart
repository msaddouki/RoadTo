import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/trip_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> sent;
  setUp(() {
    sent = [];
    messenger.setMockMethodCallHandler(TripService.channel, (call) async {
      sent.add(call.method);
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(TripService.channel, null));

  test('the service runs with the trip only', () async {
    final navigating = ValueNotifier(false);
    TripService(navigating).start(android: true);
    navigating.value = true;
    navigating.value = true;
    navigating.value = false;
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['start', 'stop']);
  });

  test('a trip already running at start starts it', () async {
    TripService(ValueNotifier(true)).start(android: true);
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['start']);
  });

  test('nothing outside Android', () async {
    final navigating = ValueNotifier(false);
    TripService(navigating).start(android: false);
    navigating.value = true;
    await Future<void>.delayed(Duration.zero);
    expect(sent, isEmpty);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/location_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the Android channel like DeviceLocation.kt would.
  List<String> answer({required bool service, required String permission, String? request}) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AndroidLocation.methods, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'status' => {'service': service, 'permission': permission},
        'request' => request,
        _ => null,
      };
    });
    return calls;
  }

  tearDown(() => messenger.setMockMethodCallHandler(AndroidLocation.methods, null));

  group('Android permission', () {
    test('granted: no prompt', () async {
      final calls = answer(service: true, permission: 'granted');
      expect(await AndroidLocation.ensurePermission(), LocationAvailability.ok);
      expect(calls, ['status']);
    });

    test('location turned off comes first', () async {
      final calls = answer(service: false, permission: 'denied');
      expect(await AndroidLocation.ensurePermission(), LocationAvailability.serviceDisabled);
      expect(calls, ['status']);
    });

    test('asks when not granted', () async {
      final calls = answer(service: true, permission: 'denied', request: 'granted');
      expect(await AndroidLocation.ensurePermission(), LocationAvailability.ok);
      expect(calls, ['status', 'request']);
    });

    test('refusals', () async {
      answer(service: true, permission: 'denied', request: 'denied');
      expect(await AndroidLocation.ensurePermission(), LocationAvailability.denied);
      answer(service: true, permission: 'denied', request: 'deniedForever');
      expect(await AndroidLocation.ensurePermission(), LocationAvailability.deniedForever);
    });
  });

  group('Android fixes', () {
    test('moving: speed and bearing', () {
      final f = AndroidLocation.fixFromMap({
        'lat': 45.7578,
        'lon': 4.832,
        'speed': 13.9,
        'bearing': 92.5,
        'accuracy': 4.0,
        'provider': 'gps',
      });
      expect(f.position.lat, 45.7578);
      expect(f.position.lon, 4.832);
      expect(f.speedMps, 13.9);
      expect(f.bearingDeg, 92.5);
    });

    test('unknown speed and bearing, or standing still: no bearing', () {
      final unknown = AndroidLocation.fixFromMap({'lat': 45.0, 'lon': 4.0, 'speed': -1.0, 'bearing': -1.0});
      expect(unknown.speedMps, 0);
      expect(unknown.bearingDeg, isNull);
      final still = AndroidLocation.fixFromMap({'lat': 45.0, 'lon': 4.0, 'speed': 0.3, 'bearing': 180.0});
      expect(still.bearingDeg, isNull);
    });

    test('stream maps the platform events', () async {
      messenger.setMockStreamHandler(
        AndroidLocation.fixes,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            sink.success({'lat': 45.1, 'lon': 4.1, 'speed': 5.0, 'bearing': 10.0});
            sink.endOfStream();
          },
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(AndroidLocation.fixes, null));
      final fixes = await AndroidLocation.stream().toList();
      expect(fixes.single.position.lat, 45.1);
      expect(fixes.single.bearingDeg, 10.0);
    });
  });
}

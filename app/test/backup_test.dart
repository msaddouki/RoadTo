import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('backup'));
  tearDown(() {
    messenger.setMockMethodCallHandler(BackupExclusion.channel, null);
    tmp.deleteSync(recursive: true);
  });

  test('iOS: creates the directory and asks the platform to exclude it', () async {
    final calls = <Object?>[];
    messenger.setMockMethodCallHandler(BackupExclusion.channel, (call) async {
      calls.add([call.method, call.arguments]);
      return null;
    });
    final dir = Directory('${tmp.path}/regions');
    await BackupExclusion.exclude(dir, isIOS: true);
    expect(dir.existsSync(), isTrue);
    expect(calls, [
      [
        'excludeFromBackup',
        {'path': dir.path},
      ],
    ]);
  });

  test('a platform failure is not fatal', () async {
    messenger.setMockMethodCallHandler(BackupExclusion.channel, (call) async => throw Exception('io'));
    await BackupExclusion.exclude(Directory('${tmp.path}/regions'), isIOS: true);
  });

  test('Android: nothing to do at run time', () async {
    var called = false;
    messenger.setMockMethodCallHandler(BackupExclusion.channel, (call) async => called = true);
    await BackupExclusion.exclude(Directory('${tmp.path}/regions'), isIOS: false);
    expect(called, isFalse);
  });
}

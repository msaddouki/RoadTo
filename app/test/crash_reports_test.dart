import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/crash_reports.dart';
import 'package:roadto/ui/crash_reports_screen.dart';

/// Reports in memory: widget tests run in a fake clock that file I/O does
/// not follow.
class _MemoryReports extends CrashReports {
  final List<CrashReport> reports;

  _MemoryReports(this.reports) : super(Directory('unused'), platform: 'test');

  @override
  Future<List<CrashReport>> list() async => List.of(reports);

  @override
  Future<void> delete(CrashReport r) async => reports.remove(r);

  @override
  Future<void> clear() async => reports.clear();
}

CrashReport _report(String error, DateTime time) =>
    CrashReport(file: File('unused'), time: time, error: error, stack: '#0 main', platform: 'test');

void main() {
  group('scrub', () {
    test('removes coordinates but keeps line numbers and versions', () {
      expect(
        CrashReports.scrub('No route to 45.764043,4.835659 (dart 3.13.5, map.dart:12:5)'),
        'No route to [number],[number] (dart 3.13.5, map.dart:12:5)',
      );
      expect(CrashReports.scrub('at -12.34567 0.57'), 'at [number] 0.57');
    });

    test('removes keys, secrets and addresses', () {
      final hex = 'a' * 64;
      expect(CrashReports.scrub('bad key $hex'), 'bad key [hex]');
      expect(CrashReports.scrub('nsec1qqqsyqcyq5rqwzqfpg9scrgwpugpzysn'), '[secret]');
      expect(CrashReports.scrub('ncryptsec1qgg9947rlpvqu76pj5ecreduf9jx'), '[secret]');
      expect(CrashReports.scrub('Connection refused: 192.168.1.20:7777'), 'Connection refused: [address]:7777');
    });

    test('removes URL parameters but keeps the host and path', () {
      expect(
        CrashReports.scrub('GET https://photon.example/api?q=12%20rue%20Neuve&lat=45.7 failed'),
        'GET https://photon.example/api?q=[value]&lat=[value] failed',
      );
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('crashes'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('records scrubbed reports and lists them newest first', () async {
      final reports = CrashReports(dir, platform: 'android 14');
      await reports.record(
        StateError('first at 45.123456'),
        StackTrace.fromString('#0 a'),
        now: DateTime.utc(2026, 1, 1),
      );
      await reports.record('second', null, context: 'building Map', now: DateTime.utc(2026, 1, 2));

      final list = await reports.list();
      expect(list.map((r) => r.title), ['second', 'Bad state: first at [number]']);
      expect(list.first.context, 'building Map');
      expect(list.last.stack, '#0 a');
      expect(list.last.time, DateTime.utc(2026, 1, 1));
      expect(list.last.text, contains('Platform: android 14'));
    });

    test('keeps only the most recent reports', () async {
      final reports = CrashReports(dir, keep: 3, platform: 'test');
      for (var day = 1; day <= 5; day++) {
        await reports.record('error $day', null, now: DateTime.utc(2026, 1, day));
      }
      expect((await reports.list()).map((r) => r.error), ['error 5', 'error 4', 'error 3']);
    });

    test('deletes one report, or all of them', () async {
      final reports = CrashReports(dir, platform: 'test');
      await reports.record('one', null, now: DateTime.utc(2026, 1, 1));
      await reports.record('two', null, now: DateTime.utc(2026, 1, 2));
      await reports.delete((await reports.list()).first);
      expect((await reports.list()).map((r) => r.error), ['one']);
      await reports.clear();
      expect(await reports.list(), isEmpty);
    });

    test('skips unreadable files, and an empty store lists nothing', () async {
      expect(await CrashReports(Directory('${dir.path}/missing')).list(), isEmpty);
      File('${dir.path}/crash-1.json').writeAsStringSync('not json');
      final reports = CrashReports(dir, platform: 'test');
      await reports.record('ok', null);
      expect((await reports.list()).map((r) => r.error), ['ok']);
    });

    test('recording never throws, even when the folder cannot be written', () async {
      final blocker = File('${dir.path}/file')..writeAsStringSync('');
      await CrashReports(Directory('${blocker.path}/crashes')).record('boom', null);
    });

    test('long errors are cut', () async {
      final reports = CrashReports(dir, platform: 'test');
      await reports.record('x' * 10000, null);
      final error = (await reports.list()).single.error;
      expect(error.length, lessThan(4100));
      expect(error, endsWith('[… cut]'));
    });
  });

  group('screen', () {
    testWidgets('says when there is nothing', (tester) async {
      await tester.pumpWidget(MaterialApp(home: CrashReportsScreen(reports: _MemoryReports([]))));
      await tester.pumpAndSettle();
      expect(find.text('Aucune erreur enregistrée'), findsOneWidget);
      expect(find.byTooltip('Tout supprimer'), findsNothing);
    });

    testWidgets('opens a report, saves it, and deletes it', (tester) async {
      final reports = _MemoryReports([
        _report('Bad state: newest\nmore', DateTime.utc(2026, 1, 2)),
        _report('older', DateTime.utc(2026, 1, 1)),
      ]);
      CrashReport? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: CrashReportsScreen(reports: reports, save: (r) async => saved = r),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bad state: newest'), findsOneWidget);
      expect(find.text('older'), findsOneWidget);

      await tester.tap(find.text('Bad state: newest'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RoadTo error report'), findsOneWidget);
      await tester.tap(find.text('Enregistrer dans un fichier'));
      await tester.pump();
      expect(saved!.error, 'Bad state: newest\nmore');

      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Bad state: newest'), findsNothing);
      expect(find.text('older'), findsOneWidget);

      await tester.tap(find.byTooltip('Tout supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Aucune erreur enregistrée'), findsOneWidget);
    });
  });
}

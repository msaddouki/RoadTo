import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadto/services/identity_store.dart';
import 'package:roadto/ui/identity_screens.dart';
import 'package:roadto_core/roadto_core.dart';

class _MemoryStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _nip06Phrase = 'leader monkey parrot ring guide accident before fence cannon height naive bean';
const _nip06Public = '17162c921dc4d2518f9a101db33695df1afb56ab82f5ff3e5da6eec3ca5cd917';

void main() {
  group('identity store', () {
    test('a new install gets an identity with a recovery phrase', () async {
      final store = _MemoryStore();
      final id = await IdentityStore(store).loadOrCreate();
      expect(id.hasRecoveryPhrase, isTrue);
      final reloaded = await IdentityStore(store).loadOrCreate();
      expect(reloaded.keys.publicKey, id.keys.publicKey);
      expect((await IdentityStore(store).recoveryPhrase())!.keyPair().publicKey, id.keys.publicKey);
    });

    test('an identity created before phrases keeps working, flagged without phrase', () async {
      final legacy = KeyPair.generate();
      final store = _MemoryStore()..values['roadto.identity.sk'] = legacy.privateKey;
      final id = await IdentityStore(store).loadOrCreate();
      expect(id.keys.publicKey, legacy.publicKey);
      expect(id.hasRecoveryPhrase, isFalse);
    });

    test('restoring a phrase gives the NIP-06 key, and survives a restart', () async {
      final store = _MemoryStore();
      await IdentityStore(store).loadOrCreate();
      final restored = await IdentityStore(store).restore(RecoveryPhrase.parse(_nip06Phrase));
      expect(restored.keys.publicKey, _nip06Public);
      expect((await IdentityStore(store).loadOrCreate()).keys.publicKey, _nip06Public);
    });
  });

  group('encrypted backup (NIP-49)', () {
    test('export then restore on another phone gives the same key, without phrase', () async {
      final phone1 = _MemoryStore();
      final original = await IdentityStore(phone1, 4).restore(RecoveryPhrase.parse(_nip06Phrase));
      final backup = await IdentityStore(phone1, 4).exportEncrypted('correct horse battery');
      expect(backup, startsWith('ncryptsec1'));

      final phone2 = _MemoryStore();
      await IdentityStore(phone2, 4).loadOrCreate();
      final restored = await IdentityStore(phone2, 4).restoreEncrypted(backup, 'correct horse battery');
      expect(restored.keys.publicKey, original.keys.publicKey);
      expect(restored.hasRecoveryPhrase, isFalse);
      final reloaded = await IdentityStore(phone2, 4).loadOrCreate();
      expect(reloaded.keys.publicKey, _nip06Public);
      expect(reloaded.hasRecoveryPhrase, isFalse);
    });

    test('a wrong password leaves the identity untouched', () async {
      final store = _MemoryStore();
      final id = await IdentityStore(store, 4).loadOrCreate();
      final backup = await IdentityStore(store, 4).exportEncrypted('correct horse battery');
      await expectLater(
        IdentityStore(store, 4).restoreEncrypted(backup, 'wrong'),
        throwsA(isA<EncryptedKeyException>()),
      );
      expect((await IdentityStore(store, 4).loadOrCreate()).keys.publicKey, id.keys.publicKey);
    });
  });

  group('screens', () {
    testWidgets('the phrase is shown numbered', (tester) async {
      await tester.pumpWidget(MaterialApp(home: RecoveryPhraseScreen(phrase: RecoveryPhrase.parse(_nip06Phrase))));
      expect(find.text('1. leader'), findsOneWidget);
      expect(find.text('12. bean'), findsOneWidget);
    });

    testWidgets('restore explains a typo, then restores after confirmation', (tester) async {
      RecoveryPhrase? restored;
      await tester.pumpWidget(MaterialApp(home: RestoreIdentityScreen(onRestore: (p) async => restored = p)));
      await tester.enterText(find.byKey(const Key('phrase-input')), _nip06Phrase.replaceFirst('bean', 'beans'));
      await tester.tap(find.text('Restaurer'));
      await tester.pump();
      expect(find.text('Mot inconnu : beans'), findsOneWidget);
      expect(restored, isNull);

      await tester.enterText(find.byKey(const Key('phrase-input')), _nip06Phrase);
      await tester.tap(find.text('Restaurer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurer').last);
      await tester.pumpAndSettle();
      expect(restored!.keyPair().publicKey, _nip06Public);
    });

    testWidgets('export checks the password, then shows the backup', (tester) async {
      String? used;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportIdentityScreen(
            export: (pw) async {
              used = pw;
              return 'ncryptsec1test';
            },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('export-password')), 'court');
      await tester.enterText(find.byKey(const Key('export-confirm')), 'court');
      await tester.tap(find.text('Chiffrer'));
      await tester.pump();
      expect(find.text('Au moins 10 caractères'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('export-password')), 'un long mot de passe');
      await tester.enterText(find.byKey(const Key('export-confirm')), 'un long mot de passe!');
      await tester.tap(find.text('Chiffrer'));
      await tester.pump();
      expect(find.text('Les deux mots de passe diffèrent'), findsOneWidget);
      expect(used, isNull);

      await tester.enterText(find.byKey(const Key('export-confirm')), 'un long mot de passe');
      await tester.tap(find.text('Chiffrer'));
      await tester.pumpAndSettle();
      expect(used, 'un long mot de passe');
      expect(find.text('ncryptsec1test'), findsOneWidget);
    });

    testWidgets('restoring a backup shows a wrong password, then restores', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RestoreEncryptedScreen(
            open: () async => '  ncryptsec1fromfile\n',
            onRestore: (text, pw) async {
              expect(text, 'ncryptsec1fromfile');
              if (pw != 'bon mot de passe') throw const EncryptedKeyException('Mot de passe incorrect');
            },
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir un fichier'));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('restore-password')), 'mauvais');
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurer').last);
      await tester.pumpAndSettle();
      expect(find.text('Mot de passe incorrect'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('restore-password')), 'bon mot de passe');
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restaurer').last);
      await tester.pumpAndSettle();
      expect(find.byType(RestoreEncryptedScreen), findsNothing);
    });
  });
}

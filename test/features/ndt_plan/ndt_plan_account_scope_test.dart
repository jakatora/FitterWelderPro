import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_page.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/ndt_plan_export.dart';
import 'package:cut_list_app/services/owned_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  late AccountService account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((request) async {
      final id = (jsonDecode(request.body)['email'] as String).split('@').first;
      return http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'},
          }),
          200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
    addTearDown(() {
      AccountService.instance = previous;
      account.dispose();
      client.close();
    });

    final db = await AppDatabase.get();
    await db.delete('weld_repairs');
    await db.delete('weld_journal_history');
    await db.delete('weld_journal');
    for (final id in ['a', 'b']) {
      await account.signIn('$id@example.test', 'test-password');
      await WeldJournalDao().insert(
          weld('weld-$id',
              project: '${id.toUpperCase()}_PRIVATE', date: '2026-10-14'),
          by: 'TEST');
    }
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarty plan NDT przełącza spoiny na nowe konto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child:
          MaterialApp(home: NdtPlanPage(clock: () => DateTime(2026, 10, 14))),
    ));
    await _settle(tester);
    expect(find.text('A_PRIVATE'), findsWidgets);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_PRIVATE'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis reguł nie trafia do nowego konta', () async {
    const project = 'A_PRIVATE';
    final owner = await LocalRecordOwner.capture();
    final oldStore =
        NdtPlanStore(prefs: () => OwnedPrefs.instance(() async => owner));
    final rules = NdtRuleSet.fromPreset(NdtPreset.rt100);
    await oldStore.save(project, rules);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        oldStore.save(project, rules), throwsA(isA<AccountException>()));
    expect((await const NdtPlanStore().load(project)).saved, isFalse);
    await account.signIn('a@example.test', 'test-password');
    expect((await const NdtPlanStore().load(project)).set, rules);
  });

  testWidgets('otwarty edytor reguły ukrywa ją po zmianie konta',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child:
          MaterialApp(home: NdtPlanPage(clock: () => DateTime(2026, 10, 14))),
    ));
    await _settle(tester);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ndt-rule-add')), 300,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('ndt-list')),
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.byKey(const ValueKey('ndt-rule-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ndt-editor')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('ndt-editor')), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('PDF zlecenia nie jest udostępniany po zmianie konta', () async {
    final owner = await LocalRecordOwner.capture();
    final entered = Completer<void>();
    final release = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      return ByteData.sublistView(await File(key).readAsBytes());
    });
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    var shareCalls = 0;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shareCalls++;
      return 'share-complete';
    });
    addTearDown(() {
      messenger.setMockMessageHandler('flutter/assets', null);
      messenger.setMockMethodCallHandler(shareChannel, null);
    });

    final plan = computeNdtPlan(await WeldJournalDao().listAll(),
        rules: NdtRuleSet.fromPreset(NdtPreset.rt100).rules,
        project: 'A_PRIVATE');
    final report = NdtOrderReport(
        project: 'A_PRIVATE', plan: plan, generatedAt: DateTime(2026, 10, 14));
    final pending =
        NdtPlanExport.sharePdf(report, false, mayShare: () => owner.isCurrent);
    await entered.future.timeout(const Duration(seconds: 5));
    await account.signIn('b@example.test', 'test-password');
    release.complete();
    await pending;
    expect(shareCalls, 0);
  });
}

import 'dart:convert';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pre_weld_checklist_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/owned_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

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
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarta checklista nie przenosi odhaczeń na nowe konto',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: PreWeldChecklistScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('0/11'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('checklist-na-univ-test-coupon')));
    await tester.pumpAndSettle();
    expect(find.text('n/a: 1'), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('n/a: 1'), findsNothing);
    expect(find.text('0/11'), findsOneWidget);
    final bPrefs = await OwnedPrefs.instance();
    final today = DateTime.now();
    final key = 'preweld_na_${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    expect(bPrefs.getStringList(key), isNull);
    await tester
        .tap(find.byKey(const ValueKey('checklist-na-univ-tube-ends-clean')));
    await tester.pumpAndSettle();
    expect(bPrefs.getStringList(key), ['univ-tube-ends-clean']);

    await tester
        .runAsync(() => account.signIn('a@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('n/a: 1'), findsOneWidget);
    expect(
        (await OwnedPrefs.instance()).getStringList(key), ['univ-test-coupon']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty dialog zerowania nie pokazuje danych poprzedniego konta',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: PreWeldChecklistScreen()),
    ));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text('Fit-up gap ≈ 0, tubes aligned (no land mismatch)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New weld'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('The account changed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty wybór spoiny ukrywa dane po zmianie konta',
      (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('weld_repairs');
      await db.delete('weld_journal_history');
      await db.delete('weld_journal');
      await WeldJournalDao().insert(weld('a-weld', weldNo: 'A-001'));
    });
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(home: PreWeldChecklistScreen()),
    ));
    await tester.pumpAndSettle();
    final keys = tester
        .widgetList<TextButton>(find.byType(TextButton))
        .map((button) => button.key)
        .whereType<ValueKey<String>>()
        .where((key) => key.value.startsWith('checklist-na-'))
        .toList();
    expect(keys.length, 11);
    for (final key in keys) {
      await tester.tap(find.byKey(key));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checklist-save-to-weld')));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist-weld-pick')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist-weld-pick')), findsNothing);
    expect(find.textContaining('The account changed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

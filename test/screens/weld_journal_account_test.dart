import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/widgets/weld_journal/weld_editor_sheet.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 40; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty && i >= 5) {
      break;
    }
  }
  expect(find.byType(CircularProgressIndicator), findsNothing,
      reason: 'real journal I/O must complete before settling animations');
  await t.pumpAndSettle();
}

void main() {
  useTestDatabase();
  late AccountService account;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final previous = AccountService.instance;
    final client = MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
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
  });
  Future<void> mountJournal(WidgetTester t) async {
    await t.runAsync(() async {
      await account.load();
      final db = await AppDatabase.get();
      for (final table in [
        'weld_journal',
        'weld_journal_history',
        'weld_repairs',
        'weld_journal_projects'
      ]) {
        await db.delete(table);
      }
      await account.signIn('A', 'fixture-password');
      await WeldJournalDao().insert(
          weld('a', weldNo: 'A_ONLY_JOURNAL', project: 'A_ONLY_PROJECT'));
      await account.signIn('B', 'fixture-password');
      await WeldJournalDao().insert(
          weld('b', weldNo: 'B_ONLY_JOURNAL', project: 'B_ONLY_PROJECT'));
      await account.signIn('A', 'fixture-password');
    });
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: WeldJournalScreen())));
    await settle(t);
  }

  testWidgets(
      'journal rows and project filters disappear when the account changes and reload for the new owner',
      (t) async {
    await mountJournal(t);
    expect(find.textContaining('A_ONLY_JOURNAL'), findsWidgets);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.textContaining('A_ONLY_JOURNAL'), findsNothing);
    expect(find.textContaining('A_ONLY_PROJECT'), findsNothing);
    expect(find.textContaining('B_ONLY_JOURNAL'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'an open journal editor blocks normal account replacement and hides its old data on forced revocation',
      (t) async {
    await mountJournal(t);
    final editor = showWeldEditor(t.element(find.byType(WeldJournalScreen)),
        initial: weld('draft', weldNo: 'A_PRIVATE_DRAFT'),
        isNew: true,
        journal: [],
        journalProjects: [],
        stamp: 'SAME');
    await settle(t);
    expect(find.text('A_PRIVATE_DRAFT'), findsWidgets);
    final error = await t.runAsync(() async {
      try {
        await account.signIn('B', 'fixture-password');
        return null;
      } catch (e) {
        return e;
      }
    });
    expect(error, isA<AccountException>());
    expect(account.account!['id'], 'A');
    expect(find.text('A_PRIVATE_DRAFT'), findsWidgets);
    await t.runAsync(account.invalidateSession);
    await settle(t);
    expect(find.text('A_PRIVATE_DRAFT'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    expect(await editor, isNull);
    expect(find.textContaining('B_ONLY_JOURNAL'), findsWidgets);
    expect(find.textContaining('A_ONLY_JOURNAL'), findsNothing);
    expect(t.takeException(), isNull);
  });
}

import '../../support/weld_fixtures.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/features/interpass/interpass_page.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

void main() {
  late AccountService account;
  const store = InterpassStore();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
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
    await account.load();
  });
  Future<void> mount(WidgetTester t,
      {InterpassJournalSource? loadWelds}) async {
    await t.runAsync(() async {
      for (final id in ['A', 'B']) {
        await account.signIn(id, 'fixture-password');
        await store.upsert(
            InterpassWeld.blank(id: 'same-id', now: DateTime(2026, 10, 22))
                .copyWith(
                    weldNo: '${id}_PRIVATE', description: '${id}_DESCRIPTION'));
      }
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
        child: MaterialApp(
            home: InterpassPage(
                loadWelds: loadWelds ?? interpassDefaultJournalWelds))));
    await settle(t);
  }

  testWidgets(
      'mounted list reloads only the new account even with identical ids',
      (t) async {
    await mount(t);
    expect(find.text('A_PRIVATE'), findsWidgets);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('A_DESCRIPTION'), findsNothing);
    expect(find.text('B_PRIVATE'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'open editor hides old data, detaches fields and preserves both owners',
      (t) async {
    await mount(t);
    await t.tap(find.byKey(const Key('ip-open-0')));
    await settle(t);
    await t.enterText(find.byKey(const Key('ip-f-desc')), 'A_SAVED_EDIT');
    await settle(t);
    expect((await store.load()).welds.single.description, 'A_SAVED_EDIT');
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.byKey(const Key('ip-f-desc')), findsNothing);
    expect(find.text('A_SAVED_EDIT'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect((await store.load()).welds.single.description, 'B_DESCRIPTION');
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    expect(find.text('B_PRIVATE'), findsWidgets);
    await t.runAsync(() => account.signIn('A', 'fixture-password'));
    await settle(t);
    expect((await store.load()).welds.single.description, 'A_SAVED_EDIT');
    expect(t.takeException(), isNull);
  });
  testWidgets('delete modal cannot expose or delete the previous owners weld',
      (t) async {
    await mount(t);
    await t.tap(find.byKey(const Key('ip-del-0')));
    await settle(t);
    expect(find.byKey(const Key('ip-delete-confirm')), findsOneWidget);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.byKey(const Key('ip-delete-confirm')), findsNothing);
    expect(find.textContaining('A_PRIVATE'), findsNothing);
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    expect((await store.load()).welds.single.weldNo, 'B_PRIVATE');
    await t.runAsync(() => account.signIn('A', 'fixture-password'));
    await settle(t);
    expect((await store.load()).welds.single.weldNo, 'A_PRIVATE');
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'journal picker hides old account records and cannot populate the new editor',
      (t) async {
    await mount(t,
        loadWelds: () async => [weld('j', weldNo: 'A_JOURNAL_SECRET')]);
    await t.tap(find.byKey(const Key('ip-open-0')));
    await settle(t);
    await t.ensureVisible(find.byKey(const Key('ip-pick-journal')));
    await t.tap(find.byKey(const Key('ip-pick-journal')));
    await settle(t);
    expect(find.textContaining('A_JOURNAL_SECRET'), findsWidgets);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.textContaining('A_JOURNAL_SECRET'), findsNothing);
    expect(find.byKey(const Key('ip-f-desc')), findsNothing);
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    expect((await store.load()).welds.single.weldNo, 'B_PRIVATE');
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'a captured delete undo never restores an old weld into the next account',
      (t) async {
    await mount(t);
    await t.tap(find.byKey(const Key('ip-del-0')));
    await settle(t);
    await t.tap(find.byKey(const Key('ip-delete-confirm')));
    await settle(t);
    final undo = t.widget<SnackBarAction>(find.byType(SnackBarAction));
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.byType(SnackBarAction), findsNothing);
    undo.onPressed();
    await settle(t);
    expect((await store.load()).welds.single.weldNo, 'B_PRIVATE');
    await t.runAsync(() => account.signIn('A', 'fixture-password'));
    await settle(t);
    expect((await store.load()).welds, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'forced session revocation removes the old editor before another login',
      (t) async {
    await mount(t);
    await t.tap(find.byKey(const Key('ip-open-0')));
    await settle(t);
    expect(find.text('A_PRIVATE'), findsWidgets);
    await t.runAsync(account.invalidateSession);
    await settle(t);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.byKey(const Key('ip-f-desc')), findsNothing);
    expect((await store.load()).welds, isEmpty);
    await t.runAsync(() => account.signIn('B', 'fixture-password'));
    await settle(t);
    expect(find.byKey(const Key('ip-f-desc')), findsNothing);
    await t.tap(find.text('Zamknij').last);
    await settle(t);
    expect(find.text('B_PRIVATE'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}

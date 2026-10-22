import 'dart:convert';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/welder_pipes_screen.dart';
import 'package:cut_list_app/screens/account_screen.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/weld_param_owner_test.dart' show param;
import '../support/test_database.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();
  late AccountService account;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    account = AccountService.forTesting(MockClient((r) async {
      final id = jsonDecode(r.body)['email'];
      return http.Response(
          jsonEncode({
            'token': 'fixture-$id',
            'account': {'id': id}
          }),
          200);
    }));
    AccountService.instance = account;
    await (await AppDatabase.get()).delete('weld_params');
    await account.signIn('A', 'fixture-password');
    await WeldParamDao().insert(param('a'));
    await account.signIn('B', 'fixture-password');
    await WeldParamDao().insert(param('b'));
    await account.signIn('A', 'fixture-password');
  });

  testWidgets(
      'unverified offline session can explicitly return to its guest records',
      (tester) async {
    await tester.runAsync(() async {
      await account.forgetSession();
      await WeldParamDao().insert(param('guest'));
    });
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'fixture-unknown-token'});
    account = AccountService.forTesting(MockClient(
        (_) async => http.Response('{"error":{"message":"Offline"}}', 503)));
    AccountService.instance = account;
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: const MaterialApp(home: AccountScreen())));
    await settle(tester);
    expect(find.byKey(const Key('account-offline-guest')), findsOneWidget);
    await tester.runAsync(() async {
      await expectLater(WeldParamDao().listAll(), throwsA(isA<AccountException>()));
    });
    await tester.ensureVisible(find.byKey(const Key('account-offline-guest')));
    await settle(tester);
    expect(find.byKey(const Key('account-offline-guest')).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const Key('account-offline-guest')));
    await settle(tester);
    expect(
        (await tester.runAsync(() => WeldParamDao().listAll()))!
            .map((r) => r.id),
        ['guest']);
    expect(find.widgetWithText(FilledButton, 'Zaloguj się'), findsOneWidget);
    final raw = await tester.runAsync(() async => (await AppDatabase.get())
        .query('weld_params',
            where: 'owner_scope = ?', whereArgs: ['account:A']));
    expect(raw!.single['id'], 'a');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  for (final mode in ['edit', 'add', 'delete']) {
    testWidgets('session change hides old list and closes $mode dialog',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey, home: const WelderPipesScreen()),
      ));
      await settle(tester);
      await tester.tap(find.text('Moje parametry'));
      await settle(tester);
      expect(find.textContaining('private-a'), findsOneWidget);
      expect(find.textContaining('private-b'), findsNothing);
      if (mode == 'edit') {
        await tester.tap(find.textContaining('private-a'));
      } else if (mode == 'add') {
        await tester.tap(find.text('Dodaj'));
      } else {
        await tester.tap(find.byTooltip('Usuń'));
      }
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.runAsync(() => account.signIn('B', 'fixture-password'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('private-a'), findsNothing);
      expect(find.textContaining('private-b'), findsOneWidget);
      expect(
          (await tester.runAsync(() => WeldParamDao().listAll()))!
              .map((r) => r.id),
          ['b']);
      await tester.runAsync(() => account.signIn('A', 'fixture-password'));
      await settle(tester);
      expect(find.textContaining('private-a'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }
}

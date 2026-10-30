import 'dart:convert';

import 'package:cut_list_app/domain/spool_check/spool_check.dart';
import 'package:cut_list_app/features/spool_check/spool_check_page.dart';
import 'package:cut_list_app/features/spool_check/spool_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/owned_prefs.dart';
import 'package:cut_list_app/widgets/local_record_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 30, 9);

void main() {
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
    await const SpoolCheckStore().upsert(
        SpoolCheck.blank(id: 'a', now: _now).copyWith(spoolNo: 'A_PRIVATE'));
    await account.signIn('b@example.test', 'test-password');
    await const SpoolCheckStore().upsert(
        SpoolCheck.blank(id: 'b', now: _now).copyWith(spoolNo: 'B_RECORD'));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: SpoolCheckPage(now: () => _now)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> switchToB(WidgetTester tester) async {
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
  }

  testWidgets('otwarta historia spooli pokazuje bieżące konto', (tester) async {
    await open(tester);
    expect(find.text('A_PRIVATE'), findsWidgets);
    await switchToB(tester);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_RECORD'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog usuwania ukrywa tytuł A po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('sc-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sc-menu-del')));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsWidgets);
    await switchToB(tester);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
  });

  testWidgets('kalendarz edytora znika po zmianie konta', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('sc-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sc-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await switchToB(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
  });

  test('spóźniony zapis A nie trafia na konto B', () async {
    final session = LocalRecordSession.capture();
    final stale =
        SpoolCheckStore(prefs: () => OwnedPrefs.instance(session.captureOwner));
    await account.signIn('b@example.test', 'test-password');
    await expectLater(
        stale.upsert(SpoolCheck.blank(id: 'late', now: _now)
            .copyWith(spoolNo: 'A_LATE')),
        throwsA(isA<AccountException>()));
    expect((await const SpoolCheckStore().load()).map((c) => c.id), ['b']);
    await account.signIn('a@example.test', 'test-password');
    expect((await const SpoolCheckStore().load()).map((c) => c.id), ['a']);
  });
}

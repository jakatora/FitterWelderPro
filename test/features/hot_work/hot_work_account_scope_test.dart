import 'dart:convert';

import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/features/hot_work/hot_work_page.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
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
    await const HotWorkStore().upsert(HotWorkPermit.blank(id: 'a', now: _now)
        .copyWith(location: 'A_PRIVATE'));
    await account.signIn('b@example.test', 'test-password');
    await const HotWorkStore().upsert(
        HotWorkPermit.blank(id: 'b', now: _now).copyWith(location: 'B_RECORD'));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: HotWorkPage(now: () => _now)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> switchToB(WidgetTester tester) async {
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
  }

  testWidgets('otwarta historia pokazuje wyłącznie bieżące konto',
      (tester) async {
    await open(tester);
    expect(find.text('A_PRIVATE'), findsWidgets);
    await switchToB(tester);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_RECORD'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog usuwania ukrywa stary tytuł po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hw-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hw-menu-del')));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsWidgets);
    await switchToB(tester);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kalendarz edytora znika po zmianie konta', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hw-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hw-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await switchToB(tester);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wybór godziny znika po zmianie konta', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('hw-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hw-from')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await switchToB(tester);
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis A nie trafia na konto B', () async {
    final session = LocalRecordSession.capture();
    final stale =
        HotWorkStore(captureOwner: session.captureOwner).withClock(() => _now);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(
        stale.upsert(HotWorkPermit.blank(id: 'late', now: _now)
            .copyWith(location: 'A_LATE')),
        throwsA(isA<AccountException>()));
    expect((await const HotWorkStore().load()).map((p) => p.id), ['b']);
    await account.signIn('a@example.test', 'test-password');
    expect((await const HotWorkStore().load()).map((p) => p.id), ['a']);
  });
}

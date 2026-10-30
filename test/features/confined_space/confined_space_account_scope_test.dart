import 'dart:convert';

import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/features/confined_space/confined_space_page.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
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
    await const ConfinedSpaceStore().upsert(
        ConfinedSpaceRecord.blank(id: 'a', now: _now)
            .copyWith(location: 'A_PRIVATE'));
    await account.signIn('b@example.test', 'test-password');
    await const ConfinedSpaceStore().upsert(
        ConfinedSpaceRecord.blank(id: 'b', now: _now)
            .copyWith(location: 'B_RECORD'));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: ConfinedSpacePage(now: () => _now)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('otwarta historia przestrzeni pokazuje bieżące konto',
      (tester) async {
    await open(tester);
    expect(find.text('A_PRIVATE'), findsWidgets);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_RECORD'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog usuwania ukrywa stary tytuł po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cs-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cs-menu-del')));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsWidgets);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty kalendarz edytora znika po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cs-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cs-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarty wybór godziny znika po zmianie konta', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('cs-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cs-from')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis protokołu A nie trafia do konta B', () async {
    final session = LocalRecordSession.capture();
    final stale = ConfinedSpaceStore(captureOwner: session.captureOwner)
        .withClock(() => _now);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(
        stale.upsert(ConfinedSpaceRecord.blank(id: 'late', now: _now)
            .copyWith(location: 'A_LATE')),
        throwsA(isA<AccountException>()));
    expect((await const ConfinedSpaceStore().load()).records.map((r) => r.id),
        ['b']);
    await account.signIn('a@example.test', 'test-password');
    expect((await const ConfinedSpaceStore().load()).records.map((r) => r.id),
        ['a']);
  });
}

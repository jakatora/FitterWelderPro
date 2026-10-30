import 'dart:convert';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_page.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/widgets/local_record_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 30);

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
    await const FerritePmiStore().upsert(
        FerritePmiProtocol.blank(id: 'a', now: _now)
            .copyWith(title: 'A_PRIVATE'));
    await account.signIn('b@example.test', 'test-password');
    await const FerritePmiStore().upsert(
        FerritePmiProtocol.blank(id: 'b', now: _now)
            .copyWith(title: 'B_RECORD'));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: FerritePmiPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('otwarta historia pokazuje tylko bieżące konto', (tester) async {
    await open(tester);
    expect(find.text('A_PRIVATE'), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.text('B_RECORD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dialog usuwania nie ujawnia protokołu po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('fp-menu-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fp-menu-del')));
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
    await tester.tap(find.byKey(const ValueKey('fp-open-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fp-date')));
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

  testWidgets('otwarty wybór zakresu znika po zmianie konta', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('fp-open-0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('fp-preset-picker')));
    await tester.tap(find.byKey(const ValueKey('fp-preset-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fp-preset-custom')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fp-preset-custom')), findsNothing);
    expect(find.text('A_PRIVATE'), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis protokołu A nie trafia do konta B', () async {
    final session = LocalRecordSession.capture();
    final stale = FerritePmiStore(captureOwner: session.captureOwner);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(
        stale.upsert(FerritePmiProtocol.blank(id: 'late', now: _now)
            .copyWith(title: 'A_LATE')),
        throwsA(isA<AccountException>()));
    expect((await const FerritePmiStore().load()).map((p) => p.id), ['b']);
    await account.signIn('a@example.test', 'test-password');
    expect((await const FerritePmiStore().load()).map((p) => p.id), ['a']);
  });
}

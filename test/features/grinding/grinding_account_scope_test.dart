import 'dart:convert';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/features/grinding/grinding_page.dart';
import 'package:cut_list_app/features/grinding/grinding_store.dart';
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
    await const GrinderStore().save(const [
      GrinderProfile(
          id: 'a', name: 'Szlifierka A', maxRpm: 11000, diameterMm: 125),
    ]);
    await account.signIn('b@example.test', 'test-password');
    await const GrinderStore().save(const [
      GrinderProfile(
          id: 'b', name: 'Szlifierka B', maxRpm: 8500, diameterMm: 180),
    ]);
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: GrindingPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('zmiana konta resetuje otwarty kalkulator i listę kontrolną',
      (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('gr-grinder-rpm')),
            matching: find.byType(EditableText)),
        '11000');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gr-tab-list')));
    await tester.pumpAndSettle();
    final firstCheck = find.byType(CheckboxListTile).first;
    await tester.tap(firstCheck);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('gr-checklist-status')))
            .data,
        startsWith('Niekompletna: 1/'));

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsNothing);
    expect(find.byKey(const ValueKey('gr-grinder-b')), findsOneWidget);
    expect(
        tester
            .widget<EditableText>(find.descendant(
                of: find.byKey(const ValueKey('gr-grinder-rpm')),
                matching: find.byType(EditableText)))
            .controller
            .text,
        isEmpty);
    await tester.tap(find.byKey(const ValueKey('gr-tab-list')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('gr-checklist-status')))
            .data,
        startsWith('Niekompletna: 0/'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('otwarte okno nazwy nie pokazuje danych po zmianie konta',
      (tester) async {
    await open(tester);
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('gr-grinder-rpm')),
            matching: find.byType(EditableText)),
        '11000');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('gr-grinder-d')),
            matching: find.byType(EditableText)),
        '125');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('gr-save-grinder')));
    await tester.tap(find.byKey(const ValueKey('gr-save-grinder')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('gr-grinder-name')), 'Poufna nazwa A');
    expect(find.text('Poufna nazwa A'), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gr-grinder-name')), findsNothing);
    expect(find.textContaining('Konto zmieniło się'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis szlifierki A nie zmienia konta B', () async {
    final session = LocalRecordSession.capture();
    final stale = GrinderStore(
        openPrefs: () => OwnedPrefs.instance(session.captureOwner));
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        stale.upsert(const GrinderProfile(
            id: 'x', name: 'Spóźniona A', maxRpm: 11000, diameterMm: 125)),
        throwsA(isA<AccountException>()));
    expect(
        (await const GrinderStore().load()).grinders.map((g) => g.id), ['b']);
    await account.signIn('a@example.test', 'test-password');
    expect(
        (await const GrinderStore().load()).grinders.map((g) => g.id), ['a']);
  });
}

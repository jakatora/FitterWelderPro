import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/fume/fume_assessment.dart';
import 'package:cut_list_app/domain/fume/fume_checklist.dart';
import 'package:cut_list_app/domain/fume/fume_inputs.dart';
import 'package:cut_list_app/features/fume/fume_input_store.dart';
import 'package:cut_list_app/features/fume/fume_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

FumeInputs _inputs(double flow) => FumeInputs(
      lev: FumeLevStatus.present,
      flow: flow,
      diameter: 300,
      distance: 200,
    );

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
    await const FumeInputStore().save(_inputs(1200));
    await account.signIn('b@example.test', 'test-password');
    await const FumeInputStore().save(_inputs(800));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: FumePage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    final list = find.descendant(
        of: find.byKey(const ValueKey('fume-list')),
        matching: find.byType(Scrollable));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 300,
          scrollable: list.first, maxScrolls: 100);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('pomiary odciągu A ustępują pomiarom B po zmianie konta',
      (tester) async {
    await pumpPage(tester);
    await reveal(tester, 'fume-flow');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fume-flow')))
            .controller!
            .text,
        '1200');

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    await reveal(tester, 'fume-flow');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fume-flow')))
            .controller!
            .text,
        '800');
  });

  testWidgets('odhaczenie listy A nie przechodzi na konto B', (tester) async {
    await pumpPage(tester);
    await reveal(tester, 'fume-check-lev-close');
    await tester.tap(find.byKey(const ValueKey('fume-check-lev-close')));
    await tester.pumpAndSettle();
    await reveal(tester, 'fume-check-count');
    expect(
        find.textContaining(
            'Otwarte: ${kFumeChecks.length - 1} z ${kFumeChecks.length}'),
        findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    await reveal(tester, 'fume-check-count');
    expect(
        find.textContaining(
            'Otwarte: ${kFumeChecks.length} z ${kFumeChecks.length}'),
        findsOneWidget);
  });

  test('spóźniony zapis wejść A nie nadpisuje konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = FumeInputStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await stale.save(_inputs(1500));
    expect((await const FumeInputStore().load()).inputs.flow, 800);
    await account.signIn('a@example.test', 'test-password');
    expect((await const FumeInputStore().load()).inputs.flow, 1200);
  });
}

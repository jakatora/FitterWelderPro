import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'package:cut_list_app/features/pass_plan/pass_plan_page.dart';
import 'package:cut_list_app/features/pass_plan/pass_plan_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowFirstLoadStore extends PassPlanStore {
  final firstReadReady = Completer<void>();
  final release = Completer<void>();
  var _reads = 0;

  @override
  Future<({Map<String, String> form, bool lossy})?> load() async {
    final saved = await super.load();
    if (_reads++ == 0) {
      firstReadReady.complete();
      await release.future;
    }
    return saved;
  }
}

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
    await const PassPlanStore()
        .save({...passPlanDefaultForm(), PassPlanField.count: '2'});
    await account.signIn('b@example.test', 'test-password');
    await const PassPlanStore()
        .save({...passPlanDefaultForm(), PassPlanField.count: '5'});
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarty plan A przełącza dane i szkic na konto B',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: PassPlanPage()),
    ));
    await tester.pumpAndSettle();
    final count = find.byKey(const ValueKey('pp-count'));
    expect(tester.widget<TextField>(count).controller!.text, '2');
    await tester.enterText(count, '3');
    await tester.pumpAndSettle();

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(count).controller!.text, '5');
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis planu A nie zmienia planu B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = PassPlanStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        stale.save({...passPlanDefaultForm(), PassPlanField.count: '9'}),
        throwsA(isA<AccountException>()));
    expect(
        (await const PassPlanStore().load())!.form[PassPlanField.count], '5');
    await account.signIn('a@example.test', 'test-password');
    expect(
        (await const PassPlanStore().load())!.form[PassPlanField.count], '2');
  });

  testWidgets('opóźniony odczyt A nie nadpisuje widoku B', (tester) async {
    final store = _SlowFirstLoadStore();
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: PassPlanPage(store: store)),
    ));
    await tester.runAsync(() => store.firstReadReady.future);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    final count = find.byKey(const ValueKey('pp-count'));
    expect(tester.widget<TextField>(count).controller!.text, '5');

    store.release.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(count).controller!.text, '5');
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_inputs.dart';
import 'package:cut_list_app/features/rigging/rigging_page.dart';
import 'package:cut_list_app/features/rigging/rigging_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
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
    await const RiggingStore()
        .save(const RiggingSavedInputs(mode: HitchMode.straight));
    await account.signIn('b@example.test', 'test-password');
    await const RiggingStore()
        .save(const RiggingSavedInputs(mode: HitchMode.choke));
    await account.signIn('a@example.test', 'test-password');
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: RiggingPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ustawienia i kontrola podnoszenia A nie przechodzą na B',
      (tester) async {
    await pumpPage(tester);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('rig-mode-straight')))
            .selected,
        isTrue);
    await tester.enterText(find.byKey(const ValueKey('rig-mass')), '1600');
    await tester.tap(find.byKey(const ValueKey('rig-label-readable')));
    await tester.tap(find.byKey(const ValueKey('rig-check-tx-cuts-ok')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('rig-label-readable')))
            .selected,
        isTrue);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('rig-mode-choke')))
            .selected,
        isTrue);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('rig-mass')))
            .controller!
            .text,
        isEmpty);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('rig-label-readable')))
            .selected,
        isFalse);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('rig-check-tx-cuts-ok')))
            .selected,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis konfiguracji A nie nadpisuje konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = RiggingStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');

    await expectLater(
        stale.save(const RiggingSavedInputs(mode: HitchMode.straight)),
        throwsA(isA<AccountException>()));
    expect((await const RiggingStore().load()).inputs!.mode, HitchMode.choke);
    await account.signIn('a@example.test', 'test-password');
    expect(
        (await const RiggingStore().load()).inputs!.mode, HitchMode.straight);
  });
}

import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/bolting/bolt_kit.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_page.dart';
import 'package:cut_list_app/features/bolt_kit/bolt_kit_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _jointA = BoltKitJoint(
  id: 'account-a',
  dn: 150,
  cls: 300,
  facing: FlangeFacing.rf,
  material: BoltMaterial.b7,
  count: 4,
);
const _jointB = BoltKitJoint(
  id: 'account-b',
  dn: 80,
  cls: 600,
  facing: FlangeFacing.rtj,
  material: BoltMaterial.b7m,
  count: 2,
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
    await const BoltKitStore()
        .save(const BoltKitState(joints: [_jointA], sparePercent: 5));
    await account.signIn('b@example.test', 'test-password');
    await const BoltKitStore()
        .save(const BoltKitState(joints: [_jointB], sparePercent: 10));
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarta lista i pola A znikają po przełączeniu na B',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: BoltKitPage()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-mode-dims')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bk-f1')), '123');
    await tester.tap(find.byKey(const ValueKey('bk-tab-kit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-j-account-a')), findsOneWidget);

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-tab-kit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-j-account-a')), findsNothing);
    expect(find.byKey(const ValueKey('bk-j-account-b')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bk-tab-length')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-f1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis listy A nie nadpisuje B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = BoltKitStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(stale.save(const BoltKitState(joints: [_jointA])),
        throwsA(isA<AccountException>()));
    expect((await const BoltKitStore().load()).state.joints.single.id,
        'account-b');
    await account.signIn('a@example.test', 'test-password');
    expect((await const BoltKitStore().load()).state.joints.single.id,
        'account-a');
  });
}

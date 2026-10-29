import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/fitter/tube_bending.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_page.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

TubeBendingSaved _tube(double leg) => TubeBendingSaved(
      mode: TubeBendingMode.single,
      unit: TubeUnit.mm,
      clrMm: 38,
      singleAngleDeg: 90,
      singleLegAMm: leg,
      singleLegBMm: 150,
      segmentsMm: const [150, 200],
      anglesDeg: const [90],
      rotationsDeg: const [null],
    );

class _SlowFirstLoadStore extends TubeBendingStore {
  final firstReadReady = Completer<void>();
  final release = Completer<void>();
  var reads = 0;

  @override
  Future<TubeBendingLoad> load() async {
    final result = await super.load();
    if (reads++ == 0) {
      firstReadReady.complete();
      await release.future;
    }
    return result;
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
    await const TubeBendingStore().save(_tube(200));
    await account.signIn('b@example.test', 'test-password');
    await const TubeBendingStore().save(_tube(400));
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarta rurka i szkic A znikają po zmianie na B',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: TubeBendingPage()),
    ));
    await tester.pumpAndSettle();
    final leg = find.byKey(const ValueKey('tb-s-a'));
    final clr = find.byKey(const ValueKey('tb-clr'));
    expect(tester.widget<TextField>(leg).controller!.text, '200');
    await tester.enterText(leg, '250');
    await tester.enterText(clr, '50');
    await tester.pumpAndSettle();

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(leg).controller!.text, '400');
    expect(tester.widget<TextField>(clr).controller!.text, '38');
    expect(tester.takeException(), isNull);
  });

  test('spóźniony zapis rurki A nie zmienia konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = TubeBendingStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(stale.save(_tube(250)), throwsA(isA<AccountException>()));
    expect((await const TubeBendingStore().load()).state!.singleLegAMm, 400);
    await account.signIn('a@example.test', 'test-password');
    expect((await const TubeBendingStore().load()).state!.singleLegAMm, 200);
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
      child: MaterialApp(home: TubeBendingPage(store: store)),
    ));
    await tester.runAsync(() => store.firstReadReady.future);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    final leg = find.byKey(const ValueKey('tb-s-a'));
    expect(tester.widget<TextField>(leg).controller!.text, '400');

    store.release.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(leg).controller!.text, '400');
    expect(tester.takeException(), isNull);
  });
}

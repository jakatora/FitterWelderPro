import 'dart:async';
import 'dart:convert';

import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/welding/power_source.dart';
import 'package:cut_list_app/features/power_source/power_source_page.dart';
import 'package:cut_list_app/features/power_source/power_source_plate_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowPlateStore extends PowerSourcePlateStore {
  final firstReadReady = Completer<void>();
  final release = Completer<void>();
  var _reads = 0;

  @override
  Future<List<PlatePoint>> load() async {
    final saved = await super.load();
    if (_reads++ == 0) {
      firstReadReady.complete();
      await release.future;
    }
    return saved;
  }
}

class _DelayedFirstSaveStore extends PowerSourcePlateStore {
  final firstSaveStarted = Completer<void>();
  final release = Completer<void>();
  var _writes = 0;

  @override
  Future<void> save(List<PlatePoint> points) async {
    if (_writes++ == 0) {
      firstSaveStarted.complete();
      await release.future;
    }
    await super.save(points);
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
    await const PowerSourcePlateStore().save(const [PlatePoint(200, 35)]);
    await account.signIn('b@example.test', 'test-password');
    await const PowerSourcePlateStore().save(const [PlatePoint(300, 40)]);
    await account.signIn('a@example.test', 'test-password');
  });

  testWidgets('otwarta tabliczka i szkic A znikają po zmianie na B',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: PowerSourcePage()),
    ));
    await tester.pumpAndSettle();
    final plate = find.byKey(const ValueKey('ps-plate-i-1'));
    final lead = find.byKey(const ValueKey('ps-lead-weld'));
    expect(tester.widget<TextField>(plate).controller!.text, '200');
    await tester.enterText(plate, '250');
    await tester.enterText(lead, '40');
    await tester.pumpAndSettle();

    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).controller!.text, '300');
    expect(tester.widget<TextField>(lead).controller!.text, '25');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wpis przed odczytem zachowuje pozostałe zapisane punkty',
      (tester) async {
    await const PowerSourcePlateStore()
        .save(const [PlatePoint(200, 35), PlatePoint(160, 60)]);
    final store = _SlowPlateStore();
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: PowerSourcePage(plateStore: store)),
    ));
    await tester.runAsync(() => store.firstReadReady.future);
    await tester.enterText(find.byKey(const ValueKey('ps-plate-i-1')), '250');
    await tester.pumpAndSettle();
    expect(await const PowerSourcePlateStore().load(),
        const [PlatePoint(200, 35), PlatePoint(160, 60)]);

    store.release.complete();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ps-plate-i-1')))
            .controller!
            .text,
        '250');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ps-plate-i-3')))
            .controller!
            .text,
        isEmpty);
    expect(await const PowerSourcePlateStore().load(),
        const [PlatePoint(250, 35), PlatePoint(160, 60)]);
  });

  test('spóźniony zapis tabliczki A nie zmienia konta B', () async {
    final owner = await LocalRecordOwner.capture();
    final stale = PowerSourcePlateStore(captureOwner: () async => owner);
    await account.signIn('b@example.test', 'test-password');
    await expectLater(stale.save(const [PlatePoint(250, 35)]),
        throwsA(isA<AccountException>()));
    expect(await const PowerSourcePlateStore().load(),
        const [PlatePoint(300, 40)]);
    await account.signIn('a@example.test', 'test-password');
    expect(await const PowerSourcePlateStore().load(),
        const [PlatePoint(200, 35)]);
  });

  testWidgets('opóźniony odczyt A nie nadpisuje widoku B', (tester) async {
    final store = _SlowPlateStore();
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: PowerSourcePage(plateStore: store)),
    ));
    await tester.runAsync(() => store.firstReadReady.future);
    await tester
        .runAsync(() => account.signIn('b@example.test', 'test-password'));
    await tester.pumpAndSettle();
    final plate = find.byKey(const ValueKey('ps-plate-i-1'));
    expect(tester.widget<TextField>(plate).controller!.text, '300');

    store.release.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(plate).controller!.text, '300');
    expect(tester.takeException(), isNull);
  });

  testWidgets('nowsza edycja tabliczki wygrywa ze spóźnionym zapisem',
      (tester) async {
    final store = _DelayedFirstSaveStore();
    addTearDown(() {
      if (!store.release.isCompleted) store.release.complete();
    });
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: PowerSourcePage(plateStore: store)),
    ));
    await tester.pumpAndSettle();
    final plate = find.byKey(const ValueKey('ps-plate-i-1'));
    await tester.enterText(plate, '250');
    await tester.runAsync(() => store.firstSaveStarted.future);
    await tester.enterText(plate, '260');
    await tester.pumpAndSettle();
    store.release.complete();
    await tester.pumpAndSettle();
    expect((await const PowerSourcePlateStore().load()).first.currentA, 260);
  });
}

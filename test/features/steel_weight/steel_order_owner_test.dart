import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/database/local_record_owner.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/i18n/app_language.dart';

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

class ControlledPreferences extends InMemorySharedPreferencesStore {
  ControlledPreferences() : super.empty();
  bool reject = false;
  String? holdKey;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (holdKey != null && key.endsWith(holdKey!)) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    if (reject) return false;
    return super.setValue(valueType, key, value);
  }
}

class FailOnceStore extends SteelOrderStore {
  int loads = 0;
  @override
  Future<SteelOrder> load() async {
    if (++loads == 1) throw StateError('fixture read failure');
    return original;
  }
}

const original = SteelOrder(items: [
  SteelItem(shape: SteelShape.ipe, section: 'IPE 100', lengthMm: 1000, count: 2)
], pricePerKg: 4.5, wastePct: 10);
const changed = SteelOrder(items: [
  SteelItem(shape: SteelShape.heb, section: 'HEB 200', lengthMm: 3000, count: 3)
], pricePerKg: 8.25, wastePct: 5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AccountService account, previous;
  late ControlledPreferences disk;
  late http.Client client;
  setUp(() async {
    previous = AccountService.instance;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    disk = ControlledPreferences();
    SharedPreferencesStorePlatform.instance = disk;
    client = MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        final id =
            (jsonDecode(request.body)['email'] as String).split('@').first;
        return http.Response(
            jsonEncode({
              'token': 'fixture-$id',
              'account': {'id': id, 'role': 'user'}
            }),
            200);
      }
      return http.Response('{}', 200);
    });
    account = AccountService.forTesting(client);
    AccountService.instance = account;
  });
  tearDown(() {
    AccountService.instance = previous;
    account.dispose();
    client.close();
  });
  Future<void> login(String id) =>
      account.signIn('$id@example.invalid', 'fixture-password');
  Future<void> finish(WidgetTester t, Future<void> operation) async {
    var done = false;
    Object? failure;
    StackTrace? stack;
    operation.then((_) => done = true,
        onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
      done = true;
    });
    for (var i = 0; i < 30 && !done; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(done, true,
        reason: 'Account operation did not finish within bounded widget pumps');
    if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  }

  Future<void> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(1200, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: SteelWeightPage())));
    await settle(t);
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
  }

  Future<void> tap(WidgetTester t, String key) async {
    final finder = find.byKey(ValueKey(key));
    await t.ensureVisible(finder);
    await settle(t);
    await t.tap(finder);
    await settle(t);
  }

  test('legacy device list belongs only to guest; account lists never copy it',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = jsonEncode(original.toJson());
    await prefs.setString(SteelOrderStore.key, legacy);
    expect((await const SteelOrderStore().load()).pricePerKg, 4.5);
    await login('A');
    expect((await const SteelOrderStore().load()).items, isEmpty);
    await const SteelOrderStore().save(changed);
    await login('B');
    expect((await const SteelOrderStore().load()).items, isEmpty);
    await const SteelOrderStore().save(original);
    await login('A');
    expect((await const SteelOrderStore().load()).toJson(), changed.toJson());
    await account.forgetSession();
    expect((await const SteelOrderStore().load()).toJson(), original.toJson());
    expect(prefs.getString(SteelOrderStore.key), legacy);
  });
  test('captured owner cannot read or write after account change', () async {
    await login('A');
    final store = SteelOrderStore.forOwner(await LocalRecordOwner.capture());
    await store.save(original);
    await login('B');
    await expectLater(store.save(changed), throwsA(isA<AccountException>()));
    await expectLater(store.load(), throwsA(isA<AccountException>()));
    expect((await const SteelOrderStore().load()).items, isEmpty);
  });
  test('late A disk write stays under A and cannot overwrite B', () async {
    await login('A');
    final store = SteelOrderStore.forOwner(await LocalRecordOwner.capture());
    disk.holdKey = SteelOrderStore.keyForScope('account:A');
    final save = store.save(changed);
    final rejected = expectLater(save, throwsA(isA<AccountException>()));
    await disk.entered.future;
    await account.invalidateSession();
    await login('B');
    await const SteelOrderStore().save(original);
    disk.release.complete();
    await rejected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect((await const SteelOrderStore().load()).toJson(), original.toJson());
    await login('A');
    expect((await const SteelOrderStore().load()).toJson(), changed.toJson());
  });
  test('false preference result is a failed save, not success', () async {
    disk.reject = true;
    await expectLater(const SteelOrderStore().save(original), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect((await const SteelOrderStore().load()).items, isEmpty);
  });

  test(
      'stale bound screen cannot overwrite a newer list and readLatest does not rebase it',
      () async {
    final owner = await LocalRecordOwner.capture();
    final first = SteelOrderStore.forOwner(owner),
        second = SteelOrderStore.forOwner(owner);
    await first.load();
    await second.load();
    final tagged = original.copyWith(
        items: [original.items.single.copyWith(recordId: 'fixture-record')]);
    await first.save(tagged);
    await expectLater(second.save(changed), throwsA(isA<SteelOrderConflict>()));
    expect((await second.readLatest()).toJson(), tagged.toJson());
    await expectLater(second.save(changed), throwsA(isA<SteelOrderConflict>()));
    final refreshed = await second.load();
    await second.save(refreshed.copyWith(pricePerKg: 8.25));
    final persisted = await const SteelOrderStore().load();
    expect(persisted.items.single.recordId, 'fixture-record');
    expect(persisted.pricePerKg, 8.25);
  });
  test(
      'malformed quantities, prices and identities are never normalized into an overwrite',
      () async {
    final prefs = await SharedPreferences.getInstance();
    for (final invalid in [
      {...original.toJson(), 'priceKg': 'invalid'},
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'price': 'invalid'}
        ]
      },
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'mat': 'unknown'}
        ]
      },
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'pu': 'unknown'}
        ]
      },
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'n': 1.5}
        ]
      },
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'recordId': 12}
        ]
      },
      {
        ...original.toJson(),
        'items': [
          {...original.items.single.toJson(), 'recordId': 'duplicate'},
          {...original.items.single.toJson(), 'recordId': 'duplicate'}
        ]
      },
    ]) {
      final raw = jsonEncode(invalid);
      await prefs.setString(SteelOrderStore.key, raw);
      await expectLater(const SteelOrderStore().load(), throwsFormatException);
      await expectLater(
          const SteelOrderStore().save(changed), throwsFormatException);
      expect(prefs.getString(SteelOrderStore.key), raw);
    }
  });

  test(
      'invalid target data is rejected before overwriting valid saved prices and items',
      () async {
    await const SteelOrderStore().save(original);
    for (final target in [
      original.copyWith(items: [original.items.single.copyWith(count: 0)]),
      original.copyWith(pricePerKg: double.infinity),
      original.copyWith(pricePerKg: 1e300),
      original.copyWith(wastePct: 1e300),
      original.copyWith(
          items: [original.items.single.copyWith(lengthMm: double.infinity)]),
      original.copyWith(items: [
        original.items.single.copyWith(recordId: 'same'),
        original.items.single.copyWith(recordId: 'same')
      ]),
    ]) {
      await expectLater(
          const SteelOrderStore().save(target), throwsFormatException);
      expect(
          (await const SteelOrderStore().load()).toJson(), original.toJson());
    }
  });

  testWidgets('open page clears A list on B switch and restores A later',
      (t) async {
    await finish(t, login('A'));
    await const SteelOrderStore().save(original);
    await mount(t);
    expect(find.text('Lista (1)'), findsOneWidget);
    await finish(t, login('B'));
    await settle(t);
    expect(find.text('Lista (0)'), findsOneWidget);
    await tap(t, 'sw-tab-list');
    expect(find.byKey(const ValueKey('sw-empty')), findsOneWidget);
    await finish(t, login('A'));
    await settle(t);
    expect(find.text('Lista (1)'), findsOneWidget);
    expect((await const SteelOrderStore().load()).pricePerKg, 4.5);
  });
  testWidgets('pending autosave finishes for A before explicit B activation',
      (t) async {
    await finish(t, login('A'));
    await mount(t);
    final add = find.byKey(const ValueKey('sw-add'));
    await t.ensureVisible(add);
    await t.pump();
    await t.tap(add);
    await t.pump();
    // No400ms debounce elapses before the explicit account transition.
    await finish(t, login('B'));
    await settle(t);
    expect(account.account!['id'], 'B');
    expect(find.text('Lista (0)'), findsOneWidget);
    await finish(t, login('A'));
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
  });
  testWidgets(
      'failed save keeps A active, retry persists before switching to B',
      (t) async {
    await finish(t, login('A'));
    await mount(t);
    final add = find.byKey(const ValueKey('sw-add'));
    await t.ensureVisible(add);
    await t.pump();
    await t.tap(add);
    await t.pump();
    disk.reject = true;
    await finish(t, expectLater(login('B'), throwsA(isA<AccountException>())));
    await settle(t);
    expect(account.account!['id'], 'A');
    expect(find.text('Lista (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-retry-save')), findsOneWidget);
    disk.reject = false;
    await finish(t, login('B'));
    await settle(t);
    expect(find.text('Lista (0)'), findsOneWidget);
    await finish(t, login('A'));
    await settle(t);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
  });
  testWidgets('forced session revocation closes only the old steel edit dialog',
      (t) async {
    await finish(t, login('A'));
    await const SteelOrderStore().save(original);
    await mount(t);
    await tap(t, 'sw-tab-list');
    await tap(t, 'sw-item-0');
    expect(find.byKey(const ValueKey('sw-edit-save')), findsOneWidget);
    await finish(t, account.invalidateSession());
    await settle(t);
    expect(find.byKey(const ValueKey('sw-edit-save')), findsNothing);
    expect(find.text('Lista (0)'), findsOneWidget);
    await finish(t, login('A'));
    await settle(t);
    expect((await const SteelOrderStore().load()).toJson(), original.toJson());
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'unresolved signed-in owner never falls back to legacy guest data',
      (t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(SteelOrderStore.key, jsonEncode(original.toJson()));
    FlutterSecureStorage.setMockInitialValues(
        {'railway_account_session_v1': 'unknown-owner-fixture'});
    await mount(t);
    expect(find.text('Nie udało się wczytać listy dla bieżącego konta.'),
        findsOneWidget);
    expect(find.text('Lista (1)'), findsNothing);
    expect(find.byKey(const ValueKey('sw-add')), findsNothing);
    expect(prefs.getString(SteelOrderStore.key), jsonEncode(original.toJson()));
  });
  testWidgets(
      'failed load blocks empty overwrite and explicit retry recovers the list',
      (t) async {
    final store = FailOnceStore();
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: MaterialApp(home: SteelWeightPage(store: store))));
    await settle(t);
    expect(find.text('Nie udało się wczytać listy dla bieżącego konta.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('sw-add')), findsNothing);
    await t.tap(find.text('Spróbuj ponownie'));
    await settle(t);
    expect(find.text('Lista (1)'), findsOneWidget);
    expect(store.loads, 2);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
  testWidgets(
      'normal back waits for persistence; failed save keeps the page open',
      (t) async {
    t.view.physicalSize = const Size(1200, 2600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await finish(t, login('A'));
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const SteelWeightPage())),
                        child: const Text('Open steel')))))));
    await t.tap(find.text('Open steel'));
    await settle(t);
    final add = find.byKey(const ValueKey('sw-add'));
    await t.ensureVisible(add);
    await t.pump();
    await t.tap(add);
    await t.pump();
    disk.reject = true;
    final context = t.element(find.byType(SteelWeightPage));
    await Navigator.of(context).maybePop();
    await settle(t);
    expect(find.byType(SteelWeightPage), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-retry-save')), findsOneWidget);
    disk.reject = false;
    await Navigator.of(context).maybePop();
    await settle(t);
    expect(find.byType(SteelWeightPage), findsNothing);
    expect(find.text('Open steel'), findsOneWidget);
    expect((await const SteelOrderStore().load()).items, hasLength(1));
  });
}

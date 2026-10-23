// Zapisy zawodowe w SharedPreferences (protokoły, stawki, historia
// asystenta) należą do konta: gość zostaje przy starym kluczu, konto ma
// własny, inne konto ich nie widzi, a zapis po zmianie sesji jest odrzucany.

import 'dart:convert';

import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/domain/quotes/hourly_rate.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/services/owned_prefs.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_account.dart';

Future<void> signIn(String id) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance =
      AccountService.forTesting(MockClient((_) async => http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200)));
  await AccountService.instance.signIn('$id@example.test', 'test-password');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AssistantHistoryStore.instance.resetForTest();
    await seedGuestAccount();
  });

  test('gość: stary klucz; konto: własny; nic nie przecieka', () async {
    final guest = await OwnedPrefs.instance();
    await guest.setString('demo_v1', 'G');
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('demo_v1'), 'G', reason: 'dane sprzed kont zostają');

    await signIn('a');
    final a = await OwnedPrefs.instance();
    expect(a.getString('demo_v1'), isNull);
    await a.setString('demo_v1', 'A');
    expect(a.getKeys(), {'demo_v1'});
    expect(raw.getString('demo_v1'), 'G');

    await signIn('b');
    final b = await OwnedPrefs.instance();
    expect(b.getString('demo_v1'), isNull);
    expect(b.getKeys(), isEmpty);
    await b.remove('demo_v1');

    await seedGuestAccount();
    final g = await OwnedPrefs.instance();
    expect(g.getString('demo_v1'), 'G');
    expect(g.getKeys(), contains('demo_v1'));
    expect(g.getKeys().where((k) => k.contains('.owner.')), isEmpty);
    await signIn('a');
    expect((await OwnedPrefs.instance()).getString('demo_v1'), 'A',
        reason: 'B nie usunęło wpisu A');
  });

  test('zapis po zmianie sesji jest odrzucony, nie trafia do innego konta',
      () async {
    await signIn('a');
    final a = await OwnedPrefs.instance();
    await signIn('b');
    expect(() => a.setString('demo_v1', 'late-A'),
        throwsA(isA<AccountException>()));
    expect((await OwnedPrefs.instance()).getString('demo_v1'), isNull);
  });

  test('protokoły prac pożarowo niebezpiecznych: każde konto swoje', () async {
    const store = HotWorkStore();
    final now = DateTime(2026, 10, 23, 8);
    await signIn('a');
    await store.withClock(() => now).insertNew(
        HotWorkPermit.blank(id: 'hw-a', now: now).copyWith(location: 'Hala A'));
    await signIn('b');
    expect(await store.withClock(() => now).load(), isEmpty);
    await signIn('a');
    expect((await store.withClock(() => now).load()).single.location, 'Hala A');
  });

  test('stawka godzinowa: konto B nie widzi i nie nadpisuje stawki A',
      () async {
    const store = HourlyRateStore();
    await signIn('a');
    await store.save(const HourlyRateInput(netIncome: 12000));
    await signIn('b');
    expect((await store.load()).netIncome, const HourlyRateInput().netIncome);
    await store.save(const HourlyRateInput(netIncome: 7000));
    await signIn('a');
    expect((await store.load()).netIncome, 12000);
  });

  test('historia asystenta: wpis dostaje konto, inne konto go nie widzi '
      'i nie kasuje', () async {
    final history = AssistantHistoryStore.instance;
    AssistantHistoryEntry entry(String id) => AssistantHistoryEntry(
        id: id,
        kind: 'hot_work.prepare',
        summary: 'Hala $id',
        recordId: id,
        at: DateTime(2026, 10, 23),
        byVoice: true);
    await history.add(entry('g'));
    await signIn('a');
    await history.add(entry('a'));
    expect(history.entries.map((e) => e.id), ['a']);
    expect(history.entries.single.ownerScope, 'account:a');

    await signIn('b');
    expect(history.entries, isEmpty);
    await history.clear();

    await signIn('a');
    expect(history.entries.map((e) => e.id), ['a']);
    await seedGuestAccount();
    expect(history.entries.map((e) => e.id), ['g']);
  });
}

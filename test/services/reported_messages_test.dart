import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/blocked_users.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DelayedReportedDisk extends InMemorySharedPreferencesStore {
  _DelayedReportedDisk() : super.empty();
  final entered = Completer<void>(), release = Completer<void>();
  var writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${ReportedMessages.prefsKey}' && ++writes == 1) {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

class _FailedReportedRemoval extends InMemorySharedPreferencesStore {
  _FailedReportedRemoval(this.refuse) : super.empty();
  final bool refuse;
  @override
  Future<bool> remove(String key) async => !refuse;
}

class _FailedReportedWrite extends InMemorySharedPreferencesStore {
  _FailedReportedWrite(this.refuse) : super.empty();
  bool refuse;
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail) return !refuse;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final raw in ['{broken', '{"ids":[11]}', '[11,"bad"]']) {
    test('nieczytelny zapis oznaczeń nie jest nadpisywany: $raw', () async {
      SharedPreferences.setMockInitialValues({ReportedMessages.prefsKey: raw});
      final store = ReportedMessages.instance;
      store.resetForTest();
      await store.add(13);
      expect(store.isReported(13), isTrue);
      await store.add(14);
      expect(store.isReported(13), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(ReportedMessages.prefsKey), raw);
    });
  }

  test('czyszczenie uszkodzonej listy przywraca trwały zapis nowych oznaczeń',
      () async {
    SharedPreferences.setMockInitialValues(
        {ReportedMessages.prefsKey: '{broken'});
    final store = ReportedMessages.instance;
    store.resetForTest();
    await store.add(12);
    await store.clear();
    await store.add(13);
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.isReported(12), isFalse);
    expect(store.isReported(13), isTrue);
  });

  for (final refuse in [false, true]) {
    test(
        'nieutrwalone czyszczenie nie odblokowuje nadpisania (odmowa: $refuse)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final disk = _FailedReportedRemoval(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      await disk.setValue(
          'String', 'flutter.${ReportedMessages.prefsKey}', '[11]');
      final store = ReportedMessages.instance;
      store.resetForTest();
      await store.load();
      expect(await store.clear(), isFalse);
      await store.add(13);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(ReportedMessages.prefsKey), '[11]');
      expect(store.isReported(13), isTrue);
    });
  }

  for (final refuse in [false, true]) {
    test(
        'nieutrwalone oznaczenie daje false i można ponowić zapis (odmowa: $refuse)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final disk = _FailedReportedWrite(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      final store = ReportedMessages.instance;
      store.resetForTest();
      expect(await store.add(13), isFalse);
      expect(store.isReported(13), isTrue);
      disk.fail = false;
      expect(await store.add(13), isTrue);
      await (await SharedPreferences.getInstance()).reload();
      store.resetForTest();
      await store.load();
      expect(store.isReported(13), isTrue);
    });
  }

  test('opóźniony starszy zapis nie usuwa nowszego oznaczenia', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedReportedDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final store = ReportedMessages.instance;
    store.resetForTest();
    final older = store.add(12);
    await disk.entered.future;
    final newer = store.add(13);
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await Future.wait([older, newer]);
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.isReported(12), isTrue);
    expect(store.isReported(13), isTrue);
  });

  test('równoległe pierwsze zgłoszenia zachowują wszystkie oznaczenia',
      () async {
    SharedPreferences.setMockInitialValues({ReportedMessages.prefsKey: '[11]'});
    final store = ReportedMessages.instance;
    store.resetForTest();
    await Future.wait([store.add(12), store.add(13), store.add(14)]);
    store.resetForTest();
    await store.load();
    for (final id in [11, 12, 13, 14]) {
      expect(store.isReported(id), isTrue, reason: 'message $id');
    }
  });
  test('nowe zgłoszenie zachowuje wcześniej ukryte wiadomości bez jawnego load',
      () async {
    SharedPreferences.setMockInitialValues(
        {ReportedMessages.prefsKey: '[11,12]'});
    final store = ReportedMessages.instance;
    store.resetForTest();
    await store.add(13);
    store.resetForTest();
    await store.load();
    for (final id in [11, 12, 13]) {
      expect(store.isReported(id), isTrue, reason: 'message $id');
    }
  });
}

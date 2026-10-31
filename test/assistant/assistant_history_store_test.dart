import 'dart:async';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/test_account.dart';

AssistantHistoryEntry entry(String id) => AssistantHistoryEntry(
    id: id,
    kind: 'test',
    summary: id,
    recordId: id,
    at: DateTime.utc(2026, 10, 31),
    byVoice: false,
    ownerScope: 'guest');

class _DelayedHistoryDisk extends InMemorySharedPreferencesStore {
  _DelayedHistoryDisk({this.key = 'assistant_history_v1'}) : super.empty();
  final String key;
  final entered = Completer<void>(), release = Completer<void>();
  var writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${this.key}' && ++writes == 1) {
      entered.complete();
      await release.future;
    }
    return super.setValue(type, key, value);
  }
}

class _FailedHistoryDisk extends InMemorySharedPreferencesStore {
  _FailedHistoryDisk(this.refuse) : super.empty();
  final bool refuse;
  bool failWrites = true;
  bool failRemovals = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.assistant_history_v1' && failWrites) return !refuse;
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key == 'flutter.assistant_history_v1' && failRemovals) return !refuse;
    return super.remove(key);
  }
}

class _FailedSpeechPreferenceDisk extends InMemorySharedPreferencesStore {
  _FailedSpeechPreferenceDisk(this.refuse) : super.empty();
  final bool refuse;
  bool fail = true;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.assistant_speak_replies_v1' && fail) return !refuse;
    return super.setValue(type, key, value);
  }
}

void main() {
  useGuestAccount();
  test('usunięcie historii nie przegrywa z opóźnionym zapisem', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedHistoryDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    final adding = store.add(entry('one'));
    await disk.entered.future;
    final clearing = store.clear();
    await Future<void>.delayed(Duration.zero);
    disk.release.complete();
    await Future.wait([adding, clearing]);
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(store.entries, isEmpty);
  });

  test('oczekujące usunięcie historii nie przechodzi na nowe konto', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedHistoryDisk();
    SharedPreferencesStorePlatform.instance = disk;
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    final adding = store.add(entry('guest'));
    await disk.entered.future;
    final clearing = store.clear();
    final rejected = expectLater(clearing, throwsA(anything));
    await seedSignedInAccount();
    disk.release.complete();
    await adding;
    await rejected;
  });

  for (final raw in ['{broken', '{"history":[]}', '[{"bad":true}]']) {
    test('nowy wpis nie nadpisuje nieczytelnej historii: $raw', () async {
      SharedPreferences.setMockInitialValues({'assistant_history_v1': raw});
      final store = AssistantHistoryStore.instance;
      store.resetForTest();
      await store.add(entry('new'));
      expect(store.entries.map((e) => e.id), contains('new'));
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('assistant_history_v1'), raw);
    });
  }

  test('clear nie usuwa nieczytelnej historii o nieznanych właścicielach',
      () async {
    const raw = '[{"bad":true}]';
    SharedPreferences.setMockInitialValues({'assistant_history_v1': raw});
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    expect(await store.clear(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString('assistant_history_v1'), raw);
  });

  for (final refuse in [true, false]) {
    test('historia sygnalizuje nietrwały zapis i odzyskuje trwałość: $refuse',
        () async {
      SharedPreferences.setMockInitialValues({});
      final disk = _FailedHistoryDisk(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      final store = AssistantHistoryStore.instance;
      store.resetForTest();
      await store.add(entry('one'));
      expect(store.persistenceFailed, isTrue);
      expect(store.entries, hasLength(1));
      disk.failWrites = false;
      await store.add(entry('two'));
      expect(store.persistenceFailed, isFalse);
      expect(await store.clear(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString('assistant_history_v1'), isNotNull);
    });
  }

  for (final refuse in [false, true]) {
    test('preferencja głosu wykrywa brak trwałości i pozwala ponowić: $refuse',
        () async {
      SharedPreferences.setMockInitialValues({});
      final disk = _FailedSpeechPreferenceDisk(refuse);
      SharedPreferencesStorePlatform.instance = disk;
      final store = AssistantHistoryStore.instance;
      store.resetForTest();
      expect(await store.setSpeakReplies(true), isFalse);
      expect(store.speakReplies, isTrue);
      disk.fail = false;
      expect(await store.setSpeakReplies(true), isTrue);
      store.resetForTest();
      await store.load();
      expect(store.speakReplies, isTrue);
    });
  }

  test('wyłączenie czytania wygrywa z opóźnionym włączeniem', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _DelayedHistoryDisk(key: 'assistant_speak_replies_v1');
    SharedPreferencesStorePlatform.instance = disk;
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    final enabling = store.setSpeakReplies(true);
    await disk.entered.future;
    final disabling = store.setSpeakReplies(false);
    disk.release.complete();
    expect(await enabling, isTrue);
    expect(await disabling, isTrue);
    store.resetForTest();
    await store.load();
    expect(store.speakReplies, isFalse);
  });

  test('udane usunięcie historii wyłącza poprzedni błąd trwałości', () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _FailedHistoryDisk(true)..failRemovals = false;
    SharedPreferencesStorePlatform.instance = disk;
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    await store.add(entry('one'));
    expect(store.persistenceFailed, isTrue);
    expect(await store.clear(), isTrue);
    expect(store.persistenceFailed, isFalse);
  });

  test('równoległe pierwsze wpisy nie znikają podczas wczytywania historii',
      () async {
    SharedPreferences.setMockInitialValues({'assistant_history_v1': '[]'});
    final store = AssistantHistoryStore.instance;
    store.resetForTest();
    await Future.wait([
      store.add(entry('one')),
      store.add(entry('two')),
      store.add(entry('three'))
    ]);
    await (await SharedPreferences.getInstance()).reload();
    store.resetForTest();
    await store.load();
    expect(
        store.entries.map((e) => e.id), containsAll(['one', 'two', 'three']));
  });
}

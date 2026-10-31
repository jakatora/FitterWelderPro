// Zapis statystyk egzaminu spawacza: uszkodzony JSON nie ginie — kopia pod
// kluczem _corrupt przed nadpisaniem, tylko raz.

import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/exam/exam_session.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _UnpersistedDisk extends InMemorySharedPreferencesStore {
  _UnpersistedDisk() : super.empty();
  String? pretendKey;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (pretendKey == null || pretendKey == key) return true;
    return super.setValue(type, key, value);
  }
}

/// Magazyn, którego pierwszy odczyt rzuca (chwilowy błąd platformy).
class _FlakyStore extends WelderExamStore {
  _FlakyStore();

  var reads = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('kanał platformy niedostępny');
    return super.readRaw();
  }
}

ExamStats _someStats() {
  final q = drawExamQuestions(seed: 1, en: false).first;
  return const ExamStats().withAnswer(q, correct: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pozorny sukces zapisu statystyk jest wykrywany', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _UnpersistedDisk();
    await expectLater(
        const WelderExamStore().save(_someStats()), throwsStateError);
  });

  test('nieutrwalona kopia blokuje nadpisanie uszkodzonych statystyk',
      () async {
    SharedPreferences.setMockInitialValues({});
    final disk = _UnpersistedDisk()
      ..pretendKey = 'flutter.${WelderExamStore.corruptKey}';
    SharedPreferencesStorePlatform.instance = disk;
    const damaged = '{broken exam';
    await disk.setValue('String', 'flutter.${WelderExamStore.key}', damaged);
    await expectLater(
        const WelderExamStore().save(_someStats()), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.get(WelderExamStore.key), damaged);
    expect(prefs.get(WelderExamStore.corruptKey), isNull);
  });

  test('brak zapisu: puste statystyki bez flagi uszkodzenia', () async {
    SharedPreferences.setMockInitialValues({});
    final load = await const WelderExamStore().load();
    expect(load.damaged, isFalse);
    expect(load.stats.missed, isEmpty);
  });

  test('zapis i odczyt: nienaruszony zapis bez kopii', () async {
    SharedPreferences.setMockInitialValues({});
    const store = WelderExamStore();
    final stats = _someStats();
    await store.save(stats);
    await store.save(stats.withAnswer(
        drawExamQuestions(seed: 2, en: false).first,
        correct: true));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(WelderExamStore.corruptKey), isFalse);
    final load = await store.load();
    expect(load.damaged, isFalse);
    expect(load.stats.missed.keys, stats.missed.keys);
  });

  test('uszkodzony JSON: kopia przed nadpisaniem; zajęta kopia blokuje zapis',
      () async {
    SharedPreferences.setMockInitialValues(
        {WelderExamStore.key: '{"v":1,"categories":'});
    const store = WelderExamStore();
    final load = await store.load();
    expect(load.damaged, isTrue);
    expect(load.stats.categories, isEmpty);

    await store.save(_someStats());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.corruptKey), '{"v":1,"categories":');
    expect(
        decodeExamStats(prefs.getString(WelderExamStore.key)!).intact, isTrue);

    // Drugi uszkodzony zapis nie może zniknąć przy zajętym miejscu na kopię.
    await prefs.setString(WelderExamStore.key, 'znowu zepsute');
    await expectLater(store.save(_someStats()), throwsA(isA<StateError>()));
    expect(prefs.getString(WelderExamStore.corruptKey), '{"v":1,"categories":');
    expect(prefs.getString(WelderExamStore.key), 'znowu zepsute');
  });

  test('wartość innego typu pod kluczem → flaga i kopia', () async {
    SharedPreferences.setMockInitialValues({WelderExamStore.key: 42});
    const store = WelderExamStore();
    final load = await store.load();
    expect(load.damaged, isTrue);
    await store.save(_someStats());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.corruptKey), '42');
  });

  test('nieudany odczyt: pierwszy zapis kopiuje surową wartość', () async {
    final good = encodeExamStats(_someStats());
    SharedPreferences.setMockInitialValues({WelderExamStore.key: good});
    final store = _FlakyStore();
    final load = await store.load();
    expect(load.readFailed, isTrue);
    await store.save(const ExamStats(), afterFailedRead: true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.corruptKey), good);
  });
}

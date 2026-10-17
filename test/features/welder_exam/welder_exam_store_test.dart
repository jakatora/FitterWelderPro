// Zapis statystyk egzaminu spawacza: uszkodzony JSON nie ginie — kopia pod
// kluczem _corrupt przed nadpisaniem, tylko raz.

import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/exam/exam_session.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test(
      'uszkodzony JSON: pusty stan z flagą, kopia przed nadpisaniem — tylko '
      'raz', () async {
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

    // Drugi uszkodzony zapis nie nadpisuje pierwszej kopii.
    await prefs.setString(WelderExamStore.key, 'znowu zepsute');
    await store.save(_someStats());
    expect(prefs.getString(WelderExamStore.corruptKey), '{"v":1,"categories":');
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

// Sesja egzaminu spawacza: wynik, statystyki per kategoria, lista powtórek
// z błędnych odpowiedzi, zapis i odczyt JSON (także uszkodzonego).

import 'dart:math';

import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/exam/exam_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// Odpowiada na wszystkie pytania: dobrze, gdy [good] dla indeksu.
ExamSession _play(List<ExamQuestion> qs, bool Function(int i) good) {
  final s = ExamSession(questions: qs, mode: ExamMode.quick);
  for (var i = 0; i < qs.length; i++) {
    final q = s.current;
    final pick =
        good(i) ? q.correctIndex : (q.correctIndex + 1) % q.options.length;
    expect(s.answer(pick), good(i));
    s.next();
  }
  return s;
}

ExamStats _record(ExamStats stats, ExamSession s) {
  var out = stats;
  for (var i = 0; i < s.total; i++) {
    out = out.withAnswer(s.questions[i], correct: s.isCorrect(i));
  }
  return out;
}

void main() {
  final qs = drawExamQuestions(seed: 11, en: false);

  test('sesja: wynik, błędne odpowiedzi i wynik per kategoria', () {
    final s = _play(qs, (i) => i.isEven);
    expect(s.finished, isTrue);
    expect(s.total, 10);
    expect(s.score, 5);
    expect(s.wrong.map((q) => q.id), [
      for (var i = 0; i < qs.length; i++)
        if (i.isOdd) qs[i].id,
    ]);
    final byCat = s.byCategory;
    expect(byCat.values.fold<int>(0, (a, e) => a + e.total), 10);
    expect(byCat.values.fold<int>(0, (a, e) => a + e.correct), 5);
  });

  test(
      'sesja: druga odpowiedź na to samo pytanie jest ignorowana; dalej '
      'dopiero po odpowiedzi', () {
    final s = ExamSession(questions: qs, mode: ExamMode.quick);
    expect(s.next(), isFalse);
    expect(s.index, 0);
    final first = s.current;
    expect(s.answer(first.correctIndex), isTrue);
    expect(s.answer((first.correctIndex + 1) % first.options.length), isNull);
    expect(s.answerAt(0), first.correctIndex);
    expect(s.answer(99), isNull);
    expect(s.next(), isTrue);
    expect(s.index, 1);
    expect(s.finished, isFalse);
  });

  test(
      'statystyki: licznik kategorii i lista powtórek (źle → dopisane, '
      'dobrze → usunięte)', () {
    final s = _play(qs, (i) => i.isEven);
    final stats = _record(const ExamStats(), s);
    final answered =
        stats.categories.values.fold<int>(0, (a, c) => a + c.answered);
    final correct =
        stats.categories.values.fold<int>(0, (a, c) => a + c.correct);
    expect(answered, 10);
    expect(correct, 5);
    expect(stats.missed.keys.toSet(), {for (final q in s.wrong) q.id});
    expect(stats.missed.values.every((n) => n == 1), isTrue);

    // Drugi raz źle — licznik 2; potem dobrze — znika z listy.
    final q = s.wrong.first;
    final again = stats.withAnswer(q, correct: false);
    expect(again.missed[q.id], 2);
    expect(again.missed.keys.last, q.id);
    final fixed = again.withAnswer(q, correct: true);
    expect(fixed.missed.containsKey(q.id), isFalse);
    expect(fixed.statFor(q.category).answered,
        stats.statFor(q.category).answered + 2);
  });

  test('statystyki: limit listy powtórek i historii', () {
    final items = examItems(en: false);
    var stats = const ExamStats();
    for (var i = 0; i < kExamMissedMax + 5; i++) {
      stats = stats.withAnswer(examQuestionFrom(items[i], Random(i)),
          correct: false);
    }
    expect(stats.missed.length, kExamMissedMax);
    expect(stats.missed.containsKey(items[0].id), isFalse);
    expect(stats.missed.keys.last, items[kExamMissedMax + 4].id);
    for (var i = 0; i < kExamHistoryMax + 3; i++) {
      stats = stats.withSession(ExamSessionRecord(
          at: DateTime(2026, 10, 17, 8, i),
          mode: ExamMode.quick,
          score: i % 11,
          total: 10 + i));
    }
    expect(stats.history.length, kExamHistoryMax);
    expect(stats.last!.total, 10 + kExamHistoryMax + 2);
  });

  test('procent wyniku w dół: 199 / 200 → 99 %, 100 % tylko przy komplecie',
      () {
    expect(examPercent(199, 200), 99);
    expect(examPercent(200, 200), 100);
    expect(examPercent(2, 3), 66);
    expect(examPercent(0, 10), 0);
    expect(examPercent(0, 0), 0);
    expect(const ExamCategoryStat(answered: 200, correct: 199).percent, 99);
    expect(const ExamCategoryStat(answered: 3, correct: 2).percent, 66);
    expect(const ExamCategoryStat().percent, isNull);
  });

  test('powtórki z błędnych: sesja review losuje tylko pytania z listy', () {
    final s = _play(qs, (i) => i < 7);
    final stats = _record(const ExamStats(), s);
    expect(stats.missed.length, 3);
    final review =
        drawExamQuestions(seed: 2, en: false, onlyIds: stats.missed.keys);
    expect(review.map((q) => q.id).toSet(), stats.missed.keys.toSet());
    final r = ExamSession(questions: review, mode: ExamMode.review);
    expect(r.total, 3);
  });

  test('JSON: zapis i odczyt bez strat', () {
    final s = _play(qs, (i) => i.isEven);
    final stats = _record(const ExamStats(), s).withSession(ExamSessionRecord(
      at: DateTime.utc(2026, 10, 17, 9, 30),
      mode: ExamMode.category,
      category: ExamCategory.qualification,
      score: 7,
      total: 10,
    ));
    final d = decodeExamStats(encodeExamStats(stats));
    expect(d.intact, isTrue);
    expect(d.stats.missed, stats.missed);
    for (final c in ExamCategory.values) {
      expect(d.stats.statFor(c).answered, stats.statFor(c).answered);
      expect(d.stats.statFor(c).correct, stats.statFor(c).correct);
    }
    final r = d.stats.last!;
    expect(r.at, DateTime.utc(2026, 10, 17, 9, 30));
    expect(r.mode, ExamMode.category);
    expect(r.category, ExamCategory.qualification);
    expect(r.score, 7);
    expect(r.total, 10);
  });

  test(
      'JSON: uszkodzony, inna wersja albo złe wpisy → intact = false, '
      'reszta odczytana', () {
    for (final raw in ['{nie json', '[]', '{"v": 2}', '"tekst"', '']) {
      final d = decodeExamStats(raw);
      expect(d.intact, isFalse, reason: raw);
      expect(d.stats.missed, isEmpty);
    }
    const mixed = '{"v":1,'
        '"categories":{"processes":{"answered":4,"correct":3},'
        '"nieznana":{"answered":1,"correct":1},'
        '"positions":{"answered":1,"correct":5}},'
        '"missed":{"proc.name.p135":2,"x":-1,"":3},'
        '"history":[{"at":"2026-10-17T08:00:00.000","mode":"quick",'
        '"score":8,"total":10},{"at":"zła data","mode":"quick","score":1,'
        '"total":2},"śmieć"]}';
    final d = decodeExamStats(mixed);
    expect(d.intact, isFalse);
    expect(d.stats.statFor(ExamCategory.processes).answered, 4);
    expect(d.stats.statFor(ExamCategory.processes).correct, 3);
    expect(d.stats.categories.containsKey(ExamCategory.positions), isFalse);
    expect(d.stats.missed, {'proc.name.p135': 2});
    expect(d.stats.history.length, 1);
    expect(d.stats.last!.score, 8);
  });
}

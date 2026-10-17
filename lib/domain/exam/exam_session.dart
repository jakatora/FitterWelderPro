// Egzamin spawacza — sesja pytań, wynik i statystyki (zapis JSON).
// Czysty Dart: zapis w SharedPreferences robi warstwa ekranu
// (lib/features/welder_exam/welder_exam_store.dart).
//
// Statystyki:
//  • per kategoria: ile odpowiedzi, ile dobrych;
//  • „nie wychodzą mi”: pytania z błędną odpowiedzią — wypadają z listy
//    dopiero po dobrej odpowiedzi; lista ma limit (najstarsze odpadają);
//  • historia: ostatnie wyniki sesji.
// Odczyt JSON jest tolerancyjny: uszkodzone wpisy są pomijane, a wynik mówi,
// czy zapis był nienaruszony ([ExamStatsDecode.intact]) — ekran robi wtedy
// kopię surowej wartości przed nadpisaniem.

import 'dart:convert';

import 'exam_questions.dart';

/// Wersja formatu JSON (klucz w SharedPreferences też ma wersję).
const int kExamStatsVersion = 1;

/// Ile pytań „do powtórki” pamiętamy.
const int kExamMissedMax = 200;

/// Ile ostatnich wyników sesji pamiętamy.
const int kExamHistoryMax = 30;

/// Tryb sesji.
enum ExamMode {
  /// Szybka sesja — losowe kategorie.
  quick,

  /// Nauka jednej kategorii.
  category,

  /// Pytania, które nie wychodzą (z błędnych odpowiedzi).
  review;

  static ExamMode? parse(Object? raw) {
    for (final m in values) {
      if (m.name == raw) return m;
    }
    return null;
  }
}

/// Jedna sesja: pytania, odpowiedzi, bieżące pytanie.
class ExamSession {
  ExamSession({
    required List<ExamQuestion> questions,
    required this.mode,
    this.category,
  })  : questions = List.unmodifiable(questions),
        _answers = List<int?>.filled(questions.length, null);

  final List<ExamQuestion> questions;
  final ExamMode mode;
  final ExamCategory? category;
  final List<int?> _answers;
  int _index = 0;

  int get index => _index;
  int get total => questions.length;
  bool get isEmpty => questions.isEmpty;
  ExamQuestion get current => questions[_index];

  /// Wybrana odpowiedź pytania [i] (`null` — jeszcze bez odpowiedzi).
  int? answerAt(int i) => _answers[i];

  bool get currentAnswered => _answers[_index] != null;
  bool get isLast => _index >= questions.length - 1;

  /// Odpowiedź na bieżące pytanie. `true` / `false` — poprawna / błędna;
  /// `null` — pytanie ma już odpowiedź albo [option] spoza zakresu (bez
  /// zmiany).
  bool? answer(int option) {
    if (questions.isEmpty || _answers[_index] != null) return null;
    if (option < 0 || option >= current.options.length) return null;
    _answers[_index] = option;
    return option == current.correctIndex;
  }

  bool isCorrect(int i) => _answers[i] == questions[i].correctIndex;

  /// Następne pytanie (tylko po odpowiedzi na bieżące).
  bool next() {
    if (!currentAnswered || isLast) return false;
    _index++;
    return true;
  }

  bool get finished => _answers.every((a) => a != null);

  int get score => [
        for (var i = 0; i < questions.length; i++)
          if (isCorrect(i)) i,
      ].length;

  /// Pytania z błędną odpowiedzią (w kolejności sesji).
  List<ExamQuestion> get wrong => [
        for (var i = 0; i < questions.length; i++)
          if (_answers[i] != null && !isCorrect(i)) questions[i],
      ];

  /// Wynik per kategoria w tej sesji: (dobre, wszystkie).
  Map<ExamCategory, ({int correct, int total})> get byCategory {
    final out = <ExamCategory, ({int correct, int total})>{};
    for (var i = 0; i < questions.length; i++) {
      if (_answers[i] == null) continue;
      final c = questions[i].category;
      final prev = out[c] ?? (correct: 0, total: 0);
      out[c] = (
        correct: prev.correct + (isCorrect(i) ? 1 : 0),
        total: prev.total + 1,
      );
    }
    return out;
  }
}

/// Licznik odpowiedzi w kategorii.
class ExamCategoryStat {
  const ExamCategoryStat({this.answered = 0, this.correct = 0});

  final int answered;
  final int correct;

  /// Odsetek dobrych (0–100, w dół) albo `null`, gdy bez odpowiedzi.
  int? get percent => answered == 0 ? null : examPercent(correct, answered);
}

/// Odsetek dobrych odpowiedzi zaokrąglony W DÓŁ — 199 / 200 to 99 %, nie
/// 100 % (100 % tylko przy komplecie).
int examPercent(int correct, int total) =>
    total <= 0 ? 0 : (correct * 100) ~/ total;

/// Wynik zakończonej sesji.
class ExamSessionRecord {
  const ExamSessionRecord({
    required this.at,
    required this.mode,
    required this.score,
    required this.total,
    this.category,
  });

  final DateTime at;
  final ExamMode mode;
  final ExamCategory? category;
  final int score;
  final int total;
}

/// Statystyki zapisywane między uruchomieniami (niezmienne — zmiany dają
/// nowy obiekt).
class ExamStats {
  const ExamStats({
    this.categories = const {},
    this.missed = const {},
    this.history = const [],
  });

  final Map<ExamCategory, ExamCategoryStat> categories;

  /// Pytania do powtórki: id → ile razy z rzędu źle; kolejność = od
  /// najdawniej dopisanego.
  final Map<String, int> missed;

  /// Ostatnie wyniki sesji (najnowszy na końcu).
  final List<ExamSessionRecord> history;

  ExamCategoryStat statFor(ExamCategory c) =>
      categories[c] ?? const ExamCategoryStat();

  ExamSessionRecord? get last => history.isEmpty ? null : history.last;

  /// Po odpowiedzi: licznik kategorii; błędna — pytanie na listę powtórek
  /// (na koniec), dobra — z listy znika.
  ExamStats withAnswer(ExamQuestion q, {required bool correct}) {
    final cats = {...categories};
    final prev = statFor(q.category);
    cats[q.category] = ExamCategoryStat(
      answered: prev.answered + 1,
      correct: prev.correct + (correct ? 1 : 0),
    );
    final miss = {...missed};
    final before = miss.remove(q.id);
    if (!correct) {
      miss[q.id] = (before ?? 0) + 1;
      while (miss.length > kExamMissedMax) {
        miss.remove(miss.keys.first);
      }
    }
    return ExamStats(categories: cats, missed: miss, history: history);
  }

  ExamStats withSession(ExamSessionRecord record) {
    final list = [...history, record];
    final trimmed = list.length > kExamHistoryMax
        ? list.sublist(list.length - kExamHistoryMax)
        : list;
    return ExamStats(categories: categories, missed: missed, history: trimmed);
  }
}

String encodeExamStats(ExamStats s) => jsonEncode({
      'v': kExamStatsVersion,
      'categories': {
        for (final e in s.categories.entries)
          e.key.name: {
            'answered': e.value.answered,
            'correct': e.value.correct
          },
      },
      'missed': s.missed,
      'history': [
        for (final r in s.history)
          {
            'at': r.at.toIso8601String(),
            'mode': r.mode.name,
            if (r.category != null) 'category': r.category!.name,
            'score': r.score,
            'total': r.total,
          },
      ],
    });

/// Wynik odczytu: statystyki (to, co dało się odczytać) i czy zapis był
/// nienaruszony.
class ExamStatsDecode {
  const ExamStatsDecode(this.stats, {required this.intact});

  final ExamStats stats;
  final bool intact;
}

/// Odczyt JSON — nigdy nie rzuca. Nieczytelny JSON, inna wersja, zły typ
/// pola albo wpis nie do odczytania → [ExamStatsDecode.intact] = false
/// (pomijamy tylko to, czego nie da się odczytać).
ExamStatsDecode decodeExamStats(String raw) {
  Object? root;
  try {
    root = jsonDecode(raw);
  } catch (_) {
    return const ExamStatsDecode(ExamStats(), intact: false);
  }
  if (root is! Map || root['v'] != kExamStatsVersion) {
    return const ExamStatsDecode(ExamStats(), intact: false);
  }
  var intact = true;

  int? count(Object? v) => v is int && v >= 0 ? v : null;

  final categories = <ExamCategory, ExamCategoryStat>{};
  final rawCats = root['categories'];
  if (rawCats is Map) {
    for (final e in rawCats.entries) {
      final c = ExamCategory.parse(e.key);
      final v = e.value;
      final answered = v is Map ? count(v['answered']) : null;
      final correct = v is Map ? count(v['correct']) : null;
      if (c == null ||
          answered == null ||
          correct == null ||
          correct > answered) {
        intact = false;
        continue;
      }
      categories[c] = ExamCategoryStat(answered: answered, correct: correct);
    }
  } else if (rawCats != null) {
    intact = false;
  }

  final missed = <String, int>{};
  final rawMissed = root['missed'];
  if (rawMissed is Map) {
    for (final e in rawMissed.entries) {
      final n = count(e.value);
      if (e.key is! String ||
          (e.key as String).isEmpty ||
          n == null ||
          n == 0) {
        intact = false;
        continue;
      }
      missed[e.key as String] = n;
    }
  } else if (rawMissed != null) {
    intact = false;
  }

  final history = <ExamSessionRecord>[];
  final rawHistory = root['history'];
  if (rawHistory is List) {
    for (final r in rawHistory) {
      if (r is! Map) {
        intact = false;
        continue;
      }
      final at =
          r['at'] is String ? DateTime.tryParse(r['at'] as String) : null;
      final mode = ExamMode.parse(r['mode']);
      final rawCategory = r['category'];
      final category =
          rawCategory == null ? null : ExamCategory.parse(rawCategory);
      final score = count(r['score']);
      final total = count(r['total']);
      if (at == null ||
          mode == null ||
          (rawCategory != null && category == null) ||
          score == null ||
          total == null ||
          score > total) {
        intact = false;
        continue;
      }
      history.add(ExamSessionRecord(
        at: at,
        mode: mode,
        category: category,
        score: score,
        total: total,
      ));
    }
  } else if (rawHistory != null) {
    intact = false;
  }

  return ExamStatsDecode(
    ExamStats(categories: categories, missed: missed, history: history),
    intact: intact,
  );
}

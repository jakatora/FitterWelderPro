// Egzamin spawacza na ekranie: zastrzeżenie, szybka sesja 10 pytań do końca
// z wynikiem i zapisem statystyk, wyjaśnienie ze źródłem, nauka kategorii,
// powtórki z błędnych, symbol spoiny, EN, wąski ekran 320×640 z tekstem
// ×1,3, cele dotyku ≥ 48 dp, uszkodzony zapis.

import 'package:cut_list_app/domain/exam/exam_questions.dart';
import 'package:cut_list_app/domain/exam/exam_session.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_page.dart';
import 'package:cut_list_app/features/welder_exam/welder_exam_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seed = 7;

class _FlakyReadWriteStore extends WelderExamStore {
  var reads = 0;
  var writes = 0;

  @override
  Future<Object?> readRaw() async {
    if (reads++ == 0) throw StateError('read unavailable');
    return super.readRaw();
  }

  @override
  Future<void> save(ExamStats stats, {bool afterFailedRead = false}) async {
    if (writes++ == 0) throw StateError('write unavailable');
    await super.save(stats, afterFailedRead: afterFailedRead);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(800, 1400),
  double textScale = 1.0,
  Map<String, Object> prefs = const {},
  WelderExamStore store = const WelderExamStore(),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: WelderExamPage(
        store: store,
        seed: _seed,
        clock: () => DateTime(2026, 10, 17, 9, 30),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

/// Odpowiada na bieżące pytanie [q] (sprawdza, że to ono jest na ekranie)
/// i przechodzi dalej.
Future<void> _answer(WidgetTester tester, ExamQuestion q,
    {required bool good, bool next = true}) async {
  expect(_text(tester, 'we-prompt'), q.prompt);
  final pick = good ? q.correctIndex : (q.correctIndex + 1) % q.options.length;
  await _tap(tester, 'we-opt-$pick');
  expect(tester.takeException(), isNull);
  if (next) await _tap(tester, 'we-next');
}

Future<ExamStats> _savedStats() async {
  final p = await SharedPreferences.getInstance();
  final raw = p.getString(WelderExamStore.key);
  expect(raw, isNotNull);
  final d = decodeExamStats(raw!);
  expect(d.intact, isTrue);
  return d.stats;
}

void main() {
  testWidgets(
      'start: zastrzeżenie „nie są oficjalnymi pytaniami” i kategorie '
      'z liczbą pytań', (tester) async {
    await _pump(tester);
    expect(find.text('Egzamin spawacza: pytania'), findsOneWidget);
    expect(
        find.descendant(
            of: _key('we-disclaimer'),
            matching: find.textContaining(
                'Ćwiczenia z danych aplikacji — nie są oficjalnymi pytaniami '
                'egzaminacyjnymi')),
        findsOneWidget);
    final counts = examCategoryCounts(en: false);
    for (final c in ExamCategory.values) {
      final tile = _key('we-cat-${c.name}');
      expect(tile, findsOneWidget, reason: c.name);
      expect(find.descendant(of: tile, matching: find.text(c.titlePl)),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile, matching: find.textContaining('${counts[c]} pyta')),
          findsOneWidget,
          reason: c.name);
    }
    // Bez błędnych odpowiedzi przycisk powtórek jest nieaktywny.
    final review = tester.widget<ButtonStyleButton>(_key('we-review'));
    expect(review.onPressed, isNull);
    expect(find.text('Pytania, które mi nie wychodzą (0)'), findsOneWidget);
  });

  testWidgets('szybka sesja 10 pytań do końca: wynik i zapis statystyk',
      (tester) async {
    await _pump(tester);
    final expected = drawExamQuestions(seed: _seed, en: false);
    await _tap(tester, 'we-quick');
    for (var i = 0; i < expected.length; i++) {
      expect(_text(tester, 'we-progress'), 'Pytanie ${i + 1} / 10');
      await _answer(tester, expected[i], good: i.isEven, next: false);
      expect(_text(tester, 'we-verdict'), i.isEven ? 'Dobrze!' : 'Źle.');
      await _tap(tester, 'we-next');
    }
    expect(_key('we-result'), findsOneWidget);
    expect(_text(tester, 'we-score'), '5 / 10');
    expect(_text(tester, 'we-score-percent'), '50 % dobrych odpowiedzi');

    await tester.pumpAndSettle();
    final stats = await _savedStats();
    final answered =
        stats.categories.values.fold<int>(0, (a, c) => a + c.answered);
    final correct =
        stats.categories.values.fold<int>(0, (a, c) => a + c.correct);
    expect(answered, 10);
    expect(correct, 5);
    expect(stats.missed.keys.toSet(), {
      for (var i = 0; i < expected.length; i++)
        if (i.isOdd) expected[i].id,
    });
    expect(stats.history.single.score, 5);
    expect(stats.history.single.total, 10);
    expect(stats.history.single.mode, ExamMode.quick);
    expect(stats.history.single.at, DateTime(2026, 10, 17, 9, 30));

    await _tap(tester, 'we-home');
    expect(_text(tester, 'we-last'), 'Ostatnia sesja: 5 / 10 (50 %)');
  });

  testWidgets('odpowiedź: poprawna wskazana, wyjaśnienie i źródło danych',
      (tester) async {
    await _pump(tester);
    final q = drawExamQuestions(seed: _seed, en: false).first;
    await _tap(tester, 'we-quick');
    await _answer(tester, q, good: false, next: false);
    expect(
        _text(tester, 'we-correct-answer'), 'Poprawna odpowiedź: ${q.answer}');
    expect(_text(tester, 'we-explanation'), q.explanation);
    expect(_text(tester, 'we-source'), 'Źródło: ${q.source}');
    // Po odpowiedzi przyciski odpowiedzi są zablokowane.
    final opt = tester.widget<OutlinedButton>(find.descendant(
        of: _key('we-opt-0'), matching: find.byType(OutlinedButton)));
    expect(opt.onPressed, isNull);
  });

  testWidgets('wybór kategorii: wszystkie pytania z tej kategorii',
      (tester) async {
    await _pump(tester);
    final expected = drawExamQuestions(
        seed: _seed, en: false, category: ExamCategory.qualification);
    await _tap(tester, 'we-cat-qualification');
    for (var i = 0; i < expected.length; i++) {
      expect(
          _text(tester, 'we-q-category'), ExamCategory.qualification.titlePl);
      await _answer(tester, expected[i], good: true);
    }
    expect(
        _text(tester, 'we-score'), '${expected.length} / ${expected.length}');
    expect(_text(tester, 'we-res-cat-qualification'),
        '${expected.length} / ${expected.length}');
    await _tap(tester, 'we-home');
    expect(
        find.descendant(
            of: _key('we-cat-qualification'),
            matching: find.textContaining('100 % dobrych')),
        findsOneWidget);
  });

  testWidgets('pytania, które mi nie wychodzą: po błędach sesja z błędnych',
      (tester) async {
    await _pump(tester);
    final expected = drawExamQuestions(seed: _seed, en: false);
    await _tap(tester, 'we-quick');
    for (var i = 0; i < expected.length; i++) {
      await _answer(tester, expected[i], good: i >= 3);
    }
    expect(find.text('Powtórz błędne z tej sesji (3)'), findsOneWidget);
    await _tap(tester, 'we-home');
    expect(find.text('Pytania, które mi nie wychodzą (3)'), findsOneWidget);

    final wrong = {for (final q in expected.take(3)) q.prompt: q};
    await _tap(tester, 'we-review');
    for (var i = 0; i < 3; i++) {
      expect(_text(tester, 'we-progress'), 'Pytanie ${i + 1} / 3');
      final q = wrong[_text(tester, 'we-prompt')];
      expect(q, isNotNull);
      // Kolejność odpowiedzi losowana od nowa — dobra odpowiedź po tekście.
      final options = [
        for (var o = 0; o < 4; o++)
          if (_key('we-opt-$o').evaluate().isNotEmpty)
            tester
                .widget<Text>(find
                    .descendant(
                        of: _key('we-opt-$o'), matching: find.byType(Text))
                    .last)
                .data,
      ];
      await _tap(tester, 'we-opt-${options.indexOf(q!.answer)}');
      expect(_text(tester, 'we-verdict'), 'Dobrze!');
      await _tap(tester, 'we-next');
    }
    expect(_text(tester, 'we-score'), '3 / 3');
    await _tap(tester, 'we-home');
    // Dobra odpowiedź zdejmuje pytanie z listy powtórek.
    expect(find.text('Pytania, które mi nie wychodzą (0)'), findsOneWidget);
  });

  testWidgets('symbol spoiny: rysunek symbolu nad pytaniem', (tester) async {
    await _pump(tester);
    final expected = drawExamQuestions(
        seed: _seed, en: false, category: ExamCategory.symbols);
    await _tap(tester, 'we-cat-symbols');
    for (final q in expected) {
      expect(_key('we-glyph'), q.glyph == null ? findsNothing : findsOneWidget,
          reason: q.id);
      await _answer(tester, q, good: true);
    }
    expect(expected.any((q) => q.glyph != null), isTrue);
  });

  testWidgets('przycisk wstecz w sesji wraca do listy', (tester) async {
    await _pump(tester);
    final q = drawExamQuestions(seed: _seed, en: false).first;
    await _tap(tester, 'we-quick');
    await _answer(tester, q, good: false, next: false);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('we-quick'), findsOneWidget);
    expect(find.text('Pytania, które mi nie wychodzą (1)'), findsOneWidget);
  });

  testWidgets('EN: teksty i pytania po angielsku', (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Welder exam: questions'), findsOneWidget);
    expect(find.textContaining('these are not official exam questions'),
        findsOneWidget);
    expect(find.text(ExamCategory.qualification.titleEn), findsOneWidget);
    final expected = drawExamQuestions(seed: _seed, en: true);
    await _tap(tester, 'we-quick');
    expect(_text(tester, 'we-progress'), 'Question 1 / 10');
    await _answer(tester, expected.first, good: true, next: false);
    expect(_text(tester, 'we-verdict'), 'Correct!');
    expect(_text(tester, 'we-source'), 'Source: ${expected.first.source}');
    await _tap(tester, 'we-next');
    await _answer(tester, expected[1], good: false, next: false);
    expect(_text(tester, 'we-correct-answer'),
        'Correct answer: ${expected[1].answer}');
  });

  for (final lang in AppLanguage.values) {
    testWidgets(
        'wąski ekran 320×640, tekst ×1,3 — bez wyjątków i przepełnień '
        '(${lang.name})', (tester) async {
      final en = lang == AppLanguage.en;
      await _pump(tester,
          lang: lang, size: const Size(320, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      // Pełna szybka sesja — każde pytanie, odpowiedź i wyjaśnienie.
      final expected = drawExamQuestions(seed: _seed, en: en);
      await _tap(tester, 'we-quick');
      for (var i = 0; i < expected.length; i++) {
        await _answer(tester, expected[i], good: i.isOdd);
        expect(tester.takeException(), isNull);
      }
      expect(_key('we-result'), findsOneWidget);
      await tester.ensureVisible(_key('we-home'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Kategoria z rysunkami symboli i najdłuższymi treściami.
      await _tap(tester, 'we-home');
      final symbols = drawExamQuestions(
          seed: _seed + 1, en: en, category: ExamCategory.symbols);
      await _tap(tester, 'we-cat-symbols');
      for (final q in symbols) {
        await _answer(tester, q, good: false);
        expect(tester.takeException(), isNull);
      }
      await _tap(tester, 'we-home');
      final quality = drawExamQuestions(
          seed: _seed + 2, en: en, category: ExamCategory.quality);
      await _tap(tester, 'we-cat-quality');
      for (final q in quality) {
        await _answer(tester, q, good: true);
        expect(tester.takeException(), isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    void big(String k) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }

    big('we-quick');
    big('we-review');
    for (final c in ExamCategory.values) {
      big('we-cat-${c.name}');
    }
    final expected = drawExamQuestions(seed: _seed, en: false);
    await _tap(tester, 'we-quick');
    final q = expected.first;
    for (var i = 0; i < q.options.length; i++) {
      big('we-opt-$i');
    }
    await _answer(tester, q, good: false, next: false);
    big('we-next');
    await _tap(tester, 'we-next');
    for (var i = 1; i < expected.length; i++) {
      await _answer(tester, expected[i], good: true);
    }
    big('we-again');
    big('we-retry-wrong');
    big('we-home');
  });

  testWidgets('procent na ekranie w dół: 199 / 200 → 99 %, nie 100 %',
      (tester) async {
    final stats = const ExamStats(categories: {
      ExamCategory.processes: ExamCategoryStat(answered: 200, correct: 199),
    }).withSession(ExamSessionRecord(
      at: DateTime(2026, 10, 17, 8),
      mode: ExamMode.category,
      category: ExamCategory.processes,
      score: 199,
      total: 200,
    ));
    await _pump(tester, prefs: {WelderExamStore.key: encodeExamStats(stats)});
    expect(_text(tester, 'we-last'), 'Ostatnia sesja: 199 / 200 (99 %)');
    expect(
        find.descendant(
            of: _key('we-cat-processes'),
            matching: find.textContaining('99 % dobrych (200 odp.)')),
        findsOneWidget);
    expect(find.textContaining('100 %'), findsNothing);
  });

  testWidgets('uszkodzony zapis: komunikat i kopia przed nadpisaniem',
      (tester) async {
    await _pump(tester, prefs: {WelderExamStore.key: '{"v":1,"missed":'});
    expect(_key('we-damaged'), findsOneWidget);
    final q = drawExamQuestions(seed: _seed, en: false).first;
    await _tap(tester, 'we-quick');
    await _answer(tester, q, good: true, next: false);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.corruptKey), '{"v":1,"missed":');
    expect((await _savedStats()).statFor(q.category).correct, 1);
  });

  testWidgets(
      'po błędzie zapisu kolejna odpowiedź zachowuje nieodczytane statystyki',
      (tester) async {
    final original = encodeExamStats(ExamStats(history: [
      ExamSessionRecord(
        at: DateTime.utc(2026, 10, 17),
        mode: ExamMode.quick,
        score: 3,
        total: 10,
      ),
    ]));
    final store = _FlakyReadWriteStore();
    await _pump(tester, prefs: {WelderExamStore.key: original}, store: store);
    final questions = drawExamQuestions(seed: _seed, en: false);
    await _tap(tester, 'we-quick');
    await _answer(tester, questions[0], good: false);
    expect(_key('we-save-failed'), findsOneWidget);
    await _answer(tester, questions[1], good: true, next: false);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.corruptKey), original);
    expect(_key('we-save-failed'), findsNothing);
  });

  testWidgets('zajęta kopia: zapis wstrzymany z komunikatem', (tester) async {
    await _pump(tester, prefs: {
      WelderExamStore.key: 'drugie uszkodzenie',
      WelderExamStore.corruptKey: 'pierwsze uszkodzenie',
    });
    await _tap(tester, 'we-quick');
    await _answer(tester, drawExamQuestions(seed: _seed, en: false).first,
        good: true, next: false);
    expect(_key('we-save-failed'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(WelderExamStore.key), 'drugie uszkodzenie');
  });
}

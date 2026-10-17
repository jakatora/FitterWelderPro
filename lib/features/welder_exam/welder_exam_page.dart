// Egzamin spawacza: pytania — ćwiczenie teorii przed egzaminem na
// uprawnienia (EN ISO 9606-1) i przed odnowieniem. Offline, PL / EN.
//
// Pytania generuje lib/domain/exam/exam_questions.dart WYŁĄCZNIE z danych,
// które już są w aplikacji (słownik, tabele ISO 9606-1 / 5817 / 2553,
// limity elektrod, dobór spoiwa). To ćwiczenia — nie oficjalne pytania
// egzaminacyjne; ekran mówi to wprost.
//
// Tryby: szybka sesja 10 pytań (losowe kategorie), nauka wybranej
// kategorii, „pytania, które mi nie wychodzą” (z błędnych odpowiedzi). Po
// odpowiedzi: poprawna odpowiedź, wyjaśnienie i źródło danych. Statystyki
// per kategoria i wyniki sesji — SharedPreferences (welder_exam_store.dart).
//
// Rękawice: odpowiedzi to duże przyciski na całą szerokość (≥ 56 dp).

import 'package:flutter/material.dart';

import '../../domain/exam/exam_questions.dart';
import '../../domain/exam/exam_session.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_theme.dart';
import '../weld_symbols/weld_symbol_painter.dart';
import 'welder_exam_store.dart';

/// Wysokość przycisku odpowiedzi — więcej niż minimum, pod rękawicę.
const double _kAnswerHeight = 56;

enum _View { home, question, result }

class WelderExamPage extends StatefulWidget {
  const WelderExamPage({
    super.key,
    this.store = const WelderExamStore(),
    this.clock,
    this.seed,
  });

  /// Zapis statystyk (w testach podmieniany).
  final WelderExamStore store;

  /// Zegar (data wyniku sesji, ziarno losowania); `null` — systemowy.
  final DateTime Function()? clock;

  /// Ziarno pierwszej sesji (kolejne: +1, +2…); `null` — z zegara.
  final int? seed;

  @override
  State<WelderExamPage> createState() => _WelderExamPageState();
}

class _WelderExamPageState extends State<WelderExamPage> {
  ExamStats _stats = const ExamStats();
  bool _loaded = false;
  bool _damaged = false;
  bool _readFailed = false;

  ExamSession? _session;
  _View _view = _View.home;
  int _sessionsStarted = 0;

  Future<void> _saving = Future<void>.value();
  final GlobalKey _feedbackKey = GlobalKey();
  final ScrollController _scroll = ScrollController();

  bool get _en => context.language == AppLanguage.en;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  String _t(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.store.load();
    if (!mounted) return;
    setState(() {
      _stats = r.stats;
      _damaged = r.damaged;
      _readFailed = r.readFailed;
      _loaded = true;
    });
  }

  void _persist() {
    final snapshot = _stats;
    final afterFailedRead = _readFailed;
    _readFailed = false;
    _saving = _saving
        .then((_) =>
            widget.store.save(snapshot, afterFailedRead: afterFailedRead))
        .catchError((Object e) {
      debugPrint('[welder_exam] save failed: $e');
    });
  }

  int _nextSeed() {
    final base = widget.seed;
    final seed = base == null
        ? _now().microsecondsSinceEpoch + _sessionsStarted
        : base + _sessionsStarted;
    _sessionsStarted++;
    return seed;
  }

  /// Pytania do powtórki dostępne w bieżącym języku (najnowsze na końcu).
  List<String> _reviewIds() => [
        for (final id in _stats.missed.keys)
          if (examItemById(id, en: _en) != null) id,
      ];

  void _start(ExamMode mode, {ExamCategory? category, List<String>? ids}) {
    final questions = drawExamQuestions(
      seed: _nextSeed(),
      en: _en,
      category: mode == ExamMode.category ? category : null,
      onlyIds: mode == ExamMode.review ? (ids ?? _reviewIds()) : null,
    );
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t('Brak pytań do powtórki.', 'No questions to repeat.')),
      ));
      return;
    }
    setState(() {
      _session =
          ExamSession(questions: questions, mode: mode, category: category);
      _view = _View.question;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _answer(int option) {
    final s = _session;
    if (s == null) return;
    final question = s.current;
    final ok = s.answer(option);
    if (ok == null) return;
    setState(() => _stats = _stats.withAnswer(question, correct: ok));
    _persist();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _feedbackKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _next() {
    final s = _session;
    if (s == null || !s.currentAnswered) return;
    if (s.isLast) {
      _finish();
      return;
    }
    setState(s.next);
    _scrollToTop();
  }

  void _finish() {
    final s = _session!;
    setState(() {
      _stats = _stats.withSession(ExamSessionRecord(
        at: _now(),
        mode: s.mode,
        category: s.category,
        score: s.score,
        total: s.total,
      ));
      _view = _View.result;
    });
    _persist();
    _scrollToTop();
  }

  void _goHome() {
    setState(() {
      _view = _View.home;
      _session = null;
    });
    _scrollToTop();
  }

  void _again() {
    final s = _session;
    if (s == null) return;
    _start(s.mode, category: s.category);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _view == _View.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goHome();
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(_t('Egzamin spawacza: pytania', 'Welder exam: questions')),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            key: const ValueKey('we-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: switch (_view) {
              _View.home => _home(),
              _View.question => _question(_session!),
              _View.result => _result(_session!),
            },
          ),
        ),
      ),
    );
  }

  // ── Ekran startowy ────────────────────────────────────────────────────────

  Widget _disclaimer() => Card(
        key: const ValueKey('we-disclaimer'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: kWarn),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t(
                      'Ćwiczenia z danych aplikacji — nie są oficjalnymi '
                          'pytaniami egzaminacyjnymi. Przy każdej odpowiedzi '
                          'jest źródło danych.',
                      'Practice built from the app’s data — these are not '
                          'official exam questions. Every answer shows its '
                          'data source.'),
                  style: const TextStyle(color: kText, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _home() {
    final counts = examCategoryCounts(en: _en);
    final review = _reviewIds().length;
    final last = _stats.last;
    final bigButton = ButtonStyle(
      minimumSize:
          WidgetStateProperty.all(const Size.fromHeight(_kAnswerHeight)),
      padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _disclaimer(),
        if (_damaged) ...[
          const SizedBox(height: 12),
          Text(
            _t(
                'Zapisanych statystyk nie dało się w całości odczytać — '
                    'liczymy od nowa, a stary zapis zostanie skopiowany '
                    'przed nadpisaniem.',
                'The saved statistics could not be fully read — counting '
                    'starts again, and the old record is copied before it is '
                    'overwritten.'),
            key: const ValueKey('we-damaged'),
            style: const TextStyle(color: kWarn),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('we-quick'),
          style: bigButton,
          onPressed: _loaded ? () => _start(ExamMode.quick) : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(_t('Szybka sesja: $kExamSessionLength pytań',
              'Quick session: $kExamSessionLength questions')),
        ),
        const SizedBox(height: 4),
        Text(
          _t('Losowe kategorie, wynik na koniec.',
              'Random categories, score at the end.'),
          style: const TextStyle(color: kTextMut, fontSize: 13),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('we-review'),
          style: bigButton,
          onPressed:
              _loaded && review > 0 ? () => _start(ExamMode.review) : null,
          icon: const Icon(Icons.replay),
          label: Text(_t('Pytania, które mi nie wychodzą ($review)',
              'Questions I keep missing ($review)')),
        ),
        if (review == 0) ...[
          const SizedBox(height: 4),
          Text(
            _t('Tu trafią pytania, na które odpowiesz źle.',
                'Questions you answer wrong will land here.'),
            style: const TextStyle(color: kTextMut, fontSize: 13),
          ),
        ],
        if (last != null) ...[
          const SizedBox(height: 12),
          Text(
            _t(
                'Ostatnia sesja: ${last.score} / ${last.total} '
                    '(${_percent(last.score, last.total)} %)',
                'Last session: ${last.score} / ${last.total} '
                    '(${_percent(last.score, last.total)} %)'),
            key: const ValueKey('we-last'),
            style: const TextStyle(color: kTextSec),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          _t('Nauka wybranej kategorii', 'Study one category'),
          style: const TextStyle(
              color: kTextMut, fontWeight: FontWeight.w700, letterSpacing: 0.4),
        ),
        const SizedBox(height: 8),
        for (final c in ExamCategory.values)
          if (counts[c]! > 0)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: ValueKey('we-cat-${c.name}'),
                enabled: _loaded,
                minVerticalPadding: 10,
                title: Text(c.title(en: _en)),
                subtitle: Text(_categorySubtitle(c, counts[c]!)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _start(ExamMode.category, category: c),
              ),
            ),
      ],
    );
  }

  String _categorySubtitle(ExamCategory c, int count) {
    final stat = _stats.statFor(c);
    final n = _en ? '$count questions' : '$count ${_questionsPl(count)}';
    final p = stat.percent;
    if (p == null) {
      return '$n · ${_t('jeszcze bez odpowiedzi', 'not practised yet')}';
    }
    return _t('$n · $p % dobrych (${stat.answered} odp.)',
        '$n · $p % correct (${stat.answered} answers)');
  }

  static String _questionsPl(int n) {
    if (n == 1) return 'pytanie';
    final last = n % 10, lastTwo = n % 100;
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
      return 'pytania';
    }
    return 'pytań';
  }

  static int _percent(int score, int total) => examPercent(score, total);

  // ── Pytanie ───────────────────────────────────────────────────────────────

  Widget _question(ExamSession s) {
    final q = s.current;
    final answered = s.currentAnswered;
    final chosen = s.answerAt(s.index);
    final correctSoFar = [
      for (var i = 0; i <= s.index; i++)
        if (s.answerAt(i) != null && s.isCorrect(i)) i,
    ].length;
    final done = s.index + (answered ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _t('Pytanie ${s.index + 1} / ${s.total}',
                    'Question ${s.index + 1} / ${s.total}'),
                key: const ValueKey('we-progress'),
                style: const TextStyle(
                    color: kText, fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Text(
              _t('Dobrze: $correctSoFar', 'Correct: $correctSoFar'),
              key: const ValueKey('we-running'),
              style: const TextStyle(color: kTextSec),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: s.total == 0 ? 0 : done / s.total,
          minHeight: 4,
          color: kArc,
          backgroundColor: kBorder,
        ),
        const SizedBox(height: 12),
        Text(
          q.category.title(en: _en),
          key: const ValueKey('we-q-category'),
          style: const TextStyle(color: kTextMut, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (q.glyph != null) ...[
                  Container(
                    key: const ValueKey('we-glyph'),
                    height: 96,
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CustomPaint(
                      painter: GlyphOnLinePainter(q.glyph!),
                      size: Size.infinite,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  q.prompt,
                  key: const ValueKey('we-prompt'),
                  style: const TextStyle(
                    color: kText,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AnswerButton(
              key: ValueKey('we-opt-$i'),
              letter: String.fromCharCode(0x41 + i),
              text: q.options[i],
              state: !answered
                  ? _AnswerState.open
                  : i == q.correctIndex
                      ? _AnswerState.correct
                      : i == chosen
                          ? _AnswerState.wrong
                          : _AnswerState.other,
              onTap: answered ? null : () => _answer(i),
            ),
          ),
        if (answered) _feedback(s, q, chosen == q.correctIndex),
      ],
    );
  }

  Widget _feedback(ExamSession s, ExamQuestion q, bool ok) {
    return Column(
      key: _feedbackKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        DecoratedBox(
          key: const ValueKey('we-feedback'),
          decoration: BoxDecoration(
            color: (ok ? kPass : kFail).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ok ? kPass : kFail),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(ok ? Icons.check_circle : Icons.cancel,
                        color: ok ? kPass : kFail),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ok ? _t('Dobrze!', 'Correct!') : _t('Źle.', 'Wrong.'),
                        key: const ValueKey('we-verdict'),
                        style: TextStyle(
                          color: ok ? kPass : kFail,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!ok) ...[
                  const SizedBox(height: 8),
                  Text(
                    _t('Poprawna odpowiedź: ${q.answer}',
                        'Correct answer: ${q.answer}'),
                    key: const ValueKey('we-correct-answer'),
                    style: const TextStyle(
                        color: kText, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  q.explanation,
                  key: const ValueKey('we-explanation'),
                  style: const TextStyle(color: kTextSec, height: 1.4),
                ),
                const SizedBox(height: 8),
                Text(
                  _t('Źródło: ${q.source}', 'Source: ${q.source}'),
                  key: const ValueKey('we-source'),
                  style: const TextStyle(color: kTextMut, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('we-next'),
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(_kAnswerHeight)),
          onPressed: _next,
          child: Text(s.isLast
              ? _t('Zobacz wynik', 'See the score')
              : _t('Dalej', 'Next')),
        ),
      ],
    );
  }

  // ── Wynik ─────────────────────────────────────────────────────────────────

  Widget _result(ExamSession s) {
    final wrong = s.wrong;
    final pct = _percent(s.score, s.total);
    final byCategory = s.byCategory;
    final bigButton = ButtonStyle(
      minimumSize:
          WidgetStateProperty.all(const Size.fromHeight(_kAnswerHeight)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const ValueKey('we-result'),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_t('Wynik sesji', 'Session score'),
                    style: const TextStyle(color: kTextSec)),
                const SizedBox(height: 6),
                Text(
                  '${s.score} / ${s.total}',
                  key: const ValueKey('we-score'),
                  style: const TextStyle(
                      color: kArc, fontSize: 36, fontWeight: FontWeight.w800),
                ),
                Text(
                  _t('$pct % dobrych odpowiedzi', '$pct % correct'),
                  key: const ValueKey('we-score-percent'),
                  style: const TextStyle(color: kText),
                ),
              ],
            ),
          ),
        ),
        if (byCategory.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_t('Według kategorii', 'By category'),
              style: const TextStyle(
                  color: kTextMut, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final e in byCategory.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(e.key.title(en: _en),
                        style: const TextStyle(color: kText)),
                  ),
                  const SizedBox(width: 8),
                  Text('${e.value.correct} / ${e.value.total}',
                      key: ValueKey('we-res-cat-${e.key.name}'),
                      style: const TextStyle(color: kTextSec)),
                ],
              ),
            ),
        ],
        if (wrong.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_t('Do powtórki', 'To repeat'),
              style: const TextStyle(
                  color: kTextMut, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final q in wrong)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(q.prompt, style: const TextStyle(color: kTextSec)),
                  const SizedBox(height: 2),
                  Text(
                    _t('Poprawna: ${q.answer}', 'Correct: ${q.answer}'),
                    style: const TextStyle(
                        color: kPass, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const ValueKey('we-again'),
          style: bigButton,
          onPressed: _again,
          child: Text(_t('Nowa sesja', 'New session')),
        ),
        if (wrong.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('we-retry-wrong'),
            style: bigButton,
            onPressed: () =>
                _start(ExamMode.review, ids: [for (final q in wrong) q.id]),
            child: Text(_t('Powtórz błędne z tej sesji (${wrong.length})',
                'Repeat this session’s mistakes (${wrong.length})')),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('we-home'),
          style: bigButton,
          onPressed: _goHome,
          child: Text(_t('Wróć do listy', 'Back to the list')),
        ),
        const SizedBox(height: 16),
        Text(
          _t(
              'Ćwiczenia z danych aplikacji — nie są oficjalnymi pytaniami '
                  'egzaminacyjnymi.',
              'Practice built from the app’s data — not official exam '
                  'questions.'),
          style: const TextStyle(color: kTextMut, fontSize: 12),
        ),
      ],
    );
  }
}

enum _AnswerState { open, correct, wrong, other }

/// Odpowiedź: duży przycisk na całą szerokość z literą A–D.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final _AnswerState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (state) {
      _AnswerState.correct => kPass,
      _AnswerState.wrong => kFail,
      _ => kBorder,
    };
    final tint = switch (state) {
      _AnswerState.correct => kPass.withValues(alpha: 0.16),
      _AnswerState.wrong => kFail.withValues(alpha: 0.16),
      _ => kCard,
    };
    final fg = state == _AnswerState.other ? kTextMut : kText;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(_kAnswerHeight),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignment: Alignment.centerLeft,
        backgroundColor: tint,
        foregroundColor: fg,
        disabledBackgroundColor: tint,
        disabledForegroundColor: fg,
        side: BorderSide(
            color: state == _AnswerState.open ? kBorder : accent, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: state == _AnswerState.open ? kTextMut : accent),
            ),
            child: Text(letter,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontSize: 15, height: 1.3),
            ),
          ),
          if (state == _AnswerState.correct) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check, color: kPass),
          ] else if (state == _AnswerState.wrong) ...[
            const SizedBox(width: 8),
            const Icon(Icons.close, color: kFail),
          ],
        ],
      ),
    );
  }
}

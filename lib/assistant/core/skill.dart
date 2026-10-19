// Kontrakt umiejętności asystenta (spec §4.2, plan zadanie 1.2).
//
// Jedna umiejętność = jedno zadanie użytkownika („średnica zewnętrzna rury
// z DN/NPS"). Umiejętności NIE znają UI: liczą funkcjami domeny i mówią tylko,
// co pokazać w module ([ShowInModule]). Zasady nienaruszalne:
//   • `match()` jest synchroniczne i bez I/O (mózg ocenia nim wszystkie
//     umiejętności dla każdej alternatywy rozpoznania mowy);
//   • liczby w odpowiedzi tylko z kodu domeny, przy normach — norma
//     ([AssistantAnswer.source]);
//   • niejednoznaczność → [AskResult], nigdy zgadywanie;
//   • zmiana danych → [ConfirmResult] (podsumowanie, potwierdzenie, zapis,
//     Cofnij); moduły bezpieczeństwa: potwierdzenie tylko dotykiem.

import '../../i18n/app_language.dart';
import 'assistant_text.dart';
import 'module_context.dart';
import 'utterance.dart';

export 'assistant_text.dart';
export 'module_context.dart';
export 'utterance.dart';

/// Przykład użycia w obu językach — dokumentacja, korpus testu routera
/// i lista „co umiem". Pierwszy przykład umiejętności jest „kanoniczny".
class SkillExample {
  const SkillExample(this.pl, this.en);
  final String pl, en;
}

/// Wypowiedź, która NIE może trafić w daną umiejętność (pułapka w korpusie).
///
/// Rozszerzenie planu: plan wymaga korpusu odrzuceń, ale interfejs nie miał
/// na niego miejsca — globalny test routera czyta odrzucenia stąd.
class SkillRejection {
  const SkillRejection(this.text,
      {this.routesTo, this.alsoNot = const [], this.lang = AppLanguage.pl});

  final String text;

  /// Id umiejętności, w którą wypowiedź MA trafić (null = dowolna inna albo
  /// „nie rozumiem").
  final String? routesTo;

  /// Inne id, w które wypowiedź też nie może trafić (np. „dodaj zawór
  /// kulowy dn50" ani w `pipe.od`, ani w `legacy.save`).
  final List<String> alsoNot;

  final AppLanguage lang;
}

/// A otwórz/wyjaśnij, B licz + wypełnij, C rekord, D rysuj.
enum AssistantTier { a, b, c, d }

abstract class AssistantSkill {
  String get id;

  /// Narzędzie z rejestru (`kToolRegistry`), którego dotyczy umiejętność.
  String? get toolId;

  AssistantTier get tier;

  List<SkillExample> get examples;

  /// false = zmienia dane → [ConfirmResult].
  bool get readOnly => true;

  /// true = potwierdzenie tylko dotykiem (moduły bezpieczeństwa).
  bool get safetyCritical => false;

  /// Synchronicznie, bez I/O. null = to nie do mnie.
  SkillMatch? match(Utterance u, AssistantContext ctx);

  Future<SkillResult> run(SkillMatch m, AssistantContext ctx);

  // ─── Rozszerzenia planu (domyślne implementacje, nic nie psują) ───────────

  /// Pułapki korpusu: wypowiedzi, które nie mogą trafić w tę umiejętność.
  List<SkillRejection> get rejections => const [];

  /// null = zwykła umiejętność (oceniana w rundzie głównej). Liczba =
  /// fallback mózgu w tej kolejności (co umiem → otwórz → wyjaśnij → wiedza),
  /// oceniany dopiero, gdy nic z rundy głównej nie przekroczyło progu.
  int? get fallbackOrder => null;

  /// Sloty, które wypowiedź podaje DLA TEJ umiejętności, nawet bez słów
  /// zamiaru („a dla DN50?" → {dn: 50}). Mózg używa tego do kontynuacji.
  /// Domyślnie: sloty z [match].
  Map<String, Object?> slotsFrom(Utterance u, AssistantContext ctx) =>
      match(u, ctx)?.slots ?? const {};

  /// Odpowiedź na [AskResult] tej umiejętności o [slot]: wszystkie sloty
  /// odczytane z wypowiedzi (z [slot] w środku) albo null, gdy to nie jest
  /// odpowiedź na pytanie. Domyślnie przez [slotsFrom].
  Map<String, Object?>? fillSlot(
      String slot, Utterance u, AssistantContext ctx) {
    final s = slotsFrom(u, ctx);
    return s.containsKey(slot) ? s : null;
  }
}

class SkillMatch {
  const SkillMatch(this.skill, this.score,
      {this.slots = const {}, this.missing = const [], this.utterance});

  final AssistantSkill skill;

  /// 0–1. Mózg wybiera najwyższy wynik ≥ progu.
  final double score;
  final Map<String, Object?> slots;

  /// Sloty, o które trzeba dopytać.
  final List<String> missing;
  final Utterance? utterance;

  SkillMatch copyWith({
    double? score,
    Map<String, Object?>? slots,
    List<String>? missing,
    Utterance? utterance,
  }) =>
      SkillMatch(skill, score ?? this.score,
          slots: slots ?? this.slots,
          missing: missing ?? this.missing,
          utterance: utterance ?? this.utterance);

  @override
  String toString() => 'SkillMatch(${skill.id}, $score, $slots)';
}

class AnswerLine {
  const AnswerLine(this.label, this.value);
  final AssistantText label;
  final String value;
}

class AssistantAnswer {
  const AssistantAnswer(
      {required this.text, this.spoken, this.lines = const [], this.source});

  /// Tekst karty.
  final AssistantText text;

  /// Tekst do przeczytania (krótszy, z jednostkami słownie); null = [text].
  final AssistantText? spoken;
  final List<AnswerLine> lines;

  /// Norma / źródło liczb („EN 10220 / ISO 4200 seria 1, ASME B36.10M").
  final AssistantText? source;
}

/// Co pokazać w module: id narzędzia i pola do ustawienia (uchwyt strony,
/// zadanie 1.4, ustawia je i jawnie przelicza).
class ShowInModule {
  const ShowInModule(this.toolId, [this.fields = const {}]);
  final String toolId;
  final Map<String, Object?> fields;
}

/// Chip kontynuacji: etykieta i wypowiedź wysyłana po stuknięciu.
class FollowUp {
  const FollowUp(this.label, this.utterance);
  final AssistantText label;
  final String utterance;
}

sealed class SkillResult {
  const SkillResult();
}

class AnswerResult extends SkillResult {
  const AnswerResult(this.answer, {this.show, this.followUps = const []});
  final AssistantAnswer answer;
  final ShowInModule? show;
  final List<FollowUp> followUps;
}

class AskResult extends SkillResult {
  const AskResult(this.slot, this.question,
      {required this.partial, this.choices = const []});
  final String slot;
  final AssistantText question;

  /// To, co już wiadomo; odpowiedź dokleja slot i woła `run` jeszcze raz.
  final SkillMatch partial;
  final List<FollowUp> choices;
}

typedef UndoAction = Future<void> Function();

class ConfirmResult extends SkillResult {
  const ConfirmResult(this.summary, this.perform,
      {this.show, this.touchOnly = false});
  final AssistantAnswer summary;

  /// Zapis — dopiero po potwierdzeniu. Zwraca Cofnij (null = nie da się).
  final Future<UndoAction?> Function() perform;
  final ShowInModule? show;

  /// Potwierdzenie tylko dotykiem (moduły bezpieczeństwa) — głosowe „tak"
  /// nic nie robi.
  final bool touchOnly;
}

class NotUnderstood extends SkillResult {
  const NotUnderstood(this.suggestions);
  final List<FollowUp> suggestions;
}

class FailedResult extends SkillResult {
  const FailedResult(this.message);
  final AssistantText message;
}

/// Okno kontynuacji („a dla DN50?") — spec §4.3.
const Duration kContinuationWindow = Duration(minutes: 2);

/// Okno dopowiedzenia (wypowiedź bez własnego zamiaru) — spec §4.7.
const Duration kAppendWindow = Duration(seconds: 8);

class AssistantContext {
  AssistantContext(
      {required this.lang, required this.modules, DateTime Function()? now})
      : now = now ?? DateTime.now;

  AppLanguage lang;
  final ModuleContext modules;
  final DateTime Function() now;

  /// Ostatnie trafienie i jego czas — kontynuacja (2 min) i dopowiedzenie
  /// (8 s).
  SkillMatch? lastMatch;
  DateTime? lastAt;

  /// Zapamiętuje trafienie jako „ostatnie" (woła mózg po udanej turze).
  void remember(SkillMatch m) {
    lastMatch = m;
    lastAt = now();
  }

  /// Ostatnie trafienie, jeśli nie starsze niż [within].
  SkillMatch? recentMatch({Duration within = kContinuationWindow}) {
    final m = lastMatch, at = lastAt;
    if (m == null || at == null) return null;
    final age = now().difference(at);
    if (age.isNegative || age > within) return null;
    return m;
  }

  /// Slot ostatniego trafienia („a ścianka?" po DN40 → dn = 40), jeśli
  /// trafienie nie jest starsze niż [within].
  Object? recentSlot(String name, {Duration within = kContinuationWindow}) =>
      recentMatch(within: within)?.slots[name];
}

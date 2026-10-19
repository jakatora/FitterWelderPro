// Rozpoznanie, czy wypowiedź do asystenta jest sygnałem dla twórcy aplikacji.
//
// Czysta funkcja, bez I/O. Tekst przechodzi przez `normalizeForSearch`
// (małe litery, bez polskich znaków, interpunkcja → spacja), więc reguły są
// pisane bez ogonków: „zgłoś błąd” = „zglos blad”, „doesn't” = „doesn t”.
//
// Kolejność (pierwsza pasująca wygrywa):
//   1. explicit  — „zgłoś problem / błąd …”, „report a bug …”;
//   2. cantFind  — „gdzie jest…”, „nie mogę znaleźć…”, „where is…”;
//      wyżej niż narzekanie, bo mówi konkretnie, czego brakuje
//      („nie da się znaleźć…” to cantFind, nie complaint);
//   3. complaint — słowo narzekania („nie działa”, „głupie”, „bez sensu”…)
//      LICZY SIĘ TYLKO, gdy:
//        - wypowiedź odnosi się do aplikacji (apka, aplikacja, program,
//          asystent, „ten moduł / kalkulator / ekran…”), albo
//        - zaczyna się od zaimka „to / tu / it / this / that” tuż przed
//          narzekaniem („to nie działa”, „kurde, to jest bez sensu”), albo
//        - jest zwrócona do asystenta w 2. osobie („nie rozumiesz”), albo
//        - poprzednia tura asystenta była nieudana ([lastTurnFailed]).
//      „Spawarka nie działa” po udanej turze to rozmowa o spawarce → null.
//
// `notUnderstood` i `error` nie pochodzą z tekstu — nadaje je 5.1b.

import '../services/help_search.dart' show normalizeForSearch;
import 'feedback_signal.dart';

final List<RegExp> _explicit = [
  RegExp(r'\b(?:zglos|zglosic|zglaszam|zglosze|zgloszenie|zgloszenia)'
      r'(?: \w+){0,3}? (?:problem\w*|blad|bledu|bledy|bledow|bledzie|'
      r'usterk\w*|uwag\w*|sugesti\w*|zazaleni\w*|reklamacj\w*)\b'),
  RegExp(r'\bzglos (?:to|tworcy|tworcom|autorowi|autorom)\b'),
  RegExp(r'\b(?:chce|chcialbym|chcialabym|moge) (?:cos )?zglosic\b'),
  RegExp(r'\breport(?:ing)? (?:a |an |the |this )?'
      r'(?:problem|bug|issue|error|glitch)s?\b'),
  RegExp(r'\b(?:bug report|send feedback|give feedback|leave feedback|'
      r'file a bug|submit a bug|i want to report)\b'),
];

final List<RegExp> _cantFind = [
  RegExp(r'\bgdzie (?:jest|sa|znajde|znajduje|znajduja|moge|mam|mozna|'
      r'szukac|to|sie|podzial\w*|schowal\w*|znalezc|bylo|byl|byla)\b'),
  RegExp(r'\bnie (?:moge|mozna|umiem|potrafie|da sie|mozemy)(?: \w+){0,2} '
      r'(?:znalezc|odnalezc|znalesc)\b'),
  RegExp(r'\bsie nie da (?:\w+ )?znalezc\b'),
  RegExp(r'\b(?:jak|gdzie) (?:mam |moge |mozna )?'
      r'(?:znalezc|odnalezc|znalesc|znajde|dotrzec do|trafic do)\b'),
  RegExp(r'\bnigdzie nie (?:ma|widze|moge)\b'),
  RegExp(r'\bwhere (?:is|are|s|can|do|did|would|should|has|have)\b'),
  RegExp(r'\b(?:can t|cannot|can not|cant|couldn t|could not|unable to) '
      r'(?:\w+ ){0,2}find\b'),
  RegExp(r'\bhow (?:do i|can i|to|would i|should i|do you) find\b'),
];

/// Słowa i zwroty narzekania (PL + EN), bez warunku odniesienia.
const String _complaintWords = r'(?:'
    r'nie dzial\w*|nie chce dzialac|przestal\w* dzialac|zle dziala|'
    r'dziala zle|nic nie daje|'
    r'glup\w*|bez sensu|bezsens\w*|beznadziej\w*|wkurz\w*|denerwuj\w*|'
    r'irytuj\w*|nie da sie|sie nie da|'
    r'zle (?:liczy|policzyl\w*|wylicza\w*|przelicza\w*|pokazuje|rysuje|'
    r'narysowal\w*|zrozumial\w*|rozumie)|'
    r'(?:zly|zle|bledny|bledne|bledna) wynik\w*|'
    r'wynik\w* (?:jest |sa )?(?:zly|zle|bledn\w*)|'
    r'do niczego|do bani|do dupy|badziew\w*|porazk\w*|'
    r'zepsu\w*|psuje sie|zawiesza sie|zawiesil\w* sie|wywala sie|'
    r'wywalil\w* sie|sie sypie|crash\w*|nie ogarnia\w*|nie rozumie|'
    r'(?:not|isn t|is not|aren t|doesn t|does not|don t|do not|didn t|'
    r'did not|won t|will not) work\w*|stopped working|'
    r'broken|stupid|dumb|useless|pointless|nonsense|makes no sense|'
    r'(?:doesn t|does not) make sense|annoying|frustrating|sucks|terrible|'
    r'awful|garbage|rubbish|'
    r'wrong (?:result|answer|number|calculation|value)s?|'
    r'calculates wrong\w*|(?:result|answer)s? (?:is |are )?wrong|'
    r'keeps crashing|freez\w*'
    r')';

final RegExp _complaint = RegExp('\\b$_complaintWords\\b');

/// Zwroty skierowane do asystenta (2. osoba) — odniesienie jest w nich samych.
final RegExp _selfDirected = RegExp(r'\b(?:'
    r'(?:nic )?nie rozumiesz|(?:nic )?nie umiesz|nie potrafisz|nie slyszysz|'
    r'jestes (?:\w+ )?(?:glup\w*|beznadziej\w*|do niczego|do bani|'
    r'bezuzyteczn\w*|tep\w*)|'
    r'you (?:re|are) (?:\w+ )?(?:stupid|useless|dumb|terrible|awful|broken|'
    r'hopeless)|'
    r'you (?:don t|do not|never) (?:understand|get it)|'
    r'you (?:can t|cannot) do anything'
    r')\b');

/// Odniesienie do aplikacji w dowolnym miejscu wypowiedzi.
final RegExp _appReference = RegExp(r'\b(?:'
    r'apk\w*|appk\w*|aplikacj\w*|program\w*|asystent\w*|'
    r'app|apps|application\w*|assistant\w*|software'
    r')\b|'
    r'\b(?:ten|ta|to|tym|tego|tej|te|tych|this|the|that)(?: \w+)? (?:'
    r'modul\w*|kalkulator\w*|ekran\w*|funkcj\w*|narzedzi\w*|przycisk\w*|'
    r'wyszukiwark\w*|zakladk\w*|opcj\w*|zeszyt\w*|'
    r'module|modules|calculator|screen|feature|button|page|search|tool|'
    r'function|notebook'
    r')\b');

/// Wtrącenia, które mogą stać przed zaimkiem („kurde, to nie działa”).
const String _fillers = r'(?:kurde|kurcze|kurna|cholera|kurwa|no|ale|i|a|ej|'
    r'halo|serio|naprawde|jezu|boze|o|oj|ech|eh|znowu|przeciez|ugh|man|well|'
    r'but|and|seriously|oh|so|jeez|wow|again|just)';

/// Dopowiedzenia między zaimkiem a narzekaniem („to jest w ogóle …”).
const String _modifiers = r'(?:jest|sa|mnie|znowu|dalej|ciagle|nadal|juz|'
    r'po prostu|w ogole|wcale|naprawde|totalnie|kompletnie|calkiem|chyba|tez|'
    r'nic|serio|s|is|was|keeps|still|just|really|totally|completely|so|'
    r'seems|again|also)';

/// Zaimek na początku wypowiedzi (po ewentualnych wtrąceniach) tuż przed
/// narzekaniem: „to nie działa”, „it's broken”, „tutaj nic nie działa”.
final RegExp _pronounComplaint = RegExp('^(?:$_fillers )*'
    '(?:to|tu|tutaj|it|this|that)(?: $_modifiers)* $_complaintWords\\b');

/// Rodzaj sygnału w wypowiedzi albo null (zwykła rozmowa / polecenie).
///
/// [lastTurnFailed] — poprzednia odpowiedź asystenta była nieudana
/// (nie rozpoznał polecenia albo zgłosił błąd); wtedy samo słowo narzekania
/// wystarcza, bez odniesienia do aplikacji.
FeedbackKind? classifyFeedback(String text, {required bool lastTurnFailed}) {
  final t = normalizeForSearch(text);
  if (t.isEmpty) return null;

  if (_explicit.any((r) => r.hasMatch(t))) return FeedbackKind.explicit;
  if (_cantFind.any((r) => r.hasMatch(t))) return FeedbackKind.cantFind;
  if (_selfDirected.hasMatch(t)) return FeedbackKind.complaint;

  if (!_complaint.hasMatch(t)) return null;
  if (lastTurnFailed ||
      _appReference.hasMatch(t) ||
      _pronounComplaint.hasMatch(t)) {
    return FeedbackKind.complaint;
  }
  return null;
}

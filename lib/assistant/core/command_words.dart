// Słowa, po których widać, że wypowiedź to polecenie albo pytanie o INNY
// moduł („dodaj zawór…", „ile waży…", „otwórz…"). Mózg używa ich, żeby
// pytanie w toku („Jakie DN?") nie połknęło nowego polecenia; umiejętności
// — żeby nie kraść cudzych zamiarów. Re-eksportowane przez
// skills/core/skill_words.dart (wcześniej tam były).

import 'utterance.dart';

/// A translation/explanation quotes an instruction; its verbs are data.
/// Keep this before pending slots as well as before direct action routing.
bool referencesInstruction(Utterance u) => RegExp(
        r'^(?:(?:prosze|please|hej|hey|asystencie)\s+)*'
        r'(?:przetlumacz\w*|tlumacz\w*|translate|wyjasnij|wytlumacz|explain|'
        r'co (?:to )?znaczy|co oznacza|what does|jak powiedziec|jak (?:jest|bedzie)|'
        r'powiedz po (?:angielsku|niemiecku|polsku|holendersku|norwesku)|'
        r'how (?:do (?:i|you) (?:say|translate)|to say))\b')
    .hasMatch(u.folded);

/// Czasowniki poleceń zapisu i rysowania („dodaj zawór", „zapisz TIG…",
/// „narysuj rurę") — przy nich pytania o liczby z tabel nie trafiają.
final RegExp kCommandVerbRe = RegExp(
    r'\b(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|wpisz|save|store|remember|'
    r'record|add|log|narysuj|rysuj|dorysuj|draw|wstaw|insert)\b');

/// „Otwórz / pokaż / włącz…" na początku zdania (jak w starym parserze).
final RegExp kOpenVerbAtStartRe = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:otworz|pokaz|uruchom|wlacz|przejdz do|idz do|open|show|launch|start|'
    r'go to|take me to)\b');

/// Słowa ciężaru — pytanie o masę to inny moduł (pipe_weight, steel_weight).
bool mentionsWeight(Utterance u) =>
    u.hasStem(
        const ['waz', 'waga', 'wagi', 'ciezar', 'masa', 'masy', 'weigh']) ||
    u.hasAny(const ['kg', 'kilogram', 'kilogramow', 'mass', 'mase', 'wage']);

/// Słowa ścianki i harmonogramu.
bool mentionsWall(Utterance u) =>
    u.hasStem(const ['sciank', 'grubos', 'schedul', 'szedul', 'szedzul']) ||
    u.hasAny(const ['wall', 'walls', 'thickness', 'sch']);

/// Kształtki — „wymiar kolana DN50" to moduł kolan, nie „DN ↔ mm".
bool mentionsFitting(Utterance u) => u.hasStem(const [
      'kolan',
      'luk',
      'trojnik',
      'redukc',
      'zawor',
      'kolnierz',
      'zaslep',
      'denn',
      'elbow',
      'tee',
      'reducer',
      'valve',
      'flange',
      'cap',
    ]);

/// Wyraźnie inne polecenie: czasownik zapisu/rysowania, „otwórz", ciężar
/// albo kształtka. Ścianki tu NIE ma — bywa odpowiedzią na pytanie zapisu
/// parametru („Jaka grubość ścianki?" → „ścianka dwa milimetry").
bool looksLikeOtherCommand(Utterance u) =>
    kCommandVerbRe.hasMatch(u.folded) ||
    kOpenVerbAtStartRe.hasMatch(u.folded) ||
    mentionsWeight(u) ||
    mentionsFitting(u);

/// A negated instruction is handled locally before ISO, writes or remote AI.
final _negatedCommand = RegExp(
    r'^(?:(?:prosze|please|hej|hey|asystencie|asystent)\s+)*'
    r'(?:nie\s+(?:oblicz\w*|policz\w*|przelicz\w*|otwier\w*|otworz\w*|pokaz\w*|'
    r'wybier\w*|wybierz\w*|wyczys\w*|czys\w*|skopi\w*|kopi\w*|uruch\w*|wlacz\w*|rozpocz\w*|wznow\w*|zatrzy\w*|pauz\w*|wyzer\w*|odlicz\w*|znajdz\w*|szukaj\w*|wyszuk\w*|sprawdz\w*|dobierz\w*|dobier\w*|skroc\w*|skrac\w*|przytn\w*|wylicz\w*|podlicz\w*|licz\w*|tnij\w*|rysuj\w*|narysuj\w*|zapis\w*|dodaw\w*|dodaj\w*|usun\w*|ustaw\w*|zmien\w*|wpis\w*)'
    r'|(?:do not|dont|don t)\s+(?:copy|choose|clear|start|stop|pause|resume|reset|find|lookup|look up|check|size|select|pick|calculate|compute|convert|trim|cut|open|show|draw|save|add|delete|set|change|insert)\b)');
bool isNegatedCommand(Utterance u) => _negatedCommand.hasMatch(u.folded);

/// A relation or correction is not a literal scalar, even if a native parser
/// can find a number in it. Use AI instead of silently taking that number.
bool pendingReplyNeedsInterpretation(Utterance u) =>
    u.hasStem(const [
      'polow',
      'half',
      'dwukrot',
      'twice',
      'double',
      'pomnoz',
      'multiply',
      'podziel',
      'divide'
    ]) ||
    u.hasAny(const [
      'razy',
      'zamiast',
      'instead',
      'mam na mysli',
      'i mean',
      'jednak'
    ]) ||
    RegExp(r'\d\s*[+*/]\s*\d').hasMatch(u.raw);

bool requestsWeldingCables(Utterance u) =>
    u.hasStem(const ['przewod', 'kabel', 'kabl', 'cable', 'lead']) &&
    (u.hasStem(
            const ['spawal', 'masow', 'weld', 'return', 'ground', 'torch']) ||
        u.hasAny(const ['h01n2']));

/// Cooling time consumes heat input as a parameter; it is a separate task.
bool requestsCoolingTime(Utterance u) =>
    RegExp(r'\bt\s*8\s*[/ ]\s*5\b|\bt85\b', caseSensitive: false)
        .hasMatch(u.raw) ||
    u.hasAny(const [
      'czas stygnięcia',
      'czas stygniecia',
      'cooling time',
      't osiem na pięć',
      't osiem pięć',
      't eight to five',
      't eight five'
    ]);

/// Explicit calculations may open their calculator, unlike factual questions.
bool requestsCalculation(Utterance u) =>
    !isNegatedCommand(u) &&
    (u.hasStem(const [
          'oblicz',
          'policz',
          'przelicz',
          'wylicz',
          'dobierz',
          'sprawdz',
          'check',
          'size',
          'select',
          'pick',
          'skroc',
          'przytn',
          'ciec',
          'cieci',
          'trim',
          'cut',
          'calculate',
          'compute',
          'convert'
        ]) ||
        (u.hasStem(const ['slownik', 'glossary', 'dictionary']) &&
            u.hasStem(const [
              'znajdz',
              'wyszuk',
              'pokaz',
              'find',
              'lookup',
              'look'
            ])));

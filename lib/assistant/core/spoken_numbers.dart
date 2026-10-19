// Wspólny tokenizer mowy asystenta — wyciągnięty 1:1 ze starego parsera
// (assistant_parser.dart), żeby nowy mózg i stary parser zwijały tekst
// i czytały liczby identycznie.
//
// Zasada nadrzędna („brudna mowa"): NIGDY cichy zły wynik.
//   • dwie liczby słownie obok siebie („dwa sześćdziesiąt") to DWIE liczby
//     (2 i 60), nie 62;
//   • ułamek („3/4", „trzy czwarte") ma flagę [SpokenItem.fraction] — sens ma
//     tylko z calami;
//   • żargon („dwójka" = 2 mm, „jedynka" = drut 1 mm, „na setkę" = 100 A,
//     „rura setka" = DN100) i literowanie z rozpoznawania mowy („pe ef" = PF).

const _plFold = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', //
  'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
};

/// Mianowniki ułamków calowych, które traktujemy jako ułamek (1/2, 3/4,
/// 1/8 …). Inne „a/b" to nie ułamek (np. data) — „/" staje się spacją.
const Set<int> _inchDenominators = {2, 4, 8, 16};

String _fractionToken(int whole, int num, int den) {
  final v = whole + num / den;
  var s = v.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
  if (s.isEmpty) s = '0';
  return ' frac$s ';
}

final _alnum = RegExp(r'[a-z0-9]');
final _digit = RegExp(r'\d');

/// Małe litery, bez polskich znaków, przecinek dziesiętny → kropka, reszta
/// interpunkcji → spacja. „l/min" → „lpm", „Ø"/„⌀" → „fi", `2"` → „2 cal",
/// „3/4" → „frac0.75". Potem żargon i literowanie z rozpoznawania mowy.
String foldSpeech(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[ø⌀]'), ' fi ');
  // Tylko „60,3" bez spacji — „2, 60" to wyliczenie, nie ułamek.
  s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  // Cale zapisane cudzysłowem: 2" / 2”.
  s = s.replaceAllMapped(
      RegExp('(\\d)\\s*(?:"|”|″|\'\')'), (m) => '${m[1]} cal ');
  // Ułamki calowe: „1 1/4", „3/4".
  s = s.replaceAllMapped(RegExp(r'\b(\d+)\s+(\d+)\s*/\s*(\d+)\b'), (m) {
    final w = int.parse(m[1]!), n = int.parse(m[2]!), d = int.parse(m[3]!);
    if (!_inchDenominators.contains(d) || n >= d || n == 0) return m[0]!;
    return _fractionToken(w, n, d);
  });
  s = s.replaceAllMapped(RegExp(r'\b(\d+)\s*/\s*(\d+)\b'), (m) {
    final n = int.parse(m[1]!), d = int.parse(m[2]!);
    if (!_inchDenominators.contains(d) || n == 0) return m[0]!;
    return _fractionToken(0, n, d);
  });
  s = s.replaceAll(RegExp(r'\b(?:l|ltr|litr)\s*/\s*(?:min|m)\b'), ' lpm ');
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final folded = _plFold[c];
    if (folded != null) {
      buf.write(folded);
    } else if (_alnum.hasMatch(c)) {
      buf.write(c);
    } else if (c == '.' &&
        i > 0 &&
        i + 1 < s.length &&
        _digit.hasMatch(s[i - 1]) &&
        _digit.hasMatch(s[i + 1])) {
      buf.write('.');
    } else {
      buf.write(' ');
    }
  }
  final out = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return _normalizeSpoken(out);
}

const Map<String, String> _spelledLetter = {
  'a': 'a', 'be': 'b', 'b': 'b', 'ce': 'c', 'c': 'c', 'de': 'd', 'd': 'd',
  'e': 'e', 'ef': 'f', 'f': 'f', 'gie': 'g', 'ge': 'g', 'g': 'g', 'ha': 'h',
  'h': 'h', 'jot': 'j', 'j': 'j',
};

const Map<String, String> _spokenDigit = {
  'jeden': '1', 'dwa': '2', 'trzy': '3', 'cztery': '4', 'piec': '5',
  'szesc': '6',
};

/// Żargon i literowanie po zwinięciu tekstu (na słowach bez polskich znaków).
String _normalizeSpoken(String s) {
  var out = ' $s ';
  // „na setkę" / „na stówę" = 100 A.
  out = out.replaceAll(
      RegExp(r' na (?:setke|setce|stowe|stowke|stowce) '), ' na 100 a ');
  // „rura setka" = DN100.
  out = out.replaceAllMapped(
      RegExp(r' (rur\w*) (?:setka|setke|setki|stowka|stowke) '),
      (m) => ' ${m[1]} dn 100 ');
  // H-L045 / J-L045 w każdej postaci: „h l045", „ha el zero czterdzieści pięć".
  out = out.replaceAll(
      RegExp(r' (?:ha|h) ?(?:el|l) ?(?:0 ?45|045|zero czterdziesci piec) '),
      ' pozycja hl045 ');
  out = out.replaceAll(
      RegExp(r' (?:jot|j) ?(?:el|l) ?(?:0 ?45|045|zero czterdziesci piec) '),
      ' pozycja jl045 ');
  // Literowane ISO 6947: „pe ef" = PF, „pe a" = PA, „p c" = PC.
  out = out.replaceAllMapped(
      RegExp(r' (?:pe|p) (ef|e|a|be|b|ce|c|de|d|f|gie|ge|g|ha|h|jot|j)(?= )'),
      (m) => ' pozycja p${_spelledLetter[m[1]]!}');
  // ASME ze spacją: „5 G", „6 G R", „pięć gie".
  out = out.replaceAllMapped(RegExp(r' ([1-6]) (g r|gr|g|gie|f|ef)(?= )'),
      (m) => ' ${m[1]}${_asmeSuffix(m[2]!)}');
  out = out.replaceAllMapped(
      RegExp(r' (jeden|dwa|trzy|cztery|piec|szesc) (gie|g|ef|f|gr)(?= )'),
      (m) => ' ${_spokenDigit[m[1]]}${_asmeSuffix(m[2]!)}');
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _asmeSuffix(String s) => switch (s) {
      'g r' || 'gr' => 'gr',
      'g' || 'gie' => 'g',
      _ => 'f',
    };

// ─── Liczby ──────────────────────────────────────────────────────────────────

const Map<String, int> _plainNumberWords = {
  // PL — jedności (mianownik i dopełniacz/miejscownik)
  'zero': 0, 'jeden': 1, 'jedna': 1, 'jedno': 1, 'jednego': 1, 'jednej': 1,
  'dwa': 2, 'dwie': 2, 'dwoch': 2, 'dwu': 2, 'trzy': 3, 'trzech': 3,
  'cztery': 4, 'czterech': 4, 'piec': 5, 'pieciu': 5, 'szesc': 6,
  'szesciu': 6, 'siedem': 7, 'siedmiu': 7, 'osiem': 8, 'osmiu': 8,
  'dziewiec': 9, 'dziewieciu': 9,
  // PL — nastki
  'dziesiec': 10, 'dziesieciu': 10, 'jedenascie': 11, 'jedenastu': 11,
  'dwanascie': 12, 'dwunastu': 12, 'trzynascie': 13, 'trzynastu': 13,
  'czternascie': 14, 'czternastu': 14, 'pietnascie': 15, 'pietnastu': 15,
  'szesnascie': 16, 'szesnastu': 16, 'siedemnascie': 17, 'siedemnastu': 17,
  'osiemnascie': 18, 'osiemnastu': 18, 'dziewietnascie': 19,
  'dziewietnastu': 19,
  // PL — dziesiątki
  'dwadziescia': 20, 'dwudziestu': 20, 'trzydziesci': 30, 'trzydziestu': 30,
  'czterdziesci': 40, 'czterdziestu': 40, 'piecdziesiat': 50,
  'piecdziesieciu': 50, 'szescdziesiat': 60, 'szescdziesieciu': 60,
  'siedemdziesiat': 70, 'siedemdziesieciu': 70, 'osiemdziesiat': 80,
  'osiemdziesieciu': 80, 'dziewiecdziesiat': 90, 'dziewiecdziesieciu': 90,
  // PL — setki
  'sto': 100, 'stu': 100, 'dwiescie': 200, 'dwustu': 200, 'trzysta': 300,
  'trzystu': 300, 'czterysta': 400, 'czterystu': 400, 'piecset': 500,
  'pieciuset': 500, 'szescset': 600, 'szesciuset': 600, 'siedemset': 700,
  'siedmiuset': 700, 'osiemset': 800, 'osmiuset': 800, 'dziewiecset': 900,
  'dziewieciuset': 900,
  // EN
  'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
  'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20,
  'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'seventy': 70,
  'eighty': 80, 'ninety': 90,
};

const Set<String> _hundredWords = {'hundred', 'hundreds'};
const Set<String> _thousandWords = {
  'tysiac', 'tysiaca', 'tysiace', 'tysiecy', 'thousand', 'thousands',
};
const Map<String, double> _standaloneFractions = {
  'poltora': 1.5,
  'poltorej': 1.5,
};
const Set<String> _decimalWords = {'przecinek', 'koma', 'point', 'comma'};
const Set<String> _quarterWords = {'czwarte', 'czwartych', 'czwarta'};

/// Jednostka „średnica drutu" (z żargonu „jedynka" = drut 1 mm). Do ścianki
/// nie pasuje; stary parser wpisuje ją do pola tylko przy MIG/MAG.
const String kWireUnit = 'mmdrut';

/// Żargon liczbowy: słowo → (liczba, jednostka).
const Map<String, (String, String)> _jargonNumbers = {
  'dwojka': ('2', 'mm'), 'dwojke': ('2', 'mm'), 'dwojki': ('2', 'mm'),
  'dwojeczka': ('2', 'mm'), 'dwojeczke': ('2', 'mm'),
  'jedynka': ('1', kWireUnit), 'jedynke': ('1', kWireUnit),
  'jedynki': ('1', kWireUnit),
};

bool _isNumberWord(String w) =>
    _plainNumberWords.containsKey(w) ||
    _hundredWords.contains(w) ||
    _thousandWords.contains(w);

final _digits = RegExp(r'^\d+(?:\.\d+)?$');
final _fracToken = RegExp(r'^frac(\d+(?:\.\d+)?)$');

/// Cale: „cal", „cala", „cale", „cali", „calowa", „inch", „inches".
bool isInchUnit(String w) =>
    w == 'cal' ||
    w == 'cala' ||
    w == 'cale' ||
    w == 'cali' ||
    w.startsWith('calow') ||
    w == 'inch' ||
    w == 'inches';

/// Element zdania po zwinięciu liczb: słowo albo liczba.
class SpokenItem {
  /// Słowo (dla liczby: „#").
  final String word;

  /// Wartość liczby (null dla słowa).
  final double? value;

  /// Surowy zapis cyframi (np. „141", „1.4404") — do rozpoznania kodów
  /// procesu i gatunku stali. Null dla liczb słownie.
  final String? raw;

  /// Ułamek (3/4, „trzy czwarte", „pół cala") — ma sens tylko z calami.
  final bool fraction;

  const SpokenItem.word(this.word)
      : value = null,
        raw = null,
        fraction = false;
  const SpokenItem.number(this.value, this.raw, {this.fraction = false})
      : word = '#';

  bool get isNumber => value != null;

  /// Liczba powiedziana słowami (nie cyframi, nie ułamek).
  bool get isSpoken => isNumber && raw == null && !fraction;

  /// Zapis tokenu: słowo albo liczba cyframi („45", „2.5", „1.4404").
  String get text {
    if (!isNumber) return word;
    if (raw != null) return raw!;
    final v = value!;
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  }

  @override
  String toString() => isNumber ? 'SpokenItem($value)' : 'SpokenItem($word)';
}

/// Słowa po zwinięciu, z rozbitymi sklejkami („60a", „2mm", „dn40", „fi60")
/// i żargonem liczbowym.
List<String> _wordTokens(String folded) {
  final out = <String>[];
  final withUnit = RegExp(r'^(\d+(?:\.\d+)?)(a|mm|lpm|amp\w*)$');
  final withPrefix = RegExp(r'^(dn|fi)(\d+(?:\.\d+)?)$');
  for (final t in folded.split(' ')) {
    if (t.isEmpty) continue;
    final jargon = _jargonNumbers[t];
    if (jargon != null) {
      out
        ..add(jargon.$1)
        ..add(jargon.$2);
      continue;
    }
    final u = withUnit.firstMatch(t);
    if (u != null) {
      out
        ..add(u[1]!)
        ..add(u[2]!);
      continue;
    }
    final p = withPrefix.firstMatch(t);
    if (p != null) {
      out
        ..add(p[1]!)
        ..add(p[2]!);
      continue;
    }
    out.add(t);
  }
  return out;
}

/// Elementy zdania ZWINIĘTEGO już przez [foldSpeech]: ciągi liczb słownych
/// złożone w jedną liczbę, ułamki i „półtora" jako liczby.
List<SpokenItem> spokenItems(String folded) {
  final t = _wordTokens(folded);
  final out = <SpokenItem>[];
  var i = 0;
  while (i < t.length) {
    final w = t[i];
    double? value;
    String? raw;
    var fraction = false;
    final frac = _fracToken.firstMatch(w);
    if (frac != null) {
      value = double.parse(frac[1]!);
      fraction = true;
      i++;
    } else if (_digits.hasMatch(w)) {
      value = double.parse(w);
      raw = w;
      i++;
    } else if (_standaloneFractions.containsKey(w)) {
      value = _standaloneFractions[w];
      i++;
    } else if (w == 'pol' && i + 1 < t.length && isInchUnit(t[i + 1])) {
      // „pół cala"
      value = 0.5;
      fraction = true;
      i++;
    } else if (_isNumberWord(w)) {
      final (v, next) = _readNumberWords(t, i);
      value = v;
      i = next;
    }
    if (value == null) {
      out.add(SpokenItem.word(w));
      i++;
      continue;
    }
    // „trzy czwarte" (cala)
    if (i < t.length && _quarterWords.contains(t[i]) && raw == null) {
      value = value / 4;
      fraction = true;
      i++;
    }
    // „i pół" / „and a half" / „and half" / „i ćwierć"
    if (i + 1 < t.length && t[i] == 'i' && t[i + 1] == 'pol') {
      value += 0.5;
      raw = null;
      i += 2;
    } else if (i + 1 < t.length && t[i] == 'i' && t[i + 1] == 'cwierc') {
      value += 0.25;
      raw = null;
      fraction = true;
      i += 2;
    } else if (i + 2 < t.length &&
        t[i] == 'and' &&
        t[i + 1] == 'a' &&
        t[i + 2] == 'half') {
      value += 0.5;
      raw = null;
      i += 3;
    } else if (i + 1 < t.length && t[i] == 'and' && t[i + 1] == 'half') {
      value += 0.5;
      raw = null;
      i += 2;
    } else if (i + 1 < t.length && _decimalWords.contains(t[i])) {
      // „trzy przecinek dwa" / „three point two" / „2 przecinek 77"
      double? decimals;
      var next = i + 1;
      if (_digits.hasMatch(t[next]) && !t[next].contains('.')) {
        decimals = double.parse('0.${t[next]}');
        next++;
      } else if (_plainNumberWords.containsKey(t[next])) {
        final (v, n) = _readNumberWords(t, next);
        final digits = v.toInt().toString();
        decimals = double.parse('0.$digits');
        next = n;
      }
      if (decimals != null) {
        value = value.truncateToDouble() + decimals;
        raw = null;
        i = next;
      }
    }
    out.add(SpokenItem.number(value, raw, fraction: fraction));
  }
  return out;
}

/// Czyta ciąg słów-liczb od [start]. Zwraca (wartość, indeks za ciągiem).
///
/// Słowa łączą się tylko w porządku malejących rzędów, jak w mowie:
/// setki + dziesiątki + jedności („sto dwadzieścia pięć" = 125), dziesiątki
/// + jedności („sixty five" = 65). „Dwa sześćdziesiąt" to DWIE liczby (2 i
/// 60), a nie 62.
(double, int) _readNumberWords(List<String> t, int start) {
  var total = 0.0;
  var current = 0.0;
  // Ostatnio dodane słowo-liczba bieżącej grupy (0 = grupa pusta).
  var last = 0;
  var i = start;
  while (i < t.length) {
    final w = t[i];
    final plain = _plainNumberWords[w];
    if (plain != null) {
      if (!_canFollow(last, plain, current)) break;
      current += plain;
      last = plain;
    } else if (_hundredWords.contains(w)) {
      if (last >= 100) break;
      current = (current == 0 ? 1 : current) * 100;
      last = 100;
    } else if (_thousandWords.contains(w)) {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
      last = 0;
    } else if (w == 'and' &&
        i + 1 < t.length &&
        _plainNumberWords.containsKey(t[i + 1]) &&
        i > start) {
      // „one hundred and ten" — ale nie „and a half"
    } else {
      break;
    }
    i++;
  }
  return (total + current, i);
}

/// Czy słowo o wartości [next] może dopełnić bieżącą grupę, w której ostatnio
/// padło [last] (a suma to [current]).
bool _canFollow(int last, int next, double current) {
  if (last == 0 && current == 0) return true;
  if (last >= 100) {
    // „sto dwadzieścia", „sto pięć", „dwieście jedenaście"
    return next < 100 && current % 100 == 0;
  }
  if (last >= 20 && last % 10 == 0) {
    // „sześćdziesiąt pięć"
    return next < 10 && next > 0;
  }
  return false; // po jednościach i nastkach nic się nie dokleja
}

/// Tokeny po zwinięciu; ciągi liczb słownych zamienione na cyfry
/// („czterdzieści pięć" → „45"); dwie liczby słowne obok siebie zostają
/// osobno („dwa sześćdziesiąt" → „2", „60"). „metr dwadzieścia" zostaje jako
/// „metr", „20" — długość składa `Utterance.lengthMm()`.
List<String> spokenTokens(String text) =>
    [for (final item in spokenItems(foldSpeech(text))) item.text];

/// Pierwsza liczba w tekście (cyframi albo słownie, PL/EN), albo null.
double? parseSpokenNumber(String text) {
  for (final item in spokenItems(foldSpeech(text))) {
    if (item.isNumber) return item.value;
  }
  return null;
}

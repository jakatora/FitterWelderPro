// Parser lokalny asystenta — deterministyczny, bez sieci, PL i EN naraz
// (monter w polskiej wersji też mówi „wall" czy „stick").
//
// Zamienia zdanie w propozycję: intencję z [kAssistantIntentsV1] i mapę pól.
// NIE waliduje (to robi assistant_validator.dart) i NIE zgaduje pól, których
// w zdaniu nie było — brak pola to pytanie, nie domysł. Jedyny wyjątek:
// wymiar w mm bez słowa-klucza trafia do ścianki (a drugi do średnicy), bo tak
// mówi się na budowie („TIG 2 mm 60 A"), a podsumowanie i tak pokazuje wynik
// przed zapisem.

import '../data/nps_dn_od_r.dart';
import 'assistant_intents.dart';

class AssistantProposal {
  final String intent;
  final Map<String, Object?> fields;
  const AssistantProposal(this.intent, this.fields);

  @override
  String toString() => 'AssistantProposal($intent, $fields)';
}

/// Rozpoznaje polecenie. Nigdy nie rzuca.
AssistantProposal parseAssistantCommand(String text) {
  final folded = _fold(text);
  if (folded.isEmpty) return const AssistantProposal(kIntentUnknown, {});

  if (_openAtStart.hasMatch(folded)) {
    final query = _openQuery(text);
    return AssistantProposal(
        kIntentOpenTool, {if (query.isNotEmpty) 'query': query});
  }

  final fields = _extractWeldFields(folded);
  final hasVerb = _saveVerb.hasMatch(folded);
  final looksLikeParam = (fields.containsKey('material') ||
          fields.containsKey('process')) &&
      (fields.containsKey('current_a') || fields.containsKey('wall_mm'));
  if (hasVerb || looksLikeParam) {
    return AssistantProposal(kIntentSaveWeldParameter, fields);
  }
  return const AssistantProposal(kIntentUnknown, {});
}

/// Pierwsza liczba w tekście (cyframi albo słownie, PL/EN), albo null.
double? parseSpokenNumber(String text) {
  for (final item in _items(_fold(text))) {
    if (item.isNumber) return item.value;
  }
  return null;
}

/// Odpowiedź na pytanie asystenta o JEDNO pole. Zwraca to pole (jeśli dało
/// się je odczytać) plus inne pola parametru, które padły przy okazji.
Map<String, Object?> parseFieldAnswer(String field, String text) {
  final folded = _fold(text);
  final out = <String, Object?>{..._extractWeldFields(folded)};
  if (out.containsKey(field)) return out;

  if (field == 'filler') {
    final tokens = folded.split(' ').toSet();
    if (tokens.intersection(const {'bez', 'without', 'nie', 'no'}).isNotEmpty) {
      out['filler'] = false;
    } else if (tokens
        .intersection(const {'z', 'ze', 'with', 'tak', 'yes'}).isNotEmpty) {
      out['filler'] = true;
    }
    return out;
  }
  if (kAssistantRanges.containsKey(field)) {
    final n = parseSpokenNumber(text);
    if (n != null) out[field] = n;
  }
  return out;
}

// ─── Normalizacja ────────────────────────────────────────────────────────────

const _plFold = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', //
  'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
};

/// Małe litery, bez polskich znaków, przecinek dziesiętny → kropka, reszta
/// interpunkcji → spacja. „l/min" → „lpm", „Ø"/„⌀" → „fi".
String _fold(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp('[ø⌀]'), ' fi ');
  // Tylko „60,3" bez spacji — „2, 60" to wyliczenie, nie ułamek.
  s = s.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m[1]}.${m[2]}');
  s = s.replaceAll(RegExp(r'\b(?:l|ltr|litr)\s*/\s*(?:min|m)\b'), ' lpm ');
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final folded = _plFold[c];
    if (folded != null) {
      buf.write(folded);
    } else if (RegExp(r'[a-z0-9]').hasMatch(c)) {
      buf.write(c);
    } else if (c == '.' &&
        i > 0 &&
        i + 1 < s.length &&
        RegExp(r'\d').hasMatch(s[i - 1]) &&
        RegExp(r'\d').hasMatch(s[i + 1])) {
      buf.write('.');
    } else {
      buf.write(' ');
    }
  }
  return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

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

bool _isNumberWord(String w) =>
    _plainNumberWords.containsKey(w) ||
    _hundredWords.contains(w) ||
    _thousandWords.contains(w);

final _digits = RegExp(r'^\d+(?:\.\d+)?$');

/// Element zdania po zwinięciu liczb: słowo albo liczba.
class _Item {
  final String word;
  final double? value;

  /// Surowy zapis cyframi (np. „141", „1.4404") — do rozpoznania kodów
  /// procesu i gatunku stali. Null dla liczb słownie.
  final String? raw;
  const _Item.word(this.word)
      : value = null,
        raw = null;
  const _Item.number(this.value, this.raw) : word = '#';

  bool get isNumber => value != null;
}

List<String> _tokens(String folded) {
  final out = <String>[];
  final withUnit = RegExp(r'^(\d+(?:\.\d+)?)(a|mm|lpm|amp|amps|ampy)$');
  final withPrefix = RegExp(r'^(dn|fi)(\d+(?:\.\d+)?)$');
  for (final t in folded.split(' ')) {
    if (t.isEmpty) continue;
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

List<_Item> _items(String folded) {
  final t = _tokens(folded);
  final out = <_Item>[];
  var i = 0;
  while (i < t.length) {
    final w = t[i];
    double? value;
    String? raw;
    if (_digits.hasMatch(w)) {
      value = double.parse(w);
      raw = w;
      i++;
    } else if (_standaloneFractions.containsKey(w)) {
      value = _standaloneFractions[w];
      i++;
    } else if (_isNumberWord(w)) {
      final (v, next) = _readNumberWords(t, i);
      value = v;
      i = next;
    }
    if (value == null) {
      out.add(_Item.word(w));
      i++;
      continue;
    }
    // „i pół" / „and a half" / „and half"
    if (i + 1 < t.length && t[i] == 'i' && t[i + 1] == 'pol') {
      value += 0.5;
      raw = null;
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
      double? frac;
      var next = i + 1;
      if (_digits.hasMatch(t[next]) && !t[next].contains('.')) {
        frac = double.parse('0.${t[next]}');
        next++;
      } else if (_plainNumberWords.containsKey(t[next])) {
        final (v, n) = _readNumberWords(t, next);
        final digits = v.toInt().toString();
        frac = double.parse('0.$digits');
        next = n;
      }
      if (frac != null) {
        value = value.truncateToDouble() + frac;
        raw = null;
        i = next;
      }
    }
    out.add(_Item.number(value, raw));
  }
  return out;
}

/// Czyta ciąg słów-liczb od [start]. Zwraca (wartość, indeks za ciągiem).
(double, int) _readNumberWords(List<String> t, int start) {
  var total = 0.0;
  var current = 0.0;
  var i = start;
  while (i < t.length) {
    final w = t[i];
    if (_plainNumberWords.containsKey(w)) {
      current += _plainNumberWords[w]!;
    } else if (_hundredWords.contains(w)) {
      current = (current == 0 ? 1 : current) * 100;
    } else if (_thousandWords.contains(w)) {
      total += (current == 0 ? 1 : current) * 1000;
      current = 0;
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

// ─── Jednostki i słowa-klucze ────────────────────────────────────────────────

bool _isAmpUnit(String w) =>
    w == 'a' ||
    w == 'amp' ||
    w == 'amps' ||
    w == 'ampy' ||
    w.startsWith('amper');

bool _isMmUnit(String w) =>
    w == 'mm' ||
    w == 'mili' ||
    w.startsWith('milimetr') ||
    w.startsWith('millimet');

bool _isFlowUnit(String w) =>
    w == 'lpm' ||
    w == 'l' ||
    w.startsWith('litr') ||
    w.startsWith('liter') ||
    w.startsWith('litre');

enum _Kw { wall, diameter, dn, electrode, current, flow }

_Kw? _keyword(String w) {
  if (w.startsWith('sciank') ||
      w.startsWith('grubos') ||
      w == 'wall' ||
      w == 'thickness') {
    return _Kw.wall;
  }
  if (w == 'dn') return _Kw.dn;
  if (w == 'fi' ||
      w.startsWith('rur') ||
      w.startsWith('srednic') ||
      w == 'pipe' ||
      w == 'tube' ||
      w == 'diameter' ||
      w == 'od') {
    return _Kw.diameter;
  }
  if (w.startsWith('elektrod') ||
      w.startsWith('wolfram') ||
      w == 'tungsten' ||
      w == 'electrode') {
    return _Kw.electrode;
  }
  if (w.startsWith('prad') ||
      w.startsWith('natezen') ||
      w == 'current' ||
      w == 'amperage') {
    return _Kw.current;
  }
  if (w.startsWith('przeplyw') || w == 'flow') return _Kw.flow;
  return null;
}

/// Słowa, które mogą stać między słowem-kluczem a liczbą („ścianka MA 2 mm",
/// „prąd NA 60").
const Set<String> _bridgeWords = {
  'na', 'ma', 'to', 'o', 'of', 'is', 'at', 'the', 'a', 'jest', 'wynosi',
  'rowna', 'okolo', 'about', 'ok', 'z', 'ze', 'w', 'we', 'mam', 'daje',
};

const Set<String> _processCodesMigMag = {'131', '135', '136', '138'};
const Set<String> _processCodesTig = {'141', '142'};
const Set<String> _processCodesMma = {'111'};
const Set<String> _materialCodes = {
  '316', '304', '321', '2205', '1.4301', '1.4307', '1.4404', '1.4571',
  '1.4462',
};

/// DN → OD wg ASME B36.10 / EN 10220 szereg 1 (ta sama tabela co „DN ↔ mm").
/// Nieznane DN → null (nie zgadujemy średnicy).
double? _odForDn(double dn) {
  if (dn != dn.roundToDouble()) return null;
  NpsRow? fallback;
  for (final r in kNpsTable) {
    if (r.dn != dn.round()) continue;
    if (r.series == OdSeries.asmeAndEn1 || r.series == OdSeries.asme) {
      return r.odMm;
    }
    fallback ??= r;
  }
  return fallback?.odMm;
}

// ─── Pola parametru spawania ─────────────────────────────────────────────────

Map<String, Object?> _extractWeldFields(String s) {
  final out = <String, Object?>{};
  final items = _items(s);

  final processHits = <String>{};
  final unlabelledMm = <double>[];

  for (var j = 0; j < items.length; j++) {
    final item = items[j];
    if (!item.isNumber) continue;
    final v = item.value!;
    final unit = j + 1 < items.length && !items[j + 1].isNumber
        ? items[j + 1].word
        : null;

    // Słowo-klucz przed liczbą: najbliższe, do 3 słów wstecz, bez przeskoku
    // przez inną liczbę. Słowa-mosty („na", „ma") nie liczą się do okna.
    _Kw? kw;
    var seen = 0;
    for (var k = j - 1; k >= 0 && seen < 3; k--) {
      final w = items[k];
      if (w.isNumber) break;
      final found = _keyword(w.word);
      if (found != null) {
        kw = found;
        break;
      }
      if (!_bridgeWords.contains(w.word)) seen++;
    }

    if (unit != null && _isAmpUnit(unit)) {
      out.putIfAbsent('current_a', () => v);
      continue;
    }
    if (unit != null && _isFlowUnit(unit)) {
      out.putIfAbsent('flow_lpm', () => v);
      continue;
    }
    if (unit != null && _isMmUnit(unit)) {
      // Po angielsku słowo-klucz stoi często ZA jednostką: „2 mm wall".
      if (kw == null && j + 2 < items.length) {
        final after = _keyword(items[j + 2].word);
        if (after == _Kw.wall || after == _Kw.diameter || after == _Kw.electrode) {
          kw = after;
        }
      }
      switch (kw) {
        case _Kw.wall:
          out.putIfAbsent('wall_mm', () => v);
        case _Kw.diameter:
          out.putIfAbsent('diameter_mm', () => v);
        case _Kw.dn:
          final od = _odForDn(v);
          if (od != null) out.putIfAbsent('diameter_mm', () => od);
        case _Kw.electrode:
          out.putIfAbsent('electrode_mm', () => v);
        case _Kw.current:
        case _Kw.flow:
        case null:
          unlabelledMm.add(v);
      }
      continue;
    }

    // Bez jednostki: najpierw prąd i przepływ nazwane wprost, potem kody
    // procesu i gatunku stali („141", „316"), dopiero potem pozostałe klucze.
    if (kw == _Kw.current) {
      out.putIfAbsent('current_a', () => v);
      continue;
    }
    if (kw == _Kw.flow) {
      out.putIfAbsent('flow_lpm', () => v);
      continue;
    }
    final raw = item.raw;
    if (raw != null) {
      if (_processCodesTig.contains(raw)) {
        processHits.add('TIG');
        continue;
      }
      if (_processCodesMigMag.contains(raw)) {
        processHits.add('MIG_MAG');
        continue;
      }
      if (_processCodesMma.contains(raw)) {
        processHits.add('MMA');
        continue;
      }
      if (_materialCodes.contains(raw)) continue;
    }
    switch (kw) {
      case _Kw.wall:
        out.putIfAbsent('wall_mm', () => v);
      case _Kw.diameter:
        out.putIfAbsent('diameter_mm', () => v);
      case _Kw.dn:
        final od = _odForDn(v);
        if (od != null) out.putIfAbsent('diameter_mm', () => od);
      case _Kw.electrode:
        out.putIfAbsent('electrode_mm', () => v);
      case _Kw.current:
      case _Kw.flow:
      case null:
        break;
    }
  }

  for (final v in unlabelledMm) {
    if (!out.containsKey('wall_mm') && v <= 50) {
      out['wall_mm'] = v;
    } else if (!out.containsKey('diameter_mm') && v >= 3) {
      out['diameter_mm'] = v;
    }
  }

  final material = _single(_materialPatterns, s);
  if (material != null) out['material'] = material;

  final process = _process(s, processHits);
  if (process != null) out['process'] = process;

  final filler = _filler(s);
  if (filler != null) {
    out['filler'] = filler;
  } else if (process == 'MIG_MAG' || process == 'MMA') {
    // Drut (MIG/MAG) i elektroda (MMA) same są spoiwem.
    out['filler'] = true;
  }

  final position = _position(s);
  if (position != null) out['position'] = position;

  final gas = _gas(s);
  if (gas != null) out['gas'] = gas;

  final joint = _single(_jointPatterns, s);
  if (joint != null) out['joint'] = joint;

  return out;
}

/// Jedyna kategoria, której wzorzec pasuje; dwie różne → null (niejasne).
String? _single(Map<String, RegExp> patterns, String s) {
  final hits = <String>{
    for (final e in patterns.entries)
      if (e.value.hasMatch(s)) e.key,
  };
  return hits.length == 1 ? hits.single : null;
}

final Map<String, RegExp> _materialPatterns = {
  'DUPLEX': RegExp(r'\b(?:super ?)?dupleks?\b|\bduplex\b|\b2205\b|\b1\.4462\b'),
  'AL': RegExp(r'\balumin\w*|\balu\b'),
  'OTHER': RegExp(
      r'\btytan\w*|\btitanium\b|\bmiedz\w*|\bcopper\b|\binconel\w*|\bhastelloy\w*|\bmonel\w*'),
  'SS': RegExp(r'\bnierdzew\w*|\b316l?\b|\b304l?\b|\b321\b|\b1\.4(?:301|307|404|571)\b|'
      r'\binox\b|\bkwasow\w*|\bkwasoodporn\w*|\bstainless\b|\bss\b|\baustenit\w*'),
  'CS': RegExp(r'\bczarn\w*|\bweglow\w*|\bcs\b|\bcarbon\b(?! dioxide)|\bs235\w*|'
      r'\bs355\w*|\bp235\w*|\bp265\w*|\ba106\w*|\bmild steel\b|\bblack steel\b|\bst ?37\b'),
};

final _tigRe = RegExp(r'\b(?:tig|wig|gtaw)\b');
final _migRe = RegExp(
    r'\b(?:mig|mag|gmaw|fcaw|migomat\w*|migowk\w*)\b|\bdrut\w* proszkow\w*|\bflux ?cor\w*');
final _mmaRe = RegExp(r'\b(?:mma|smaw|stick)\b|\botulon\w*');
final _electrodeWordRe = RegExp(r'\belektrod\w*|\belectrode\b');
final _tungstenRe = RegExp(r'\bwolfram\w*|\btungsten\b');

String? _process(String s, Set<String> fromCodes) {
  final hits = <String>{...fromCodes};
  if (_tigRe.hasMatch(s)) hits.add('TIG');
  if (_migRe.hasMatch(s)) hits.add('MIG_MAG');
  if (_mmaRe.hasMatch(s)) hits.add('MMA');
  // „Elektroda" sama w sobie oznacza MMA — chyba że mowa o TIG/MIG (wtedy to
  // wolfram albo drut) albo padło słowo „wolfram".
  if (hits.isEmpty && _electrodeWordRe.hasMatch(s) && !_tungstenRe.hasMatch(s)) {
    hits.add('MMA');
  }
  return hits.length == 1 ? hits.single : null;
}

final _noFillerRe = RegExp(
    r'\bbez (?:drutu|spoiwa|pret\w*|dodatk\w*|material\w*)|\bna sucho\b|\bautogen\w*|'
    r'\bwithout (?:filler|wire|rod)\b|\bno (?:filler|wire|rod)\b|\bfusion\b');
final _fillerRe = RegExp(
    r'\bz (?:drutem|pretem|dodatkiem|material\w*)|\bze spoiwem\b|'
    r'\bwith (?:filler|wire|rod)\b|\bfiller (?:wire|rod)\b');

bool? _filler(String s) {
  final no = _noFillerRe.hasMatch(s);
  final yes = _fillerRe.hasMatch(s);
  if (no == yes) return null;
  return yes;
}

String? _position(String s) {
  final code = RegExp(r'\b(6gr|[1-6]g|[1-4]f)\b').firstMatch(s);
  if (code != null) return code[1]!.toUpperCase();
  if (RegExp(r'\bh l ?045\b').hasMatch(s)) return 'H-L045';
  if (RegExp(r'\bj l ?045\b').hasMatch(s)) return 'J-L045';
  final iso = RegExp(r'\b(?:pozycj\w*|position|pos)\s+(p[a-hj])\b').firstMatch(s);
  if (iso != null) return iso[1]!.toUpperCase();
  final words = <String, RegExp>{
    'PF': RegExp(r'\bpionow\w* (?:w|pod) gore\b|\bpod gore\b|\buphill\b|\bvertical up\w*'),
    'PG': RegExp(r'\bpionow\w* (?:w|z) dol\b|\bz gory\b|\bdownhill\b|\bvertical down\w*'),
    'PA': RegExp(r'\bpodoln\w*|\bflat\b'),
    'PC': RegExp(r'\bnascienn\w*|\bhorizontal\b|\bpoziom\w*'),
    'PE': RegExp(r'\bpulapow\w*|\bsufitow\w*|\boverhead\b'),
  };
  return _single(words, s);
}

String? _gas(String s) {
  final ar = RegExp(r'\bargon\w*').hasMatch(s);
  final co2 =
      RegExp(r'\bco2\b|\bdwutlenek\w* wegl\w*|\bcarbon dioxide\b').hasMatch(s);
  final he = RegExp(r'\b(?:hel|helem|helu|helium)\b').hasMatch(s);
  final h2 = RegExp(r'\bwodor\w*|\bhydrogen\b|\bh2\b').hasMatch(s);
  final n2 = RegExp(r'\bazot\w*|\bnitrogen\b|\bn2\b').hasMatch(s);
  final m21 = RegExp(r'\bm21\b|\bmieszank\w*|\bmix\w*|\bcorgon\w*').hasMatch(s);
  if (m21 || (ar && co2)) return 'M21';
  if (he) return 'AR_HE';
  if (ar && h2) return 'AR_H2';
  if (co2) return 'CO2';
  if (n2) return 'N2';
  if (ar) return 'AR';
  return null;
}

final Map<String, RegExp> _jointPatterns = {
  'BUTT': RegExp(r'\bdoczolow\w*|\bbutt\b|\bna styk\b'),
  'FILLET': RegExp(r'\bpachwin\w*|\bfillet\b'),
  'SOCKET': RegExp(r'\bmufow\w*|\bmuf[aey]?\b|\bsocket\b|\bkielich\w*'),
  'BRANCH': RegExp(r'\bodgalezien\w*|\bkrocc\w*|\bkrociec\b|\bbranch\b|\bsiodl\w*|\bsaddle\b'),
};

// ─── Intencje ────────────────────────────────────────────────────────────────

final _openAtStart = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:otworz|pokaz|uruchom|wlacz|przejdz do|idz do|open|show|launch|start|go to|take me to)\b');

final _saveVerb = RegExp(
    r'\b(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|save|store|remember|record|add|log)\b');

/// Zapytanie dla `open_tool` z ORYGINALNEGO tekstu (z polskimi znakami —
/// wyszukiwarka narzędzi i tak je zwija), bez czasownika i grzeczności.
String _openQuery(String text) {
  var q = text.toLowerCase().trim();
  const sep = r'[\s,.:!?]+';
  final lead = RegExp(
      '^(?:(?:proszę|prosze|please|hej|hey|ok|okej|asystencie|asystent)$sep)*'
      '(?:otwórz|otworz|pokaż|pokaz|uruchom|włącz|wlacz|przejdź do|przejdz do|'
      'idź do|idz do|open|show|launch|start|go to|take me to)(?=[\\s,.:!?]|\$)'
      '[\\s,.:!?]*'
      '(?:(?:mi|me|the|proszę|prosze|please)$sep)*');
  q = q.replaceFirst(lead, '');
  q = q.replaceFirst(RegExp(r'[\s,.:!?]+$'), '');
  q = q.replaceFirst(RegExp(r'[\s,]+(?:proszę|prosze|please)$'), '');
  return q.trim();
}

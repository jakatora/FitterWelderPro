// Parser lokalny asystenta — deterministyczny, bez sieci, PL i EN naraz
// (monter w polskiej wersji też mówi „wall" czy „stick").
//
// Zamienia zdanie w propozycję: intencję z [kAssistantIntents] i mapę pól.
// NIE waliduje (to robi assistant_validator.dart) i NIE zgaduje pól, których
// w zdaniu nie było — brak pola to pytanie, nie domysł. Jedyny wyjątek:
// wymiar w mm bez słowa-klucza trafia do ścianki (a drugi do średnicy), bo tak
// mówi się na budowie („TIG 2 mm 60 A"), a podsumowanie i tak pokazuje wynik
// przed zapisem.
//
// „Brudna mowa" (rozpoznawanie mowy w hałasie, żargon): zasada nadrzędna —
// NIGDY cichy zły wynik. Co jest niejednoznaczne, zostaje puste i walidator
// o to dopyta:
//   • dwie liczby słownie obok siebie („ścianka dwa sześćdziesiąt") to dwie
//     liczby, nie 62 — a gdy nie wiadomo, do których pól należą, żadna nie
//     trafia do pola;
//   • ułamek („3/4", „trzy czwarte") tylko z calami, i to jako rozmiar rury
//     NPS → średnica, nigdy ścianka;
//   • pozycje literowane przez rozpoznawanie mowy („pe ef" = PF, „ha el zero
//     czterdzieści pięć" = H-L045, „5 G" = 5G);
//   • formowanie („formowanie 5 l", „gaz formujący azot") to osobne pole,
//     nie przepływ i gaz na palnik;
//   • żargon: „ampów/ampy", „na setkę" (100 A), „dwójka" (2 mm), „jedynka"
//     (drut 1 mm — tylko przy MIG/MAG), „tik", „argonówka", „nierdzewka",
//     „czarna", „elektroda".
//
// Zwijanie tekstu, żargon liczbowy i liczby słownie są we wspólnym
// core/spoken_numbers.dart (ten sam tokenizer ma mózg asystenta), a DN/NPS →
// OD w lib/domain/fitter/pipe_size_lookup.dart.

import '../domain/fitter/pipe_size_lookup.dart';
import '../i18n/app_language.dart';
import 'assistant_intents.dart';
import 'core/spoken_numbers.dart';
import 'core/command_words.dart' show referencesInstruction;
import 'core/utterance.dart';

export 'core/spoken_numbers.dart' show parseSpokenNumber;

class AssistantProposal {
  final String intent;
  final Map<String, Object?> fields;
  const AssistantProposal(this.intent, this.fields);

  @override
  String toString() => 'AssistantProposal($intent, $fields)';
}

/// Rozpoznaje polecenie. Nigdy nie rzuca.
AssistantProposal parseAssistantCommand(String text) {
  final folded = foldSpeech(text);
  if (folded.isEmpty) return const AssistantProposal(kIntentUnknown, {});
  if (referencesInstruction(Utterance(text, lang: AppLanguage.pl))) {
    return AssistantProposal(kIntentAnswerQuestion, {'text': text.trim()});
  }

  // „Jaki prąd mam zapisany na…", „pokaż moje parametry…" — odczyt lokalny.
  if (!_hardOpenAtStart.hasMatch(folded) && _myParamsRe.hasMatch(folded)) {
    final all = _extractWeldFields(folded);
    final allowed = kAssistantIntents[kIntentQueryMyParams]!.allFields;
    return AssistantProposal(kIntentQueryMyParams, {
      for (final e in all.entries)
        if (allowed.contains(e.key)) e.key: e.value,
    });
  }

  if (_openAtStart.hasMatch(folded)) {
    final query = _openQuery(text);
    return AssistantProposal(
        kIntentOpenTool, {if (query.isNotEmpty) 'query': query});
  }

  if (_isJournalCommand(text, folded)) {
    return AssistantProposal(kIntentAddWeldJournalEntry, _journalFields(text));
  }

  if (_isQuestion(text, folded)) {
    return AssistantProposal(kIntentAnswerQuestion, {'text': text.trim()});
  }

  final fields = _extractWeldFields(folded);
  final hasVerb = _saveVerb.hasMatch(folded);
  final looksLikeParam =
      (fields.containsKey('material') || fields.containsKey('process')) &&
          (fields.containsKey('current_a') || fields.containsKey('wall_mm'));
  if (hasVerb || looksLikeParam) {
    return AssistantProposal(kIntentSaveWeldParameter, fields);
  }
  return const AssistantProposal(kIntentUnknown, {});
}

/// Odpowiedź na pytanie asystenta o JEDNO pole. Zwraca to pole (jeśli dało
/// się je odczytać) plus inne pola, które padły przy okazji. Niejasna
/// odpowiedź („dwa sześćdziesiąt" na pytanie o ściankę) nie daje pola —
/// asystent zapyta jeszcze raz.
Map<String, Object?> parseFieldAnswer(String field, String text) {
  switch (field) {
    case 'weld_no':
      final no = _weldNoFrom('spoina $text') ?? _weldNoFrom(text);
      return {if (no != null) 'weld_no': no};
    case 'project':
      final p = _cleanFreeText(text.replaceFirst(
          RegExp(r'^\s*(?:do\s+)?(?:projekt\S*|project)\s*[:\-]?\s*',
              caseSensitive: false),
          ''));
      return {if (p != null) 'project': p};
    case 'wps':
      final w = _wpsFrom('WPS $text');
      return {if (w != null) 'wps': w};
    case 'text':
      final t = text.trim();
      return {if (t.isNotEmpty) 'text': t};
  }

  final folded = foldSpeech(text);
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
    // Sama liczba („60", „dwa przecinek pięć") trafia w pytane pole — ale
    // tylko JEDNA, nie ułamek i bez jednostki innego pola (odpowiedź „20 A"
    // na pytanie o ściankę to nie ścianka 20 mm).
    final items = spokenItems(folded);
    final numbers = [
      for (var i = 0; i < items.length; i++)
        if (items[i].isNumber) i,
    ];
    if (numbers.length != 1) return out;
    final i = numbers.single;
    final item = items[i];
    if (item.fraction) return out;
    final unit = i + 1 < items.length && !items[i + 1].isNumber
        ? items[i + 1].word
        : null;
    if (unit != null && !_unitFitsField(unit, field)) return out;
    out[field] = item.value;
  }
  return out;
}

bool _unitFitsField(String unit, String field) {
  final isUnit = _isAmpUnit(unit) ||
      _isMmUnit(unit) ||
      _isFlowUnit(unit) ||
      isInchUnit(unit) ||
      unit == kWireUnit;
  if (!isUnit) return true; // zwykłe słowo po liczbie
  return switch (field) {
    'current_a' => _isAmpUnit(unit),
    'wall_mm' || 'diameter_mm' || 'electrode_mm' => _isMmUnit(unit),
    'flow_lpm' || 'purge_lpm' => _isFlowUnit(unit),
    _ => false,
  };
}

// ─── Jednostki i słowa-klucze ────────────────────────────────────────────────

bool _isAmpUnit(String w) => w == 'a' || w.startsWith('amp');

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

enum _Kw { wall, diameter, dn, electrode, current, flow, purge }

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
  if (w.startsWith('formow') ||
      w.startsWith('formuj') ||
      w.startsWith('purg') ||
      w == 'backing') {
    return _Kw.purge;
  }
  if (w.startsWith('przeplyw') ||
      w == 'flow' ||
      w.startsWith('palnik') ||
      w == 'torch') {
    return _Kw.flow;
  }
  return null;
}

/// Słowa, które mogą stać między słowem-kluczem a liczbą („ścianka MA 2 mm",
/// „prąd NA 60").
const Set<String> _bridgeWords = {
  'na',
  'ma',
  'to',
  'o',
  'of',
  'is',
  'at',
  'the',
  'a',
  'jest',
  'wynosi',
  'rowna',
  'okolo',
  'about',
  'ok',
  'z',
  'ze',
  'w',
  'we',
  'mam',
  'daje',
};

const Set<String> _processCodesMigMag = {'131', '135', '136', '138'};
const Set<String> _processCodesTig = {'141', '142'};
const Set<String> _processCodesMma = {'111'};
const Set<String> _materialCodes = {
  '316',
  '304',
  '321',
  '2205',
  '1.4301',
  '1.4307',
  '1.4404',
  '1.4571',
  '1.4462',
};

/// DN → OD serii głównej (ta sama tabela co „DN ↔ mm"). Nieznane albo
/// ułamkowe DN → null (nie zgadujemy średnicy).
double? _odForDn(double dn) =>
    dn == dn.roundToDouble() ? odForDn(dn.round()) : null;

// ─── Pola parametru spawania ─────────────────────────────────────────────────

/// Słowo-klucz przed liczbą [j]: najbliższe, do 3 słów wstecz, bez przeskoku
/// przez inną liczbę. Słowa-mosty („na", „ma") nie liczą się do okna.
/// Formowanie w oknie wygrywa ze zwykłym „przepływ" („przepływ formujący 5").
_Kw? _keywordBefore(List<SpokenItem> items, int j) {
  _Kw? found;
  var seen = 0;
  for (var k = j - 1; k >= 0 && seen < 3; k--) {
    final w = items[k];
    if (w.isNumber) break;
    final kw = _keyword(w.word);
    if (kw == _Kw.purge) return _Kw.purge;
    if (kw != null) {
      if (kw != _Kw.flow) return found ?? kw;
      found ??= kw;
    }
    if (!_bridgeWords.contains(w.word)) seen++;
  }
  return found;
}

/// Rodzaj pola, na który wskazuje jednostka ('current', 'flow', 'length').
String? _unitKind(String? unit) {
  if (unit == null) return null;
  if (_isAmpUnit(unit)) return 'current';
  if (_isFlowUnit(unit)) return 'flow';
  if (_isMmUnit(unit) || isInchUnit(unit) || unit == kWireUnit) {
    return 'length';
  }
  return null;
}

String? _kwKind(_Kw? kw) => switch (kw) {
      _Kw.wall || _Kw.diameter || _Kw.dn || _Kw.electrode => 'length',
      _Kw.current => 'current',
      _Kw.flow || _Kw.purge => 'flow',
      null => null,
    };

String? _unitAfter(List<SpokenItem> items, int j) =>
    j + 1 < items.length && !items[j + 1].isNumber ? items[j + 1].word : null;

/// Indeksy liczb niejednoznacznych: dwie liczby słownie obok siebie, których
/// nie da się rozdzielić na dwa RÓŻNE pola („ścianka dwa sześćdziesiąt" —
/// 2 i 60 czy 2,60?). Wyjątek: „ścianka dwa sześćdziesiąt amper" — pierwsza
/// ma klucz ścianki, druga jednostkę prądu, więc to dwa pola.
Set<int> _ambiguousNumbers(List<SpokenItem> items) {
  final out = <int>{};
  for (var j = 0; j + 1 < items.length; j++) {
    final a = items[j];
    final b = items[j + 1];
    if (!a.isSpoken || !b.isSpoken) continue;
    final kindA =
        _unitKind(_unitAfter(items, j)) ?? _kwKind(_keywordBefore(items, j));
    final kindB = _unitKind(_unitAfter(items, j + 1));
    if (kindA == null) continue; // pierwsza i tak do niczego nie trafi
    if (kindB != null && kindB != kindA) continue;
    out
      ..add(j)
      ..add(j + 1);
  }
  return out;
}

Map<String, Object?> _extractWeldFields(String s) {
  final out = <String, Object?>{};
  final items = spokenItems(s);
  final ambiguous = _ambiguousNumbers(items);

  final processHits = <String>{};
  final unlabelledMm = <double>[];
  final wireMm = <double>[];

  for (var j = 0; j < items.length; j++) {
    final item = items[j];
    if (!item.isNumber || ambiguous.contains(j)) continue;
    final v = item.value!;
    final unit = _unitAfter(items, j);
    var kw = _keywordBefore(items, j);

    if (unit != null && isInchUnit(unit)) {
      // Cale na budowie = rozmiar rury NPS → średnica zewnętrzna. Nigdy
      // ścianka („3/4 cala" to nie 3 mm).
      if (kw != _Kw.current && kw != _Kw.flow && kw != _Kw.purge) {
        final od = odForNps(v);
        if (od != null) out.putIfAbsent('diameter_mm', () => od);
      }
      continue;
    }
    // Ułamek bez cali — nie wiadomo, co to jest.
    if (item.fraction) continue;
    if (unit == kWireUnit) {
      wireMm.add(v);
      continue;
    }
    if (unit != null && _isAmpUnit(unit)) {
      out.putIfAbsent('current_a', () => v);
      continue;
    }
    if (unit != null && _isFlowUnit(unit)) {
      if (kw == _Kw.purge) {
        out.putIfAbsent('purge_lpm', () => v);
      } else {
        out.putIfAbsent('flow_lpm', () => v);
      }
      continue;
    }
    if (unit != null && _isMmUnit(unit)) {
      // Po angielsku słowo-klucz stoi często ZA jednostką: „2 mm wall".
      if (kw == null && j + 2 < items.length) {
        final after = _keyword(items[j + 2].word);
        if (after == _Kw.wall ||
            after == _Kw.diameter ||
            after == _Kw.electrode) {
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
        case _Kw.purge:
        case null:
          unlabelledMm.add(v);
      }
      continue;
    }

    // Bez jednostki: najpierw prąd i przepływy nazwane wprost, potem kody
    // procesu i gatunku stali („141", „316"), dopiero potem pozostałe klucze.
    if (kw == _Kw.current) {
      out.putIfAbsent('current_a', () => v);
      continue;
    }
    if (kw == _Kw.flow) {
      out.putIfAbsent('flow_lpm', () => v);
      continue;
    }
    if (kw == _Kw.purge) {
      out.putIfAbsent('purge_lpm', () => v);
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
      case _Kw.purge:
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

  // „Jedynka" = drut 1 mm: przy MIG/MAG drut JEST elektrodą (średnica
  // drutu). Przy TIG / MMA / nieznanej metodzie nie zgadujemy.
  if (process == 'MIG_MAG' && wireMm.isNotEmpty) {
    out.putIfAbsent('electrode_mm', () => wireMm.first);
  }

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
  'SS': RegExp(
      r'\bnierdzew\w*|\b316l?\b|\b304l?\b|\b321\b|\b1\.4(?:301|307|404|571)\b|'
      r'\binox\b|\bkwasow\w*|\bkwasoodporn\w*|\bstainless\b|\bss\b|\baustenit\w*'),
  'CS': RegExp(
      r'\bczarn\w*|\bweglow\w*|\bcs\b|\bcarbon\b(?! dioxide)|\bs235\w*|'
      r'\bs355\w*|\bp235\w*|\bp265\w*|\ba106\w*|\bmild steel\b|\bblack steel\b|\bst ?37\b'),
};

// „tik"/„tyk" — tak rozpoznawanie mowy zapisuje „TIG"; „argonówka" = TIG.
final _tigRe = RegExp(r'\b(?:tig|tik|tyk|tick|wig|gtaw|argonowk\w*)\b');
final _migRe = RegExp(
    r'\b(?:mig|mag|migiem|magiem|gmaw|fcaw|migomat\w*|migowk\w*|magowk\w*)\b|'
    r'\bdrut\w* proszkow\w*|\bflux ?cor\w*');
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
  if (hits.isEmpty &&
      _electrodeWordRe.hasMatch(s) &&
      !_tungstenRe.hasMatch(s)) {
    hits.add('MMA');
  }
  return hits.length == 1 ? hits.single : null;
}

final _noFillerRe = RegExp(
    r'\bbez (?:drutu|spoiwa|pret\w*|dodatk\w*|material\w*)|\bna sucho\b|\bautogen\w*|'
    r'\bwithout (?:filler|wire|rod)\b|\bno (?:filler|wire|rod)\b|\bfusion\b');
final _fillerRe =
    RegExp(r'\bz (?:drutem|pretem|dodatkiem|material\w*)|\bze spoiwem\b|'
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
  if (RegExp(r'\bh ?l ?045\b').hasMatch(s)) return 'H-L045';
  if (RegExp(r'\bj ?l ?045\b').hasMatch(s)) return 'J-L045';
  final iso =
      RegExp(r'\b(?:pozycj\w*|position|pos)\s+(p[a-hj])\b').firstMatch(s);
  if (iso != null) return iso[1]!.toUpperCase();
  // Sam kod bez słowa „pozycja" — tylko jednoznaczne (nie „pa"/„pe").
  final bare = RegExp(r'\b(p[bcdfghj])\b').firstMatch(s);
  if (bare != null) return bare[1]!.toUpperCase();
  final words = <String, RegExp>{
    'PF': RegExp(
        r'\bpionow\w* (?:w|pod) gore\b|\bpod gore\b|\buphill\b|\bvertical up\w*'),
    'PG': RegExp(
        r'\bpionow\w* (?:w|z) dol\b|\bz gory\b|\bdownhill\b|\bvertical down\w*'),
    'PA': RegExp(r'\bpodoln\w*|\bflat\b'),
    'PC': RegExp(r'\bnascienn\w*|\bhorizontal\b|\bpoziom\w*'),
    'PE': RegExp(r'\bpulapow\w*|\bsufitow\w*|\boverhead\b'),
  };
  return _single(words, s);
}

/// Gaz formujący („formowanie azotem", „gaz formujący argon") to NIE gaz na
/// palnik — wycinamy go przed rozpoznaniem gazu osłonowego.
final _purgeGasRe = RegExp(
    r'\b(?:formowan\w*|formujac\w*|purg\w*|backing)\s+(?:gaz\w*\s+)?'
    r'(?:argon\w*|azot\w*|n2|formier\w*|forming gas|wodor\w*|h2|mieszank\w*)\b|'
    r'\bgaz\w* formujac\w*(?:\s+(?:argon\w*|azot\w*|n2|formier\w*|wodor\w*|h2))?');

String? _gas(String input) {
  final s = input.replaceAll(_purgeGasRe, ' ');
  final ar = RegExp(r'\bargon(?!owk)\w*').hasMatch(s);
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
  'BRANCH': RegExp(
      r'\bodgalezien\w*|\bkrocc\w*|\bkrociec\b|\bbranch\b|\bsiodl\w*|\bsaddle\b'),
};

// ─── Intencje ────────────────────────────────────────────────────────────────

final _openAtStart = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:otworz|pokaz|uruchom|wlacz|przejdz do|idz do|open|show|launch|start|go to|take me to)\b');

/// Otwarcie wprost (bez „pokaż") — „otwórz moje parametry" to nawigacja.
final _hardOpenAtStart = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:otworz|uruchom|wlacz|przejdz do|idz do|open|launch|start|go to|take me to)\b');

final _saveVerb = RegExp(
    r'\b(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|save|store|remember|record|add|log)\b');

final _saveVerbAtStart = RegExp(
    r'^(?:(?:prosze|please|hej|hey|ok|okej|asystencie|asystent)\s+)*'
    r'(?:zapisz|zapamietaj|zanotuj|dodaj|dopisz|wpisz|save|store|remember|record|add|log)\b');

/// Odczyt moich zapisów: „mam zapisany", „moje parametry", „what did I save".
final _myParamsRe = RegExp(
    r'\bmam (?:zapisan\w*|zapamietan\w*|w parametrach|w moich\w*|parametr\w*)|'
    r'\bmoje (?:parametr\w*|zapis\w*)|\bmoich (?:parametr\w*|zapis\w*)|'
    r'\bzapisal(?:em|am)\b|\bmy (?:saved|param\w*)\b|\bi saved\b|'
    r'\bhave i saved\b|\bdid i save\b');

/// Pytanie wiedzowe na początku zdania.
final _questionStart = RegExp(
    r'^(?:(?:a|i|hej|hey|ok|okej|asystencie|asystent|powiedz|powiedz mi|prosze|'
    r'please|tell me|and|so)\s+)*'
    r'(?:jak\w*|ile|czy|co|kiedy|dlaczego|czemu|gdzie|ktor\w*|po co|'
    r'what\w*|how|which|why|when|where|is|are|does|can|should)\b');

/// Czasowniki rozkazujące, po których to polecenie, nie pytanie („czy możesz
/// zapisać…" jest poleceniem).
final _commandVerbAnywhere = RegExp(
    r'\b(?:zapisz|zapisac|zapamietaj|zapamietac|dodaj|dodac|dopisz|dopisac|'
    r'wpisz|wpisac|zanotuj|zanotowac|save|store|remember|record)\b');

bool _isQuestion(String original, String folded) {
  if (_saveVerbAtStart.hasMatch(folded)) return false;
  if (original.trim().endsWith('?')) return true;
  if (_commandVerbAnywhere.hasMatch(folded)) return false;
  return _questionStart.hasMatch(folded);
}

// ─── Dziennik spoin ──────────────────────────────────────────────────────────

final _journalVerb = RegExp(
    r'\b(?:dopisz|dodaj|wpisz|zapisz|zaloguj|zarejestruj|zanotuj|add|log|record|register)\b');
final _journalWord = RegExp(r'\bdziennik\w*|\bjournal\b|\bweld log\b');

bool _isJournalCommand(String original, String folded) {
  if (!_journalVerb.hasMatch(folded)) return false;
  return _journalWord.hasMatch(folded) || _weldNoFrom(original) != null;
}

Map<String, Object?> _journalFields(String original) {
  final no = _weldNoFrom(original);
  final project = _projectFrom(original);
  final wps = _wpsFrom(original);
  return {
    if (no != null) 'weld_no': no,
    if (project != null) 'project': project,
    if (wps != null) 'wps': wps,
  };
}

/// Numer spoiny po „spoina"/„weld"/„numer"/„nr": „12", „W-12", „12a",
/// „S1-W3", albo słownie („spoinę dwanaście"). Null, gdy go nie ma.
String? _weldNoFrom(String original) {
  final m = RegExp(
    r'(?:^|[\s,;:(])(?:spoin\S*|weld|numer\S*|nr\.?|no\.|number)\s+'
    r'(?:(?:numer\S*|nr\.?|no\.?|number)\s+)?'
    r'([A-Za-z]{0,3}[-/]?\d+[A-Za-z]{0,2}(?:[-/][A-Za-z]{0,3}\d+[A-Za-z]{0,2})?)(?=$|[\s,;:.)])',
    caseSensitive: false,
  ).firstMatch(original);
  if (m != null) {
    final no = m[1]!.toUpperCase();
    // „fillet weld 2F", „spoina 6G" — to pozycja, nie numer spoiny.
    if (!RegExp(r'^(?:[1-6]GR?|[1-4]F)$').hasMatch(no)) return no;
  }

  // Słownie: „spoinę dwanaście", „spoina numer sto dwa".
  final folded = foldSpeech(original);
  final items = spokenItems(folded);
  for (var i = 0; i < items.length; i++) {
    final w = items[i];
    if (w.isNumber) continue;
    final isRef = w.word.startsWith('spoin') ||
        w.word == 'weld' ||
        w.word.startsWith('numer') ||
        w.word == 'nr';
    if (!isRef) continue;
    var k = i + 1;
    while (k < items.length &&
        !items[k].isNumber &&
        (items[k].word.startsWith('numer') || items[k].word == 'nr')) {
      k++;
    }
    if (k < items.length && items[k].isNumber && !items[k].fraction) {
      final v = items[k].value!;
      if (v == v.roundToDouble() && v > 0 && v < 100000) {
        return v.toInt().toString();
      }
    }
  }
  return null;
}

/// Tekst po „projekt"/„project" do przecinka, kropki na końcu albo kolejnego
/// słowa-klucza (WPS, spoina, numer, dziennik).
String? _projectFrom(String original) {
  final m = RegExp(r'(?:^|\s)(?:projekt\S*|project)\s*[:\-]?\s*',
          caseSensitive: false)
      .firstMatch(original);
  if (m == null) return null;
  var rest = original.substring(m.end);
  final stop = RegExp(
    r'[,;]|\swps(?=$|[\s,;:.\-/])|\s(?:spawacz\S*|welder|spoin\S*|weld|numer\S*|nr\.?|do\s+dziennik\S*|dziennik\S*|to\s+(?:the\s+)?(?:journal|log))(?=$|[\s,;:.])',
    caseSensitive: false,
  ).firstMatch(rest);
  if (stop != null) rest = rest.substring(0, stop.start);
  return _cleanFreeText(rest);
}

/// Numer WPS po „WPS": „WPS 141-01", „WPS nr 7". Musi mieć cyfrę.
String? _wpsFrom(String original) {
  final m = RegExp(
    r'\bwps\b\s*(?:nr\.?|numer|number|no\.?)?\s*[:\-]?\s*'
    r'([A-Za-z0-9][A-Za-z0-9._/\-]*(?:\s*[-/]\s*[A-Za-z0-9]+)*)',
    caseSensitive: false,
  ).firstMatch(original);
  if (m == null) return null;
  final v = m[1]!
      .replaceAll(RegExp(r'\s+'), '')
      .replaceFirst(RegExp(r'[.\-/]+$'), '');
  if (!RegExp(r'\d').hasMatch(v) || v.length > kAssistantTextLimits['wps']!) {
    return null;
  }
  return v.toUpperCase();
}

/// Krótki tekst wolny (nazwa projektu): bez skrajnej interpunkcji i
/// podwójnych spacji; pusty albo za długi → null.
String? _cleanFreeText(String raw) {
  final t = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,.;:\-–„"”]+|[\s,.;:\-–„"”!?]+$'), '')
      .trim();
  if (t.isEmpty || t.length > kAssistantTextLimits['project']!) return null;
  return t;
}

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

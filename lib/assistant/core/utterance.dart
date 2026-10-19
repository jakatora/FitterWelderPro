// Wypowiedź użytkownika dla mózgu asystenta (spec §4.1).
//
// Jedno miejsce, w którym tekst z mikrofonu albo klawiatury zamienia się
// w wielkości: DN, NPS w calach, długość w mm, kąt, liczba przy słowie-kluczu.
// Normalizacja jest wspólna ze starym parserem (spoken_numbers.dart), więc
// „dwa sześćdziesiąt" to nadal dwie liczby, a „rura setka" to DN100.
//
// Zasada: niejasne → null (umiejętność dopyta), NIGDY cichy zły wynik.
// Przykład: „dn 4 0" (cyfry dyktowane osobno) to 40 czy 4? → [dn] daje null,
// a [mentionsDn] mówi, że DN padło — umiejętność zapyta o rozmiar.

import '../../i18n/app_language.dart';
import 'spoken_numbers.dart';

const _plFold = {
  'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', //
  'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
};

/// Zwija frazę-wzorzec tak jak wypowiedź (małe litery, bez polskich znaków,
/// interpunkcja → spacja) — ale BEZ żargonu i liczb, żeby wzorzec nie zmienił
/// sensu.
String _foldPattern(String p) => _patternCache[p] ??= _foldPatternRaw(p);

/// Wzorce to stałe w kodzie umiejętności — zwijamy każdy raz.
final Map<String, String> _patternCache = {};

final _alnum = RegExp(r'[a-z0-9]');
final _spaces = RegExp(r'\s+');

String _foldPatternRaw(String p) {
  final buf = StringBuffer();
  for (final c in p.toLowerCase().split('')) {
    final f = _plFold[c] ?? c;
    buf.write(_alnum.hasMatch(f) ? f : ' ');
  }
  return buf.toString().replaceAll(_spaces, ' ').trim();
}

/// Słowa, które mogą stać między słowem-kluczem a liczbą („prąd NA 90",
/// „ścianka MA 2 mm").
const Set<String> _bridgeWords = {
  'na', 'ma', 'to', 'o', 'of', 'is', 'at', 'the', 'a', 'jest', 'wynosi',
  'rowna', 'okolo', 'about', 'ok', 'z', 'ze', 'w', 'we', 'mam', 'daje',
};

bool _isMmWord(String w) =>
    w == 'mm' ||
    w == 'mili' ||
    w.startsWith('milimetr') ||
    w.startsWith('millimet');

bool _isCmWord(String w) =>
    w == 'cm' || w.startsWith('centymetr') || w.startsWith('centimet');

bool _isMeterWord(String w) =>
    w == 'm' ||
    w.startsWith('metr') ||
    w == 'meter' ||
    w == 'meters' ||
    w == 'metre' ||
    w == 'metres';

/// Pojedyncze „metr" („rura metr", „metr dwadzieścia") = 1 m.
bool _isSingleMeterWord(String w) =>
    w == 'metr' || w == 'meter' || w == 'metre';

bool _isDegreeWord(String w) =>
    w.startsWith('stopn') ||
    w.startsWith('stopie') ||
    w == 'st' ||
    w == 'deg' ||
    w.startsWith('degree');

/// Jednostki, po których liczba NIE jest ani DN, ani długością bez jednostki.
bool _isOtherUnit(String w) =>
    w == 'a' ||
    w.startsWith('amp') ||
    w == 'v' ||
    w.startsWith('volt') ||
    w == 'bar' ||
    w.startsWith('bar') ||
    w == 'kg' ||
    w == 't' ||
    w.startsWith('ton') ||
    w == 'lpm' ||
    w.startsWith('litr') ||
    w == 'proc' ||
    w.startsWith('procent') ||
    w.startsWith('percent') ||
    w == kWireUnit;

bool _isAnyUnit(String w) =>
    _isMmWord(w) ||
    _isCmWord(w) ||
    _isMeterWord(w) ||
    isInchUnit(w) ||
    _isDegreeWord(w) ||
    _isOtherUnit(w);

/// Słowa, po których liczba bez jednostki jest kątem (typowe kąty kolan).
bool _isElbowWord(String w) =>
    w.startsWith('kolan') ||
    w.startsWith('luk') ||
    w == 'elbow' ||
    w == 'elbows' ||
    w == 'bend';

/// Słowa, po których dowolna liczba jest kątem.
bool _isAngleWord(String w) => w == 'kat' || w == 'kata' || w == 'angle';

const List<double> _elbowAngles = [11.25, 15, 22.5, 30, 45, 60, 90, 180];

final _continuationRe = RegExp(
    r'^(?:a|i|to|oraz|and|also|then|what about|how about)(?: |$)');

final _attachedDnRe = RegExp(r'\bdn(\d+(?:\.\d+)?)\b');
final _attachedLengthRe = RegExp(r'^(\d+(?:\.\d+)?)(m|cm)$');
final _degreeSignRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*°');

class Utterance {
  Utterance(this.raw,
      {required this.lang, this.byVoice = false, this.alternatives = const []});

  /// Tekst tak, jak przyszedł (z rozpoznawania mowy albo z klawiatury).
  final String raw;
  final AppLanguage lang;

  /// Powiedziane głosem (a nie wpisane).
  final bool byVoice;

  /// N-best z rozpoznawania mowy (bez [raw]).
  final List<String> alternatives;

  late final String folded = foldSpeech(raw);
  late final List<SpokenItem> items = spokenItems(folded);
  late final List<String> tokens = [for (final i in items) i.text];

  late final String _padded = ' $folded ';

  /// Czy padło któreś słowo albo fraza (całe słowa; wzorce są zwijane).
  bool hasAny(Iterable<String> foldedWordsOrPhrases) {
    for (final p in foldedWordsOrPhrases) {
      final f = _foldPattern(p);
      if (f.isNotEmpty && _padded.contains(' $f ')) return true;
    }
    return false;
  }

  /// Czy któryś token zaczyna się od rdzenia („kolan" → kolano/kolanko/kolana).
  bool hasStem(Iterable<String> stems) {
    for (final t in tokens) {
      for (final s in stems) {
        if (t.startsWith(s)) return true;
      }
    }
    return false;
  }

  /// Wypowiedź zaczyna się słowem kontynuacji („a dla DN50?", „a ścianka?",
  /// „and DN50?", „what about…").
  late final bool isContinuation = _continuationRe.hasMatch(folded);

  // ─── DN ───────────────────────────────────────────────────────────────────

  /// Indeks elementu, który jest znacznikiem DN (słowo „dn" albo drugie
  /// słowo literowanego „de en" / „d n"), dla każdego wystąpienia.
  late final List<int> _dnMarkers = () {
    final out = <int>[];
    for (var i = 0; i < items.length; i++) {
      final w = items[i];
      if (w.isNumber) continue;
      if (w.word == 'dn') {
        out.add(i);
      } else if ((w.word == 'de' || w.word == 'd' || w.word == 'dee') &&
          i + 1 < items.length &&
          !items[i + 1].isNumber &&
          (items[i + 1].word == 'en' || items[i + 1].word == 'n')) {
        out.add(i + 1);
        i++;
      }
    }
    return out;
  }();

  /// Padło „DN" (z liczbą albo bez) — także „średnica nominalna".
  bool get mentionsDn =>
      _dnMarkers.isNotEmpty ||
      hasAny(const ['srednica nominalna', 'nominal diameter', 'nominal size']);

  /// Indeksy elementów zużytych przez DN (liczba za znacznikiem i — przy
  /// dwuznaczności — następna).
  late final (int?, Set<int>) _dnParse = () {
    final used = <int>{};
    int? result;
    var decided = false;
    for (final m in _dnMarkers) {
      final j = m + 1;
      if (j >= items.length || !items[j].isNumber) continue;
      used.add(j);
      if (decided) continue;
      decided = true;
      final v = items[j].value!;
      if (items[j].fraction || v != v.roundToDouble() || v <= 0) continue;
      // „dn 4 0" — kolejna cyfra bez jednostki: 40 czy 4? Nie zgadujemy.
      final k = j + 1;
      final attached = _attachedDnRe.hasMatch(folded) &&
          _attachedDnRe.firstMatch(folded)![1] == items[j].raw;
      if (!attached &&
          k < items.length &&
          items[k].isNumber &&
          items[k].value! < 10 &&
          v < 100 &&
          !(k + 1 < items.length &&
              !items[k + 1].isNumber &&
              _isAnyUnit(items[k + 1].word))) {
        used.add(k);
        continue;
      }
      result = v.toInt();
    }
    return (result, used);
  }();

  /// DN: „dn40", „dn 40", „de en 40", „d n 40", „dn czterdzieści", „rura
  /// setka". „dn 4 0" → null (dwuznaczne), brak liczby → null.
  int? dn() => _dnParse.$1;

  // ─── NPS ──────────────────────────────────────────────────────────────────

  late final (double?, int?) _npsParse = () {
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!it.isNumber) {
        if (it.word == 'nps' &&
            i + 1 < items.length &&
            items[i + 1].isNumber &&
            items[i + 1].value! > 0) {
          return (items[i + 1].value, i + 1);
        }
        continue;
      }
      final v = it.value!;
      if (v <= 0) continue;
      final next = i + 1 < items.length ? items[i + 1] : null;
      if (next != null && !next.isNumber && isInchUnit(next.word)) {
        return (v, i);
      }
      // „trzy czwarte" bez „cala": ułamek ma sens tylko jako cale.
      if (it.fraction &&
          (next == null || next.isNumber || !_isAnyUnit(next.word))) {
        return (v, i);
      }
    }
    return (null, null);
  }();

  /// Rozmiar w calach: „2"", „2 cale", „półtora cala", „trzy czwarte (cala)",
  /// „1 1/4"", „NPS 2", „two inch".
  double? npsInches() => _npsParse.$1;

  // ─── Kąt ──────────────────────────────────────────────────────────────────

  late final (double?, int?) _angleParse = () {
    final sign = _degreeSignRe.firstMatch(raw);
    double? fromSign;
    if (sign != null) {
      fromSign = double.tryParse(sign[1]!.replaceAll(',', '.'));
    }
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!it.isNumber) continue;
      final v = it.value!;
      if (fromSign != null && v == fromSign) return (v, i);
      final next = i + 1 < items.length ? items[i + 1] : null;
      if (next != null && !next.isNumber && _isDegreeWord(next.word)) {
        return (v, i);
      }
      final prev = i > 0 ? items[i - 1] : null;
      if (prev != null && !prev.isNumber) {
        if (_isAngleWord(prev.word)) return (v, i);
        if (_isElbowWord(prev.word) && _elbowAngles.contains(v)) {
          return (v, i);
        }
      }
    }
    return (fromSign, null);
  }();

  /// Kąt w stopniach: „45°", „45 stopni", „kolano 90", „kąt 37,5",
  /// „30 degrees". Liczba po „kolano" tylko gdy to typowy kąt kolana.
  double? angleDeg() => _angleParse.$1;

  // ─── Długość ──────────────────────────────────────────────────────────────

  bool? _lastAssumed;

  /// Długość w mm: „2 m", „2m", „1500", „1500 mm", „150 cm", „metr
  /// dwadzieścia" (1200), „dwa metry dwadzieścia" (2200), „półtora metra".
  /// Liczba bez jednostki: od [assumeMetersBelow] w górę to mm, poniżej —
  /// metry („rura 2" → 2000, [lengthAssumedMeters] = true). Liczby DN, cali,
  /// kątów i innych jednostek nie są długością.
  double? lengthMm({double assumeMetersBelow = 50}) {
    final (v, assumed) = _length(assumeMetersBelow);
    _lastAssumed = assumed;
    return v;
  }

  /// Ostatnia [lengthMm] przyjęła metry dla liczby bez jednostki.
  bool get lengthAssumedMeters => _lastAssumed ?? _length(50).$2;

  (double?, bool) _length(double assumeMetersBelow) {
    // 1) liczba z jednostką długości (z opcjonalnymi centymetrami po metrach)
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final next = i + 1 < items.length ? items[i + 1] : null;
      if (!it.isNumber) {
        final glued = _attachedLengthRe.firstMatch(it.word);
        if (glued != null) {
          final v = double.parse(glued[1]!);
          return (glued[2] == 'cm' ? v * 10 : v * 1000, false);
        }
        // „metr", „metr dwadzieścia"
        if (_isSingleMeterWord(it.word) &&
            (i == 0 || !items[i - 1].isNumber)) {
          return (1000 + _cmAfter(i + 1), false);
        }
        // „pół metra"
        if (it.word == 'pol' && next != null && !next.isNumber &&
            _isMeterWord(next.word)) {
          return (500, false);
        }
        continue;
      }
      if (next == null || next.isNumber) continue;
      final v = it.value!;
      if (_isMmWord(next.word)) return (v, false);
      if (_isCmWord(next.word)) return (v * 10, false);
      if (_isMeterWord(next.word)) return (v * 1000 + _cmAfter(i + 2), false);
    }
    // 2) liczba bez jednostki, której nie zużyło nic innego
    final used = <int>{
      ..._dnParse.$2,
      if (_npsParse.$2 != null) _npsParse.$2!,
      if (_angleParse.$2 != null) _angleParse.$2!,
    };
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!it.isNumber || used.contains(i) || it.fraction) continue;
      final next = i + 1 < items.length ? items[i + 1] : null;
      if (next != null && !next.isNumber && _isAnyUnit(next.word)) continue;
      final prev = i > 0 ? items[i - 1] : null;
      if (prev != null &&
          !prev.isNumber &&
          (prev.word == 'sch' || prev.word.startsWith('schedul'))) {
        continue;
      }
      final v = it.value!;
      if (v <= 0) continue;
      if (v >= assumeMetersBelow) return (v, false);
      return (v * 1000, true);
    }
    return (null, false);
  }

  /// Centymetry po metrach („dwa metry dwadzieścia"): liczba < 100 bez
  /// jednostki albo z „cm".
  double _cmAfter(int j) {
    if (j >= items.length || !items[j].isNumber) return 0;
    final v = items[j].value!;
    if (v >= 100 || v != v.roundToDouble()) return 0;
    final after = j + 1 < items.length ? items[j + 1] : null;
    if (after != null &&
        !after.isNumber &&
        _isAnyUnit(after.word) &&
        !_isCmWord(after.word)) {
      return 0;
    }
    return v * 10;
  }

  // ─── Liczba przy słowie-kluczu ────────────────────────────────────────────

  /// Liczba przy słowie zaczynającym się od któregoś klucza: najpierw za nim
  /// (do 3 słów, mosty „na"/„ma" się nie liczą), potem tuż przed nim
  /// („60 amper").
  double? numberNear(Iterable<String> keys) {
    final ks = [for (final k in keys) _foldPattern(k)];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.isNumber || !ks.any((k) => k.isNotEmpty && it.word.startsWith(k))) {
        continue;
      }
      var seen = 0;
      for (var j = i + 1; j < items.length && seen < 3; j++) {
        if (items[j].isNumber) return items[j].value;
        if (!_bridgeWords.contains(items[j].word)) seen++;
      }
      if (i > 0 && items[i - 1].isNumber) return items[i - 1].value;
    }
    return null;
  }

  /// Ta sama wypowiedź z innym tekstem (ocena alternatyw N-best).
  Utterance withRaw(String alt) =>
      Utterance(alt, lang: lang, byVoice: byVoice);

  @override
  String toString() => 'Utterance($raw)';
}

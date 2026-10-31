/// PMI (analizator XRF): ocena składu chemicznego względem wymaganego
/// gatunku i wybranej normy (EN albo ASTM — gdy się różnią, ocena wobec
/// wybranej).
///
/// Zasady bezpieczeństwa werdyktu (sprawdzane testami):
///   • „zgodny” tylko, gdy KAŻDY oceniany pierwiastek (kluczowe + każdy
///     wpisany, dla którego norma podaje zakres) leży w zakresie także po
///     uwzględnieniu niepewności przyrządu (przedział odczyt ± u w całości
///     w zakresie; granice włącznie);
///   • „niezgodny”, gdy przedział odczyt ± u leży w całości poza zakresem
///     (z u = 0: odczyt poza zakresem);
///   • „do weryfikacji”, gdy przedział zahacza o granicę (odczyt w zakresie
///     poszerzonym o niepewność, ale nie da się rozstrzygnąć) — z u = 0
///     tylko „zgodny” / „niezgodny”;
///   • wymagany pierwiastek bez odczytu (kluczowy ALBO każdy z dolną granicą
///     w wybranej normie — np. Si dla P11, Si i Mn dla P91), nieczytelny
///     odczyt, ujemna albo nieczytelna niepewność, suma odczytów > 100 % →
///     brak werdyktu;
///   • pierwiastek spoza składu gatunku (norma nie podaje zakresu) powyżej
///     progu resztkowego → „niezgodny” z podpowiedzią sąsiedniego gatunku
///     (Mo 2,1 % w 304 → możliwy 316); próg w niepewności → „do
///     weryfikacji”; pierwiastek kontrolny bez odczytu (Mo w 304) → „do
///     weryfikacji”;
///   • XRF nie mierzy węgla ani azotu: przy gatunkach niskowęglowych („L”,
///     duplex, P91) najlepszy możliwy werdykt to „zgodny (bez weryfikacji
///     C)”; minimum Ti = k × C (gatunki stabilizowane) da się potwierdzić
///     tylko, gdy Ti ≥ k × Cmax — inaczej „do weryfikacji (C)”;
///   • „najbliższy gatunek z tabeli” to wyłącznie podpowiedź (nie zmienia
///     werdyktu).
///
/// Czysty Dart (bez Fluttera).
library;

import '../../utils/decimal_parse.dart';
import '../../utils/decimal_math.dart';
import 'ferrite.dart' show ferriteExact, ferriteSnap;

// ═══════════════════════════════════════════════════════════════════════════
// PIERWIASTKI I ZAKRESY
// ═══════════════════════════════════════════════════════════════════════════

/// Pierwiastki, które przenośny XRF podaje dla stali (C i N — nie; Si
/// tylko część przyrządów i z mniejszą dokładnością — wpisz, jeśli jest).
enum PmiElement {
  cr('Cr'),
  ni('Ni'),
  mo('Mo'),
  mn('Mn'),
  si('Si'),
  ti('Ti'),
  nb('Nb'),
  cu('Cu'),
  v('V');

  const PmiElement(this.symbol);
  final String symbol;

  static PmiElement? byName(Object? n) =>
      PmiElement.values.where((e) => e.name == n).firstOrNull;
}

/// Minimum zależne od węgla (stabilizacja Ti): min = [factor] × (C [+ N]).
/// XRF nie mierzy C ani N — minimum jest pewne tylko przy najgorszym
/// dopuszczalnym C (i N): [worstCaseMin].
class PmiCarbonLinkedMin {
  final double factor;
  final bool plusN;

  /// Maksymalne C (i N) z tej samej normy — do [worstCaseMin].
  final double cMax;
  final double nMax;

  const PmiCarbonLinkedMin({
    required this.factor,
    required this.cMax,
    this.plusN = false,
    this.nMax = 0,
  });

  /// Minimum przy najwyższym dopuszczalnym C (i N) — powyżej tego odczyt
  /// spełnia wymaganie niezależnie od rzeczywistego C.
  double get worstCaseMin => decimalProduct(factor, decimalSum([cMax, if (plusN) nMax]));

  String formula({required bool en}) {
    final f = ferriteExact(factor, en: en);
    return plusN ? '$f × (C + N)' : '$f × C';
  }
}

/// Zakres pierwiastka [% masy], granice włącznie; `null` = otwarta.
class PmiRange {
  final double? min;
  final double? max;
  final PmiCarbonLinkedMin? carbonMin;

  const PmiRange({this.min, this.max, this.carbonMin});

  /// „16,5–18,5”, „≤ 2,00”, „5 × C – 0,70”.
  String text({required bool en}) {
    String n(double v) => ferriteExact(v, en: en);
    final lo = min, hi = max, cm = carbonMin;
    if (cm != null) {
      return hi == null
          ? '≥ ${cm.formula(en: en)}'
          : '${cm.formula(en: en)} – ${n(hi)}';
    }
    if (lo != null && hi != null) return '${n(lo)}–${n(hi)}';
    if (lo != null) return '≥ ${n(lo)}';
    if (hi != null) return '≤ ${n(hi)}';
    return '—';
  }

  bool sameAs(PmiRange? o) =>
      o != null &&
      o.min == min &&
      o.max == max &&
      o.carbonMin?.factor == carbonMin?.factor &&
      o.carbonMin?.plusN == carbonMin?.plusN;
}

/// Skład wg jednej normy (EN albo ASTM) — z wydaniem i źródłem.
class PmiSpec {
  /// Krótki identyfikator wariantu w obrębie gatunku (zapis protokołu).
  final String key;

  /// Norma z wydaniem, np. „EN 10088-1:2014”, „ASTM A312/A312M-24”.
  final String standard;

  /// Oznaczenie w tej normie, np. „X2CrNiMo17-12-2”, „TP316L (S31603)”.
  final String designation;

  /// C w tej normie — tylko informacja (XRF nie mierzy C).
  final String carbonText;
  final Map<PmiElement, PmiRange> ranges;

  /// Skąd liczby (norma, przedruk) — pokazywane w UI i protokole.
  final String sourcePl;
  final String sourceEn;

  const PmiSpec({
    required this.key,
    required this.standard,
    required this.designation,
    required this.carbonText,
    required this.ranges,
    required this.sourcePl,
    required this.sourceEn,
  });

  String source({required bool en}) => en ? sourceEn : sourcePl;
}

enum PmiFamily { austenitic, duplex, crMo }

/// Gatunek z tabeli: warianty norm (pierwszy = EN), pierwiastki kluczowe.
class PmiGrade {
  final String id;
  final PmiFamily family;

  /// „1.4404 / 316L”.
  final String title;
  final List<PmiSpec> specs;

  /// Pierwiastki, bez których odczytu nie ma werdyktu (dobór — przyjęty
  /// w aplikacji: pierwiastki stopowe odróżniające gatunek).
  final Set<PmiElement> keyElements;

  /// O gatunku decyduje też C (gatunki „L”, duplex, P91) — najlepszy
  /// werdykt z XRF: „zgodny (bez weryfikacji C)”.
  final bool carbonCritical;

  /// Pierwiastki KONTROLNE: nie występują w składzie gatunku, ale ich
  /// obecność wskazuje sąsiedni gatunek (Mo w 304 → 316). Brak odczytu →
  /// „do weryfikacji” (nie zielone). Wartość — nazwa gatunku, którego brak
  /// odczytu nie wyklucza (`null` — ogólnie „gatunek z tym pierwiastkiem”).
  /// Działa tylko w normie, która nie podaje zakresu tego pierwiastka.
  final Map<PmiElement, String?> controlElements;
  final String notePl;
  final String noteEn;

  const PmiGrade({
    required this.id,
    required this.family,
    required this.title,
    required this.specs,
    required this.keyElements,
    this.carbonCritical = false,
    this.controlElements = const {},
    this.notePl = '',
    this.noteEn = '',
  });

  String note({required bool en}) => en ? noteEn : notePl;

  PmiSpec? specByKey(String key) =>
      specs.where((s) => s.key == key).firstOrNull;

  /// Pierwiastki WYMAGANE w normie [spec]: kluczowe oraz każdy, dla którego
  /// norma podaje dolną granicę (min albo min zależne od C) — np. Si dla
  /// P11, Si i Mn dla P91. Bez odczytu któregoś — brak werdyktu.
  Set<PmiElement> requiredIn(PmiSpec spec) => {
        ...keyElements,
        for (final MapEntry(key: e, value: r) in spec.ranges.entries)
          if (r.min != null || r.carbonMin != null) e,
      };
}

// ═══════════════════════════════════════════════════════════════════════════
// OCENA
// ═══════════════════════════════════════════════════════════════════════════

enum PmiElementStatus {
  /// Przedział odczyt ± u w całości w zakresie.
  inRange,

  /// Przedział zahacza o granicę — nie da się rozstrzygnąć.
  toVerify,

  /// Przedział w całości poza zakresem.
  outOfRange,

  /// Minimum Ti = k × C: odczyt poniżej k × Cmax — zależy od C (OES).
  carbonDependent,

  /// Wymagany pierwiastek (kluczowy albo z dolną granicą) bez odczytu.
  missing,

  /// Odczyt albo niepewność nieczytelne / ujemne / > 100 %.
  invalid,

  /// Wpisany, norma nie podaje zakresu, a odczyt nie przekracza progu
  /// resztkowego — tylko informacja.
  notSpecified,
}

/// Dlaczego pierwiastek spoza składu gatunku zmienia werdykt.
enum PmiCheckNote {
  /// Pierwiastka nie ma w składzie, a odczyt (− u) > próg resztkowy →
  /// „poza zakresem” (np. Mo 2,1 % w 304 — możliwy 316).
  residualAbove,

  /// Próg resztkowy mieści się w odczyt ± u → „do weryfikacji”.
  residualNear,

  /// Pierwiastek kontrolny bez odczytu → „do weryfikacji” (np. brak Mo
  /// w 304 nie wyklucza 316).
  controlMissing,
}

class PmiElementCheck {
  final PmiElement element;

  /// Pierwiastek wymagany (kluczowy albo z dolną granicą w normie).
  final bool key;

  /// Pierwiastek kontrolny gatunku (bez zakresu w normie).
  final bool control;

  /// Powód statusu pierwiastka spoza składu (`null` — zwykła ocena).
  final PmiCheckNote? note;

  /// Podpowiedź: gatunek z tabeli, który ten pierwiastek zawiera
  /// ([PmiCheckNote.residualAbove] / [PmiCheckNote.residualNear]) albo
  /// nazwa gatunku, którego brak odczytu nie wyklucza
  /// ([PmiCheckNote.controlMissing]).
  final String? possibleGrade;

  /// Odczyt i niepewność jako liczby (`null` — brak / nieczytelne).
  final double? reading;
  final double uncertainty;

  /// Odczyt i niepewność tak, jak wpisano (do ekranu i protokołu).
  final String readingText;
  final String uncertaintyText;
  final PmiRange? range;
  final PmiElementStatus status;

  const PmiElementCheck({
    required this.element,
    required this.key,
    required this.reading,
    required this.uncertainty,
    required this.range,
    required this.status,
    this.readingText = '',
    this.uncertaintyText = '',
    this.control = false,
    this.note,
    this.possibleGrade,
  });
}

enum PmiVerdict {
  /// Każdy oceniany pierwiastek w zakresie (gatunek bez krytycznego C).
  conforming,

  /// Jak wyżej, ale o gatunku decyduje też C — XRF go nie mierzy.
  conformingNoCarbon,

  /// Odczyt w zakresie poszerzonym o niepewność albo zależny od C.
  toVerify,

  /// Co najmniej jeden pierwiastek wyraźnie poza zakresem.
  nonConforming,

  /// Brak werdyktu — powód w [PmiNoVerdict].
  none,
}

enum PmiNoVerdict {
  /// Gatunek / norma nie wybrane albo nieznane (zapis z innej wersji).
  noGrade,

  /// Kluczowy pierwiastek bez odczytu.
  missingKey,

  /// Nieczytelny odczyt albo niepewność.
  invalidInput,

  /// Suma odczytów > 100 % — pomyłka we wpisie.
  sumOver100,
}

class PmiResult {
  final PmiGrade? grade;
  final PmiSpec? spec;
  final List<PmiElementCheck> checks;
  final PmiVerdict verdict;
  final PmiNoVerdict? reason;

  const PmiResult({
    required this.grade,
    required this.spec,
    required this.checks,
    required this.verdict,
    this.reason,
  });

  Iterable<PmiElementCheck> withStatus(PmiElementStatus s) =>
      checks.where((c) => c.status == s);
}

/// Status przedziału [r − u, r + u] względem zakresu (granice włącznie).
PmiElementStatus pmiIntervalStatus(
    double r, double u, double? min, double? max) {
  if (!r.isFinite || !u.isFinite || u < 0 ||
      min != null && !min.isFinite || max != null && !max.isFinite) {
    return PmiElementStatus.invalid;
  }
  if ((min != null && compareDecimalSum([r, u], min) < 0) ||
      (max != null && compareDecimalSum([r, -u], max) > 0)) {
    return PmiElementStatus.outOfRange;
  }
  final inside = (min == null || compareDecimalSum([r, -u], min) >= 0) &&
      (max == null || compareDecimalSum([r, u], max) <= 0);
  return inside ? PmiElementStatus.inRange : PmiElementStatus.toVerify;
}

/// Status pierwiastka względem zakresu z minimum zależnym od C.
PmiElementStatus _carbonLinkedStatus(double r, double u, PmiRange range) {
  final cm = range.carbonMin!;
  final max = range.max;
  // Ti = 0 (nie wykryty): k × C > 0 przy każdej stali — wyraźnie poniżej.
  if (compareDecimalSum([r, u], 0) <= 0) return PmiElementStatus.outOfRange;
  if (max != null && compareDecimalSum([r, -u], max) > 0) return PmiElementStatus.outOfRange;
  if (max != null && compareDecimalSum([r, u], max) > 0) return PmiElementStatus.toVerify;
  return compareDecimalSum([r, -u], cm.worstCaseMin) >= 0
      ? PmiElementStatus.inRange
      : PmiElementStatus.carbonDependent;
}

/// Odczyt [% masy]: `null`, gdy pusty; NaN, gdy nieczytelny, ujemny albo
/// > 100 %.
double? _reading(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final v = parseDecimal(text);
  if (v == null || v < 0 || v > 100) return double.nan;
  return v;
}

/// Niepewność: pusta = 0; nieczytelna albo ujemna → NaN.
double _uncertainty(String? text) {
  if (text == null || text.trim().isEmpty) return 0;
  final v = parseDecimal(text);
  if (v == null || v < 0 || v > 100) return double.nan;
  return v;
}

/// Ocena odczytów XRF ([readings], [uncertainty] — tekst z pól, przecinek
/// albo kropka) względem gatunku [grade] wg normy [spec].
///
/// Pierwiastek wpisany, którego norma gatunku nie wymienia, jest oceniany
/// względem progu resztkowego [pmiResidualThreshold] (przyjęte w aplikacji):
/// odczyt − u > próg → „poza zakresem” (np. Mo 2,1 % w 304), próg w odczyt
/// ± u → „do weryfikacji”. [table] — tabela gatunków do podpowiedzi
/// „możliwy …” (nie zmienia werdyktu).
PmiResult evaluatePmi({
  required PmiGrade? grade,
  required PmiSpec? spec,
  required Map<PmiElement, String> readings,
  Map<PmiElement, String> uncertainty = const {},
  List<PmiGrade> table = const [],
}) {
  if (grade == null || spec == null) {
    return const PmiResult(
        grade: null,
        spec: null,
        checks: [],
        verdict: PmiVerdict.none,
        reason: PmiNoVerdict.noGrade);
  }
  final required = grade.requiredIn(spec);
  List<PmiMatch>? nearest;
  String? possibleWith(PmiElement e) {
    nearest ??= pmiNearestGrades(readings, table);
    for (final m in nearest!) {
      if (m.grade.id != grade.id && m.spec.ranges[e] != null) {
        return m.grade.title;
      }
    }
    return null;
  }

  final checks = <PmiElementCheck>[];
  final composition = <double>[];
  var anyInvalid = false;
  for (final e in PmiElement.values) {
    final r = _reading(readings[e]);
    final u = _uncertainty(uncertainty[e]);
    final range = spec.ranges[e];
    final key = required.contains(e);
    final control = range == null && grade.controlElements.containsKey(e);
    if (r != null && r.isFinite) composition.add(r);
    PmiElementStatus? status;
    PmiCheckNote? note;
    String? possible;
    if (r == null) {
      // Bez odczytu: wymagany → brak werdyktu; kontrolny → do weryfikacji
      // (nie wyklucza sąsiedniego gatunku); inny — pomijany.
      if (key) {
        status = PmiElementStatus.missing;
      } else if (control) {
        status = PmiElementStatus.toVerify;
        note = PmiCheckNote.controlMissing;
        possible = grade.controlElements[e];
      }
    } else if (r.isNaN || u.isNaN) {
      status = PmiElementStatus.invalid;
      anyInvalid = true;
    } else if (range == null) {
      // Pierwiastka nie ma w składzie gatunku — próg resztkowy.
      final t = pmiResidualThreshold(e);
      if (compareDecimalSum([r, -u], t) > 0) {
        status = PmiElementStatus.outOfRange;
        note = PmiCheckNote.residualAbove;
        possible = possibleWith(e);
      } else if (compareDecimalSum([r, u], t) > 0) {
        status = PmiElementStatus.toVerify;
        note = PmiCheckNote.residualNear;
        possible = possibleWith(e);
      } else {
        status = PmiElementStatus.notSpecified;
      }
    } else if (range.carbonMin != null) {
      status = _carbonLinkedStatus(r, u, range);
    } else {
      status = pmiIntervalStatus(r, u, range.min, range.max);
    }
    if (status == null) continue;
    checks.add(PmiElementCheck(
      element: e,
      key: key,
      control: control,
      note: note,
      possibleGrade: possible,
      reading: r == null || r.isNaN ? null : r,
      uncertainty: u.isNaN ? 0 : u,
      readingText: (readings[e] ?? '').trim(),
      uncertaintyText: (uncertainty[e] ?? '').trim(),
      range: range,
      status: status,
    ));
  }

  PmiResult result(PmiVerdict v, [PmiNoVerdict? why]) => PmiResult(
      grade: grade, spec: spec, checks: checks, verdict: v, reason: why);

  if (compareDecimalSum(composition, 100) > 0) {
    return result(PmiVerdict.none, PmiNoVerdict.sumOver100);
  }
  bool any(PmiElementStatus s) => checks.any((c) => c.status == s);
  if (any(PmiElementStatus.outOfRange)) {
    return result(PmiVerdict.nonConforming);
  }
  if (anyInvalid) return result(PmiVerdict.none, PmiNoVerdict.invalidInput);
  if (any(PmiElementStatus.missing)) {
    return result(PmiVerdict.none, PmiNoVerdict.missingKey);
  }
  if (any(PmiElementStatus.toVerify) ||
      any(PmiElementStatus.carbonDependent)) {
    return result(PmiVerdict.toVerify);
  }
  return result(grade.carbonCritical
      ? PmiVerdict.conformingNoCarbon
      : PmiVerdict.conforming);
}

// ═══════════════════════════════════════════════════════════════════════════
// PODPOWIEDŹ: NAJBLIŻSZY GATUNEK Z TABELI (tylko informacja)
// ═══════════════════════════════════════════════════════════════════════════

/// Próg „resztkowy” [% masy] dla pierwiastka, którego norma gatunku nie
/// wymienia — PRZYJĘTE W APLIKACJI (normy go nie podają): powyżej tej
/// zawartości pierwiastek „nie pasuje” do gatunku (np. Mo 2 % przy 304 —
/// możliwy 316) i werdykt to „niezgodny”. Progi z zapasem na typowe
/// zanieczyszczenia: Cu i Si do 1 %, V do 0,2 % (spotykane w stalach
/// nierdzewnych), Ti i Nb 0,1 % (stabilizacja zaczyna się wyżej).
double pmiResidualThreshold(PmiElement e) => switch (e) {
      PmiElement.ti || PmiElement.nb => 0.1,
      PmiElement.v => 0.2,
      PmiElement.si || PmiElement.cu => 1.0,
      _ => 0.5,
    };

class PmiMatch {
  final PmiGrade grade;
  final PmiSpec spec;

  /// Suma odchyłek [% masy] poza zakresy (0 = wszystkie wpisane w zakresie).
  final double score;

  /// Któryś pierwiastek kluczowy tego gatunku nie ma odczytu.
  final bool missingKey;

  const PmiMatch(this.grade, this.spec, this.score, this.missingKey);

  bool get fits => score == 0 && !missingKey;
}

/// Gatunki z tabeli uporządkowane od najbliższego. Dla Ti stabilizującego
/// dolna granica = k × Cmax (jak w werdykcie). Wyłącznie informacja.
List<PmiMatch> pmiNearestGrades(
  Map<PmiElement, String> readings,
  List<PmiGrade> grades,
) {
  final values = <PmiElement, double>{};
  for (final e in PmiElement.values) {
    final r = _reading(readings[e]);
    if (r != null && r.isFinite) values[e] = r;
  }
  if (values.isEmpty) return const [];
  final out = <(PmiMatch, int)>[];
  var order = 0;
  for (final g in grades) {
    for (final s in g.specs) {
      var score = 0.0;
      for (final MapEntry(key: e, value: r) in values.entries) {
        final range = s.ranges[e];
        if (range == null) {
          final t = pmiResidualThreshold(e);
          if (r > t) score += r - t;
          continue;
        }
        final lo = range.carbonMin?.worstCaseMin ?? range.min;
        final hi = range.max;
        if (lo != null && r < lo) score += lo - r;
        if (hi != null && r > hi) score += r - hi;
      }
      final missing = g.requiredIn(s).any((e) => !values.containsKey(e));
      out.add((PmiMatch(g, s, ferriteSnap(score), missing), order++));
    }
  }
  // Remis → kolejność tabeli (sortowanie w Dart nie jest stabilne).
  out.sort((a, b) {
    final byScore = a.$1.score.compareTo(b.$1.score);
    if (byScore != 0) return byScore;
    if (a.$1.missingKey != b.$1.missingKey) return a.$1.missingKey ? 1 : -1;
    return a.$2.compareTo(b.$2);
  });
  return [for (final (m, _) in out) m];
}

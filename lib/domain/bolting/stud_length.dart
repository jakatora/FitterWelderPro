/// Długość szpilek (stud bolts) do połączeń kołnierzowych — czysta
/// arytmetyka, bez UI. Ekran: `lib/features/bolt_kit/bolt_kit_page.dart`.
///
/// Dwa tryby:
///
/// 1. **ASME B16.5 z tabeli** — DN × Class × przylga (RF / RTJ). Liczbę
///    i średnicę szpilek bierze z [FlangeCatalog] (ASME B16.5 Table 11 —
///    jedno źródło w aplikacji, tu NIE powielone), długość z
///    [_kStudLengthQ]. Długość trzymana kanonicznie w ćwiartkach cala (tabele
///    B16.5 są co 1/4"), mm tylko do wyświetlenia (× 6,35).
///
/// 2. **Z wymiarów** (dowolne kołnierze, np. EN 1092-1) — [computeStudLength]:
///      L = t₁ + t₂ + g + 2·m + 2·p + n_w·w
///    t — grubość kołnierza w miejscu otworów (razem z przylgą), g — grubość
///    uszczelki NOMINALNA (przed ściśnięciem: szpilka wychodzi dłuższa o
///    ściśnięcie — to zapas, nie błąd), m — wysokość nakrętki, p — wystawanie
///    gwintu za nakrętką z każdej strony, n_w × w — podkładki. Wynik zawsze
///    zaokrąglany W GÓRĘ do typoszeregu ([LengthSeries]), nigdy w dół.
///
/// ŹRÓDŁA TABELI DŁUGOŚCI (sprawdzone 2026-10-17):
///   [A] DNOW „Number and Size of Bolts for Flanged Joints — ASME B16.5”
///       (DNF-140057.01, © 2023), https://www.dnow.com/hubfs/WC/PDF/Products/
///       Pipe-and-Tube/DNOW_Bolting_Chart.pdf — długości w calach, kolumny
///       „1/16 in. RF” (Class 150/300), „1/4 in. RF” (Class 400 i wyżej), RTJ.
///   [B] USA Fastener „Bolt Reference Charts for ASME B16.5 Flanges” (2023),
///       https://info.mwcomponents.com/hubfs/PDFs/MW-COMPONENTS/
///       MWC-Product-Resources-and-Technical-Data-PDFs/
///       USA_Fastener_ASME_B16.5_Flange_Charts.pdf — w calach (nagłówek
///       „Raised Face 0.06 in” błędnie powtórzony także dla Class 600+).
///   [C] wermac.org „Stud Bolts Dimensions for RF-RTJ Flanges — ASME B16.5 —
///       Class 150/300/600/900/1500” (np. https://wermac.org/bolts/
///       dimensions_stud-bolts_class-600_rf-rtj-flanges_asme-b16-5.html) —
///       metryczne tabele B16.5 (mm, co 5 mm; nie są dokładnym przeliczeniem
///       cali, np. Class 150 NPS ½: 55 mm vs 2-1/4" = 57,2 mm).
///   Liczba i średnica śrub w [A], [B], [C] zgadzają się z [FlangeCatalog]
///   dla całego zakresu DN15–DN300 × Class 150–1500 (test).
///
/// PRZYLGA: tabele B16.5 dla Class 150 i 300 zakładają przylgę RF 2 mm
/// (0,06" = 1/16"), wliczoną w grubość kołnierza; od Class 400 — 7 mm
/// (0,25" = 1/4"), doliczoną do grubości ([A]: nagłówki kolumn). Kołnierz
/// Class 150/300 z wyższą przylgą, przekładki, zaślepki okularowe, zestawy
/// izolujące, grubsze uszczelki → tryb z wymiarów.
///
/// DŁUGOŚĆ MIERZONA bez ścięć (końcówek) — od pierwszego do ostatniego
/// pełnego zwoju ([B] uwaga pod tabelą, [C]).
///
/// ROZBIEŻNOŚCI ŹRÓDEŁ — przyjęto wartość DŁUŻSZĄ (pełny gwint w nakrętce,
/// PCC-1), opis w [studLengthSourceNote]:
///   * Class 600 DN200 RTJ: [A] 7-3/4", [B] 7-1/2"; [C] 195 mm (> RF 190 mm)
///     potwierdza, że RTJ jest dłuższe od RF → 7-3/4".
///   * Class 900 DN200 RF: [A] 8-3/4", [B] 8-3/8" (poza krokiem 1/4" —
///     najpewniej literówka); [C] 220 mm ≈ 8,66" → 8-3/4".
///   * Class 1500 DN200 RTJ: [A] i [B] 12-3/4", ale [C] 300 mm ≈ 11,8"
///     (różnica ~1"). Przyjęto 12-3/4" — NIEPEWNE, do sprawdzenia
///     z egzemplarzem normy / specyfikacją.
///
/// METODA B16.5 (Nonmandatory Appendix C „Method for Calculating Bolt
/// Lengths”, wyd. 2020; spis treści normy: asme.org): długość z grubości
/// kołnierzy z tolerancją, wysokości nakrętki = średnicy nominalnej, szczeliny,
/// wysokości przylg / rowków i tolerancji długości, zaokrąglona do kroku
/// 1/4" (5 mm) — tabele [A]–[C] są dokładnie w tych krokach. Pełnego tekstu
/// załącznika nie udało się pobrać (norma płatna).
///
/// NAKRĘTKA heavy hex (A194 2H, ASME B18.2.2): wysokość podstawowa
/// H = d − 1/64" (np. 3/4" → 47/64" = 0,734"), maks. ≈ d (0,758"), stąd
/// „H ≈ d” jak w metodzie B16.5.
library;

import '../../services/flange_catalog.dart';
import '../quotes/quote_calculator.dart' show formatQty;
import 'bolt_torque.dart';

/// Przylga kołnierza: podniesiona (RF) albo rowek pod pierścień (RTJ).
enum FlangeFacing { rf, rtj }

/// 1/4" w mm (dokładnie: 25,4 / 4).
const double kMmPerQuarterInch = 6.35;

/// Długość szpilki [ASME B16.5] w ćwiartkach cala dla klucza `dn_class`:
/// (RF, RTJ). RTJ `null` = B16.5 nie przewiduje RTJ dla tej średnicy
/// (Class 150 NPS ½ i ¾). Źródła: opis biblioteki.
const Map<String, (int, int?)> _kStudLengthQ = {
  // ── Class 150 (RF 1/16") ───────────────────────────────────────────────
  '15_150': (9, null), // 2-1/4"
  '20_150': (10, null), // 2-1/2"
  '25_150': (10, 12), // 2-1/2" / 3"
  '32_150': (11, 13), // 2-3/4" / 3-1/4"
  '40_150': (11, 13),
  '50_150': (13, 15), // 3-1/4" / 3-3/4"
  '65_150': (14, 16), // 3-1/2" / 4"
  '80_150': (14, 16),
  '100_150': (14, 16),
  '150_150': (16, 18), // 4" / 4-1/2"
  '200_150': (17, 19), // 4-1/4" / 4-3/4"
  '250_150': (18, 20), // 4-1/2" / 5"
  '300_150': (19, 21), // 4-3/4" / 5-1/4"
  // ── Class 300 (RF 1/16") ───────────────────────────────────────────────
  '15_300': (10, 12), // 2-1/2" / 3"
  '20_300': (12, 14), // 3" / 3-1/2"
  '25_300': (12, 14),
  '32_300': (13, 15), // 3-1/4" / 3-3/4"
  '40_300': (14, 16), // 3-1/2" / 4"
  '50_300': (14, 16),
  '65_300': (16, 18), // 4" / 4-1/2"
  '80_300': (17, 19), // 4-1/4" / 4-3/4"
  '100_300': (18, 20), // 4-1/2" / 5"
  '150_300': (19, 22), // 4-3/4" / 5-1/2"
  '200_300': (22, 24), // 5-1/2" / 6"
  '250_300': (25, 27), // 6-1/4" / 6-3/4"
  '300_300': (27, 29), // 6-3/4" / 7-1/4"
  // ── Class 600 (RF 1/4") ────────────────────────────────────────────────
  '15_600': (12, 12), // 3"
  '20_600': (14, 14), // 3-1/2"
  '25_600': (14, 14),
  '32_600': (15, 15), // 3-3/4"
  '40_600': (17, 17), // 4-1/4"
  '50_600': (17, 17),
  '65_600': (19, 19), // 4-3/4"
  '80_600': (20, 20), // 5"
  '100_600': (23, 23), // 5-3/4"
  '150_600': (27, 27), // 6-3/4"
  '200_600': (30, 31), // 7-1/2" / 7-3/4" (RTJ: rozbieżność, patrz opis)
  '250_600': (34, 34), // 8-1/2"
  '300_600': (35, 35), // 8-3/4"
  // ── Class 900 (RF 1/4"; NPS ½–2½ jak Class 1500) ──────────────────────
  '15_900': (17, 17), // 4-1/4"
  '20_900': (18, 18), // 4-1/2"
  '25_900': (20, 20), // 5"
  '32_900': (20, 20),
  '40_900': (22, 22), // 5-1/2"
  '50_900': (23, 23), // 5-3/4"
  '65_900': (25, 25), // 6-1/4"
  '80_900': (23, 23), // 5-3/4"
  '100_900': (27, 27), // 6-3/4"
  '150_900': (30, 31), // 7-1/2" / 7-3/4"
  '200_900': (35, 35), // 8-3/4" (RF: rozbieżność, patrz opis)
  '250_900': (37, 37), // 9-1/4"
  '300_900': (40, 40), // 10"
  // ── Class 1500 (RF 1/4") ───────────────────────────────────────────────
  '15_1500': (17, 17),
  '20_1500': (18, 18),
  '25_1500': (20, 20),
  '32_1500': (20, 20),
  '40_1500': (22, 22),
  '50_1500': (23, 23),
  '65_1500': (25, 25),
  '80_1500': (28, 28), // 7"
  '100_1500': (31, 31), // 7-3/4"
  '150_1500': (41, 42), // 10-1/4" / 10-1/2"
  '200_1500': (46, 51), // 11-1/2" / 12-3/4" (RTJ: niepewne, patrz opis)
  '250_1500': (53, 54), // 13-1/4" / 13-1/2"
  '300_1500': (59, 61), // 14-3/4" / 15-1/4"
};

/// Klucze `dn_class` tabeli długości — do testu pokrycia katalogu.
Iterable<String> get studLengthTableKeys => _kStudLengthQ.keys;

String _key(int dn, int cls) => '${dn}_$cls';

/// Wysokość przylgi RF, którą zakłada tabela B16.5 dla klasy [cls] [mm]:
/// 2 mm (1/16") dla Class 150/300, 7 mm (1/4") od Class 400.
double assumedRaisedFaceMm(int cls) => cls <= 300 ? 2 : 7;

/// To samo w calach jako tekst: `1/16"` / `1/4"`.
String assumedRaisedFaceInch(int cls) => cls <= 300 ? '1/16"' : '1/4"';

// ═══════════════════════════════════════════════════════════════════════════
// TRYB 1: ASME B16.5 Z TABELI
// ═══════════════════════════════════════════════════════════════════════════

/// Szpilki dla jednego połączenia DN × Class × przylga.
class AsmeStud {
  final int dn;
  final int cls;
  final FlangeFacing facing;

  /// Liczba szpilek — z [FlangeCatalog].
  final int boltCount;

  /// Średnica i gwint — z [FlangeCatalog] przez [flangeBoltSize].
  final FlangeBoltSize size;

  /// Długość w ćwiartkach cala (kanonicznie).
  final int lengthQuarterIn;

  const AsmeStud({
    required this.dn,
    required this.cls,
    required this.facing,
    required this.boltCount,
    required this.size,
    required this.lengthQuarterIn,
  });

  double get lengthIn => lengthQuarterIn / 4;
  double get lengthMm => lengthQuarterIn * kMmPerQuarterInch;

  /// Dwie nakrętki heavy hex na szpilkę.
  int get nutCount => boltCount * 2;
}

/// Dlaczego nie ma wyniku z tabeli.
enum StudLookupProblem {
  /// DN × Class spoza katalogu aplikacji (DN15–DN300, Class 150–1500).
  notInCatalog,

  /// B16.5 nie przewiduje RTJ dla Class 150 NPS ½ i ¾.
  noRtj,
}

/// Wynik wyszukania w tabeli: szpilki albo powód braku wyniku.
sealed class StudLookup {
  const StudLookup();
}

class StudFound extends StudLookup {
  final AsmeStud stud;
  const StudFound(this.stud);
}

class StudNotFound extends StudLookup {
  final StudLookupProblem problem;
  const StudNotFound(this.problem);
}

/// Szpilki z ASME B16.5. DN × Class spoza tabeli → [StudNotFound], nigdy
/// zgadywanie.
StudLookup lookupAsmeStud(int dn, int cls, FlangeFacing facing) {
  final bolting = FlangeCatalog.lookup(dn, cls);
  final lengths = _kStudLengthQ[_key(dn, cls)];
  final size = bolting == null ? null : flangeBoltSize(bolting.boltSize);
  if (bolting == null || lengths == null || size == null) {
    return const StudNotFound(StudLookupProblem.notInCatalog);
  }
  final q = facing == FlangeFacing.rf ? lengths.$1 : lengths.$2;
  if (q == null) return const StudNotFound(StudLookupProblem.noRtj);
  return StudFound(AsmeStud(
    dn: dn,
    cls: cls,
    facing: facing,
    boltCount: bolting.boltCount,
    size: size,
    lengthQuarterIn: q,
  ));
}

/// Opis rozbieżności źródeł dla tej pozycji tabeli albo `null`.
String? studLengthSourceNote(int dn, int cls, FlangeFacing facing,
    {required bool en}) {
  String t(String pl, String e) => en ? e : pl;
  return switch ((dn, cls, facing)) {
    (200, 600, FlangeFacing.rtj) => t(
        'Źródła się różnią: 7-1/2" (USA Fastener) i 7-3/4" (DNOW; tabela '
            'metryczna B16.5: 195 mm, dłużej niż RF). Przyjęto dłuższą.',
        'Sources differ: 7-1/2" (USA Fastener) and 7-3/4" (DNOW; B16.5 metric '
            'table: 195 mm, longer than RF). The longer one is used.'),
    (200, 900, FlangeFacing.rf) => t(
        'Źródła się różnią: 8-3/8" (USA Fastener, poza krokiem 1/4") '
            'i 8-3/4" (DNOW; tabela metryczna B16.5: 220 mm). Przyjęto dłuższą.',
        'Sources differ: 8-3/8" (USA Fastener, off the 1/4" step) and 8-3/4" '
            '(DNOW; B16.5 metric table: 220 mm). The longer one is used.'),
    (200, 1500, FlangeFacing.rtj) => t(
        'Źródła się różnią: 12-3/4" (DNOW, USA Fastener), a tabela metryczna '
            'B16.5 (wermac.org) podaje 300 mm ≈ 11,8". Przyjęto dłuższą — '
            'sprawdź ze specyfikacją.',
        'Sources differ: 12-3/4" (DNOW, USA Fastener), while the B16.5 metric '
            'table (wermac.org) gives 300 mm ≈ 11.8". The longer one is used — '
            'check against the specification.'),
    _ => null,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// TRYB 2: Z WYMIARÓW
// ═══════════════════════════════════════════════════════════════════════════

/// Typoszereg długości handlowych — wynik zaokrąglany w górę do niego.
enum LengthSeries {
  /// Co 5 mm — szpilki cięte z pręta na wymiar; metryczne tabele B16.5 są
  /// w tym kroku.
  mm5,

  /// Co 10 mm — gdy hurtownia trzyma długości katalogowe co 10 mm.
  mm10,

  /// Co 1/4" (6,35 mm) — szpilki calowe; tabele B16.5 w calach są w tym
  /// kroku.
  quarterInch,
}

/// Krok typoszeregu w mm.
double seriesStepMm(LengthSeries s) => switch (s) {
      LengthSeries.mm5 => 5,
      LengthSeries.mm10 => 10,
      LengthSeries.quarterInch => kMmPerQuarterInch,
    };

/// Zaokrąglenie W GÓRĘ do wielokrotności kroku: liczba kroków.
///
/// Wartość „na” kroku (np. 115 mm przy kroku 5) zostaje — błąd zaokrągleń
/// liczb zmiennoprzecinkowych (114,99999999999999 albo 115,00000000000001)
/// nie przeskakuje o cały krok. Margines względny 1e-9 (5 nm przy kroku
/// 5 mm) — mniej niż jakikolwiek wpisany wymiar.
int stepsUp(double valueMm, double stepMm) {
  if (!valueMm.isFinite || !(stepMm > 0)) {
    throw ArgumentError('valueMm=$valueMm, stepMm=$stepMm');
  }
  return (valueMm / stepMm - 1e-9).ceil();
}

/// Pole formularza trybu z wymiarów, które blokuje wynik.
enum StudInputField { flange1, flange2, gasket, nut, protrusion, washer }

/// Granice pól [mm] — wartość spoza to literówka, nie kołnierz.
const double kMaxFlangeMm = 400;
const double kMaxGasketMm = 300; // z przekładką / zaślepką okularową
const double kMaxNutMm = 150;
const double kMaxProtrusionMm = 50;
const double kMaxWasherMm = 30;

/// Dozwolona łączna liczba podkładek na szpilkę.
const List<int> kWasherCounts = [0, 1, 2, 4];

/// Wynik trybu z wymiarów.
class StudDimensionsResult {
  final double flange1Mm;
  final double flange2Mm;
  final double gasketMm;
  final double nutMm;
  final double protrusionMm;
  final int washers;
  final double washerMm;
  final LengthSeries series;

  /// L obliczona przed zaokrągleniem [mm].
  final double requiredMm;

  /// Liczba kroków typoszeregu (długość do zamówienia = kroki × krok).
  final int steps;

  const StudDimensionsResult({
    required this.flange1Mm,
    required this.flange2Mm,
    required this.gasketMm,
    required this.nutMm,
    required this.protrusionMm,
    required this.washers,
    required this.washerMm,
    required this.series,
    required this.requiredMm,
    required this.steps,
  });

  /// Długość do zamówienia [mm] (≥ [requiredMm]).
  double get orderMm => steps * seriesStepMm(series);

  /// Długość do zamówienia w ćwiartkach cala — tylko dla typoszeregu
  /// calowego.
  int? get orderQuarterIn => series == LengthSeries.quarterInch ? steps : null;
}

/// Wynik albo lista pól do poprawy (puste / nieczytelne / poza zakresem).
sealed class StudDimensionsOutcome {
  const StudDimensionsOutcome();
}

class StudDimensionsOk extends StudDimensionsOutcome {
  final StudDimensionsResult result;
  const StudDimensionsOk(this.result);
}

class StudDimensionsInvalid extends StudDimensionsOutcome {
  final List<StudInputField> fields;
  const StudDimensionsInvalid(this.fields);
}

bool _inRange(double? v, {required double max, bool allowZero = false}) =>
    v != null && v.isFinite && (allowZero ? v >= 0 : v > 0) && v <= max;

/// L = t₁ + t₂ + g + 2·m + 2·p + n_w·w, zaokrąglone w górę do [series].
///
/// `null` = pole puste albo nieczytelne → brak wyniku (nie zero). Grubość
/// podkładki liczy się (i jest wymagana) tylko przy [washers] > 0.
StudDimensionsOutcome computeStudLength({
  required double? flange1Mm,
  required double? flange2Mm,
  required double? gasketMm,
  required double? nutMm,
  required double? protrusionMm,
  int washers = 0,
  double? washerMm,
  LengthSeries series = LengthSeries.mm5,
}) {
  final bad = <StudInputField>[
    if (!_inRange(flange1Mm, max: kMaxFlangeMm)) StudInputField.flange1,
    if (!_inRange(flange2Mm, max: kMaxFlangeMm)) StudInputField.flange2,
    if (!_inRange(gasketMm, max: kMaxGasketMm, allowZero: true))
      StudInputField.gasket,
    if (!_inRange(nutMm, max: kMaxNutMm)) StudInputField.nut,
    if (!_inRange(protrusionMm, max: kMaxProtrusionMm, allowZero: true))
      StudInputField.protrusion,
    if (!kWasherCounts.contains(washers) ||
        (washers > 0 && !_inRange(washerMm, max: kMaxWasherMm)))
      StudInputField.washer,
  ];
  if (bad.isNotEmpty) return StudDimensionsInvalid(bad);
  final w = washers > 0 ? washerMm! : 0.0;
  final required = flange1Mm! +
      flange2Mm! +
      gasketMm! +
      2 * nutMm! +
      2 * protrusionMm! +
      washers * w;
  return StudDimensionsOk(StudDimensionsResult(
    flange1Mm: flange1Mm,
    flange2Mm: flange2Mm,
    gasketMm: gasketMm,
    nutMm: nutMm,
    protrusionMm: protrusionMm,
    washers: washers,
    washerMm: w,
    series: series,
    requiredMm: required,
    steps: stepsUp(required, seriesStepMm(series)),
  ));
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE (przecinek w PL, kropka w EN)
// ═══════════════════════════════════════════════════════════════════════════

/// Liczba bez zbędnych zer: PL „120,7”, EN „120.7”. NaN/∞ → „—”.
String fmtStudNum(double v, {int decimals = 1, required bool en}) {
  if (!v.isFinite) return '—';
  final s = formatQty(v, decimals: decimals);
  return en ? s.replaceAll(',', '.') : s;
}

/// „120,7 mm”.
String formatMm(double mm, {int decimals = 1, required bool en}) =>
    '${fmtStudNum(mm, decimals: decimals, en: en)} mm';

/// Ćwiartki cala jako ułamek z łącznikiem: 19 → `4-3/4"`, 16 → `4"`,
/// 3 → `3/4"`.
String formatQuarterInch(int quarters) {
  if (quarters <= 0) return '—';
  final whole = quarters ~/ 4;
  final frac = switch (quarters % 4) {
    1 => '1/4',
    2 => '1/2',
    3 => '3/4',
    _ => '',
  };
  if (frac.isEmpty) return '$whole"';
  return whole == 0 ? '$frac"' : '$whole-$frac"';
}

/// Średnica szpilki jak w katalogu: `5/8"`, `1-1/8"`.
String formatBoltDiameter(FlangeBoltSize size) => '${size.label}"';

/// „5/8" × 3-1/2"”.
String studDesignation(FlangeBoltSize size, int lengthQuarterIn) =>
    '${formatBoltDiameter(size)} × ${formatQuarterInch(lengthQuarterIn)}';

/// Nazwa przylgi: „RF” / „RTJ”.
String facingLabel(FlangeFacing f) => f == FlangeFacing.rf ? 'RF' : 'RTJ';

// Czas stygnięcia t8/5 — EN 1011-2:2001, załącznik D. Czyste funkcje, bez
// Fluttera.
//
// t8/5 to czas, w jakim spoina i SWC stygną od 800 °C do 500 °C. Przy
// stalach drobnoziarnistych o podwyższonej wytrzymałości (S460–S960, QT /
// TMCP) WPS albo producent stali podaje okno t8/5: za krótko — twarda,
// krucha SWC; za długo — spada udarność i wytrzymałość.
//
// __ŹRÓDŁA__ (tekst normy niedostępny publicznie — wzory i tabl. D.1
// potwierdzone w opracowaniach, które je z niej przytaczają):
//  [O] Ovako, „Welding guide”, wzór (2) i tablica współczynników kształtu
//      https://metals.ovako.com/globalassets/downloads/tools---metal/welding_guide.pdf
//  [M] MIGAL.CO, kalkulator heat input / t8/5 — cytuje EN 1011-2:2001+A1:2003
//      zał. D (wzory 2D, 3D, d_t, tabl. D.1, przykłady liczbowe)
//      https://migal.co/en/service/welding-calculators/heat-input-calculator
//  [L] Lorch / voestalpine: Jaeschke, Luritzhofer (2014), wg DIN EN
//      1011-2:2001-05 (wzory 2D/3D)
//  [R] Rontescu i in. (2008) — wzór 2D z przykładem TIG.
// Numerów równań (D.x) w samej normie nie dało się potwierdzić — dlatego
// wzory są nazwane „3D”, „2D”, „d_t”, bez numerów.
//
// Q to energia liniowa wg EN 1011-1 (Z SPRAWNOŚCIĄ k procesu):
// Q = k × U × I × 60 / (v × 1000) [kJ/mm] — liczy ją `heat_input.dart`
// ([heatInputKJPerMm] z [HeatInputStandard.en1011]); ten plik jej nie
// powiela. Energia łuku wg ASME IX (bez k) NIE jest tym Q.

import 'dart:math' as math;

import 'heat_input.dart';

/// Rodzaj przepływu ciepła w modelu zał. D.
enum HeatFlow {
  /// Przepływ dwuwymiarowy — „cienka” blacha (d < d_t).
  twoD,

  /// Przepływ trójwymiarowy — „gruba” blacha (d ≥ d_t).
  threeD,
}

/// Rodzaj spoiny → współczynniki kształtu F2 (przepływ 2D) i F3 (3D)
/// wg EN 1011-2:2001 zał. D, tabl. D.1 (wartości za [O] i [M]).
///
/// Dla jednościegowych spoin pachwinowych tablica podaje F2 jako PRZEDZIAŁ
/// (narożna 0,67–0,9, teowa 0,45–0,67). Aplikacja liczy wtedy t8/5 dla obu
/// końców i pokazuje przedział wyniku; werdykt „w oknie” tylko wtedy, gdy
/// w oknie leży cały przedział (dolny koniec — krótszy t8/5 — chroni przed
/// za szybkim stygnięciem, górny przed za wolnym).
///
/// Pozostałe wiersze spotykane w tablicach t8/5 (3./4. pachwina w złączu
/// krzyżowym, zakładkowe, grań V) pochodzą z SEW 088, nie z EN 1011-2 —
/// pominięte.
enum WeldShape {
  /// Ścieg na powierzchni blachy (napawanie, „bead on plate”): F2 = F3 = 1.
  beadOnPlate(1.0, 1.0, 1.0),

  /// Ściegi wypełniające złącza doczołowego: F2 = F3 = 0,9.
  buttFillRun(0.9, 0.9, 0.9),

  /// Jednościegowa spoina pachwinowa w złączu narożnym: F2 = 0,67–0,9,
  /// F3 = 0,67.
  filletCorner(0.67, 0.9, 0.67),

  /// Jednościegowa spoina pachwinowa w złączu teowym: F2 = 0,45–0,67,
  /// F3 = 0,67.
  filletTee(0.45, 0.67, 0.67);

  const WeldShape(this.f2Min, this.f2Max, this.f3);

  /// F2 — dolna granica (tabl. D.1).
  final double f2Min;

  /// F2 — górna granica (tabl. D.1); równa [f2Min], gdy tablica podaje
  /// jedną liczbę.
  final double f2Max;

  /// F3 (tabl. D.1).
  final double f3;

  bool get hasF2Range => f2Max - f2Min > 1e-12;
}

/// Wzory zał. D mają człon 1/(500 − T0) — T0 ≥ 500 °C nie ma sensu
/// fizycznego ani matematycznego.
const double _t0Pole = 500;

bool _validQ(double q) => q.isFinite && q > 0;
bool _validT0(double t0) => t0.isFinite && t0 > -273.15 && t0 < _t0Pole;
bool _validD(double d) => d.isFinite && d > 0;
bool _validF(double f) => f.isFinite && f > 0;

/// t8/5 [s] dla przepływu TRÓJWYMIAROWEGO (gruba blacha), EN 1011-2:2001
/// zał. D, wzór 3D (potwierdzony: [O] wzór (2), [M], [L]):
///
///   t8/5 = (6700 − 5·T0) · Q · [1/(500 − T0) − 1/(800 − T0)] · F3
///
/// Q [kJ/mm], T0 — temperatura podgrzewania / międzyściegowa [°C].
/// `null` dla danych, z których nie da się liczyć.
double? t85ThreeD({
  required double heatInputKjMm,
  required double preheatC,
  double f3 = 1.0,
}) {
  if (!_validQ(heatInputKjMm) || !_validT0(preheatC) || !_validF(f3)) {
    return null;
  }
  final t0 = preheatC;
  return (6700 - 5 * t0) *
      heatInputKjMm *
      (1 / (500 - t0) - 1 / (800 - t0)) *
      f3;
}

/// t8/5 [s] dla przepływu DWUWYMIAROWEGO (cienka blacha), EN 1011-2:2001
/// zał. D, wzór 2D (potwierdzony: [O], [M], [L], [R]):
///
///   t8/5 = (4300 − 4,3·T0) · 10⁵ · Q²/d² · [(1/(500 − T0))² − (1/(800 − T0))²] · F2
///
/// d — grubość blachy [mm]. Q wchodzi do kwadratu — błąd Q podwaja się
/// w wyniku ([L]).
double? t85TwoD({
  required double heatInputKjMm,
  required double preheatC,
  required double thicknessMm,
  double f2 = 1.0,
}) {
  if (!_validQ(heatInputKjMm) ||
      !_validT0(preheatC) ||
      !_validD(thicknessMm) ||
      !_validF(f2)) {
    return null;
  }
  final t0 = preheatC;
  final a = 1 / (500 - t0);
  final b = 1 / (800 - t0);
  final q = heatInputKjMm;
  return (4300 - 4.3 * t0) *
      1e5 *
      (q * q) /
      (thicknessMm * thicknessMm) *
      (a * a - b * b) *
      f2;
}

/// Współczynnik C(T0) = (4300 − 4,3·T0) / (6700 − 5·T0) · 10⁵ · [1/(500 − T0)
/// + 1/(800 − T0)] — taki, że d_t² = C·Q (wzór na d_t, niżej).
double _transitionFactor(double t0) =>
    (4300 - 4.3 * t0) /
    (6700 - 5 * t0) *
    1e5 *
    (1 / (500 - t0) + 1 / (800 - t0));

/// Grubość przejściowa d_t [mm] między przepływem 2D i 3D, EN 1011-2:2001
/// zał. D (potwierdzona w [M]; BEZ współczynników F2/F3):
///
///   d_t = √{ (4300 − 4,3·T0)/(6700 − 5·T0) · 10⁵ · Q · [1/(500 − T0) + 1/(800 − T0)] }
///
/// d < d_t → przepływ 2D, w przeciwnym razie 3D ([M]). Z wzorów wynika
/// t2D/t3D = (F2/F3)·(d_t/d)², więc przy F2 = F3 wybór wg d i d_t to
/// po prostu większy z dwóch wyników.
double? transitionThicknessMm({
  required double heatInputKjMm,
  required double preheatC,
}) {
  if (!_validQ(heatInputKjMm) || !_validT0(preheatC)) return null;
  return math.sqrt(_transitionFactor(preheatC) * heatInputKjMm);
}

/// Energia Q [kJ/mm], przy której blacha grubości d przechodzi z przepływu
/// 3D w 2D (odwrócony wzór na d_t: Q = d² / C(T0)). Dla Q powyżej tej
/// wartości d < d_t, więc liczy się wzór 2D.
double? transitionHeatInputKjMm({
  required double preheatC,
  required double thicknessMm,
}) {
  if (!_validT0(preheatC) || !_validD(thicknessMm)) return null;
  return thicknessMm * thicknessMm / _transitionFactor(preheatC);
}

/// Wynik obliczenia t8/5.
class CoolingTimeResult {
  const CoolingTimeResult({
    required this.heatInputKjMm,
    required this.preheatC,
    required this.thicknessMm,
    required this.shape,
    required this.flow,
    required this.transitionThicknessMm,
    required this.t85MinS,
    required this.t85MaxS,
    required this.t85ThreeDS,
    required this.t85TwoDMinS,
    required this.t85TwoDMaxS,
  });

  final double heatInputKjMm;
  final double preheatC;
  final double thicknessMm;
  final WeldShape shape;

  /// Model wybrany przez porównanie d z d_t.
  final HeatFlow flow;
  final double transitionThicknessMm;

  /// t8/5 [s] w wybranym modelu. Dla spoin pachwinowych w przepływie 2D
  /// (F2 jako przedział z tabl. D.1) min < max; poza tym min == max.
  final double t85MinS;
  final double t85MaxS;

  /// Wartości obu modeli — do pokazania obok (bez wpływu na wynik).
  final double t85ThreeDS;
  final double t85TwoDMinS;
  final double t85TwoDMaxS;

  bool get isRange => t85MaxS - t85MinS > 1e-9;

  /// Współczynnik kształtu użyty w wybranym modelu (min; max).
  (double, double) get shapeFactor => flow == HeatFlow.threeD
      ? (shape.f3, shape.f3)
      : (shape.f2Min, shape.f2Max);
}

/// t8/5 wg zał. D z automatycznym wyborem 2D/3D. `null` dla danych, z których
/// nie da się liczyć (Q ≤ 0, d ≤ 0, T0 ≥ 500 °C, NaN).
CoolingTimeResult? coolingTime({
  required double heatInputKjMm,
  required double preheatC,
  required double thicknessMm,
  required WeldShape shape,
}) {
  if (!_validQ(heatInputKjMm) ||
      !_validT0(preheatC) ||
      !_validD(thicknessMm)) {
    return null;
  }
  final dt = transitionThicknessMm(
      heatInputKjMm: heatInputKjMm, preheatC: preheatC)!;
  final t3 = t85ThreeD(
      heatInputKjMm: heatInputKjMm, preheatC: preheatC, f3: shape.f3)!;
  final t2min = t85TwoD(
      heatInputKjMm: heatInputKjMm,
      preheatC: preheatC,
      thicknessMm: thicknessMm,
      f2: shape.f2Min)!;
  final t2max = t85TwoD(
      heatInputKjMm: heatInputKjMm,
      preheatC: preheatC,
      thicknessMm: thicknessMm,
      f2: shape.f2Max)!;
  // Absurdalnie duże Q (≈1e154) przepełnia Q² do ∞ — wynik „Infinity” na
  // ekranie byłby gorszy niż brak wyniku. Odrzucamy też underflow,
  // aby dodatnie obliczenie nie dawało pozornie prawidłowego zera.
  if (![dt, t3, t2min, t2max].every((v) => v.isFinite && v > 0)) return null;
  final flow = thicknessMm < dt ? HeatFlow.twoD : HeatFlow.threeD;
  return CoolingTimeResult(
    heatInputKjMm: heatInputKjMm,
    preheatC: preheatC,
    thicknessMm: thicknessMm,
    shape: shape,
    flow: flow,
    transitionThicknessMm: dt,
    t85MinS: flow == HeatFlow.twoD ? t2min : t3,
    t85MaxS: flow == HeatFlow.twoD ? t2max : t3,
    t85ThreeDS: t3,
    t85TwoDMinS: t2min,
    t85TwoDMaxS: t2max,
  );
}

/// Porównanie t8/5 z oknem z WPS / od producenta stali.
enum T85Verdict {
  /// Nie wpisano okna.
  notSet,

  /// Min > max, zero, ujemne — okno do poprawy.
  invalidWindow,

  /// Cały wynik w oknie.
  inWindow,

  /// Za krótko — stygnie za szybko (twarda, krucha SWC).
  tooShort,

  /// Za długo — stygnie za wolno (spadek udarności i wytrzymałości).
  tooLong,

  /// Przedział wyniku (spoina pachwinowa, F2 z tabl. D.1 jako przedział)
  /// częściowo poza oknem.
  partly,
}

bool _validWindow(double? min, double? max) =>
    !((min != null && (!min.isFinite || min <= 0)) ||
        (max != null && (!max.isFinite || max <= 0)) ||
        (min != null && max != null && min > max));

/// Werdykt dla przedziału t8/5 [tMin; tMax] (dla jednej liczby tMin == tMax).
/// Granice okna są granicami — bez pasma tolerancji. Wystarczy jedna.
T85Verdict checkT85Window(
  double tMin,
  double tMax, {
  double? min,
  double? max,
}) {
  if (min == null && max == null) return T85Verdict.notSet;
  if (!_validWindow(min, max)) return T85Verdict.invalidWindow;
  final lowOk = min == null || tMin >= min;
  final highOk = max == null || tMax <= max;
  if (lowOk && highOk) return T85Verdict.inWindow;
  if (min != null && tMax < min) return T85Verdict.tooShort;
  if (max != null && tMin > max) return T85Verdict.tooLong;
  return T85Verdict.partly;
}

/// Przedział wartości z rozwiązania odwrotnego. [clippedLow] / [clippedHigh]
/// — granica to brzeg przeszukiwanego zakresu, a nie granica okna t8/5
/// (np. „Q ≤ 1,2 kJ/mm” zamiast „0,05–1,2”).
class SolvedRange {
  const SolvedRange(this.min, this.max,
      {this.clippedLow = false, this.clippedHigh = false});

  final double min;
  final double max;
  final bool clippedLow;
  final bool clippedHigh;

  double get mid => (min + max) / 2;

  @override
  String toString() => 'SolvedRange($min–$max'
      '${clippedLow ? ', od brzegu' : ''}${clippedHigh ? ', do brzegu' : ''})';
}

/// Zakres Q przeszukiwany w rozwiązaniu odwrotnym [kJ/mm]. Granice
/// techniczne (od cienkiego ściegu TIG do grubego łuku krytego) — nie są
/// zakresem stosowania normy.
const double kQSearchMinKjMm = 0.05;
const double kQSearchMaxKjMm = 10.0;

/// Zakres T0 przeszukiwany w rozwiązaniu odwrotnym [°C].
const double kT0SearchMinC = 0;
const double kT0SearchMaxC = 300;

/// Rozwiązanie odwrotne: jakie Q daje t8/5 w oknie przy danym T0, d
/// i rodzaju spoiny. Szukane numerycznie (próbkowanie + bisekcja granic),
/// bo przy zmianie modelu 3D → 2D wynik może mieć skok (F2 ≠ F3).
/// Zwraca listę rozłącznych przedziałów (zwykle jeden; pusta — brak
/// rozwiązania w przeszukiwanym zakresie).
List<SolvedRange> heatInputRangesForWindow({
  required double preheatC,
  required double thicknessMm,
  required WeldShape shape,
  double? min,
  double? max,
}) {
  if (min == null && max == null) return const [];
  if (!_validWindow(min, max)) return const [];
  if (!_validT0(preheatC) || !_validD(thicknessMm)) return const [];
  bool ok(double q) {
    final r = coolingTime(
        heatInputKjMm: q,
        preheatC: preheatC,
        thicknessMm: thicknessMm,
        shape: shape);
    if (r == null) return false;
    return checkT85Window(r.t85MinS, r.t85MaxS, min: min, max: max) ==
        T85Verdict.inWindow;
  }

  return _solveSet(kQSearchMinKjMm, kQSearchMaxKjMm, ok, logScale: true);
}

/// Rozwiązanie odwrotne: jakie T0 daje t8/5 w oknie przy danym Q, d
/// i rodzaju spoiny (przeszukiwane [kT0SearchMinC]–[kT0SearchMaxC] °C).
List<SolvedRange> preheatRangesForWindow({
  required double heatInputKjMm,
  required double thicknessMm,
  required WeldShape shape,
  double? min,
  double? max,
}) {
  if (min == null && max == null) return const [];
  if (!_validWindow(min, max)) return const [];
  if (!_validQ(heatInputKjMm) || !_validD(thicknessMm)) return const [];
  bool ok(double t0) {
    final r = coolingTime(
        heatInputKjMm: heatInputKjMm,
        preheatC: t0,
        thicknessMm: thicknessMm,
        shape: shape);
    if (r == null) return false;
    return checkT85Window(r.t85MinS, r.t85MaxS, min: min, max: max) ==
        T85Verdict.inWindow;
  }

  return _solveSet(kT0SearchMinC, kT0SearchMaxC, ok);
}

/// Zbiór {x ∈ [lo; hi] : ok(x)} jako lista przedziałów. Próbkowanie gęste
/// (2000 kroków, w skali log dla Q), granice doprecyzowane bisekcją.
List<SolvedRange> _solveSet(
  double lo,
  double hi,
  bool Function(double) ok, {
  bool logScale = false,
  int steps = 2000,
}) {
  double at(int i) {
    if (i <= 0) return lo;
    if (i >= steps) return hi;
    final f = i / steps;
    return logScale
        ? lo * math.pow(hi / lo, f).toDouble()
        : lo + (hi - lo) * f;
  }

  // Granica między a (stan sa) i b (stan przeciwny) — bisekcja.
  double edge(double a, double b, bool sa) {
    for (var k = 0; k < 60; k++) {
      final m = (a + b) / 2;
      if (ok(m) == sa) {
        a = m;
      } else {
        b = m;
      }
    }
    return (a + b) / 2;
  }

  final out = <SolvedRange>[];
  var prevX = at(0);
  var prevOk = ok(prevX);
  double? start = prevOk ? lo : null;
  var startClipped = prevOk;
  for (var i = 1; i <= steps; i++) {
    final x = at(i);
    final cur = ok(x);
    if (cur && !prevOk) {
      start = edge(prevX, x, false);
      startClipped = false;
    } else if (!cur && prevOk && start != null) {
      out.add(SolvedRange(start, edge(prevX, x, true),
          clippedLow: startClipped));
      start = null;
    }
    prevX = x;
    prevOk = cur;
  }
  if (prevOk && start != null) {
    out.add(SolvedRange(start, hi,
        clippedLow: startClipped, clippedHigh: true));
  }
  return out;
}

/// Prędkość spawania [mm/min], przy której zadane U, I i k dają energię Q
/// (odwrócone Q = k·U·I·60/(v·1000)). Liczone przez [heatInputKJPerMm]
/// przy v = 1 mm/min — ten sam wzór, bez powielania stałych.
double? travelSpeedForHeatInput({
  required double volts,
  required double amps,
  required double efficiency,
  required double heatInputKjMm,
}) {
  if (!_validQ(heatInputKjMm)) return null;
  final qAtUnitSpeed = heatInputKJPerMm(
    volts: volts,
    amps: amps,
    travelMmPerMin: 1,
    standard: HeatInputStandard.en1011,
    efficiency: efficiency,
  );
  if (qAtUnitSpeed == null) return null;
  return qAtUnitSpeed / heatInputKjMm;
}

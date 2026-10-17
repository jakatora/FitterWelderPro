/// Spawarka: cykl pracy źródła z tabliczki znamionowej i przewody
/// spawalnicze — spadek napięcia, nagrzewanie, dobór przekroju.
///
/// Problemy spawacza, na które to odpowiada:
///  • „spawarka się wyłącza / przegrzewa” — ile minut na 10 może spawać przy
///    danym prądzie;
///  • „na końcu 40 m przewodu łuk słaby, elektroda się klei” — za cienki
///    przewód, za duży spadek napięcia;
///  • „jaki przekrój kupić / czy mogę przedłużyć”.
///
/// ŹRÓDŁA (sprawdzone 2026-10-17):
///
/// 1. Cykl pracy (duty cycle) — okres 10 min, otoczenie 40 °C:
///    • IEC 60974-1:2012 (wyd. 4; obecne wyd. 6:2021) — streszczenie IEC:
///      próba nagrzewania w temperaturze otoczenia 40 °C (p. 5.1);
///    • Lincoln Electric IM3014 (405-S/635-S): „sortie nominale à 40 °C”,
///      cykl „basé sur une période de 10 min”, nie używać powyżej 40 °C;
///    • Miller OM-360 (Syncrowave 180 SD), p. 3-5: cykl pracy to procent
///      10 minut, przez który źródło spawa obciążeniem znamionowym bez
///      przegrzania.
///    Tekstu normy (definicji) nie udało się otworzyć — okres 10 min za
///    instrukcjami producentów.
///
/// 2. Cykl pracy przy innym prądzie — AWS Welding Handbook, 9. wyd., t. 2
///    (cytowane w nocie AWS „Calculation of Duty Cycle other than rated
///    outputs”, 2008): Tₐ = (I/Iₐ)²·T oraz Iₐ = I·(T/Tₐ)^½; przykład
///    200 A / 60 % przy 250 A → 38 % (3,8 min na 10), przy 100 % → 155 A.
///    To SZACUNEK (nagrzewanie ∝ I²). Nota zaznacza „as far as permitted” —
///    powyżej prądu, który źródło ma na tabliczce, nie szacujemy („poza
///    zakresem źródła”). Wynik nie może przekroczyć 100 %.
///
/// 3. Obciążalność przewodów H01N2-D / H01N2-E (miedź) — tabela wg CENELEC
///    HD 22.6 S2 i HD 516 S2, otoczenie 25 °C, okres powtarzania 10 min
///    (dokument typu „Current ratings for welding cables”, HVJ 22.10.2003,
///    udostępniony przez waspsupplies.com). HD 516 S2 zastąpiła
///    EN 50565-1:2014 — jej zał. D ma tabelę D.4 „repeat cycle operation
///    based on a 10 min repeat period”; samej tabeli D.4 (płatnej) nie
///    porównaliśmy. Okres 10 min = okres cyklu pracy spawarki, i jest
///    ostrzejszy niż tabela 5-minutowa. Współczynniki temperatury
///    otoczenia: HVJ 2003 (25–45 °C) i Top Cable, karta TOPWELD H01N2-D,
///    wersja 10, 20.03.2025 (50 °C: 0,76).
///
/// 4. Spadek napięcia — „V na 100 A i 10 m przewodu, żyła w 85 °C, prąd
///    stały”: Top Cable 2025 (te same liczby w HVJ 2003). 85 °C =
///    maksymalna temperatura żyły H01N2-D (Top Cable). V/(100 A·10 m) to
///    liczbowo mΩ/m, więc ΔU = I·L·r. Odpowiada to ρ ≈ 0,0244–0,0251
///    Ω·mm²/m — więcej niż sama miedź w 85 °C (ρ₂₀ = 1/58 = 0,017241
///    Ω·mm²/m wg IEC 60028, α = 0,00393 1/K → 0,02165), bo żyła
///    wielodrutowa klasy 5 ma większy opór niż ρ/A. Liczymy z danych
///    przewodu (gorący przewód) — to bezpieczny kierunek.
///
/// 5. Próg spadku 4 V — Miller OM-360, p. 3-7: „Weld cable size (AWG) is
///    based on either a 4 volts or less drop or a current density of at
///    least 300 circular mils per ampere”; tabela liczy CAŁĄ pętlę
///    („Total Cable (Copper) Length In Weld Circuit”). Tabele Millera
///    odpowiadają miedzi w 20 °C (sprawdzone: 200 A, 60 m → 1/0), więc nasze
///    sprawdzenie z gorącym przewodem jest ostrzejsze — dobór bywa o rozmiar
///    większy. Normy EN jednej wartości nie podają → próg edytowalny.
///
/// Aluminium: brak tabel dla przewodów spawalniczych w źródłach (EN 50525-2-81
/// to miedź) — moduł liczy tylko miedź.
///
/// Bezpieczeństwo wyniku: cykl pracy W DÓŁ do 1 %, prąd maks. W DÓŁ do 1 A,
/// obciążalność W DÓŁ do 1 A, spadek napięcia W GÓRĘ do 0,1 V, dobór
/// przekroju W GÓRĘ do typoszeregu. Werdykty liczone z tych samych
/// zaokrąglonych liczb, które stoją na ekranie. Puste albo nieczytelne pole
/// przychodzi jako NaN i zawsze jest problemem — nigdy wynikiem.
///
/// Czysty Dart.
library;

import 'dart:convert';
import 'dart:math' as math;

// ─── Stałe ze źródeł ─────────────────────────────────────────────────────

/// Okres cyklu pracy [min] (IEC 60974-1; Lincoln IM3014; Miller OM-360).
const double kDutyPeriodMin = 10;

/// Temperatura otoczenia, dla której podaje się cykl pracy [°C].
const double kRatingAmbientC = 40;

/// Przekroje przewodów spawalniczych w module [mm²] (typoszereg H01N2-D).
const List<int> kCableSectionsMm2 = [16, 25, 35, 50, 70, 95];

/// Kolumny cyklu pracy tabeli obciążalności [%] — kolejność jak w źródle.
const List<int> kCableDutyColumnsPct = [100, 85, 80, 60, 35, 20, 8];

/// Obciążalność H01N2-D/E [A]: otoczenie 25 °C, okres powtarzania 10 min
/// (HD 22.6 S2 / HD 516 S2, dokument HVJ 2003). Kolumny jak
/// [kCableDutyColumnsPct].
const Map<int, List<int>> kCableAmpacity10MinA = {
  16: [135, 136, 136, 139, 150, 174, 243],
  25: [180, 182, 183, 190, 213, 254, 366],
  35: [225, 229, 231, 243, 279, 338, 497],
  50: [285, 293, 296, 316, 371, 457, 681],
  70: [355, 367, 373, 403, 482, 602, 908],
  95: [430, 448, 456, 498, 606, 765, 1164],
};

/// Temperatura odniesienia tabeli obciążalności [°C].
const int kCableTableAmbientC = 25;

/// Współczynniki obciążalności dla temperatury otoczenia „do X °C”
/// (HVJ 2003: 25–45 °C; Top Cable 2025: 50 °C). Bez współczynników > 1.
const List<(int, double)> kCableAmbientFactors = [
  (25, 1.00),
  (30, 0.96),
  (35, 0.91),
  (40, 0.87),
  (45, 0.82),
  (50, 0.76),
];

/// Spadek napięcia [V na 100 A i 10 m] = opór żyły [mΩ/m] w 85 °C, prąd
/// stały (Top Cable 2025; HVJ 2003).
const Map<int, double> kCableDropPer100A10mV = {
  16: 1.560,
  25: 0.998,
  35: 0.709,
  50: 0.493,
  70: 0.348,
  95: 0.264,
};

/// Maksymalna temperatura żyły H01N2-D [°C] (Top Cable 2025).
const double kCableConductorMaxC = 85;

/// Rezystywność miedzi wyżarzonej przy 20 °C [Ω·mm²/m] (IEC 60028: 1/58).
const double kCopperResistivity20 = 0.017241;

/// Współczynnik temperaturowy rezystancji miedzi przy 20 °C [1/K]
/// (IEC 60028).
const double kCopperTempCoef20 = 0.00393;

/// Domyślny próg spadku napięcia na przewodach [V] (Miller OM-360, IEWC).
const double kDefaultDropLimitV = 4.0;

// ─── Zakresy pól (granice wpisu, nie dane techniczne) ────────────────────

const int kPlateRows = 3;
const double kMaxCurrentA = 1500;
const double kMinDutyPct = 1;
const double kMaxDutyPct = 100;
const double kMaxLeadM = 500;
const double kMinDropLimitV = 0.5;
const double kMaxDropLimitV = 20;

const double _eps = 1e-9;

/// Rezystywność miedzi w temperaturze [t] °C [Ω·mm²/m] — tylko do opisu
/// i testu zgodności danych przewodu z fizyką.
double copperResistivityAt(double t) =>
    kCopperResistivity20 * (1 + kCopperTempCoef20 * (t - 20));

// ─── Zaokrąglenia ────────────────────────────────────────────────────────

/// W dół do liczby całkowitej (tolerancja na arytmetykę zmiennoprzecinkową).
int floorSafe(double v) => (v + _eps).floor();

/// W górę do 0,1.
double roundUpToTenth(double v) => (v * 10 - 1e-6).ceil() / 10;

// ─── Cykl pracy źródła ───────────────────────────────────────────────────

/// Punkt z tabliczki znamionowej: prąd I przy cyklu pracy X.
class PlatePoint {
  final double currentA;
  final double dutyPct;

  const PlatePoint(this.currentA, this.dutyPct);

  @override
  bool operator ==(Object other) =>
      other is PlatePoint &&
      other.currentA == currentA &&
      other.dutyPct == dutyPct;

  @override
  int get hashCode => Object.hash(currentA, dutyPct);

  @override
  String toString() => 'PlatePoint($currentA A, $dutyPct %)';
}

/// Wiersz tabliczki z ekranu. Pusty wiersz (oba pola puste) ekran pomija;
/// tu przychodzą tylko wiersze, w których coś wpisano — puste albo
/// nieczytelne pole jako NaN.
class PlateRowInput {
  /// Numer wiersza na ekranie (od 1) — do komunikatów.
  final int row;
  final double currentA;
  final double dutyPct;

  const PlateRowInput({
    required this.row,
    required this.currentA,
    required this.dutyPct,
  });

  bool get currentOk =>
      currentA.isFinite && currentA > 0 && currentA <= kMaxCurrentA;
  bool get dutyOk =>
      dutyPct.isFinite && dutyPct >= kMinDutyPct && dutyPct <= kMaxDutyPct;
  bool get ok => currentOk && dutyOk;
}

class DutyCycleInput {
  final List<PlateRowInput> rows;

  /// Prąd spawania I₂ [A].
  final double weldCurrentA;

  const DutyCycleInput({required this.rows, required this.weldCurrentA});
}

enum DutyProblemKind {
  /// Żadnego wiersza tabliczki.
  noPlate,

  /// Prąd w wierszu pusty / poza zakresem.
  plateCurrent,

  /// Cykl w wierszu pusty / poza 1–100 %.
  plateDuty,

  /// Dwa wiersze z tym samym prądem.
  duplicateCurrent,

  /// Większy prąd z większym cyklem — tabliczka tak nie wygląda.
  inconsistentPlate,

  /// Prąd spawania pusty / poza zakresem.
  weldCurrent,
}

class DutyProblem {
  final DutyProblemKind kind;

  /// Numer wiersza tabliczki (od 1) albo null.
  final int? row;

  const DutyProblem(this.kind, [this.row]);

  @override
  bool operator ==(Object other) =>
      other is DutyProblem && other.kind == kind && other.row == row;

  @override
  int get hashCode => Object.hash(kind, row);

  @override
  String toString() => 'DutyProblem($kind, $row)';
}

/// Poprawne punkty z wierszy (do zapisu ostatniej tabliczki) — wiersze
/// z błędem pomijane.
List<PlatePoint> validPlatePoints(List<PlateRowInput> rows) => [
      for (final r in rows)
        if (r.ok) PlatePoint(r.currentA, r.dutyPct),
    ];

List<DutyProblem> dutyProblems(DutyCycleInput i) {
  final out = <DutyProblem>[];
  if (i.rows.isEmpty) out.add(const DutyProblem(DutyProblemKind.noPlate));
  for (final r in i.rows) {
    if (!r.currentOk) out.add(DutyProblem(DutyProblemKind.plateCurrent, r.row));
    if (!r.dutyOk) out.add(DutyProblem(DutyProblemKind.plateDuty, r.row));
  }
  if (i.rows.isNotEmpty && i.rows.every((r) => r.ok)) {
    final sorted = [...i.rows]
      ..sort((a, b) => a.currentA.compareTo(b.currentA));
    var duplicate = false;
    var inconsistent = false;
    for (var k = 1; k < sorted.length; k++) {
      final lo = sorted[k - 1], hi = sorted[k];
      if ((hi.currentA - lo.currentA).abs() < _eps) {
        duplicate = true;
      } else if (hi.dutyPct > lo.dutyPct + _eps) {
        inconsistent = true;
      }
    }
    if (duplicate) out.add(const DutyProblem(DutyProblemKind.duplicateCurrent));
    if (inconsistent) {
      out.add(const DutyProblem(DutyProblemKind.inconsistentPlate));
    }
  }
  final w = i.weldCurrentA;
  if (!(w.isFinite && w > 0 && w <= kMaxCurrentA)) {
    out.add(const DutyProblem(DutyProblemKind.weldCurrent));
  }
  return out;
}

/// Szacunek AWS: cykl pracy przy prądzie [currentA] z punktu tabliczki
/// (bez obcięcia do 100 %).
double dutyFromPoint(PlatePoint p, double currentA) =>
    p.dutyPct * math.pow(p.currentA / currentA, 2);

/// Szacunek AWS: prąd przy cyklu [dutyPct] z punktu tabliczki.
double currentFromPoint(PlatePoint p, double dutyPct) =>
    p.currentA * math.sqrt(p.dutyPct / dutyPct);

class DutyCycleResult {
  /// Tabliczka posortowana rosnąco po prądzie.
  final List<PlatePoint> plate;
  final double weldCurrentA;

  /// Dopuszczalny cykl pracy [%] (maks. 100) przed zaokrągleniem; null —
  /// prąd powyżej największego z tabliczki (poza zakresem źródła).
  final double? dutyExactPct;

  /// Punkt, z którego wyszedł decydujący (najmniejszy) szacunek.
  final PlatePoint? estimateBasis;

  /// Punkt tabliczki gwarantujący cykl (najmniejszy prąd ≥ I₂), gdy to on
  /// decyduje (wartość z tabliczki ≥ szacunku).
  final PlatePoint? plateBasis;

  /// Prąd przy 100 % przed zaokrągleniem [A].
  final double i100ExactA;

  /// Prąd przy 100 % wprost z tabliczki (punkt 100 % ≥ szacunku).
  final bool i100FromPlate;

  const DutyCycleResult({
    required this.plate,
    required this.weldCurrentA,
    required this.dutyExactPct,
    required this.estimateBasis,
    required this.plateBasis,
    required this.i100ExactA,
    required this.i100FromPlate,
  });

  bool get outOfRange => dutyExactPct == null;

  /// Największy prąd z tabliczki (z najmniejszym cyklem).
  PlatePoint get maxPoint => plate.last;

  /// Cykl pracy W DÓŁ do 1 % — ta liczba stoi na ekranie.
  int? get dutyPct => dutyExactPct == null ? null : floorSafe(dutyExactPct!);

  /// Minuty spawania na okres 10 min (z zaokrąglonego cyklu).
  double? get weldMinutes =>
      dutyPct == null ? null : dutyPct! * kDutyPeriodMin / 100;

  /// Minuty przerwy na okres 10 min.
  double? get restMinutes =>
      weldMinutes == null ? null : kDutyPeriodMin - weldMinutes!;

  /// Wartość wprost z tabliczki (nie szacunek).
  bool get fromPlate => plateBasis != null;

  /// Prąd maks. przy 100 % — W DÓŁ do 1 A.
  int get i100A => floorSafe(i100ExactA);
}

/// Cykl pracy przy I₂ i prąd przy 100 %.
///
/// Z każdego punktu tabliczki liczymy szacunek AWS i bierzemy NAJMNIEJSZY
/// (ostrożnie), ale nie mniej niż gwarantuje sama tabliczka: przy prądzie
/// ≤ I z wiersza źródło wytrzyma co najmniej X z tego wiersza. Tak samo dla
/// prądu przy 100 %. Powyżej największego prądu z tabliczki — poza
/// zakresem (null w [DutyCycleResult.dutyExactPct]).
///
/// null, gdy dane mają problem (nigdy NaN ani ∞).
DutyCycleResult? computeDutyCycle(DutyCycleInput i) {
  if (dutyProblems(i).isNotEmpty) return null;
  final plate = [
    for (final r in i.rows) PlatePoint(r.currentA, r.dutyPct),
  ]..sort((a, b) => a.currentA.compareTo(b.currentA));
  final i2 = i.weldCurrentA;

  // Prąd przy 100 %: najmniejszy szacunek, nie mniej niż punkt 100 %
  // z tabliczki.
  var i100Est = double.infinity;
  for (final p in plate) {
    i100Est = math.min(i100Est, currentFromPoint(p, 100));
  }
  var i100Plate = 0.0;
  for (final p in plate) {
    if (p.dutyPct >= 100 - _eps) i100Plate = math.max(i100Plate, p.currentA);
  }
  final i100FromPlate = i100Plate >= i100Est - _eps;
  final i100 = i100FromPlate ? i100Plate : i100Est;

  // Cykl pracy przy I₂.
  double? duty;
  PlatePoint? estimateBasis;
  PlatePoint? plateBasis;
  if (i2 <= plate.last.currentA + _eps) {
    var est = double.infinity;
    for (final p in plate) {
      final v = dutyFromPoint(p, i2);
      if (v < est) {
        est = v;
        estimateBasis = p;
      }
    }
    // Szacunek obcięty do 100 % — z nim porównujemy tabliczkę: gdy oba dają
    // 100 %, podstawą jest tabliczka (np. 130 A / 100 % przy 100 A), nie
    // szacunek 140 % z 200 A / 35 %.
    final capped = math.min(est, kMaxDutyPct);
    // Gwarancja z tabliczki: najmniejszy prąd ≥ I₂.
    final guarantee = plate.firstWhere((p) => p.currentA >= i2 - _eps);
    if (guarantee.dutyPct >= capped - _eps) {
      duty = math.min(guarantee.dutyPct, kMaxDutyPct);
      plateBasis = guarantee;
      estimateBasis = null;
    } else {
      duty = capped;
    }
  }
  if (duty != null && !duty.isFinite) return null;
  if (!i100.isFinite || i100 <= 0) return null;
  return DutyCycleResult(
    plate: plate,
    weldCurrentA: i2,
    dutyExactPct: duty,
    estimateBasis: estimateBasis,
    plateBasis: plateBasis,
    i100ExactA: i100,
    i100FromPlate: i100FromPlate,
  );
}

// ─── Przewody spawalnicze ────────────────────────────────────────────────

class CableInput {
  /// Prąd spawania [A].
  final double currentA;

  /// Przewód spawalniczy (do uchwytu / palnika) [m].
  final double weldLeadM;

  /// Przewód masowy (powrotny) [m].
  final double returnLeadM;

  /// Przekrój [mm²] — jeden z [kCableSectionsMm2]; dobór go pomija.
  final int sectionMm2;

  /// Cykl pracy przewodu: czas jarzenia łuku na 10 min [%].
  final double dutyPct;

  /// Temperatura otoczenia „do” [°C] — jedna z [kCableAmbientFactors].
  final int ambientC;

  /// Próg spadku napięcia [V].
  final double dropLimitV;

  const CableInput({
    required this.currentA,
    required this.weldLeadM,
    required this.returnLeadM,
    required this.sectionMm2,
    required this.dutyPct,
    required this.ambientC,
    required this.dropLimitV,
  });

  CableInput withSection(int s) => CableInput(
        currentA: currentA,
        weldLeadM: weldLeadM,
        returnLeadM: returnLeadM,
        sectionMm2: s,
        dutyPct: dutyPct,
        ambientC: ambientC,
        dropLimitV: dropLimitV,
      );
}

enum CableProblem {
  current,
  weldLead,
  returnLead,
  noLength,
  section,
  duty,
  ambient,
  dropLimit,
}

bool _leadOk(double v) => v.isFinite && v >= 0 && v <= kMaxLeadM;

/// Problemy z danymi przewodu. [forSizing] — dobór przekroju: przekrój
/// z pola nie ma znaczenia.
List<CableProblem> cableProblems(CableInput i, {bool forSizing = false}) {
  final out = <CableProblem>[];
  final c = i.currentA;
  if (!(c.isFinite && c > 0 && c <= kMaxCurrentA)) {
    out.add(CableProblem.current);
  }
  final wOk = _leadOk(i.weldLeadM), rOk = _leadOk(i.returnLeadM);
  if (!wOk) out.add(CableProblem.weldLead);
  if (!rOk) out.add(CableProblem.returnLead);
  if (wOk && rOk && i.weldLeadM + i.returnLeadM <= 0) {
    out.add(CableProblem.noLength);
  }
  if (!forSizing && !kCableSectionsMm2.contains(i.sectionMm2)) {
    out.add(CableProblem.section);
  }
  final d = i.dutyPct;
  if (!(d.isFinite && d >= kMinDutyPct && d <= kMaxDutyPct)) {
    out.add(CableProblem.duty);
  }
  if (!kCableAmbientFactors.any((f) => f.$1 == i.ambientC)) {
    out.add(CableProblem.ambient);
  }
  final l = i.dropLimitV;
  if (!(l.isFinite && l >= kMinDropLimitV && l <= kMaxDropLimitV)) {
    out.add(CableProblem.dropLimit);
  }
  return out;
}

/// Kolumna tabeli dla cyklu [dutyPct]: najmniejsza kolumna ≥ cyklu (cykl
/// między kolumnami → kolumna wyższa, mniejszy prąd — ostrożnie).
int cableDutyColumn(double dutyPct) {
  var best = 100;
  for (final c in kCableDutyColumnsPct) {
    if (c >= dutyPct - _eps && c < best) best = c;
  }
  return best;
}

/// Współczynnik temperatury otoczenia dla „do [ambientC] °C”.
double cableAmbientFactor(int ambientC) =>
    kCableAmbientFactors.firstWhere((f) => f.$1 == ambientC).$2;

/// Obciążalność z tabeli przy 25 °C [A].
int cableTableAmpacityA(int sectionMm2, double dutyPct) {
  final col = kCableDutyColumnsPct.indexOf(cableDutyColumn(dutyPct));
  return kCableAmpacity10MinA[sectionMm2]![col];
}

class CableCheckResult {
  final CableInput input;

  const CableCheckResult(this.input);

  int get sectionMm2 => input.sectionMm2;

  /// Cała pętla: przewód spawalniczy + masowy [m].
  double get loopM => input.weldLeadM + input.returnLeadM;

  /// Opór 1 m żyły w 85 °C [mΩ/m] (= V na 100 A i 10 m).
  double get resistanceMOhmPerM => kCableDropPer100A10mV[sectionMm2]!;

  /// Odpowiadająca rezystywność [Ω·mm²/m].
  double get equivalentResistivity => resistanceMOhmPerM * sectionMm2 / 1000;

  /// ΔU = I·L·r [V] przed zaokrągleniem.
  double get dropExactV => input.currentA * loopM * resistanceMOhmPerM / 1000;

  /// ΔU W GÓRĘ do 0,1 V — ta liczba stoi na ekranie i decyduje.
  double get dropV => roundUpToTenth(dropExactV);

  bool get dropOk => dropV <= input.dropLimitV + _eps;

  /// Najdłuższa pętla [m, w dół do 1 m], przy której ΔU (w górę do 0,1 V)
  /// mieści się w progu. 0 — nawet 1 m przekracza próg.
  int get maxLoopM {
    // +1 i schodzenie w dół: odporne na arytmetykę zmiennoprzecinkową
    // i zaokrąglenie spadku w górę.
    var l = (input.dropLimitV * 1000 / (input.currentA * resistanceMOhmPerM))
            .floor() +
        1;
    while (l > 0 &&
        roundUpToTenth(input.currentA * l * resistanceMOhmPerM / 1000) >
            input.dropLimitV + _eps) {
      l--;
    }
    return math.max(l, 0);
  }

  /// Kolumna tabeli obciążalności [%].
  int get dutyColumnPct => cableDutyColumn(input.dutyPct);

  /// Obciążalność z tabeli (25 °C) [A].
  int get tableAmpacityA => cableTableAmpacityA(sectionMm2, input.dutyPct);

  double get ambientFactor => cableAmbientFactor(input.ambientC);

  /// Obciążalność po współczynniku otoczenia — W DÓŁ do 1 A.
  int get ampacityA => floorSafe(tableAmpacityA * ambientFactor);

  bool get heatOk => input.currentA <= ampacityA + _eps;

  bool get ok => dropOk && heatOk;
}

/// null, gdy dane mają problem.
CableCheckResult? checkCable(CableInput i) =>
    cableProblems(i).isEmpty ? CableCheckResult(i) : null;

class CableSizingResult {
  final CableInput input;

  /// Najmniejszy przekrój z typoszeregu spełniający oba warunki; null —
  /// żaden do 95 mm².
  final int? sectionMm2;

  /// Najmniejszy przekrój ze względu na nagrzewanie (null — żaden).
  final int? heatSectionMm2;

  /// Najmniejszy przekrój ze względu na spadek napięcia (null — żaden).
  final int? dropSectionMm2;

  const CableSizingResult({
    required this.input,
    required this.sectionMm2,
    required this.heatSectionMm2,
    required this.dropSectionMm2,
  });

  /// Sprawdzenie dobranego przekroju (te same liczby co na ekranie).
  CableCheckResult? get check => sectionMm2 == null
      ? null
      : CableCheckResult(input.withSection(sectionMm2!));

  bool get heatGoverns =>
      heatSectionMm2 != null &&
      (dropSectionMm2 == null || heatSectionMm2! >= dropSectionMm2!);

  bool get dropGoverns =>
      dropSectionMm2 != null &&
      (heatSectionMm2 == null || dropSectionMm2! >= heatSectionMm2!);
}

/// Dobór najmniejszego przekroju — W GÓRĘ do typoszeregu. null, gdy dane
/// mają problem.
CableSizingResult? sizeCable(CableInput i) {
  if (cableProblems(i, forSizing: true).isNotEmpty) return null;
  int? heat, drop;
  for (final s in kCableSectionsMm2) {
    final r = CableCheckResult(i.withSection(s));
    if (heat == null && r.heatOk) heat = s;
    if (drop == null && r.dropOk) drop = s;
  }
  final chosen = (heat == null || drop == null) ? null : math.max(heat, drop);
  return CableSizingResult(
    input: i,
    sectionMm2: chosen,
    heatSectionMm2: heat,
    dropSectionMm2: drop,
  );
}

// ─── Zapis ostatniej tabliczki ───────────────────────────────────────────

/// Klucz z wersją — zmiana formatu = nowy klucz.
const String kPowerSourcePlatePrefsKey = 'power_source_plate_v1';

/// Kopia surowego zapisu odczytanego ze stratą (tylko pierwsza).
const String kPowerSourcePlateCorruptPrefsKey = 'power_source_plate_v1_corrupt';

String encodePlate(List<PlatePoint> points) => jsonEncode({
      'v': 1,
      'points': [
        for (final p in points.take(kPlateRows))
          {'i': p.currentA, 'x': p.dutyPct},
      ],
    });

/// Odczyt zapisu: to, co da się odczytać, i czy coś stracono.
({List<PlatePoint> points, bool lossy}) decodePlateDetailed(String raw) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return (points: const <PlatePoint>[], lossy: true);
  }
  if (json is! Map || json['points'] is! List) {
    return (points: const <PlatePoint>[], lossy: true);
  }
  var lossy = json['v'] != 1;
  final out = <PlatePoint>[];
  for (final e in json['points'] as List) {
    final i = e is Map ? e['i'] : null;
    final x = e is Map ? e['x'] : null;
    if (i is num && x is num) {
      final row = PlateRowInput(
          row: out.length + 1, currentA: i.toDouble(), dutyPct: x.toDouble());
      if (row.ok && out.length < kPlateRows) {
        out.add(PlatePoint(row.currentA, row.dutyPct));
        continue;
      }
    }
    lossy = true;
  }
  return (points: out, lossy: lossy);
}

// ─── Tekst ───────────────────────────────────────────────────────────────

/// Liczba z [decimals] miejscami: przecinek po polsku, kropka po angielsku.
String psFixed(double v, int decimals, {required bool en}) {
  var s = v.toStringAsFixed(decimals);
  if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  return en ? s : s.replaceAll('.', ',');
}

/// Liczba bez zbędnych zer (do 3 miejsc): 4,0 → „4”, 0,709 → „0,709”.
String psNum(double v, {required bool en}) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

String platePointText(PlatePoint p, {required bool en}) =>
    '${psNum(p.currentA, en: en)} A / ${psNum(p.dutyPct, en: en)} %';

/// Zastrzeżenie przy każdym wyniku.
String powerSourceDisclaimer({required bool en}) => en
    ? 'ESTIMATE: the rating plate, the duty cycle chart in the manual and '
        'the cable data sheet take precedence. The duty cycle applies to a '
        '10 min period and 40 °C ambient.'
    : 'SZACUNEK: pierwszeństwo mają tabliczka znamionowa, wykres cyklu '
        'pracy z instrukcji i karta katalogowa przewodu. Cykl pracy dotyczy '
        'okresu 10 min i otoczenia 40 °C.';

/// Wzór cyklu pracy i źródło.
String dutyFormulaNote({required bool en}) => en
    ? 'Estimate (AWS Welding Handbook, 9th ed., vol. 2): X₂ = X₁·(I₁/I₂)², '
        'I₁₀₀ = I₁·√(X₁/100). Worked from every plate row, the lowest result '
        'is used (never below what the plate itself guarantees); duty cycle '
        'rounded down to 1 %, current down to 1 A, max. 100 %. Above the '
        'highest plate current — outside the rating of the power source.'
    : 'Szacunek (AWS Welding Handbook, wyd. 9, t. 2): X₂ = X₁·(I₁/I₂)², '
        'I₁₀₀ = I₁·√(X₁/100). Liczymy z każdego wiersza tabliczki i bierzemy '
        'najmniejszy wynik (nie mniej, niż gwarantuje sama tabliczka); cykl '
        'w dół do 1 %, prąd w dół do 1 A, maks. 100 %. Powyżej największego '
        'prądu z tabliczki — poza zakresem źródła.';

/// Okres, temperatura otoczenia, pierwszeństwo tabliczki.
String dutyAmbientNote({required bool en}) => en
    ? 'Duty cycle on the plate: share of a 10 min period at 40 °C ambient '
        '(IEC 60974-1 heating test at 40 °C; Lincoln, Miller manuals). '
        'Lincoln: do not use the power source above 40 °C. The plate and the '
        'duty cycle chart in the manual take precedence over the formula.'
    : 'Cykl pracy z tabliczki: część okresu 10 min przy otoczeniu 40 °C '
        '(IEC 60974-1 — próba nagrzewania w 40 °C; instrukcje Lincoln, '
        'Miller). Lincoln: nie używać źródła powyżej 40 °C. Tabliczka '
        'i wykres cyklu pracy z instrukcji mają pierwszeństwo przed wzorem.';

/// Opis spadku napięcia.
String cableDropNote({required bool en}) {
  final r = [
    for (final s in kCableSectionsMm2)
      '$s mm² ${psFixed(kCableDropPer100A10mV[s]!, 3, en: en)}',
  ].join('; ');
  final rho20 = psFixed(kCopperResistivity20, 4, en: en);
  final rho85 = psFixed(copperResistivityAt(kCableConductorMaxC), 4, en: en);
  return en
      ? 'ΔU = I · L · r. L — the whole loop (welding lead + return lead), '
          'r — resistance of 1 m of H01N2-D conductor at 85 °C (max. '
          'conductor temperature), DC, in mΩ/m = V per 100 A and 10 m '
          '(Top Cable data sheet 2025, HD 516): $r. That is ρ ≈ 0.025 '
          'Ω·mm²/m: copper $rho20 at 20 °C (IEC 60028), about $rho85 at 85 °C, '
          'plus the stranded conductor. Rounded up to 0.1 V. Copper only.'
      : 'ΔU = I · L · r. L — cała pętla (przewód spawalniczy + masowy), '
          'r — opór 1 m żyły H01N2-D w 85 °C (maks. temperatura żyły), prąd '
          'stały, w mΩ/m = V na 100 A i 10 m (karta Top Cable 2025, HD 516): '
          '$r. To odpowiada ρ ≈ 0,025 Ω·mm²/m: miedź $rho20 przy 20 °C '
          '(IEC 60028), ok. $rho85 w 85 °C, plus żyła wielodrutowa. W górę do '
          '0,1 V. Tylko miedź.';
}

/// Skąd próg 4 V.
String dropLimitNote({required bool en}) {
  final v = psNum(kDefaultDropLimitV, en: en);
  return en
      ? 'Limit $v V: Miller cable size table (drop of $v V or less over the '
          'whole loop) and the IEWC chart. EN standards give no single value '
          '— enter your own if you have a guideline. Miller works with cold '
          'copper (20 °C); here the cable is hot, so the size may come out '
          'one step larger.'
      : 'Próg $v V: tabela doboru przewodów Millera (spadek do $v V na całej '
          'pętli) i tabela IEWC. Normy EN nie podają jednej wartości — wpisz '
          'własny, jeśli masz wytyczne. Miller liczy zimną miedź (20 °C), tu '
          'przewód nagrzany — przekrój bywa o rozmiar większy.';
}

/// Skąd obciążalność.
String cableHeatNote({required bool en}) {
  final f = [
    for (final (t, k) in kCableAmbientFactors.skip(1))
      '$t °C ${psFixed(k, 2, en: en)}',
  ].join('; ');
  return en
      ? 'Current rating of H01N2-D / H01N2-E to HD 22.6 and HD 516 (now '
          'EN 50565-1 Annex D): 25 °C ambient, 10 min repeat period — the '
          'same period as the welder duty cycle. A duty cycle between columns '
          'takes the higher column (lower current). Ambient factors: $f. '
          'Rounded down to 1 A. Both leads of the same size — if they differ, '
          'check the thinner one.'
      : 'Obciążalność H01N2-D / H01N2-E wg HD 22.6 i HD 516 (dziś '
          'EN 50565-1, zał. D): otoczenie 25 °C, okres powtarzania 10 min — '
          'jak cykl pracy spawarki. Cykl między kolumnami → kolumna wyższa '
          '(mniejszy prąd). Współczynniki otoczenia: $f. W dół do 1 A. Oba '
          'przewody tego samego przekroju — przy różnych sprawdź cieńszy.';
}

// ─── Szybkie wskazówki ───────────────────────────────────────────────────

class PowerSourceTip {
  final String id;
  final String titlePl;
  final String titleEn;
  final String textPl;
  final String textEn;
  final String source;

  const PowerSourceTip({
    required this.id,
    required this.titlePl,
    required this.titleEn,
    required this.textPl,
    required this.textEn,
    required this.source,
  });

  String title({required bool en}) => en ? titleEn : titlePl;
  String text({required bool en}) => en ? textEn : textPl;
}

const List<PowerSourceTip> kPowerSourceTips = [
  PowerSourceTip(
    id: 'return-close',
    titlePl: 'Masa blisko spoiny, wprost na przedmiot',
    titleEn: 'Work clamp close to the weld, on the workpiece',
    textPl: 'Zacisk masy na czystym metalu (styk metal–metal), jak najbliżej '
        'miejsca spawania — nie przez obce rurociągi, konstrukcje, szyny ani '
        'łańcuchy. Prąd płynący długą, nieznaną drogą grozi porażeniem '
        'i pożarem.',
    textEn: 'Work clamp on clean metal (metal-to-metal contact), as close to '
        'the weld as possible — never through other pipes, steelwork, rails '
        'or chains. Current travelling long, unknown paths can cause electric '
        'shock and fire.',
    source: '§ 30 pkt 3–4 rozp. MG z 27.04.2000 (Dz.U. 2000 nr 40 poz. 470); '
        'Miller OM-360, rozdz. 1',
  ),
  PowerSourceTip(
    id: 'cable-condition',
    titlePl: 'Bez przewodów zużytych i za cienkich',
    titleEn: 'No worn or undersized cables',
    textPl: 'Nie używaj przewodów zużytych, uszkodzonych, za cienkich ani '
        'źle łączonych.',
    textEn: 'Do not use worn, damaged, undersized or poorly spliced cables.',
    source: 'Miller OM-360, rozdz. 1',
  ),
  PowerSourceTip(
    id: 'cables-together',
    titlePl: 'Przewody krótko i razem, bez zwojów',
    titleEn: 'Leads short and together, no coils',
    textPl: 'Przewód spawalniczy i masowy prowadź blisko siebie (np. spięte '
        'taśmą), z boku, nie owijaj ich wokół ciała. Długość i ułożenie '
        'przewodów (zwinięty czy rozłożony) zmieniają indukcyjność obwodu; '
        'większa indukcyjność przy MIG/MAG to więcej rozprysku i mniej '
        'stabilny łuk — nadmiaru nie zostawiaj zwiniętego na szpuli.',
    textEn: 'Run the welding and return leads close together (e.g. taped), '
        'to one side, never coiled around your body. The length and the '
        'layout of the leads (coiled or straight) change the inductance of '
        'the circuit; with MIG/MAG more inductance means more spatter and a '
        'less stable arc — do not leave the spare length coiled on a reel.',
    source: 'Miller OM-360, rozdz. 1 (pola EM); Fronius „LSC Advanced”; '
        'US 11642737 B2 (Illinois Tool Works)',
  ),
  PowerSourceTip(
    id: 'no-load',
    titlePl: 'Mokro, ciasno, zbiorniki — niskie napięcie biegu jałowego',
    titleEn: 'Damp, cramped, tanks — low open-circuit voltage',
    textPl: 'Na mokro, w ciasnym miejscu i gdy grozi upadek nie spawaj prądem '
        'przemiennym (AC). W przestrzeniach zamkniętych źródło z ograniczonym '
        'napięciem biegu jałowego (U₀ na tabliczce, urządzenie VRD) — '
        'np. SafeWork NSW (AS 1674.2): maks. 48 V AC rms, gorąco i wilgotno '
        '25 V AC rms.',
    textEn: 'Do not weld with AC in damp areas, where movement is confined or '
        'where there is a danger of falling. In confined spaces use a power '
        'source with limited open-circuit voltage (U₀ on the plate, a VRD) — '
        'e.g. SafeWork NSW (AS 1674.2): max. 48 V AC rms, hot and humid '
        '25 V AC rms.',
    source: 'Miller OM-360, rozdz. 1; SafeWork NSW, alert „Arc welding”, '
        '17.03.2020',
  ),
];

// ─── Udostępnianie ───────────────────────────────────────────────────────

/// Tekst do udostępnienia. Każda część opcjonalna — brak wyniku to brak
/// sekcji, nie zero.
String powerSourceShareText({
  required bool en,
  DutyCycleResult? duty,
  CableCheckResult? cable,
  CableSizingResult? sizing,
}) {
  String n(double v) => psNum(v, en: en);
  String f1(double v) => psFixed(v, 1, en: en);
  final b = StringBuffer()
    ..writeln(en
        ? 'Welder: duty cycle and cables'
        : 'Spawarka: cykl pracy i przewody');
  if (duty != null) {
    final plate = duty.plate.map((p) => platePointText(p, en: en)).join(', ');
    b
      ..writeln()
      ..writeln(en
          ? 'Duty cycle of the power source (10 min period, 40 °C):'
          : 'Cykl pracy źródła (okres 10 min, otoczenie 40 °C):')
      ..writeln(en ? 'Rating plate: $plate' : 'Tabliczka: $plate');
    if (duty.outOfRange) {
      b.writeln(en
          ? 'Welding current ${n(duty.weldCurrentA)} A — outside the rating '
              'of the power source (highest on the plate '
              '${n(duty.maxPoint.currentA)} A).'
          : 'Prąd spawania ${n(duty.weldCurrentA)} A — poza zakresem źródła '
              '(największy z tabliczki ${n(duty.maxPoint.currentA)} A).');
    } else {
      b.writeln(en
          ? 'Welding current ${n(duty.weldCurrentA)} A → duty cycle '
              '${duty.dutyPct} %: ${f1(duty.weldMinutes!)} min welding, '
              '${f1(duty.restMinutes!)} min rest in every 10 min'
          : 'Prąd spawania ${n(duty.weldCurrentA)} A → cykl pracy '
              '${duty.dutyPct} %: ${f1(duty.weldMinutes!)} min spawania, '
              '${f1(duty.restMinutes!)} min przerwy na każde 10 min');
      if (duty.fromPlate) {
        b.writeln(en
            ? '(from the plate: ${platePointText(duty.plateBasis!, en: en)})'
            : '(z tabliczki: ${platePointText(duty.plateBasis!, en: en)})');
      } else {
        b.writeln(en
            ? '(estimate from ${platePointText(duty.estimateBasis!, en: en)}: '
                'X₂ = X₁·(I₁/I₂)²)'
            : '(szacunek z ${platePointText(duty.estimateBasis!, en: en)}: '
                'X₂ = X₁·(I₁/I₂)²)');
      }
    }
    b.writeln(en
        ? 'Continuous welding (100 %): up to ${duty.i100A} A'
        : 'Praca ciągła (100 %): do ${duty.i100A} A');
  }
  if (cable != null) {
    final i = cable.input;
    b
      ..writeln()
      ..writeln(en ? 'Cables (H01N2-D, copper):' : 'Przewody (H01N2-D, miedź):')
      ..writeln(en
          ? 'Current ${n(i.currentA)} A, loop ${n(i.weldLeadM)} + '
              '${n(i.returnLeadM)} = ${n(cable.loopM)} m, '
              '${cable.sectionMm2} mm², duty cycle ${n(i.dutyPct)} %, '
              'ambient up to ${i.ambientC} °C'
          : 'Prąd ${n(i.currentA)} A, pętla ${n(i.weldLeadM)} + '
              '${n(i.returnLeadM)} = ${n(cable.loopM)} m, '
              '${cable.sectionMm2} mm², cykl ${n(i.dutyPct)} %, otoczenie do '
              '${i.ambientC} °C')
      ..writeln(cable.dropOk
          ? (en
              ? 'Voltage drop ΔU = ${f1(cable.dropV)} V — within the '
                  '${n(i.dropLimitV)} V limit'
              : 'Spadek napięcia ΔU = ${f1(cable.dropV)} V — w progu '
                  '${n(i.dropLimitV)} V')
          : (en
              ? 'Voltage drop ΔU = ${f1(cable.dropV)} V — ABOVE the '
                  '${n(i.dropLimitV)} V limit (cable too thin or loop too '
                  'long)'
              : 'Spadek napięcia ΔU = ${f1(cable.dropV)} V — POWYŻEJ progu '
                  '${n(i.dropLimitV)} V (za cienki przewód albo za długa '
                  'pętla)'))
      ..writeln(en
          ? 'Longest loop for ${n(i.dropLimitV)} V: ${cable.maxLoopM} m'
          : 'Najdłuższa pętla dla ${n(i.dropLimitV)} V: ${cable.maxLoopM} m')
      ..writeln(cable.heatOk
          ? (en
              ? 'Heating: rating ${cable.ampacityA} A ≥ ${n(i.currentA)} A — OK'
              : 'Nagrzewanie: obciążalność ${cable.ampacityA} A ≥ '
                  '${n(i.currentA)} A — OK')
          : (en
              ? 'Heating: rating ${cable.ampacityA} A < ${n(i.currentA)} A — '
                  'SIZE TOO SMALL'
              : 'Nagrzewanie: obciążalność ${cable.ampacityA} A < '
                  '${n(i.currentA)} A — PRZEKRÓJ ZA MAŁY'));
  }
  if (sizing != null) {
    b.writeln();
    final s = sizing.sectionMm2;
    if (s == null) {
      b.writeln(en
          ? 'Smallest size: none up to 95 mm² — shorten the loop or reduce '
              'the current'
          : 'Najmniejszy przekrój: żaden do 95 mm² — skróć pętlę albo '
              'zmniejsz prąd');
    } else {
      final why = sizing.heatGoverns && sizing.dropGoverns
          ? (en ? 'heating and voltage drop' : 'nagrzewanie i spadek napięcia')
          : sizing.heatGoverns
              ? (en ? 'heating' : 'nagrzewanie')
              : (en ? 'voltage drop' : 'spadek napięcia');
      b.writeln(en
          ? 'Smallest size: $s mm² (governed by $why)'
          : 'Najmniejszy przekrój: $s mm² (decyduje $why)');
    }
  }
  b
    ..writeln()
    ..write(powerSourceDisclaimer(en: en));
  return b.toString();
}

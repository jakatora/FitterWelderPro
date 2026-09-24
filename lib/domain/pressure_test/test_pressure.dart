/// Ciśnienie próby ciśnieniowej — presety norm i czysta arytmetyka, bez UI.
///
/// Wydzielone z `hydrotest_screen.dart`, który liczył wyłącznie
/// `Pt = współczynnik × P` z podpisami mnożników niezgodnymi z normami
/// („1,43× B31.1 para”, „1,3× PED gaz”) i bez korekty temperaturowej ST/S.
///
/// Źródła (zweryfikowane 2026-09-24; szczegóły i ręczne przeliczenia w
/// `test/domain/pressure_test/test_pressure_test.dart`):
///  * ASME B31.3 §345.4.2 — hydro: Pt = 1,5·P·ST/S, ST/S ≤ 6,5.
///    §345.2.1(a) (starsze wydania: §345.4.2(c)) — obniżenie Pt, gdy
///    naprężenie przekroczyłoby Re w temp. próby lub 1,5 × rating komponentu.
///    §345.2.2(a) — min. 10 min pod ciśnieniem próby.
///  * ASME B31.3 §345.5.4 — pneumatyczna: Pt ≥ 1,1·P, ≤ mniejsza z 1,33·P
///    i ciśnienia dającego 90 % Re.
///  * ASME B31.1 §137.4.5 — hydro: Pt ≥ 1,5·P (bez ST/S).
///  * EN 13480-5 (§9.3.2), PED 2014/68/UE zał. I pkt 7.4 — hydro: większa z
///    1,25·PS·f_test/f i 1,43·PS; czas trzymania 30 min (EN 13480-5).
///  * ASME VIII-1 UG-99(b) — hydro zbiorników: Pt = 1,3·MAWP·LSR.
library;

/// Rodzaj medium próby.
enum PressureTestMethod { hydrostatic, pneumatic }

/// Preset normowy. [id] trafia do bazy/protokołu — NIE zmieniać istniejących.
enum PressureTestPreset {
  /// ASME B31.3 — próba hydrostatyczna rurociągów procesowych.
  b313Hydro(
    id: 'b31_3_hydro',
    method: PressureTestMethod.hydrostatic,
    code: 'ASME B31.3',
    clause: '§345.4.2',
    factor: 1.5,
    ratioSymbol: 'ST/S',
    ratioCap: 6.5,
    minHoldMinutes: 10,
    holdClause: 'ASME B31.3 §345.2.2(a)',
    pressureSymbol: 'P',
  ),

  /// ASME B31.3 — próba pneumatyczna.
  b313Pneumatic(
    id: 'b31_3_pneumatic',
    method: PressureTestMethod.pneumatic,
    code: 'ASME B31.3',
    clause: '§345.5.4',
    factor: 1.1,
    maxFactor: 1.33,
    minHoldMinutes: 10,
    holdClause: 'ASME B31.3 §345.2.2(a)',
    pressureSymbol: 'P',
  ),

  /// ASME B31.1 — próba hydrostatyczna rurociągów energetycznych.
  b311Hydro(
    id: 'b31_1_hydro',
    method: PressureTestMethod.hydrostatic,
    code: 'ASME B31.1',
    clause: '§137.4.5',
    factor: 1.5,
    minHoldMinutes: 10,
    holdClause: 'ASME B31.1 §137.4.5',
    pressureSymbol: 'P',
  ),

  /// EN 13480-5 / PED 2014/68/UE — próba hydrostatyczna.
  en13480Hydro(
    id: 'en13480_ped_hydro',
    method: PressureTestMethod.hydrostatic,
    code: 'EN 13480-5 / PED 2014/68/UE',
    clause: '§9.3.2 / zał. I pkt 7.4',
    factor: 1.25,
    ratioSymbol: 'f_test/f',
    floorFactor: 1.43,
    minHoldMinutes: 30,
    holdClause: 'EN 13480-5 §9.3.2',
    pressureSymbol: 'PS',
  ),

  /// ASME VIII-1 — próba hydrostatyczna zbiornika ciśnieniowego.
  asmeVIII1Hydro(
    id: 'asme_viii_1_hydro',
    method: PressureTestMethod.hydrostatic,
    code: 'ASME VIII-1',
    clause: 'UG-99(b)',
    factor: 1.3,
    ratioSymbol: 'LSR',
    pressureSymbol: 'MAWP',
  );

  const PressureTestPreset({
    required this.id,
    required this.method,
    required this.code,
    required this.clause,
    required this.factor,
    required this.pressureSymbol,
    this.ratioSymbol,
    this.ratioCap,
    this.floorFactor,
    this.maxFactor,
    this.minHoldMinutes,
    this.holdClause,
  });

  /// Stały identyfikator do zapisu (baza, protokół).
  final String id;
  final PressureTestMethod method;

  /// Norma, np. `ASME B31.3`.
  final String code;

  /// Paragraf z wzorem na ciśnienie próby.
  final String clause;

  /// Mnożnik ciśnienia obliczeniowego.
  final double factor;

  /// Symbol ciśnienia bazowego w normie: `P`, `PS`, `MAWP`.
  final String pressureSymbol;

  /// Symbol korekty temperaturowej (`ST/S`, `f_test/f`, `LSR`) albo `null`,
  /// gdy norma jej nie stosuje.
  final String? ratioSymbol;

  /// Górne ograniczenie stosunku naprężeń (B31.3: 6,5).
  final double? ratioCap;

  /// Dolna granica jako mnożnik ciśnienia (EN 13480-5: 1,43·PS).
  final double? floorFactor;

  /// Górna granica jako mnożnik ciśnienia (B31.3 pneumatyczna: 1,33·P).
  final double? maxFactor;

  /// Minimalny czas pod ciśnieniem próby [min] albo `null`, gdy aplikacja
  /// nie ma zweryfikowanej wartości dla tej normy (wtedy: wg procedury).
  final double? minHoldMinutes;

  /// Paragraf dla [minHoldMinutes].
  final String? holdClause;

  bool get isPneumatic => method == PressureTestMethod.pneumatic;

  /// `ASME B31.3 §345.4.2`.
  String get reference => '$code $clause';

  /// Wzór do wyświetlenia, np. `Pt = 1,5 · P · ST/S (ST/S ≤ 6,5)`.
  String formula({String decimalSeparator = ','}) {
    String n(double v) {
      var s = v.toString();
      if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
      return s.replaceAll('.', decimalSeparator);
    }

    final base = 'Pt = ${n(factor)} · $pressureSymbol'
        '${ratioSymbol == null ? '' : ' · $ratioSymbol'}';
    if (floorFactor != null) {
      return 'Pt = max(${base.substring(5)}; ${n(floorFactor!)} · $pressureSymbol)';
    }
    if (ratioCap != null) return '$base  ($ratioSymbol ≤ ${n(ratioCap!)})';
    if (maxFactor != null) {
      return '$base  (≤ ${n(maxFactor!)} · $pressureSymbol)';
    }
    return base;
  }

  static PressureTestPreset? fromId(String? id) {
    if (id == null) return null;
    for (final p in values) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Wynik obliczenia ciśnienia próby.
class PressureTestResult {
  final PressureTestPreset preset;
  final double designBar;

  /// Minimalne ciśnienie próby [bar].
  final double testPressureBar;

  /// Stosunek naprężeń faktycznie użyty (po ograniczeniu); 1,0 dla presetów
  /// bez korekty temperaturowej.
  final double ratioApplied;

  /// True, gdy wpisany stosunek przekroczył [PressureTestPreset.ratioCap].
  final bool ratioCapped;

  /// True, gdy o wyniku zdecydowała dolna granica (EN 13480-5: 1,43·PS).
  final bool floorGoverns;

  /// Górna granica ciśnienia próby [bar] albo `null`.
  final double? maxTestPressureBar;

  const PressureTestResult({
    required this.preset,
    required this.designBar,
    required this.testPressureBar,
    required this.ratioApplied,
    required this.ratioCapped,
    required this.floorGoverns,
    required this.maxTestPressureBar,
  });

  /// Pt / P — to, co dotąd zapisywano w rekordzie jako „factor”.
  double get effectiveFactor => testPressureBar / designBar;
}

/// Minimalne ciśnienie próby wg [preset].
///
/// [designBar] — ciśnienie obliczeniowe (P / PS / MAWP) [bar], > 0.
/// [stressRatio] — ST/S, f_test/f albo LSR (> 0); ignorowany przez presety
/// bez korekty temperaturowej.
PressureTestResult computeTestPressure({
  required PressureTestPreset preset,
  required double designBar,
  double stressRatio = 1.0,
}) {
  if (!designBar.isFinite || !(designBar > 0)) {
    throw ArgumentError.value(designBar, 'designBar', 'musi być > 0');
  }
  if (!stressRatio.isFinite || !(stressRatio > 0)) {
    throw ArgumentError.value(stressRatio, 'stressRatio', 'musi być > 0');
  }
  var ratio = preset.ratioSymbol == null ? 1.0 : stressRatio;
  var capped = false;
  final cap = preset.ratioCap;
  if (cap != null && ratio > cap) {
    ratio = cap;
    capped = true;
  }
  var pt = preset.factor * designBar * ratio;
  var floorGoverns = false;
  final floor = preset.floorFactor;
  if (floor != null && floor * designBar > pt) {
    pt = floor * designBar;
    floorGoverns = true;
  }
  final max = preset.maxFactor;
  return PressureTestResult(
    preset: preset,
    designBar: designBar,
    testPressureBar: pt,
    ratioApplied: ratio,
    ratioCapped: capped,
    floorGoverns: floorGoverns,
    maxTestPressureBar: max == null ? null : max * designBar,
  );
}

void _checkGeometry(double odMm, double wallMm) {
  if (!odMm.isFinite || !(odMm > 0)) {
    throw ArgumentError.value(odMm, 'odMm', 'musi być > 0');
  }
  if (!wallMm.isFinite || !(wallMm > 0) || 2 * wallMm >= odMm) {
    throw ArgumentError.value(wallMm, 'wallMm', 'oczekiwane 0 < t < OD/2');
  }
}

/// Nominalne naprężenie obwodowe (Barlow, średnica zewnętrzna):
/// σ = P · D / (2 · t) [MPa], P w barach (1 MPa = 10 bar).
///
/// B31.3 §345.2.1(a) każe liczyć je na MINIMALNEJ grubości ścianki — wywołujący
/// podaje tę grubość, jaką ma.
double hoopStressMpa({
  required double pressureBar,
  required double odMm,
  required double wallMm,
}) {
  _checkGeometry(odMm, wallMm);
  return (pressureBar / 10.0) * odMm / (2.0 * wallMm);
}

/// Ciśnienie [bar], przy którym naprężenie obwodowe osiąga [stressMpa]:
/// P = 2 · t · σ / D.
double pressureAtHoopStressBar({
  required double stressMpa,
  required double odMm,
  required double wallMm,
}) {
  _checkGeometry(odMm, wallMm);
  return 2.0 * wallMm * stressMpa / odMm * 10.0;
}

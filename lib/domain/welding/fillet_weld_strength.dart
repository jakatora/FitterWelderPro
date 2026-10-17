// Nośność spoiny pachwinowej — EN 1993-1-8 (Eurokod 3, część 1-8),
// metoda uproszczona (4.5.3.3) i kierunkowa (4.5.3.2). Czyste funkcje, bez
// Fluttera.
//
// Szacunek dla montera/spawacza, który przyspawa wspornik, ucho, podporę
// i chce wiedzieć „ile to udźwignie” albo „jakie a wystarczy”. Sprawdza
// TYLKO spoinę — nie blachy, śruby, wyboczenie ani zmęczenie — i nie
// zastępuje projektu konstruktora.
//
// __WYDANIE NORMY__: domyślnie (i jedynie) PN-EN 1993-1-8:2006 + AC:2009
// (= EN 1993-1-8:2005) z załącznikiem krajowym — to wydanie obowiązuje
// w Polsce. Nowe EN 1993-1-8:2024 (druga generacja Eurokodów) wprowadza
// zmodyfikowany współczynnik korelacji przy równej wytrzymałości materiału
// rodzimego i spoiwa oraz osobną regułę dla stali ≥ S460 z innym spoiwem
// (σw,Rd = (0,25·fu,PM + 0,75·fu,FM) / (βw,mod·γM2)) i reguły do S700 [J].
// Tabel nowego wydania nie dało się potwierdzić w źródle pierwotnym —
// dlatego moduł ich nie używa. Dla S420/S460 wydanie 2005 daje βw = 1,0,
// czyli nośność nie wyższą niż wartości spotykane dla wydania 2024
// (0,88 / 0,85 w opracowaniach wtórnych — niepotwierdzone).
//
// __ŹRÓDŁA__
//  [N8] EN 1993-1-8:2005 (PN-EN 1993-1-8:2006):
//       • 4.3.2.1(1) — spoiny pachwinowe dla kąta między ściankami 60°–120°
//         (< 60° — jak czołowa z niepełnym przetopem, > 120° — badania);
//       • 4.5.1(1) — długość efektywna = długość pełnego przekroju, można
//         przyjąć długość całkowitą minus 2a; bez odejmowania tylko, gdy
//         spoina ma pełny przekrój także na początku i końcu;
//       • 4.5.1(2) — spoina o l_eff < max(30 mm; 6a) nie przenosi obciążeń;
//       • 4.5.2(2) — a ≥ 3 mm;
//       • 4.5.3.2 — metoda kierunkowa:
//         [σ⊥² + 3(τ⊥² + τ∥²)]^0,5 ≤ fu/(βw·γM2) oraz σ⊥ ≤ 0,9·fu/γM2,
//         fu — słabszej z łączonych części, βw — tabl. 4.1;
//       • 4.5.3.3 — metoda uproszczona: Fw,Rd = fvw,d·a (na mm długości),
//         fvw,d = (fu/√3)/(βw·γM2);
//       • 4.11 — połączenia zakładkowe dłuższe niż 150a:
//         βLw,1 = 1,2 − 0,2·Lj/(150a) ≤ 1,0 (wzór 4.9);
//       • 4.12 — pojedyncza spoina jednostronna: unikać mimośrodu
//         rozciągającego grań;
//       • tabl. 4.1 βw: S235 0,80; S275 0,85; S355 0,90; S420 1,0; S460 1,0.
//       Wartości i treść potwierdzone w opracowaniach przytaczających normę:
//       https://help.solidworks.com/2012/English/SolidWorks/Cworks/r_Correlation_Factor_EuroCode.htm
//       https://structville.com/design-of-fillet-weld-connections
//       https://www.ideastatica.com/support-center/verification-examples/fillet-weld-in-lap-joint
//  [N1] EN 1993-1-1:2005 + AC:2009, tabl. 3.1 — fu dla t ≤ 40 mm:
//       S235 360, S275 430, S355 490 (EN 10025-2), S420 N/NL i M/ML 520,
//       S460 N/NL i M/ML 540 (S460 Q: 570 — przyjęto niższe 540) MPa.
//       S355 = 490, nie 510: poprawka AC:2009 zamieniła w tabl. 3.1 „510”
//       na „490” dla S355 i S355 W (ČSN EN 1993-1-1 Oprava 1:
//       https://www.technickenormy.cz/publicdoc/85905.pdf);
//       zestawienie: https://cdn.eurocodeapplied.com/design/en1993/steel-design-properties
//       Uwaga: S275 N/NL, S275 M/ML i S355 M/ML mają w tabl. 3.1 niższe fu
//       (390 / 370 / 470 MPa) — ekran o tym mówi.
//  [NA] γM2 = 1,25 — wartość zalecana EN 1993-1-8 tabl. 2.1, przyjęta
//       w polskim załączniku krajowym (zestawienie NA:
//       https://finesoftware.eu/help/finec/en/national-annexes-02/ ;
//       tekstu PN-EN 1993-1-8/NA nie widziano).
//  [J]  JRC, „Overview of the evolution of EN 1993” (2020), s. 20:
//       https://eurocodes.jrc.ec.europa.eu/sites/default/files/2022-04/Overview%20of%20the%20evolution%20EN%201993%20and%20parts%20(Issue%201%20dated%2015.10.2020).pdf
//  [E]  γF — EN 1990 tabl. A1.2(B): 1,35 obciążenia stałe, 1,5 zmienne.
//
// __MODEL__ (jednostki: mm, MPa = N/mm², kN):
//  • a — grubość obliczeniowa; „z” (bok) → a = z/√2 tylko dla ścianek pod
//    kątem prostym (fillet_throat.dart).
//  • Spoina liniowa: l_eff = l − 2a na każdą z n spoin.
//    Spoina obwodowa (rura do blachy): l = l_eff = π·D (spoina zamknięta,
//    bez końców — 4.5.1(1)); D — średnica zewnętrzna rury.
//  • Pole przekroju obliczeniowego A = a·Σl_eff. Nośność F_Rd = f·A·βLw,
//    gdzie f [MPa] to wytrzymałość obliczeniowa na jednostkę A dla danej
//    metody:
//      uproszczona:  f = fvw,d = fu/(√3·βw·γM2) — niezależnie od kierunku;
//      kierunkowa:   siła F pod kątem θ do osi spoiny, w płaszczyźnie jednej
//                    ze ścianek (spoina 90°, przekrój obliczeniowy pod 45°):
//                    τ∥ = F·cosθ/A, σ⊥ = τ⊥ = F·sinθ/(√2·A) →
//                    [σ⊥² + 3(τ⊥² + τ∥²)]^0,5 = (F/A)·√(2 + cos²θ), więc
//                    f = min( fu/(βw·γM2·√(2 + cos²θ)),
//                             0,9·fu·√2/(γM2·sinθ) ).
//                    θ = 0° (wzdłuż) — tyle co uproszczona; θ = 90°
//                    (w poprzek) — √(3/2) ≈ 1,22 razy więcej.
//  • βLw (4.11): dla spoiny liniowej dłuższej niż 150a stosowane
//    ZACHOWAWCZO zawsze (z Lj = l), poza czystym obciążeniem poprzecznym
//    w metodzie kierunkowej. Norma wymaga go w połączeniach zakładkowych;
//    w spoinie pasa ze środnikiem nie trzeba — moduł tego nie rozróżnia.

import 'dart:math' as math;

/// γM2 — częściowy współczynnik nośności spoin (EN 1993-1-8 tabl. 2.1,
/// wartość zalecana; PL NA: 1,25).
const double kWeldGammaM2 = 1.25;

/// Najmniejsza grubość obliczeniowa spoiny pachwinowej (4.5.2(2)).
const double kMinFilletThroatMm = 3;

/// Najmniejsza długość efektywna spoiny przenoszącej obciążenie (4.5.1(2))
/// — razem z [kMinLengthThroatRatio]·a, decyduje większa.
const double kMinFilletLengthMm = 30;

/// l_eff ≥ 6·a (4.5.1(2)).
const double kMinLengthThroatRatio = 6;

/// Tabela fu (EN 1993-1-1 tabl. 3.1) w tym module — tylko t ≤ 40 mm.
const double kMaxTableThicknessMm = 40;

/// Próg długiego połączenia: l > 150·a (4.11).
const double kLongJointThroatRatio = 150;

/// γF dla obciążeń stałych (EN 1990 tabl. A1.2(B)).
const double kGammaPermanent = 1.35;

/// γF dla obciążeń zmiennych (EN 1990 tabl. A1.2(B)).
const double kGammaVariable = 1.5;

/// Gatunek stali: fu dla t ≤ 40 mm (EN 1993-1-1 tabl. 3.1 + AC:2009)
/// i βw (EN 1993-1-8 tabl. 4.1).
enum WeldSteelGrade {
  s235('S235', 360, 0.80),
  s275('S275', 430, 0.85),
  s355('S355', 490, 0.90),
  s420('S420', 520, 1.00),
  s460('S460', 540, 1.00);

  const WeldSteelGrade(this.label, this.fuMpa, this.betaW);

  final String label;

  /// Nominalna wytrzymałość na rozciąganie fu [MPa], t ≤ 40 mm.
  final double fuMpa;

  /// Współczynnik korelacji βw.
  final double betaW;
}

/// Układ spoiny.
enum WeldLayout {
  /// Odcinki proste: n spoin o długości l (każda z dwoma końcami).
  linear,

  /// Spoina obwodowa rury do blachy: l = π·D, bez końców.
  circumferential,
}

/// Metoda obliczeń EN 1993-1-8.
enum FilletMethod {
  /// 4.5.3.3 — fvw,d niezależnie od kierunku siły (zawsze bezpieczna).
  simplified,

  /// 4.5.3.2 — naprężenia σ⊥, τ⊥, τ∥ dla siły pod kątem θ do osi spoiny.
  directional,
}

/// Co jest nie tak z danymi — ekran pokazuje komunikat zamiast wyniku.
enum FilletProblem {
  /// Brak / niepoprawna grubość obliczeniowa a.
  throat,

  /// a < 3 mm (4.5.2(2)).
  throatBelowMin,

  /// Brak / niepoprawna grubość łączonych części.
  thickness,

  /// Grubość ponad 40 mm — poza tabelą fu w module.
  thicknessOver40,

  /// Brak / niepoprawna długość spoiny.
  length,

  /// l_eff < max(30 mm; 6a) (4.5.1(2)).
  lengthTooShort,

  /// Liczba spoin poza 1–8.
  welds,

  /// Brak / niepoprawna średnica rury.
  tubeOd,

  /// Kąt siły poza 0–90°.
  angle,

  /// βLw ≤ 0 — spoina dłuższa niż 900·a (4.11).
  tooLongForThroat,
}

/// Dane wejściowe. Liczby wprost z pól — walidację robi [filletProblems].
class FilletWeldInput {
  const FilletWeldInput({
    required this.steel,
    required this.throatMm,
    required this.maxPartThicknessMm,
    this.layout = WeldLayout.linear,
    this.lengthMm = 0,
    this.welds = 1,
    this.tubeOdMm = 0,
    this.method = FilletMethod.simplified,
    this.angleDeg = 0,
  });

  final WeldSteelGrade steel;

  /// Grubość obliczeniowa a [mm].
  final double throatMm;

  /// Największa grubość łączonych części [mm] (tabela fu: ≤ 40 mm).
  final double maxPartThicknessMm;

  final WeldLayout layout;

  /// Długość JEDNEJ spoiny l [mm] (układ liniowy).
  final double lengthMm;

  /// Liczba jednakowych spoin (układ liniowy), np. 2 — obustronna.
  final int welds;

  /// Średnica zewnętrzna rury D [mm] (układ obwodowy).
  final double tubeOdMm;

  final FilletMethod method;

  /// Kąt θ między siłą a osią spoiny [°] (metoda kierunkowa, układ
  /// liniowy): 0 — wzdłuż, 90 — w poprzek. Dla spoiny obwodowej zawsze 90°
  /// (siła osiowa w rurze).
  final double angleDeg;

  /// Kąt użyty w obliczeniach.
  double get effectiveAngleDeg =>
      layout == WeldLayout.circumferential ? 90 : angleDeg;

  FilletWeldInput withThroat(double a) => FilletWeldInput(
        steel: steel,
        throatMm: a,
        maxPartThicknessMm: maxPartThicknessMm,
        layout: layout,
        lengthMm: lengthMm,
        welds: welds,
        tubeOdMm: tubeOdMm,
        method: method,
        angleDeg: angleDeg,
      );
}

bool _pos(double v) => v.isFinite && v > 0;

/// Problemy niezależne od a — od nich zależy też rozwiązanie odwrotne.
List<FilletProblem> filletGeometryProblems(FilletWeldInput i) {
  final t = i.maxPartThicknessMm;
  return [
    if (!_pos(t)) FilletProblem.thickness,
    if (_pos(t) && t > kMaxTableThicknessMm) FilletProblem.thicknessOver40,
    if (i.layout == WeldLayout.linear) ...[
      if (!_pos(i.lengthMm)) FilletProblem.length,
      if (i.welds < 1 || i.welds > 8) FilletProblem.welds,
    ] else if (!_pos(i.tubeOdMm))
      FilletProblem.tubeOd,
    if (i.method == FilletMethod.directional &&
        i.layout == WeldLayout.linear &&
        !(i.angleDeg.isFinite && i.angleDeg >= 0 && i.angleDeg <= 90))
      FilletProblem.angle,
  ];
}

/// Wszystkie problemy danych; pusta lista = można liczyć.
List<FilletProblem> filletProblems(FilletWeldInput i) {
  final geo = filletGeometryProblems(i);
  final a = i.throatMm;
  if (!_pos(a)) return [FilletProblem.throat, ...geo];
  final out = <FilletProblem>[
    if (a < kMinFilletThroatMm) FilletProblem.throatBelowMin,
    ...geo,
  ];
  final lengthOk = !geo.contains(FilletProblem.length) &&
      !geo.contains(FilletProblem.tubeOd);
  if (lengthOk) {
    final leff = effectiveLengthPerWeldMm(i.layout,
        lengthMm: i.lengthMm, tubeOdMm: i.tubeOdMm, throatMm: a);
    if (leff < minEffectiveLengthMm(a)) out.add(FilletProblem.lengthTooShort);
    if (out.isEmpty && longJointFactor(i) <= 0) {
      out.add(FilletProblem.tooLongForThroat);
    }
  }
  return out;
}

/// Najmniejsza dopuszczalna długość efektywna: max(30 mm; 6a) (4.5.1(2)).
double minEffectiveLengthMm(double throatMm) =>
    math.max(kMinFilletLengthMm, kMinLengthThroatRatio * throatMm);

/// Długość spoiny „całkowita” (do opisu): l albo π·D.
double weldLengthPerWeldMm(WeldLayout layout,
        {required double lengthMm, required double tubeOdMm}) =>
    layout == WeldLayout.linear ? lengthMm : math.pi * tubeOdMm;

/// l_eff jednej spoiny: l − 2a (liniowa) albo π·D (obwodowa, bez końców).
double effectiveLengthPerWeldMm(WeldLayout layout,
        {required double lengthMm,
        required double tubeOdMm,
        required double throatMm}) =>
    layout == WeldLayout.linear
        ? lengthMm - 2 * throatMm
        : math.pi * tubeOdMm;

/// Czy stosuje się redukcję długiego połączenia βLw (4.11) — zachowawczo:
/// spoina liniowa dłuższa niż 150a, poza czysto poprzecznym obciążeniem
/// w metodzie kierunkowej.
bool longJointApplies(FilletWeldInput i) {
  if (i.layout != WeldLayout.linear) return false;
  if (i.method == FilletMethod.directional && i.angleDeg >= 90) return false;
  return i.lengthMm > kLongJointThroatRatio * i.throatMm;
}

/// βLw,1 = 1,2 − 0,2·Lj/(150a) ≤ 1,0 (wzór 4.9) z Lj = l; 1, gdy nie
/// dotyczy. Może wyjść ≤ 0 dla l ≥ 900a — wtedy [FilletProblem.tooLongForThroat].
double longJointFactor(FilletWeldInput i) {
  if (!longJointApplies(i)) return 1;
  final b = 1.2 - 0.2 * i.lengthMm / (kLongJointThroatRatio * i.throatMm);
  return math.min(1.0, b);
}

/// fvw,d = fu/(√3·βw·γM2) [MPa] (4.5.3.3).
double simplifiedShearStrengthMpa(WeldSteelGrade s) =>
    s.fuMpa / (math.sqrt(3) * s.betaW * kWeldGammaM2);

/// Warunek 1 metody kierunkowej przeliczony na siłę: F/A ≤ fu/(βw·γM2·√(2 + cos²θ)).
double directionalVonMisesStrengthMpa(WeldSteelGrade s, double angleDeg) {
  final c = math.cos(angleDeg * math.pi / 180);
  return s.fuMpa / (s.betaW * kWeldGammaM2 * math.sqrt(2 + c * c));
}

/// Warunek 2 metody kierunkowej: σ⊥ = F·sinθ/(√2·A) ≤ 0,9·fu/γM2;
/// `double.infinity` dla θ = 0 (brak σ⊥).
double directionalNormalStrengthMpa(WeldSteelGrade s, double angleDeg) {
  final sn = math.sin(angleDeg * math.pi / 180);
  if (sn <= 1e-12) return double.infinity;
  return 0.9 * s.fuMpa * math.sqrt2 / (kWeldGammaM2 * sn);
}

/// Wytrzymałość obliczeniowa na jednostkę pola przekroju obliczeniowego
/// [MPa] dla danej metody i kąta.
double designStrengthMpa(
    WeldSteelGrade s, FilletMethod method, double angleDeg) {
  if (method == FilletMethod.simplified) return simplifiedShearStrengthMpa(s);
  return math.min(directionalVonMisesStrengthMpa(s, angleDeg),
      directionalNormalStrengthMpa(s, angleDeg));
}

/// Wynik dla poprawnych danych.
class FilletWeldResult {
  const FilletWeldResult({
    required this.input,
    required this.strengthMpa,
    required this.fvwdMpa,
    required this.weldLengthMm,
    required this.effectiveLengthPerWeldMm,
    required this.totalEffectiveLengthMm,
    required this.throatAreaMm2,
    required this.longJointFactor,
    required this.normalStressGoverns,
  });

  final FilletWeldInput input;

  /// Wytrzymałość obliczeniowa na jednostkę A [MPa] (dla metody uproszczonej
  /// = fvw,d).
  final double strengthMpa;

  /// fvw,d [MPa] — do porównania z metodą kierunkową.
  final double fvwdMpa;

  /// Długość jednej spoiny (l albo π·D) [mm].
  final double weldLengthMm;

  /// l_eff jednej spoiny [mm].
  final double effectiveLengthPerWeldMm;

  /// Σ l_eff [mm].
  final double totalEffectiveLengthMm;

  /// A = a·Σl_eff [mm²].
  final double throatAreaMm2;

  /// βLw (1, gdy nie dotyczy).
  final double longJointFactor;

  /// Metoda kierunkowa: decyduje warunek σ⊥ ≤ 0,9·fu/γM2 (w praktyce nie
  /// występuje dla βw ≥ 0,8).
  final bool normalStressGoverns;

  bool get longJointApplied => longJointFactor < 1;

  /// F_w,Rd [kN].
  double get resistanceKn =>
      strengthMpa * throatAreaMm2 * longJointFactor / 1000;

  /// F_w,Rd,∥ — ta sama spoina metodą uproszczoną [kN].
  double get simplifiedResistanceKn =>
      fvwdMpa * throatAreaMm2 * longJointFactor / 1000;
}

/// Liczy nośność; `null`, gdy [filletProblems] nie jest puste.
FilletWeldResult? computeFilletWeld(FilletWeldInput i) {
  if (filletProblems(i).isNotEmpty) return null;
  final s = i.steel;
  final angle = i.effectiveAngleDeg;
  final leff = effectiveLengthPerWeldMm(i.layout,
      lengthMm: i.lengthMm, tubeOdMm: i.tubeOdMm, throatMm: i.throatMm);
  final n = i.layout == WeldLayout.linear ? i.welds : 1;
  final total = leff * n;
  final strength = designStrengthMpa(s, i.method, angle);
  final normalGoverns = i.method == FilletMethod.directional &&
      directionalNormalStrengthMpa(s, angle) <
          directionalVonMisesStrengthMpa(s, angle);
  return FilletWeldResult(
    input: i,
    strengthMpa: strength,
    fvwdMpa: simplifiedShearStrengthMpa(s),
    weldLengthMm: weldLengthPerWeldMm(i.layout,
        lengthMm: i.lengthMm, tubeOdMm: i.tubeOdMm),
    effectiveLengthPerWeldMm: leff,
    totalEffectiveLengthMm: total,
    throatAreaMm2: i.throatMm * total,
    longJointFactor: longJointFactor(i),
    normalStressGoverns: normalGoverns,
  );
}

// ── Siła obliczeniowa i werdykt ──────────────────────────────────────────

/// Rodzaj wpisanej siły.
enum ForceKind {
  /// Siła obliczeniowa F_Ed (już ze współczynnikami) — domyślnie.
  design(1),

  /// Charakterystyczna stała (ciężar) × 1,35.
  permanent(kGammaPermanent),

  /// Charakterystyczna zmienna × 1,5.
  variable(kGammaVariable);

  const ForceKind(this.gammaF);

  final double gammaF;
}

/// F_Ed [kN] z wpisanej siły; `null` dla siły niedodatniej / nieskończonej.
double? designForceKn(double force, ForceKind kind) {
  if (!_pos(force)) return null;
  return force * kind.gammaF;
}

/// Werdykt: zielony TYLKO, gdy F_Ed ≤ F_Rd dokładnie (bez zaokrągleń).
class FilletCheck {
  const FilletCheck({required this.designForceKn, required this.resistanceKn});

  final double designForceKn;
  final double resistanceKn;

  bool get ok => designForceKn <= resistanceKn;

  /// F_Ed / F_Rd (nieskończoność przy F_Rd = 0).
  double get ratio => resistanceKn > 0
      ? designForceKn / resistanceKn
      : double.infinity;

  /// Wykorzystanie do pokazania [%], 1 miejsce, zaokrąglone W GÓRĘ — przy
  /// przekroczeniu nigdy nie mniej niż 100,1 %, przy zielonym nigdy więcej
  /// niż 100,0 %. `null` przy F_Rd = 0.
  double? get shownPercent {
    final r = ratio;
    if (!r.isFinite) return null;
    var p = (r * 1000 - 1e-6).ceilToDouble() / 10;
    if (ok && p > 100) p = 100;
    if (!ok && p <= 100) p = 100.1;
    return p;
  }
}

// ── Rozwiązanie odwrotne: jakie a wystarczy ──────────────────────────────

/// Wynik szukania wymaganego a.
enum ThroatStatus {
  /// Znaleziono a z przedziału [3 mm; a_max].
  found,

  /// Wystarczy minimum a = 3 mm.
  minimum,

  /// Nawet największe dopuszczalne a (warunek l_eff ≥ 6a) nie wystarczy —
  /// trzeba dłuższej spoiny albo więcej spoin.
  needsLongerWeld,

  /// Spoina za krótka nawet dla a = 3 mm (l_eff < 30 mm albo 18 mm).
  weldTooShort,
}

class RequiredThroat {
  const RequiredThroat({
    required this.status,
    this.exactMm,
    this.shownMm,
    this.wholeMm,
    this.maxMm,
  });

  final ThroatStatus status;

  /// Najmniejsze a [mm] (rozwiązanie dokładne).
  final double? exactMm;

  /// a do pokazania: W GÓRĘ do 0,1 mm i sprawdzone, że wystarcza.
  final double? shownMm;

  /// Najbliższe całe a [mm] W GÓRĘ, mieszczące się w warunku l_eff ≥ 6a;
  /// `null`, gdy całe a już się nie mieści.
  final int? wholeMm;

  /// Największe a dopuszczalne dla tej długości (l_eff ≥ max(30; 6a)).
  final double? maxMm;

  /// z [mm] dla [shownMm] (ścianki pod kątem prostym), W GÓRĘ do 0,1.
  double? get shownLegMm =>
      shownMm == null ? null : ceilTo(shownMm! * math.sqrt2, 1);

  /// z [mm] dla [wholeMm], W GÓRĘ do 0,1.
  double? get wholeLegMm =>
      wholeMm == null ? null : ceilTo(wholeMm! * math.sqrt2, 1);
}

/// Największe a, przy którym l_eff ≥ max(30 mm; 6a).
double maxThroatForLength(FilletWeldInput i) {
  if (i.layout == WeldLayout.circumferential) {
    final l = math.pi * i.tubeOdMm;
    // π·D < 30 mm — żadne a nie spełni l_eff ≥ 30 mm.
    if (l < kMinFilletLengthMm) return 0;
    return l / kMinLengthThroatRatio;
  }
  final l = i.lengthMm;
  // l − 2a ≥ 6a → a ≤ l/8;  l − 2a ≥ 30 → a ≤ (l − 30)/2.
  return math.min(l / (2 + kMinLengthThroatRatio), (l - kMinFilletLengthMm) / 2);
}

/// F_Rd [kN] dla danego a bez walidacji a (tylko geometria spoiny).
double _resistanceAt(FilletWeldInput i, double a) {
  final ia = i.withThroat(a);
  final leff = effectiveLengthPerWeldMm(i.layout,
      lengthMm: i.lengthMm, tubeOdMm: i.tubeOdMm, throatMm: a);
  final n = i.layout == WeldLayout.linear ? i.welds : 1;
  final beta = math.max(0.0, longJointFactor(ia));
  return designStrengthMpa(i.steel, i.method, i.effectiveAngleDeg) *
      a *
      leff *
      n *
      beta /
      1000;
}

/// Najmniejsze a dla siły [designForceKn]. `null`, gdy geometria jest
/// niepoprawna ([filletGeometryProblems]) albo siła niedodatnia.
///
/// F_Rd(a) rośnie z a w całym przedziale [3; a_max] (a ≤ l/8 < l/4, βLw
/// rośnie z a), więc wystarcza bisekcja.
RequiredThroat? requiredThroat(FilletWeldInput i, double designForceKn) {
  if (filletGeometryProblems(i).isNotEmpty) return null;
  if (!_pos(designForceKn)) return null;
  final aMax = maxThroatForLength(i);
  if (!(aMax >= kMinFilletThroatMm)) {
    return RequiredThroat(status: ThroatStatus.weldTooShort, maxMm: aMax);
  }
  bool enough(double a) => _resistanceAt(i, a) >= designForceKn;
  if (!enough(aMax)) {
    return RequiredThroat(status: ThroatStatus.needsLongerWeld, maxMm: aMax);
  }
  int? whole(double a) {
    final w = math.max(kMinFilletThroatMm, (a - 1e-9).ceilToDouble()).toInt();
    return w <= aMax ? w : null;
  }

  if (enough(kMinFilletThroatMm)) {
    return RequiredThroat(
      status: ThroatStatus.minimum,
      exactMm: kMinFilletThroatMm,
      shownMm: kMinFilletThroatMm,
      wholeMm: whole(kMinFilletThroatMm),
      maxMm: aMax,
    );
  }
  var lo = kMinFilletThroatMm, hi = aMax;
  for (var k = 0; k < 80; k++) {
    final mid = (lo + hi) / 2;
    if (enough(mid)) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  // hi zawsze wystarcza; pokazujemy W GÓRĘ do 0,1 i sprawdzamy jeszcze raz.
  var shown = ceilTo(hi, 1);
  while (!enough(shown) && shown < hi + 1) {
    shown = ceilTo(shown + 0.1, 1);
  }
  return RequiredThroat(
    status: ThroatStatus.found,
    exactMm: hi,
    shownMm: shown,
    wholeMm: whole(shown),
    maxMm: aMax,
  );
}

// ── Zaokrąglenia bezpieczne dla werdyktu ─────────────────────────────────

/// W górę do [decimals] miejsc (z tolerancją na szum zmiennoprzecinkowy).
double ceilTo(double v, int decimals) {
  final f = math.pow(10, decimals).toDouble();
  return (v * f - 1e-7).ceilToDouble() / f;
}

/// W dół do [decimals] miejsc (z tolerancją na szum zmiennoprzecinkowy).
double floorTo(double v, int decimals) {
  final f = math.pow(10, decimals).toDouble();
  return (v * f + 1e-7).floorToDouble() / f;
}

/// Jak pokazać parę F_Ed / F_Rd, żeby liczby nie przeczyły werdyktowi.
/// Zwykle F_Ed W GÓRĘ i F_Rd W DÓŁ (obie strony „na niekorzyść”), z 1–4
/// miejscami. Gdy przy zielonym obie liczby są prawie równe i żadna
/// precyzja tego nie godzi — zwykłe zaokrąglenie obu (monotoniczne, więc
/// F_Ed ≤ F_Rd zostaje).
({int decimals, bool conservative}) forcePairFormat(
    double designForceKn, double resistanceKn) {
  final ok = designForceKn <= resistanceKn;
  for (var d = 1; d <= 4; d++) {
    final e = ceilTo(designForceKn, d);
    final r = floorTo(resistanceKn, d);
    if (ok ? e <= r : e > r) return (decimals: d, conservative: true);
  }
  return (decimals: 4, conservative: false);
}

/// Liczba z [decimals] miejscami; przecinek po polsku, kropka po angielsku.
String formatFixed(double v, int decimals, {required bool en}) {
  var s = v.toStringAsFixed(decimals);
  if (s.startsWith('-') && double.parse(s) == 0) s = s.substring(1);
  return en ? s : s.replaceAll('.', ',');
}

/// Wartość wpisana przez użytkownika: do [maxDecimals] miejsc, bez zbędnych
/// zer (`100` → „100”, `60.3` → „60,3”).
String formatInput(double v, {required bool en, int maxDecimals = 2}) {
  var s = v.toStringAsFixed(maxDecimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// [v] W DÓŁ do [decimals] miejsc — wielkości po stronie nośności
/// (wytrzymałość, długość, pole przekroju, βLw, F_Rd, wymiar spoiny).
String formatDown(double v, int decimals, {required bool en}) =>
    formatFixed(floorTo(v, decimals), decimals, en: en);

/// [v] W GÓRĘ do [decimals] miejsc — obciążenie, wykorzystanie, wymagany
/// wymiar.
String formatUp(double v, int decimals, {required bool en}) =>
    formatFixed(ceilTo(v, decimals), decimals, en: en);

/// Grubość a do pokazania: W DÓŁ do 0,01 mm — nigdy nie zawyża spoiny
/// (z = 4,24 → a = 2,99, a nie „3,00” obok komunikatu „a < 3 mm”).
String formatThroat(double a, {required bool en}) =>
    formatDown(a, 2, en: en);

/// Bok z = a·√2 do pokazania: W DÓŁ do 0,01 mm (ścianki pod kątem prostym).
String formatLeg(double a, {required bool en}) =>
    formatDown(a * math.sqrt2, 2, en: en);

/// Tekst pola wymiaru spoiny dla wartości źródłowej a [mm]: grubość a albo
/// bok z, W DÓŁ do 0,01 mm, bez zbędnych zer („4”, „5,65”). Tylko do
/// wyświetlenia — obliczenia biorą wartość źródłową, nie ten tekst.
String sizeFieldText(double a, {required bool leg, required bool en}) =>
    formatInput(floorTo(leg ? a * math.sqrt2 : a, 2), en: en);

/// Liczby wyniku do pokazania — JEDNO źródło dla ekranu i tekstu do
/// udostępnienia, więc oba pokazują identyczne liczby. Strona nośności
/// (wytrzymałość, długości, pole, βLw, F_Rd) W DÓŁ; F_Ed, wykorzystanie
/// i wymagane wymiary W GÓRĘ; para F_Ed / F_Rd wg [forcePairFormat].
class FilletFigures {
  FilletFigures(this.result, {required this.en, this.designForceKn})
      : check = designForceKn == null
            ? null
            : FilletCheck(
                designForceKn: designForceKn,
                resistanceKn: result.resistanceKn);

  final FilletWeldResult result;
  final bool en;

  /// F_Ed [kN]; `null` — bez siły (bez werdyktu).
  final double? designForceKn;

  /// Werdykt; `null` bez siły.
  final FilletCheck? check;

  ({int decimals, bool conservative}) get _pair => check == null
      ? (decimals: 1, conservative: true)
      : forcePairFormat(check!.designForceKn, check!.resistanceKn);

  String _pairValue(double v, {required bool up}) {
    final f = _pair;
    final x = !f.conservative
        ? double.parse(v.toStringAsFixed(f.decimals))
        : up
            ? ceilTo(v, f.decimals)
            : floorTo(v, f.decimals);
    return formatFixed(x, f.decimals, en: en);
  }

  /// F_w,Rd [kN].
  String get resistance => _pairValue(result.resistanceKn, up: false);

  /// F_Ed [kN]; `null` bez siły.
  String? get designForce =>
      check == null ? null : _pairValue(check!.designForceKn, up: true);

  /// Wykorzystanie [%] z 1 miejscem ([FilletCheck.shownPercent]); „—”, gdy
  /// nie da się policzyć; `null` bez siły.
  String? get utilisation {
    if (check == null) return null;
    final p = check!.shownPercent;
    return p == null ? '—' : formatFixed(p, 1, en: en);
  }

  /// Wytrzymałość na mm² przekroju [MPa] (uproszczona: fvw,d).
  String get strength => formatDown(result.strengthMpa, 1, en: en);

  /// fvw,d [MPa].
  String get fvwd => formatDown(result.fvwdMpa, 1, en: en);

  /// Ta sama spoina metodą uproszczoną [kN].
  String get simplifiedResistance =>
      formatDown(result.simplifiedResistanceKn, 1, en: en);

  /// l_eff jednej spoiny [mm].
  String get effectiveLengthPerWeld =>
      formatDown(result.effectiveLengthPerWeldMm, 1, en: en);

  /// Σ l_eff [mm].
  String get totalEffectiveLength =>
      formatDown(result.totalEffectiveLengthMm, 1, en: en);

  /// Długość jednej spoiny: l albo π·D [mm].
  String get weldLength => formatDown(result.weldLengthMm, 1, en: en);

  /// a·Σl_eff [mm²].
  String get throatArea => formatDown(result.throatAreaMm2, 0, en: en);

  /// βLw.
  String get longJointFactor => formatDown(result.longJointFactor, 3, en: en);

  /// a [mm].
  String get throat => formatThroat(result.input.throatMm, en: en);

  /// z = a·√2 [mm].
  String get leg => formatLeg(result.input.throatMm, en: en);

  /// Kąt siły do osi spoiny [°].
  String get angle => formatInput(result.input.effectiveAngleDeg, en: en);
}

/// Wymagane a / z do pokazania — ekran i tekst biorą je stąd.
({String throat, String leg, String? whole, String? wholeLeg})?
    requiredThroatFigures(RequiredThroat r, {required bool en}) {
  if (r.shownMm == null) return null;
  return (
    throat: formatFixed(r.shownMm!, 1, en: en),
    leg: formatFixed(r.shownLegMm!, 1, en: en),
    whole: r.wholeMm?.toString(),
    wholeLeg: r.wholeLegMm == null ? null : formatFixed(r.wholeLegMm!, 1, en: en),
  );
}

// ── Tekst do udostępnienia ───────────────────────────────────────────────

/// Zastrzeżenie — na ekranie i w udostępnianym tekście.
String filletDisclaimer({required bool en}) => en
    ? 'Estimate per EN 1993-1-8 for the weld only; it does not check the '
        'plates, bolts, buckling or fatigue and does not replace a '
        'structural engineer’s design.'
    : 'Szacunek wg EN 1993-1-8 dla spoiny; nie sprawdza nośności blach, '
        'śrub, wyboczenia ani zmęczenia; nie zastępuje projektu konstruktora.';

/// Tekst wyniku do wysłania (SMS, komunikator, e-mail). Liczby z
/// [FilletFigures] — te same co na ekranie.
String filletShareText({
  required FilletWeldResult result,
  required bool en,
  double? forceInput,
  ForceKind forceKind = ForceKind.design,
  bool legInput = false,
}) {
  String n(double v, int d) => formatFixed(v, d, en: en);
  String tr(String pl, String e) => en ? e : pl;
  String v(double x) => formatInput(x, en: en);
  final i = result.input;
  final s = i.steel;
  final fEd = forceInput == null ? null : designForceKn(forceInput, forceKind);
  final f = FilletFigures(result, en: en, designForceKn: fEd);

  final method = i.method == FilletMethod.simplified
      ? tr('metoda uproszczona (4.5.3.3), fvw,d = ${f.fvwd} MPa',
          'simplified method (4.5.3.3), fvw,d = ${f.fvwd} MPa')
      : tr(
          'metoda kierunkowa (4.5.3.2), siła pod kątem ${f.angle}° do osi spoiny, '
              '${f.strength} MPa na mm² przekroju; uproszczona: ${f.simplifiedResistance} kN',
          'directional method (4.5.3.2), force at ${f.angle}° to the weld axis, '
              '${f.strength} MPa per mm² of throat; simplified: ${f.simplifiedResistance} kN');
  final geometry = i.layout == WeldLayout.linear
      ? tr(
          '${i.welds} × l = ${v(i.lengthMm)} mm, l_eff = l − 2a = ${f.effectiveLengthPerWeld} mm, '
              'Σ l_eff = ${f.totalEffectiveLength} mm',
          '${i.welds} × l = ${v(i.lengthMm)} mm, l_eff = l − 2a = ${f.effectiveLengthPerWeld} mm, '
              'Σ l_eff = ${f.totalEffectiveLength} mm')
      : tr('spoina obwodowa, rura D = ${v(i.tubeOdMm)} mm, l = π·D = ${f.weldLength} mm',
          'circumferential weld, tube D = ${v(i.tubeOdMm)} mm, l = π·D = ${f.weldLength} mm');
  final lines = <String>[
    tr('Nośność spoiny pachwinowej — EN 1993-1-8',
        'Fillet weld resistance — EN 1993-1-8'),
    '${s.label}: fu = ${n(s.fuMpa, 0)} MPa, βw = ${n(s.betaW, 2)}, γM2 = ${n(kWeldGammaM2, 2)}; '
        '${tr('części do ${v(i.maxPartThicknessMm)} mm', 'parts up to ${v(i.maxPartThicknessMm)} mm')}',
    'a = ${f.throat} mm'
        '${legInput ? tr(' (z boku z = ${f.leg} mm)', ' (from leg z = ${f.leg} mm)') : ''}',
    geometry,
    method,
    tr('Przekrój obliczeniowy a·Σl = ${f.throatArea} mm²',
        'Throat area a·Σl = ${f.throatArea} mm²'),
    if (result.longJointApplied)
      tr('βLw = ${f.longJointFactor} (długie połączenie, p. 4.11)',
          'βLw = ${f.longJointFactor} (long joint, cl. 4.11)'),
    'F_w,Rd = ${f.resistance} kN',
  ];
  final check = f.check;
  if (check != null) {
    final gamma = forceKind == ForceKind.design
        ? ''
        : '${v(forceKind.gammaF)} × ${v(forceInput!)} kN = ';
    final pct = f.utilisation;
    lines.add('F_Ed = $gamma${f.designForce} kN');
    lines.add(check.ok
        ? tr('Wykorzystanie $pct % — spoina wystarczy.',
            'Utilisation $pct % — the weld is sufficient.')
        : tr('Wykorzystanie $pct % — SPOINA NIE WYSTARCZY.',
            'Utilisation $pct % — the weld is NOT sufficient.'));
    final req = requiredThroat(i, check.designForceKn);
    final rf = req == null ? null : requiredThroatFigures(req, en: en);
    if (req != null) {
      if (rf != null) {
        final whole = rf.whole == null
            ? ''
            : ' → a${rf.whole} (z ≥ ${rf.wholeLeg} mm)';
        lines.add(tr('Wymagane a ≥ ${rf.throat} mm (z ≥ ${rf.leg} mm)$whole',
            'Required a ≥ ${rf.throat} mm (z ≥ ${rf.leg} mm)$whole'));
      } else {
        lines.add(tr(
            'Żadne dopuszczalne a nie wystarczy — wydłuż spoinę albo dodaj spoiny.',
            'No permissible a is enough — make the weld longer or add welds.'));
      }
    }
  }
  lines.add('');
  lines.add(filletDisclaimer(en: en));
  return lines.join('\n');
}

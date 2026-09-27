// Podgrzewanie wstępne — czyste funkcje, bez Fluttera.
//
// W aplikacji są TRZY różne źródła liczby „preheat” i każde odpowiada na
// inne pytanie. Ekrany pokazują je z nazwą, żeby spawacz nie brał dwóch
// różnych liczb za sprzeczność:
//
//  1. Minimum kodowe — dolna granica z kodu rurociągowego dla grupy P-No
//     i grubości (tu: ASME B31.3 Tab. 330.1.1 — wydanie ≥ 2014, ujednolicone
//     z B31.1, oraz dla porównania zastąpione wydanie 2012).
//  2. Seferian — szacunek z chemii i grubości (stale węglowe i niskostopowe).
//  3. Reguła orientacyjna CE (IIW) — pasma CE z praktyki warsztatowej,
//     nienormatywne.
//
// Metody obliczeniowe wiążące w Europie są w EN 1011-2 zał. C (metoda A
// oparta na CE, metoda B na CET) i uwzględniają też wodór dyfundujący
// i energię liniową. Wiąże zawsze temperatura z WPS. (EN ISO 13916 dotyczy
// POMIARU temperatury podgrzewania, nie jej wyznaczania.)

import 'dart:math' as math;

/// Równoważnik węgla IIW:
/// CE = C + Mn/6 + (Cr + Mo + V)/5 + (Ni + Cu)/15   [% mas.]
double carbonEquivalentIiw({
  required double c,
  required double mn,
  double cr = 0,
  double mo = 0,
  double v = 0,
  double ni = 0,
  double cu = 0,
}) =>
    c + mn / 6.0 + (cr + mo + v) / 5.0 + (ni + cu) / 15.0;

/// Stal nierdzewna wg definicji EN 10088-1: co najmniej 10,5 % Cr.
/// Dla takich stali CE / Seferian nie mają sensu (austenityczne się nie
/// podgrzewa; martenzytyczne prowadzi się wg WPS).
bool isStainlessComposition({required double cr}) => cr >= 10.5;

/// Wynik metody Seferiana.
class SeferianResult {
  const SeferianResult({
    required this.chemicalCe,
    required this.totalCe,
    required this.preheatC,
  });

  /// [C]c — równoważnik chemiczny.
  final double chemicalCe;

  /// [C] = [C]c × (1 + 0,005 × t) — równoważnik całkowity z grubością.
  final double totalCe;

  /// Tp [°C]; 0 gdy [C] ≤ 0,25 (podgrzewanie niewymagane).
  final double preheatC;
}

/// Metoda Seferiana (D. Seferian, „Metalurgia spawania”, 1963):
///
///   [C]c = C + (Mn + Cr)/9 + Ni/18 + 7·Mo/90
///   [C]s = 0,005 · t · [C]c            (t — grubość [mm])
///   [C]  = [C]c + [C]s = [C]c · (1 + 0,005 · t)
///   Tp   = 350 · √([C] − 0,25)  [°C],  Tp = 0 dla [C] ≤ 0,25
///
/// Źródła: G. M. Grigorenko, W. A. Kostin, „Spawalność stali i kryteria jej
/// oceny”, Przegląd Spawalnictwa 7/2013 (Tp, [C]s, [C]og) — za Seferianem;
/// postać [C]c m.in. forum.investsteel.ru „Свариваемость сталей”.
///
/// Zwraca `null` dla danych, z których nie da się liczyć (ujemne, NaN,
/// grubość ≤ 0).
SeferianResult? seferianPreheat({
  required double c,
  required double mn,
  double cr = 0,
  double ni = 0,
  double mo = 0,
  required double thicknessMm,
}) {
  final inputs = [c, mn, cr, ni, mo];
  if (inputs.any((x) => !x.isFinite || x < 0)) return null;
  if (!thicknessMm.isFinite || thicknessMm <= 0) return null;
  final chemical = c + (mn + cr) / 9.0 + ni / 18.0 + 7.0 * mo / 90.0;
  final total = chemical * (1.0 + 0.005 * thicknessMm);
  // Strażnik z audytu 2026-07-07: niskowęglowa stal dawała √(ujemnej) = NaN.
  final tp = total <= 0.25 ? 0.0 : 350.0 * math.sqrt(total - 0.25);
  return SeferianResult(chemicalCe: chemical, totalCe: total, preheatC: tp);
}

/// Pasmo reguły orientacyjnej CE.
enum CeBand {
  /// CE < 0,35
  low,

  /// 0,35 ≤ CE < 0,45
  medium,

  /// 0,45 ≤ CE < 0,55
  high,

  /// CE ≥ 0,55
  critical,
}

/// Wynik reguły orientacyjnej CE (nienormatywnej).
class CeRuleOfThumb {
  const CeRuleOfThumb({
    required this.band,
    required this.preheatC,
    required this.thickWall,
  });

  final CeBand band;

  /// Środek pasma z tabeli referencyjnej ekranu (0/50, 100–150, 150–200,
  /// 200–300 °C) — liczba orientacyjna, nie wymaganie.
  final double preheatC;

  /// Dla CE < 0,35: ścianka ≥ 25 mm (≈ 1") → 50 °C „ostrożnościowo”.
  final bool thickWall;
}

/// Reguła warsztatowa „pasma CE” (praktyka, nie norma). Wartości jak dotąd
/// na ekranie Heat input (tabela referencyjna i środki pasm).
CeRuleOfThumb ceRuleOfThumb({required double ce, required double thicknessMm}) {
  if (ce < 0.35) {
    final thick = thicknessMm >= 25;
    return CeRuleOfThumb(
      band: CeBand.low,
      preheatC: thick ? 50 : 0,
      thickWall: thick,
    );
  }
  if (ce < 0.45) {
    return const CeRuleOfThumb(
        band: CeBand.medium, preheatC: 125, thickWall: false);
  }
  if (ce < 0.55) {
    return const CeRuleOfThumb(
        band: CeBand.high, preheatC: 175, thickWall: false);
  }
  return const CeRuleOfThumb(
      band: CeBand.critical, preheatC: 250, thickWall: false);
}

/// WYDANIE ZASTĄPIONE — pokazywane obok [b313CurrentMinPreheatC] dla
/// projektów, których specyfikacja wciąż wskazuje B31.3-2012.
///
/// Minimalna temperatura podgrzewania wg ASME B31.3-2012 Tab. 330.1.1
/// („Required Minimum Temperature”) dla grupy P-No, grubości nominalnej
/// grubszego elementu w złączu i minimalnej wytrzymałości na rozciąganie.
///
///   P-No 1:  t < 25 mm i Rm ≤ 490 MPa → 10 °C; t ≥ 25 mm lub Rm > 490 → 80 °C
///   P-No 3:  t < 13 mm i Rm ≤ 490 MPa → 10 °C; t ≥ 13 mm lub Rm > 490 → 80 °C
///   P-No 4: 120 °C · P-No 5A/5B/5C: 175 °C · P-No 6: 200 °C
///   P-No 7, 8: 10 °C · P-No 15E: 200 °C
///
/// Źródło: kopia tabeli B31.3-2012 (pdfcoffee.com „P Number Table of
/// B31.3”). Przed użyciem sprawdź wydanie kodu wskazane w specyfikacji
/// projektu. Zwraca `null`, gdy aplikacja nie ma danych dla grupy (np. 10H,
/// stopy niklu) albo grubość jest nieznana.
///
/// [smtsMpa] = null oznacza Rm ≤ 490 MPa (dotyczy gatunków z katalogu).
int? b313MinPreheatC({
  required String pNo,
  required double thicknessMm,
  double? smtsMpa,
}) {
  if (!thicknessMm.isFinite || thicknessMm <= 0) return null;
  final highStrength = smtsMpa != null && smtsMpa > 490;
  switch (pNo) {
    case '1':
      return (thicknessMm >= 25 || highStrength) ? 80 : 10;
    case '3':
      return (thicknessMm >= 13 || highStrength) ? 80 : 10;
    case '4':
      return 120;
    case '5A':
    case '5B':
    case '5C':
      return 175;
    case '6':
      return 200;
    case '7':
    case '8':
      return 10;
    case '15E':
      return 200;
  }
  return null;
}

/// Grupy Cr-Mo i CSEF (P-No 4, 5A, 5B, 5C, 15E): metody szacowania z CE
/// (Seferian, pasma CE) nie są dla nich przeznaczone — o podgrzewaniu
/// decyduje minimum kodowe i WPS.
bool isCrMoPNo(String pNo) =>
    const {'4', '5A', '5B', '5C', '15E'}.contains(pNo.trim().toUpperCase());

/// Skład ręczny wyglądający na stal Cr-Mo (P-No 4 i wyżej: Cr > 0,5 %,
/// Mo ≥ 0,4 %), ale nie nierdzewną (Cr < 10,5 %). Heurystyka ekranu, gdy
/// spawacz nie wybrał gatunku z katalogu.
bool isCrMoComposition({required double cr, required double mo}) =>
    cr > 0.5 && cr < 10.5 && mo >= 0.4;

/// SMTS w pełnych ksi. ASTM podaje wartości SI jako zaokrąglone przeliczenie
/// ksi (60 ksi → 415 MPa), więc porównanie „> 60 ksi” w MPa (> 414)
/// fałszywie łapałoby P22. Stąd zaokrąglenie do całych ksi.
int _smtsKsi(double mpa) => (mpa / 6.894757).round();

/// Minimalna temperatura podgrzewania wg ASME B31.3 wydań ≥ 2014
/// (Tab. 330.1.1), ujednoliconych z ASME B31.1 — wartości przepisane
/// z ASME B31.1-2022 Table 131.4.1-1 „Preheat Temperatures”:
///
///   P-No 1:  t ≤ 25 mm → 10 °C; t > 25 mm i C ≤ 0,30 % → 10 °C;
///            t > 25 mm i C > 0,30 % → 95 °C
///   P-No 3:  t ≤ 13 mm i SMTS ≤ 65 ksi (450 MPa) → 10 °C;
///            t > 13 mm → 95 °C; SMTS > 65 ksi → 95 °C
///   P-No 4:  120 °C
///   P-No 5A: SMTS ≤ 60 ksi (414 MPa) → 150 °C; > 60 ksi → 200 °C
///   P-No 5B: SMTS ≤ 60 ksi → 150 °C; > 60 ksi → 200 °C;
///            t > 13 mm i Cr > 6,0 % → 200 °C
///   P-No 6: 200 · 9A: 120 · 9B: 150 · 10I: 150 · 15E: 200 °C
///   pozostałe materiały: 10 °C
///
/// t — grubość nominalna grubszego elementu w złączu. C i Cr — z analizy
/// wytopowej/wyrobu albo limitów specyfikacji (uwaga (3) tabeli).
///
/// Brak danych (null) dla SMTS / C / Cr → przyjmowana jest WYŻSZA wartość
/// (strona bezpieczna). P-No 5C nie ma w tabeli B31.1-2022 → `null`
/// (do potwierdzenia w normie projektu). Zwraca `null` także dla t ≤ 0.
int? b313CurrentMinPreheatC({
  required String pNo,
  required double thicknessMm,
  double? smtsMpa,
  double? carbonPct,
  double? chromiumPct,
}) {
  if (!thicknessMm.isFinite || thicknessMm <= 0) return null;
  final t = thicknessMm;
  final ksi = smtsMpa == null || !smtsMpa.isFinite ? null : _smtsKsi(smtsMpa);
  switch (pNo.trim().toUpperCase()) {
    case '1':
      if (t <= 25) return 10;
      return (carbonPct == null || carbonPct > 0.30) ? 95 : 10;
    case '3':
      if (t > 13) return 95;
      return (ksi == null || ksi > 65) ? 95 : 10;
    case '4':
      return 120;
    case '5A':
      return (ksi == null || ksi > 60) ? 200 : 150;
    case '5B':
      if (ksi == null || ksi > 60) return 200;
      if (t > 13 && (chromiumPct == null || chromiumPct > 6.0)) return 200;
      return 150;
    case '5C':
      return null;
    case '6':
      return 200;
    case '9A':
      return 120;
    case '9B':
      return 150;
    case '10I':
      return 150;
    case '15E':
      return 200;
    case '':
      return null;
  }
  return 10;
}

// ── EN 1011-2:2001 zał. C, metoda B (CET) ────────────────────────────────
//
// Sprawdzone w tekście normy (BS EN 1011-2:2001, C.3):
//   CET = C + (Mn + Mo)/10 + (Cr + Cu)/20 + Ni/40   [%]            (C.2)
//   Tp  = 697·CET + 160·tanh(d/35) + 62·HD^0,35 + (53·CET − 32)·Q − 328  (C.8)
// Zakres stosowania (C.3.3): stale konstrukcyjne o Re do 1000 N/mm²,
// CET 0,2–0,5 %, d 10–90 mm, HD 1–20 ml/100 g, Q 0,5–4,0 kJ/mm; skład
// (C.3.2.1): C 0,05–0,32; Mn 0,5–1,9; Cr ≤ 1,5; Cu ≤ 0,7; Mo ≤ 0,75;
// Ni ≤ 2,5; V ≤ 0,18. Grupy 1–4 wg CR ISO 15608. Dla złączy o różnej
// grubości liczy się grubszą blachę (C.3.1). Q — energia liniowa wg
// EN 1011-1 (z η).

/// CET wg EN 1011-2 (C.2).
double carbonEquivalentCet({
  required double c,
  required double mn,
  double mo = 0,
  double cr = 0,
  double cu = 0,
  double ni = 0,
}) =>
    c + (mn + mo) / 10.0 + (cr + cu) / 20.0 + ni / 40.0;

/// Powód, dla którego metoda B nie ma zastosowania.
enum CetOutOfRange { cet, thickness, hydrogen, heatInput, composition }

class CetPreheatResult {
  final double cet;

  /// Tp [°C] albo `null`, gdy dane są poza zakresem stosowania metody.
  final double? preheatC;
  final List<CetOutOfRange> outOfRange;

  const CetPreheatResult({
    required this.cet,
    required this.preheatC,
    required this.outOfRange,
  });
}

/// EN 1011-2 zał. C metoda B. Poza zakresem stosowania zwraca Tp = null
/// z listą przyczyn — metoda nie ekstrapoluje.
CetPreheatResult? en1011MethodBPreheat({
  required double c,
  required double mn,
  double mo = 0,
  double cr = 0,
  double cu = 0,
  double ni = 0,
  double v = 0,
  required double thicknessMm,
  required double hdMlPer100g,
  required double heatInputKjMm,
}) {
  final inputs = [c, mn, mo, cr, cu, ni, v, thicknessMm, hdMlPer100g, heatInputKjMm];
  if (inputs.any((x) => !x.isFinite || x < 0)) return null;
  final cet = carbonEquivalentCet(c: c, mn: mn, mo: mo, cr: cr, cu: cu, ni: ni);
  final out = <CetOutOfRange>[
    if (cet < 0.2 || cet > 0.5) CetOutOfRange.cet,
    if (thicknessMm < 10 || thicknessMm > 90) CetOutOfRange.thickness,
    if (hdMlPer100g < 1 || hdMlPer100g > 20) CetOutOfRange.hydrogen,
    if (heatInputKjMm < 0.5 || heatInputKjMm > 4.0) CetOutOfRange.heatInput,
    if (c < 0.05 ||
        c > 0.32 ||
        mn < 0.5 ||
        mn > 1.9 ||
        cr > 1.5 ||
        cu > 0.7 ||
        mo > 0.75 ||
        ni > 2.5 ||
        v > 0.18)
      CetOutOfRange.composition,
  ];
  if (out.isNotEmpty) {
    return CetPreheatResult(cet: cet, preheatC: null, outOfRange: out);
  }
  double tanh(double x) {
    final e2 = math.exp(2 * x);
    return (e2 - 1) / (e2 + 1);
  }

  final tp = 697 * cet +
      160 * tanh(thicknessMm / 35) +
      62 * math.pow(hdMlPer100g, 0.35) +
      (53 * cet - 32) * heatInputKjMm -
      328;
  return CetPreheatResult(cet: cet, preheatC: tp, outOfRange: const []);
}

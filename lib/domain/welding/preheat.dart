// Podgrzewanie wstępne — czyste funkcje, bez Fluttera.
//
// W aplikacji są TRZY różne źródła liczby „preheat” i każde odpowiada na
// inne pytanie. Ekrany pokazują je z nazwą, żeby spawacz nie brał dwóch
// różnych liczb za sprzeczność:
//
//  1. Minimum kodowe — dolna granica z kodu rurociągowego dla grupy P-No
//     i grubości (tu: ASME B31.3 Tab. 330.1.1). Nie zależy od rzeczywistego
//     składu z atestu.
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

/// Jednostki modułu „Tolerancje spoola”: mm (wartości kanoniczne) i cale
/// (ułamki do 1/16″ i drobniejsze).
///
/// Zasady:
/// * wszystko zapisujemy i oceniamy w mm — jednostka wyświetlania zmienia
///   tylko wygląd liczb, nigdy werdykt;
/// * rozdzielczość wartości kanonicznych to [kSpoolGridMm] = 0,000001 mm —
///   każdy ułamek do 1/64″ (1/64″ = 0,396875 mm, 1/16″ = 1,5875 mm)
///   przelicza się DOKŁADNIE, więc odchyłka 1/8″ wobec tolerancji 1/8″ jest
///   „na granicy”, nie „poza”;
/// * co nie trafia w siatkę, zaokrąglamy w stronę ostrzejszego werdyktu:
///   tolerancję W DÓŁ ([spoolFloorMm]), odchyłkę W GÓRĘ ([spoolCeilMm]).
///
/// Czysty Dart.
library;

import '../../utils/decimal_parse.dart';

enum SpoolUnit { mm, inch }

/// Dokładnie: 1″ = 25,4 mm.
const double kSpoolMmPerInch = 25.4;

/// Rozdzielczość wartości kanonicznych, mm.
const double kSpoolGridMm = 0.000001;

/// Liczba kroków siatki na 1 mm (dzielenie przez liczbę całkowitą daje
/// najbliższą liczbę zmiennoprzecinkową — 3,175, a nie 3,1750000000000003).
const int _kGridPerMm = 1000000;

/// Zapas na błąd zmiennoprzecinkowy, w krokach siatki (1e-9 mm) — różnica
/// długości rzędu 100 m liczona w double myli się o ~1e-11 mm.
const double _kEpsSteps = 1e-3;

/// Zapas porównania „odchyłka ≤ tolerancja”, mm (o rzędy wielkości mniej niż
/// krok siatki).
const double kSpoolCompareEpsMm = 1e-9;

/// Tolerancja: w dół do siatki (ostrzej).
double spoolFloorMm(double mm) =>
    (mm * _kGridPerMm + _kEpsSteps).floorToDouble() / _kGridPerMm;

/// Odchyłka: w górę do siatki (ostrzej).
double spoolCeilMm(double mm) =>
    (mm * _kGridPerMm - _kEpsSteps).ceilToDouble() / _kGridPerMm;

/// Wartość w jednostce [u] → mm (dokładnie, bez zaokrąglania).
double spoolToMm(double v, SpoolUnit u) =>
    u == SpoolUnit.mm ? v : v * kSpoolMmPerInch;

/// mm → jednostka [u] (do wyświetlania).
double spoolFromMm(double mm, SpoolUnit u) =>
    u == SpoolUnit.mm ? mm : mm / kSpoolMmPerInch;

/// Tolerancja wpisana w jednostce [u] → mm, W DÓŁ do siatki.
double spoolToleranceToMm(double v, SpoolUnit u) =>
    spoolFloorMm(spoolToMm(v, u));

/// Tolerancja podana w calach (norma) → mm, W DÓŁ do siatki.
double spoolToleranceFromInch(double inch) =>
    spoolToleranceToMm(inch, SpoolUnit.inch);

/// Wartość wyliczona (np. łuk z kąta) — W GÓRĘ do 0,001 mm.
double spoolCeilMicron(double mm) =>
    (mm * 1000 - _kEpsSteps).ceilToDouble() / 1000;

/// Odchyłka |a − b| w mm, W GÓRĘ do siatki.
double spoolDeviationMm(double a, double b) => spoolCeilMm((a - b).abs());

/// Granica włącznie: |odchyłka| = tolerancja → w tolerancji.
bool spoolWithin(double deviationMm, double toleranceMm) =>
    deviationMm <= toleranceMm + kSpoolCompareEpsMm;

// ═══════════════════════════════════════════════════════════════════════════
// ODCZYT POLA
// ═══════════════════════════════════════════════════════════════════════════

/// Tekst pola w jednostce [u] → mm. `null` dla pustego, nieczytelnego albo
/// ujemnego wpisu (nigdy cichy zero).
///
/// mm: liczba z przecinkiem albo kropką („1253,5”).
/// Cale: „98”, „98,5”, „98 1/2”, „98-1/2”, „1/2”, „8' 2 1/2"”, „8 ft 2.5 in”,
/// z ″ / " / in na końcu albo bez.
double? parseSpoolLength(String text, SpoolUnit u) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  if (u == SpoolUnit.mm) {
    final v = parseDecimal(raw.replaceFirst(RegExp(r'\s*mm$'), ''));
    if (v == null || v < 0) return null;
    return v;
  }
  final inch = parseSpoolInches(raw);
  return inch == null ? null : inch * kSpoolMmPerInch;
}

/// Cale (liczba cali) z tekstu — patrz [parseSpoolLength]. `null`, gdy
/// tekst nie jest długością albo mianownik = 0.
double? parseSpoolInches(String text) {
  var s = text
      .trim()
      .toLowerCase()
      .replaceAll('″', '"')
      .replaceAll('′', "'")
      .replaceAll('’', "'")
      .replaceAll("''", '"')
      .replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  double feet = 0;
  final ft = RegExp(r'''^(\d+(?:[.,]\d+)?)\s*(?:'|ft|feet|foot)\s*-?\s*(.*)$''')
      .firstMatch(s);
  if (ft != null) {
    final f = parseDecimal(ft.group(1));
    if (f == null) return null;
    feet = f;
    s = ft.group(2)!.trim();
    if (s.isEmpty) return feet * 12;
  }
  s = s.replaceFirst(RegExp(r'\s*(?:"|inches|inch|in)$'), '').trim();
  if (s.isEmpty) return null;
  final inches = _inchPart(s);
  if (inches == null) return null;
  return feet * 12 + inches;
}

double? _inchPart(String s) {
  final mixed =
      RegExp(r'^(\d+)(?:\s+|\s*-\s*)(\d+)\s*/\s*(\d+)$').firstMatch(s);
  if (mixed != null) {
    final den = int.parse(mixed.group(3)!);
    if (den == 0) return null;
    return int.parse(mixed.group(1)!) + int.parse(mixed.group(2)!) / den;
  }
  final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(s);
  if (frac != null) {
    final den = int.parse(frac.group(2)!);
    if (den == 0) return null;
    return int.parse(frac.group(1)!) / den;
  }
  if (!RegExp(r'^\d+(?:[.,]\d+)?$|^[.,]\d+$').hasMatch(s)) return null;
  return parseDecimal(s);
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE (przecinek w PL, kropka w EN)
// ═══════════════════════════════════════════════════════════════════════════

/// Liczba do [decimals] miejsc bez zbędnych zer: 3,175 / 3 / 1253,5 /
/// 0,79375 (1/32″ — dokładnie, bez zaokrąglenia na ekranie).
String spoolNum(double v, {required bool en, int decimals = 6}) {
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// Cale jako ułamek do 1/64 („98 1/2”, „1/16”, „3”), `null`, gdy wartość nie
/// jest wielokrotnością 1/64″.
String? spoolInchFraction(double inch) {
  if (inch < 0) return null;
  const den = 64;
  final n = inch * den;
  if ((n - n.round()).abs() > 1e-6) return null;
  final total = n.round();
  final whole = total ~/ den;
  var num = total % den;
  var d = den;
  while (num != 0 && num % 2 == 0) {
    num ~/= 2;
    d ~/= 2;
  }
  if (num == 0) return '$whole';
  return whole == 0 ? '$num/$d' : '$whole $num/$d';
}

/// mm wartości kanonicznej: „3,175 mm”.
String spoolFormatMm(double mm, {required bool en}) =>
    '${spoolNum(mm, en: en)} mm';

/// Cale: ułamek do 1/64 („1/8″”), inaczej „≈0,118″” (3 miejsca).
String spoolFormatInch(double mm, {required bool en}) {
  final inch = mm / kSpoolMmPerInch;
  final f = spoolInchFraction(inch);
  if (f != null) return '$f″';
  return '≈${spoolNum(inch, en: en, decimals: 3)}″';
}

/// Długość w jednostce [u].
String spoolFormatLength(double mm, SpoolUnit u, {required bool en}) =>
    u == SpoolUnit.mm ? spoolFormatMm(mm, en: en) : spoolFormatInch(mm, en: en);

/// Długość w jednostce [u] z drugą w nawiasie — przy werdykcie zawsze widać
/// wartość w mm, w której liczono: „1/8″ (3,175 mm)” / „3 mm (≈0,118″)”.
String spoolFormatBoth(double mm, SpoolUnit u, {required bool en}) =>
    u == SpoolUnit.mm
        ? '${spoolFormatMm(mm, en: en)} (${spoolFormatInch(mm, en: en)})'
        : '${spoolFormatInch(mm, en: en)} (${spoolFormatMm(mm, en: en)})';

/// Odchyłka ze znakiem: „+3,5 mm”, „−1/16″”, „0 mm”.
String spoolFormatSigned(double signedMm, SpoolUnit u, {required bool en}) {
  final abs = spoolFormatLength(signedMm.abs(), u, en: en);
  if (signedMm.abs() < kSpoolCompareEpsMm) return abs;
  return '${signedMm > 0 ? '+' : '−'}$abs';
}

/// Wartość do pola tekstowego w jednostce [u] (bez jednostki). Cale:
/// ułamek, gdy dokładny, inaczej dziesiętnie (4 miejsca).
String spoolFieldText(double? mm, SpoolUnit u, {required bool en}) {
  if (mm == null) return '';
  if (u == SpoolUnit.mm) return spoolNum(mm, en: en);
  final inch = mm / kSpoolMmPerInch;
  return spoolInchFraction(inch) ?? spoolNum(inch, en: en);
}

/// Krótka nazwa jednostki do pól: „mm” / „in”.
String spoolUnitSuffix(SpoolUnit u) => u == SpoolUnit.mm ? 'mm' : 'in';

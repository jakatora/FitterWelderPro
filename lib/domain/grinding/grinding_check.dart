/// Zgodność tarcza ↔ szlifierka ↔ praca: prędkość (m/s albo obr./min),
/// średnica, mocowanie, data ważności, typ tarczy wobec operacji, osłona do
/// cięcia, nierdzewka i aluminium.
///
/// MODUŁ BEZPIECZEŃSTWA. Zasady:
/// * brak albo nieczytelne dane ≠ OK — dają „brak werdyktu”, nigdy zielone;
/// * zaokrąglenia w stronę bezpieczeństwa: obroty dopuszczalne z prędkości
///   W DÓŁ, prędkość obwodowa z obrotów W GÓRĘ (tylko do pokazania);
/// * werdykt nie zależy od tego, czy tarczę opisano w m/s, czy w obr./min:
///   porównanie zawsze w całkowitych obr./min, a n ≤ ⌊v·60 000/(π·D)⌋
///   ⇔ π·D·n/60 000 ≤ v dla całkowitego n;
/// * „dziś” wstrzykiwane (`now`) — data ważności jest testowalna.
///
/// Źródła: grinding_sources.dart. Ekran: lib/features/grinding/.
///
/// Czysty Dart.
library;

import 'dart:math' as math;

import 'grinding_sources.dart';

export 'grinding_sources.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ZAKRESY DANYCH (poza zakresem = literówka → brak werdyktu)
// ═══════════════════════════════════════════════════════════════════════════

/// Obroty szlifierki i tarczy [obr./min]. Szlifierki 230 mm ≈ 6 600,
/// małe 50 mm ≈ 25 000 — wszystko poza 500–50 000 to pomyłka przy wpisie.
const int kMinRpm = 500;
const int kMaxRpm = 50000;

/// Średnica tarczy i szlifierki [mm]. EN 62841-2-3: szlifierki do 230 mm;
/// do 400 mm, żeby „300” wpisane omyłkowo dało STOP, a nie brak danych.
const double kMinDiameterMm = 25;
const double kMaxDiameterMm = 400;

/// Maks. prędkość robocza tarczy [m/s]. Tarcze na szlifierki ręczne mają
/// 50–100 m/s (EN 62841-2-3: szlifierka do 80 m/s); 125 m/s to najwyższy
/// pasek w tabeli kolorów aplikacji.
const double kMinSpeedMs = 10;
const double kMaxSpeedMs = 125;

/// Margines na błąd zmiennoprzecinkowy przy zaokrąglaniu (w stronę
/// bezpieczeństwa: odejmowany przed `floor`, przed `ceil` też — inaczej
/// 80,0000000001 pokazałoby się jako 80,1).
const double _kEps = 1e-9;

// ═══════════════════════════════════════════════════════════════════════════
// PRZELICZENIA
// ═══════════════════════════════════════════════════════════════════════════

/// Dopuszczalne obroty z prędkości obwodowej: n = v·60 000/(π·D),
/// zaokrąglone W DÓŁ do pełnych obr./min. `null` dla danych spoza zakresu.
int? maxRpmFromSpeed(double speedMs, double diameterMm) {
  if (!_validSpeed(speedMs) || !_validDiameter(diameterMm)) return null;
  return (speedMs * 60000 / (math.pi * diameterMm) - _kEps).floor();
}

/// Prędkość obwodowa v = π·D·n/60 000 [m/s] — dokładnie, bez zaokrągleń.
double peripheralSpeedMs(double diameterMm, num rpm) =>
    math.pi * diameterMm * rpm / 60000;

/// Prędkość obwodowa zaokrąglona W GÓRĘ do [decimals] miejsc — do
/// pokazania („tarcza na tej szlifierce kręci się z 72,1 m/s”).
double peripheralSpeedUpMs(double diameterMm, num rpm, {int decimals = 1}) {
  final f = math.pow(10, decimals).toDouble();
  return (peripheralSpeedMs(diameterMm, rpm) * f - _kEps).ceil() / f;
}

bool _validRpm(int? n) => n != null && n >= kMinRpm && n <= kMaxRpm;
bool _validDiameter(double? d) =>
    d != null && d.isFinite && d >= kMinDiameterMm && d <= kMaxDiameterMm;
bool _validSpeed(double? v) =>
    v != null && v.isFinite && v >= kMinSpeedMs && v <= kMaxSpeedMs;

// ═══════════════════════════════════════════════════════════════════════════
// SŁOWNIKI
// ═══════════════════════════════════════════════════════════════════════════

/// Typ narzędzia. 41, 42, 27 — ściernice spojone wg ISO 525 / EN 12413;
/// listkowa i fibrowa — nasypowe (EN 13743); szczotka — druciana.
enum DiscType {
  t41('Typ 41 — płaska do cięcia', 'Type 41 — flat cut-off wheel', 'tarcza 41',
      'type 41 wheel'),
  t42('Typ 42 — obniżona do cięcia', 'Type 42 — depressed-centre cut-off',
      'tarcza 42', 'type 42 wheel'),
  t27('Typ 27 — obniżona do szlifowania', 'Type 27 — depressed-centre grinding',
      'tarcza 27', 'type 27 wheel'),
  flap('Listkowa (lamelkowa)', 'Flap disc', 'tarcza listkowa', 'flap disc'),
  fibre('Fibrowa (na talerzu)', 'Fibre disc (on a backing pad)',
      'tarcza fibrowa', 'fibre disc'),
  wire('Szczotka druciana', 'Wire brush', 'szczotka', 'wire brush');

  const DiscType(this.labelPl, this.labelEn, this.shortPl, this.shortEn);
  final String labelPl;
  final String labelEn;
  final String shortPl;
  final String shortEn;
  String label({required bool en}) => en ? labelEn : labelPl;
  String short({required bool en}) => en ? shortEn : shortPl;

  /// Tarcza do cięcia (41, 42) — EN 12413 tab. A.2: tylko do cięcia.
  bool get isCutOff => this == t41 || this == t42;

  /// Spoiwo żywiczne (B, BF) na szlifierkę ręczną — data ważności
  /// obowiązkowa (EN 12413, oSa).
  bool get requiresExpiry => this == t41 || this == t42 || this == t27;
}

enum GrindingOperation {
  cutting('Cięcie', 'Cutting'),
  grinding('Szlifowanie, szczotkowanie', 'Grinding, brushing');

  const GrindingOperation(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

enum WorkMaterial {
  carbonSteel('Stal węglowa', 'Carbon steel'),
  stainless('Nierdzewka', 'Stainless'),
  aluminium('Aluminium', 'Aluminium'),
  other('Inny', 'Other');

  const WorkMaterial(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

/// Gwint wrzeciona szlifierki.
enum SpindleThread {
  m14('M14'),
  m16('M16'),
  unc58('5/8″-11');

  const SpindleThread(this.label);
  final String label;
}

/// Mocowanie narzędzia: otwór na kołnierze albo własny gwint.
enum DiscMount {
  bore2223('Ø 22,23', 'Ø 22.23', null),
  bore16('Ø 16', 'Ø 16', null),
  m14('M14', 'M14', SpindleThread.m14),
  m16('M16', 'M16', SpindleThread.m16),
  unc58('5/8″', '5/8″', SpindleThread.unc58);

  const DiscMount(this.labelPl, this.labelEn, this.thread);
  final String labelPl;
  final String labelEn;

  /// Gwint narzędzia; `null` = otwór (mocowanie na kołnierzach).
  final SpindleThread? thread;
  String label({required bool en}) => en ? labelEn : labelPl;
  bool get isThreaded => thread != null;
}

/// Pasek barwny prędkości (EN 12413 zał. D, informacyjny). Tylko
/// podpowiedź — decyduje nadruk na tarczy. [argb] — kolory do narysowania.
enum SpeedStripe {
  blue(50, 'niebieski', 'blue', [0xFF1E88E5]),
  yellow(63, 'żółty', 'yellow', [0xFFFDD835]),
  red(80, 'czerwony', 'red', [0xFFE53935]),
  green(100, 'zielony', 'green', [0xFF43A047]),
  blueYellow(
      125, 'niebieski + żółty', 'blue + yellow', [0xFF1E88E5, 0xFFFDD835]);

  const SpeedStripe(this.speedMs, this.colourPl, this.colourEn, this.argb);
  final double speedMs;
  final String colourPl;
  final String colourEn;
  final List<int> argb;
  String colour({required bool en}) => en ? colourEn : colourPl;
}

// ═══════════════════════════════════════════════════════════════════════════
// DATA WAŻNOŚCI
// ═══════════════════════════════════════════════════════════════════════════

/// Miesiąc i rok z pierścienia tarczy („V 07/2027”).
class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month;
  const YearMonth(this.year, this.month);

  int get _index => year * 12 + (month - 1);

  /// Miesiąc, w którym wypada [d].
  static YearMonth of(DateTime d) => YearMonth(d.year, d.month);

  YearMonth addMonths(int n) {
    final i = _index + n;
    return YearMonth(i ~/ 12, i % 12 + 1);
  }

  int monthsSince(YearMonth other) => _index - other._index;

  /// „07/2027”.
  String format() => '${month.toString().padLeft(2, '0')}/$year';

  @override
  int compareTo(YearMonth other) => _index.compareTo(other._index);

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => format();
}

final RegExp _mmYyyy = RegExp(r'^(\d{1,2})[/.\-](\d{2}|\d{4})$');
final RegExp _yyyyMm = RegExp(r'^(\d{4})[/.\-](\d{1,2})$');

/// Data z pierścienia: „07/2027”, „7/2027”, „V07/2027”, „V 07.2027”,
/// „07-27”, „2027-07”. Rok dwucyfrowy = 20xx. `null`, gdy nie da się
/// odczytać jednoznacznie (miesiąc spoza 1–12, rok spoza 2000–2099).
YearMonth? parseExpiry(String? text) {
  if (text == null) return null;
  var s = text.trim().replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('V') || s.startsWith('v')) s = s.substring(1);
  int? month;
  int? year;
  final a = _mmYyyy.firstMatch(s);
  if (a != null) {
    month = int.parse(a.group(1)!);
    final y = a.group(2)!;
    year = y.length == 2 ? 2000 + int.parse(y) : int.parse(y);
  } else {
    final b = _yyyyMm.firstMatch(s);
    if (b == null) return null;
    year = int.parse(b.group(1)!);
    month = int.parse(b.group(2)!);
  }
  if (month < 1 || month > 12 || year < 2000 || year > 2099) return null;
  return YearMonth(year, month);
}

/// Ostatni miesiąc, w którym tarcza jest ważna. Przyjęte w aplikacji
/// (wariant ostrzejszy — źródła nie rozstrzygają): do początku miesiąca
/// z nadruku, czyli do końca miesiąca poprzedniego.
YearMonth lastValidMonth(YearMonth printed) => printed.addMonths(-1);

/// Tarcza po terminie: od pierwszego dnia miesiąca z nadruku.
bool isExpired(YearMonth printed, DateTime now) =>
    YearMonth.of(now).compareTo(printed) >= 0;

// ═══════════════════════════════════════════════════════════════════════════
// DANE WEJŚCIOWE
// ═══════════════════════════════════════════════════════════════════════════

/// Wszystko, co monter wpisał: szlifierka, tarcza, praca. `null` = nie
/// podano (a dla pytań tak/nie — „nie wiem”).
class GrindingInput {
  // Szlifierka (tabliczka / instrukcja).
  final int? grinderRpm;
  final double? grinderDiameterMm;
  final SpindleThread? spindleThread;

  // Tarcza (etykieta).
  final DiscType? discType;
  final double? discDiameterMm;
  final double? discSpeedMs;
  final int? discRpm;
  final DiscMount? discMount;

  /// Tarcza z otworem: otwór pasuje do średnicy centrującej kołnierza
  /// szlifierki (EN 62841-2-3). `null` = nie wiem — to NIE jest „tak”.
  final bool? boreFitsFlange;

  final YearMonth? discExpiry;

  /// Pole daty ważności niepuste, ale nieczytelne („13/2027”, „07/2O27”).
  /// Daje brak werdyktu dla KAŻDEGO typu — także tam, gdzie data nie jest
  /// wymagana: wpisana data, której nie umiemy odczytać, mogła już minąć.
  final bool expiryUnreadable;

  /// Monter potwierdził, że na tarczy NIE MA daty ważności.
  final bool discNoExpiry;

  /// Wybrany pasek barwny — tylko podpowiedź, nie dane.
  final SpeedStripe? stripe;

  // Praca.
  final GrindingOperation? operation;

  /// Przy cięciu: osłona do cięcia (albo nakładka do cięcia) założona.
  final bool? cuttingGuard;
  final WorkMaterial? material;

  /// Oznaczenie na narzędziu: INOX (nierdzewka) / do aluminium; przy
  /// szczotce — drut ze stali nierdzewnej.
  final bool? markedForMaterial;

  /// Narzędzie było wcześniej używane na stali węglowej.
  final bool? usedOnCarbonSteel;

  const GrindingInput({
    this.grinderRpm,
    this.grinderDiameterMm,
    this.spindleThread,
    this.discType,
    this.discDiameterMm,
    this.discSpeedMs,
    this.discRpm,
    this.discMount,
    this.boreFitsFlange,
    this.discExpiry,
    this.expiryUnreadable = false,
    this.discNoExpiry = false,
    this.stripe,
    this.operation,
    this.cuttingGuard,
    this.material,
    this.markedForMaterial,
    this.usedOnCarbonSteel,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// WYNIK
// ═══════════════════════════════════════════════════════════════════════════

/// Poziom pojedynczego wyniku — od najgorszego.
enum FindingLevel { stop, missing, warn, ok }

enum FindingKind {
  speed,
  labelConsistency,
  stripe,
  diameter,
  mount,
  type,
  expiry,
  operation,
  guard,
  material,
}

class GrindingFinding {
  final FindingKind kind;
  final FindingLevel level;
  final String pl;
  final String en;

  /// Krótkie odwołanie do źródła (albo `null`).
  final String? source;

  /// Reguła przyjęta w aplikacji, nie w normie.
  final bool appRule;

  const GrindingFinding(
    this.kind,
    this.level,
    this.pl,
    this.en, {
    this.source,
    this.appRule = false,
  });

  String text({required bool en}) => en ? this.en : pl;

  String? sourceLabel({required bool en}) =>
      appRule ? (en ? kSrcAppEn : kSrcApp) : source;

  @override
  String toString() => '${kind.name}/${level.name}: $pl';
}

/// Werdykt całego zestawu.
enum GrindingVerdict {
  stop('STOP — nie używaj tego zestawu', 'STOP — do not use this set-up'),
  noVerdict('Brak werdyktu — uzupełnij dane z etykiety',
      'No verdict — complete the label data'),
  caution('Uwaga — przeczytaj ostrzeżenia', 'Caution — read the warnings'),
  ok('Zgodne — tarcza pasuje do szlifierki i pracy',
      'Compatible — disc matches the grinder and the job');

  const GrindingVerdict(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;
}

class GrindingEvaluation {
  final List<GrindingFinding> findings;

  /// Dopuszczalne obroty tarczy (mniejsza z wartości z etykiety) albo
  /// `null`, gdy nie da się ich ustalić.
  final int? allowedRpm;

  /// Prędkość obwodowa tarczy na tej szlifierce, W GÓRĘ do 0,1 m/s.
  final double? grinderSpeedUpMs;

  const GrindingEvaluation(
    this.findings, {
    this.allowedRpm,
    this.grinderSpeedUpMs,
  });

  GrindingVerdict get verdict {
    bool any(FindingLevel l) => findings.any((f) => f.level == l);
    if (any(FindingLevel.stop)) return GrindingVerdict.stop;
    if (any(FindingLevel.missing)) return GrindingVerdict.noVerdict;
    if (any(FindingLevel.warn)) return GrindingVerdict.caution;
    return GrindingVerdict.ok;
  }

  int count(FindingLevel l) => findings.where((f) => f.level == l).length;

  List<GrindingFinding> of(FindingKind k) => [
        for (final f in findings)
          if (f.kind == k) f
      ];

  /// Najgorszy poziom w danym rodzaju (albo `null`, gdy brak wyników).
  FindingLevel? levelOf(FindingKind k) {
    final l = of(k).map((f) => f.level).toList();
    if (l.isEmpty) return null;
    return l.reduce((a, b) => a.index <= b.index ? a : b);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE (PL: 11 000 · 72,1; EN: 11,000 · 72.1)
// ═══════════════════════════════════════════════════════════════════════════

/// Twarda spacja (U+00A0) — separator tysięcy w PL, liczba nie łamie się
/// na końcu wiersza.
final String kNbsp = String.fromCharCode(0xA0);

String fmtRpm(int n, {required bool en}) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(en ? ',' : kNbsp);
    b.write(s[i]);
  }
  return b.toString();
}

String fmtNum(double v, {required bool en, int decimals = 1}) {
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return en ? s : s.replaceAll('.', ',');
}

String _rpmPl(int n) => '${fmtRpm(n, en: false)} obr./min';
String _rpmEn(int n) => '${fmtRpm(n, en: true)} rpm';
String _msPl(double v) => '${fmtNum(v, en: false)} m/s';
String _msEn(double v) => '${fmtNum(v, en: true)} m/s';
String _mmPl(double d) => 'Ø${fmtNum(d, en: false)} mm';
String _mmEn(double d) => 'Ø${fmtNum(d, en: true)} mm';

// ═══════════════════════════════════════════════════════════════════════════
// OCENA
// ═══════════════════════════════════════════════════════════════════════════

GrindingEvaluation evaluateGrinding(GrindingInput i, {required DateTime now}) {
  final out = <GrindingFinding>[];
  final speed = _speed(i, out);
  _diameter(i, out);
  _mount(i, out);
  _typeAndOperation(i, out);
  _expiry(i, now, out);
  _guard(i, out);
  _material(i, out);
  return GrindingEvaluation(
    List.unmodifiable(out),
    allowedRpm: speed.$1,
    grinderSpeedUpMs: speed.$2,
  );
}

/// Prędkość: porównanie w całkowitych obr./min. Zwraca (dopuszczalne
/// obroty, prędkość obwodowa w górę).
(int?, double?) _speed(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.speed;
  final dOk = _validDiameter(i.discDiameterMm);
  final d = i.discDiameterMm;

  // ── Dane z etykiety tarczy ──
  final v = i.discSpeedMs;
  final n = i.discRpm;
  final vOk = _validSpeed(v);
  final nOk = _validRpm(n);
  var labelProblem = false;
  if (v != null && !vOk) {
    labelProblem = true;
    out.add(GrindingFinding(
      k,
      FindingLevel.missing,
      'Prędkość tarczy ${_msPl(v)} poza zakresem '
          '${fmtNum(kMinSpeedMs, en: false)}–${fmtNum(kMaxSpeedMs, en: false)} '
          'm/s — sprawdź nadruk.',
      'Disc speed ${_msEn(v)} outside '
          '${fmtNum(kMinSpeedMs, en: true)}–${fmtNum(kMaxSpeedMs, en: true)} '
          'm/s — check the label.',
    ));
  }
  if (n != null && !nOk) {
    labelProblem = true;
    out.add(GrindingFinding(
      k,
      FindingLevel.missing,
      'Obroty tarczy ${_rpmPl(n)} poza zakresem '
          '${fmtRpm(kMinRpm, en: false)}–${fmtRpm(kMaxRpm, en: false)} '
          '— sprawdź nadruk.',
      'Disc speed ${_rpmEn(n)} outside '
          '${fmtRpm(kMinRpm, en: true)}–${fmtRpm(kMaxRpm, en: true)} '
          '— check the label.',
    ));
  }
  // Błędna wartość z etykiety nie znika po cichu za drugą, poprawną —
  // nadruk trzeba przeczytać jeszcze raz.
  final fromSpeed = (vOk && dOk) ? maxRpmFromSpeed(v!, d!) : null;
  final fromLabel = nOk ? n : null;

  int? allowed;
  if (!labelProblem) {
    if (fromSpeed != null && fromLabel != null) {
      allowed = math.min(fromSpeed, fromLabel);
    } else {
      allowed = fromSpeed ?? fromLabel;
    }
  }

  // Spójność m/s ↔ obr./min dla podanej średnicy.
  if (!labelProblem && vOk && nOk && dOk) {
    final exact = v! * 60000 / (math.pi * d!);
    if ((n! - exact).abs() / exact > kLabelMismatchRatio) {
      out.add(GrindingFinding(
        FindingKind.labelConsistency,
        FindingLevel.warn,
        'Etykieta niespójna dla ${_mmPl(d)}: z ${_msPl(v)} wychodzi '
            '${_rpmPl(fromSpeed!)}, wpisano ${_rpmPl(n)}. Sprawdź średnicę '
            'i nadruk — przyjęto mniejszą wartość.',
        'Label inconsistent for ${_mmEn(d)}: ${_msEn(v)} gives '
            '${_rpmEn(fromSpeed)}, entered ${_rpmEn(n)}. Check the '
            'diameter and the label — the lower value is used.',
        appRule: true,
      ));
    }
  }

  // Pasek barwny wobec wpisanej prędkości.
  final stripe = i.stripe;
  if (stripe != null && vOk && (stripe.speedMs - v!).abs() > 1e-6) {
    out.add(GrindingFinding(
      FindingKind.stripe,
      FindingLevel.warn,
      'Pasek ${stripe.colourPl} oznacza ${_msPl(stripe.speedMs)}, a wpisano '
          '${_msPl(v)}. Decyduje nadruk na tarczy — przeczytaj go jeszcze raz.',
      'The ${stripe.colourEn} stripe means ${_msEn(stripe.speedMs)}, but '
          '${_msEn(v)} was entered. The printed label decides — read it '
          'again.',
      source: kSrcColour,
    ));
  }

  // Brak dopuszczalnej prędkości tarczy (błędna wartość ma już swój wpis).
  if (!labelProblem && allowed == null) {
    if (vOk && !dOk) {
      out.add(GrindingFinding(
        k,
        FindingLevel.missing,
        'Prędkość ${_msPl(v!)} bez średnicy tarczy nie daje obrotów — '
            'wpisz średnicę z etykiety.',
        'Speed ${_msEn(v)} gives no rpm without the disc diameter — '
            'enter the diameter from the label.',
      ));
    } else {
      out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Brak dopuszczalnej prędkości tarczy — wpisz z etykiety m/s albo '
            'obr./min. Bez niej nie ma werdyktu.',
        'No permitted disc speed — enter m/s or rpm from the label. No '
            'verdict without it.',
      ));
    }
  }

  // ── Szlifierka ──
  final g = i.grinderRpm;
  if (g == null) {
    out.add(const GrindingFinding(
      k,
      FindingLevel.missing,
      'Wpisz maks. obroty szlifierki z tabliczki (bieg jałowy).',
      'Enter the grinder max no-load speed from the nameplate.',
    ));
    return (allowed, null);
  }
  if (!_validRpm(g)) {
    out.add(GrindingFinding(
      k,
      FindingLevel.missing,
      'Obroty szlifierki ${_rpmPl(g)} poza zakresem '
          '${fmtRpm(kMinRpm, en: false)}–${fmtRpm(kMaxRpm, en: false)} '
          '— sprawdź tabliczkę.',
      'Grinder speed ${_rpmEn(g)} outside '
          '${fmtRpm(kMinRpm, en: true)}–${fmtRpm(kMaxRpm, en: true)} '
          '— check the nameplate.',
    ));
    return (allowed, null);
  }

  final vUp = dOk ? peripheralSpeedUpMs(d!, g) : null;
  if (allowed == null) return (null, vUp);

  final fromV =
      fromSpeed != null && (fromLabel == null || fromSpeed <= fromLabel);
  final basisPl = fromV ? ' (z ${_msPl(v!)} dla ${_mmPl(d!)}, w dół)' : '';
  final basisEn =
      fromV ? ' (from ${_msEn(v!)} at ${_mmEn(d!)}, rounded down)' : '';
  final atRimPl = vUp == null ? '' : ' · na obwodzie ${_msPl(vUp)}';
  final atRimEn = vUp == null ? '' : ' · rim speed ${_msEn(vUp)}';

  if (g > allowed) {
    out.add(GrindingFinding(
      k,
      FindingLevel.stop,
      'Szlifierka ${_rpmPl(g)} > dopuszczalne dla tarczy '
          '${_rpmPl(allowed)}$basisPl$atRimPl. Tarcza może pęknąć.',
      'Grinder ${_rpmEn(g)} > disc limit ${_rpmEn(allowed)}$basisEn'
          '$atRimEn. The disc may burst.',
      source: '$kSrcEn62841; $kSrcEn12413',
    ));
  } else {
    out.add(GrindingFinding(
      k,
      FindingLevel.ok,
      'Szlifierka ${_rpmPl(g)} ≤ dopuszczalne dla tarczy '
          '${_rpmPl(allowed)}$basisPl$atRimPl.',
      'Grinder ${_rpmEn(g)} ≤ disc limit ${_rpmEn(allowed)}$basisEn'
          '$atRimEn.',
      source: kSrcEn62841,
    ));
  }
  return (allowed, vUp);
}

void _diameter(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.diameter;
  final d = i.discDiameterMm;
  final gd = i.grinderDiameterMm;
  var gap = false;
  if (d == null) {
    gap = true;
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Wpisz średnicę tarczy z etykiety.',
        'Enter the disc diameter from the label.'));
  } else if (!_validDiameter(d)) {
    gap = true;
    out.add(GrindingFinding(
        k,
        FindingLevel.missing,
        'Średnica tarczy ${_mmPl(d)} poza zakresem '
            '${fmtNum(kMinDiameterMm, en: false)}–'
            '${fmtNum(kMaxDiameterMm, en: false)} mm — sprawdź.',
        'Disc diameter ${_mmEn(d)} outside '
            '${fmtNum(kMinDiameterMm, en: true)}–'
            '${fmtNum(kMaxDiameterMm, en: true)} mm — check it.'));
  }
  if (gd == null) {
    gap = true;
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Wpisz średnicę tarczy przewidzianą dla szlifierki i osłony '
            '(tabliczka, instrukcja).',
        'Enter the disc diameter the grinder and guard are made for '
            '(nameplate, manual).'));
  } else if (!_validDiameter(gd)) {
    gap = true;
    out.add(GrindingFinding(
        k,
        FindingLevel.missing,
        'Średnica szlifierki ${_mmPl(gd)} poza zakresem — sprawdź.',
        'Grinder diameter ${_mmEn(gd)} out of range — check it.'));
  }
  if (gap) return;
  if (d! > gd! + 1e-6) {
    out.add(GrindingFinding(
      k,
      FindingLevel.stop,
      'Tarcza ${_mmPl(d)} > ${_mmPl(gd)} przewidziane dla szlifierki — '
          'osłona jej nie zakrywa. Nie zakładaj większych tarcz ani '
          'zużytych tarcz z większych szlifierek.',
      'Disc ${_mmEn(d)} > ${_mmEn(gd)} the grinder is made for — the guard '
          'does not cover it. No larger discs, and no worn-down discs from '
          'larger grinders.',
      source: kSrcEn62841,
    ));
  } else {
    out.add(GrindingFinding(
      k,
      FindingLevel.ok,
      'Tarcza ${_mmPl(d)} ≤ ${_mmPl(gd)} szlifierki.',
      'Disc ${_mmEn(d)} ≤ grinder ${_mmEn(gd)}.',
      source: kSrcEn62841,
    ));
  }
}

void _mount(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.mount;
  final m = i.discMount;
  if (m == null) {
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Wybierz mocowanie tarczy: otwór (22,23 / 16 mm) albo gwint.',
        'Choose the disc mounting: bore (22.23 / 16 mm) or thread.'));
    return;
  }
  final t = m.thread;
  if (t == null) {
    // „For accessories mounted by flanges, the arbour hole of the accessory
    // must fit the locating diameter of the flange” (EN 62841-2-3). Samo
    // „otwór 16 mm” nie mówi, czy pasuje — pyta się montera.
    switch (i.boreFitsFlange) {
      case null:
        out.add(GrindingFinding(
          k,
          FindingLevel.missing,
          'Otwór ${m.labelPl} mm — potwierdź, że pasuje do średnicy '
              'centrującej kołnierza szlifierki.',
          'Bore ${m.labelEn} mm — confirm it fits the grinder flange '
              'locating diameter.',
          source: kSrcEn62841,
        ));
      case false:
        out.add(GrindingFinding(
          k,
          FindingLevel.stop,
          'Otwór ${m.labelPl} mm nie pasuje do kołnierza — tarcza nie będzie '
              'wycentrowana: bicie, drgania, pęknięcie. Nie zakładaj jej.',
          'Bore ${m.labelEn} mm does not fit the flange — the disc will not '
              'run true: wobble, vibration, bursting. Do not fit it.',
          source: kSrcEn62841,
        ));
      case true:
        out.add(GrindingFinding(
          k,
          FindingLevel.ok,
          'Otwór ${m.labelPl} mm pasuje do kołnierza szlifierki.',
          'Bore ${m.labelEn} mm fits the grinder flange.',
          source: kSrcEn62841,
        ));
    }
    return;
  }
  final s = i.spindleThread;
  if (s == null) {
    out.add(GrindingFinding(
        k,
        FindingLevel.missing,
        'Narzędzie z gwintem ${t.label} — wybierz gwint wrzeciona '
            'szlifierki.',
        'Threaded accessory (${t.label}) — choose the grinder spindle '
            'thread.'));
  } else if (s != t) {
    out.add(GrindingFinding(
      k,
      FindingLevel.stop,
      'Gwint narzędzia ${t.label} ≠ gwint wrzeciona ${s.label} — nie da się '
          'go bezpiecznie zamocować.',
      'Accessory thread ${t.label} ≠ spindle thread ${s.label} — it cannot '
          'be mounted safely.',
      source: kSrcEn62841,
    ));
  } else {
    out.add(GrindingFinding(
      k,
      FindingLevel.ok,
      'Gwint narzędzia ${t.label} = gwint wrzeciona.',
      'Accessory thread ${t.label} = spindle thread.',
      source: kSrcEn62841,
    ));
  }
}

void _typeAndOperation(GrindingInput i, List<GrindingFinding> out) {
  final t = i.discType;
  final op = i.operation;
  if (t == null) {
    out.add(const GrindingFinding(
        FindingKind.type,
        FindingLevel.missing,
        'Wybierz typ tarczy (41, 42, 27, listkowa, fibrowa, szczotka) — '
            'od niego zależą dozwolone prace i data ważności.',
        'Choose the disc type (41, 42, 27, flap, fibre, brush) — it decides '
            'the allowed work and whether an expiry date is required.'));
  }
  const k = FindingKind.operation;
  if (op == null) {
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Wybierz rodzaj pracy: cięcie albo szlifowanie / szczotkowanie.',
        'Choose the job: cutting or grinding / brushing.'));
    return;
  }
  if (t == null) return;
  final name = t.shortPl;
  final nameEn = t.shortEn;
  switch ((t, op)) {
    case (DiscType.t41 || DiscType.t42, GrindingOperation.cutting):
      out.add(GrindingFinding(
        k,
        FindingLevel.ok,
        'Cięcie — $name jest do tego przeznaczona.',
        'Cutting — a $nameEn is made for it.',
        source: kSrcEn12413Restriction,
      ));
    case (DiscType.t41 || DiscType.t42, GrindingOperation.grinding):
      out.add(GrindingFinding(
        k,
        FindingLevel.stop,
        'Tarcza do cięcia ($name) — szlifowanie bokiem zabronione: siły '
            'boczne mogą ją rozerwać. Do szlifowania załóż tarczę 27 albo '
            'listkową.',
        'Cut-off wheel ($nameEn) — never grind with its side: side forces '
            'can shatter it. Fit a type 27 or a flap disc for grinding.',
        source: '$kSrcEn12413Restriction; $kSrcEn62841',
      ));
    case (DiscType.t27, GrindingOperation.grinding):
      out.add(const GrindingFinding(
        k,
        FindingLevel.ok,
        'Szlifowanie — tarcza 27 jest do tego przeznaczona.',
        'Grinding — a type 27 wheel is made for it.',
        source: kSrcEn12413,
      ));
    case (DiscType.t27, GrindingOperation.cutting):
      out.add(const GrindingFinding(
        k,
        FindingLevel.warn,
        'Tarcza 27 jest do szlifowania, nie do cięcia. Tnij tarczą 41/42 '
            'z osłoną do cięcia — tarczą 27 tylko wtedy, gdy etykieta '
            'wprost dopuszcza cięcie.',
        'A type 27 wheel is for grinding, not cutting. Cut with a 41/42 '
            'wheel and the cutting guard — with a 27 only if its label '
            'explicitly allows cutting.',
        appRule: true,
      ));
    case (_, GrindingOperation.grinding):
      out.add(GrindingFinding(
        k,
        FindingLevel.ok,
        'Szlifowanie / szczotkowanie — $name jest do tego przeznaczona.',
        'Grinding / brushing — a $nameEn is made for it.',
        source: kSrcEn62841,
      ));
    case (_, GrindingOperation.cutting):
      out.add(GrindingFinding(
        k,
        FindingLevel.stop,
        'Tym się nie tnie ($name). Do cięcia tylko tarcza 41/42 z osłoną '
            'do cięcia.',
        'This is not for cutting ($nameEn). Cut only with a 41/42 wheel and '
            'the cutting guard.',
        appRule: true,
      ));
  }
}

void _expiry(GrindingInput i, DateTime now, List<GrindingFinding> out) {
  const k = FindingKind.expiry;
  final t = i.discType;
  final e = i.discExpiry;
  // Wpisana, ale nieczytelna data — brak werdyktu dla każdego typu (także
  // listkowej, fibrowej i szczotki): mogła już minąć.
  if (i.expiryUnreadable && e == null && !i.discNoExpiry) {
    out.add(const GrindingFinding(
      k,
      FindingLevel.missing,
      'Nie rozpoznano wpisanej daty ważności — przepisz ją z pierścienia '
          'jako MM/RRRR (np. V 07/2027).',
      'The expiry date entered cannot be read — copy it from the ring as '
          'MM/YYYY (e.g. V 07/2027).',
      source: kSrcExpiry,
    ));
    return;
  }
  if (t == null) return;
  final required = t.requiresExpiry;
  if (i.discNoExpiry && e == null) {
    if (required) {
      out.add(GrindingFinding(
        k,
        FindingLevel.stop,
        '${_cap(t.shortPl)} (spoiwo żywiczne) bez daty ważności — nie da '
            'się sprawdzić jej wieku. Nie używaj.',
        '${_cap(t.shortEn)} (resin bond) without an expiry date — its age '
            'cannot be checked. Do not use it.',
        source: kSrcExpiry,
      ));
    }
    return;
  }
  if (e == null) {
    if (required) {
      out.add(const GrindingFinding(
          k,
          FindingLevel.missing,
          'Wpisz datę ważności z metalowego pierścienia (np. V 07/2027).',
          'Enter the expiry date from the metal ring (e.g. V 07/2027).',
          source: kSrcExpiry));
    }
    return;
  }
  final today = YearMonth.of(now);
  final lastOk = lastValidMonth(e);
  if (isExpired(e, now)) {
    out.add(GrindingFinding(
      k,
      FindingLevel.stop,
      'Tarcza po terminie: V ${e.format()} — ważna do końca '
          '${lastOk.format()} (przyjęto: do początku miesiąca z nadruku). '
          'Nie używaj.',
      'Disc expired: V ${e.format()} — valid until the end of '
          '${lastOk.format()} (taken as: until the start of the printed '
          'month). Do not use it.',
      source: kSrcExpiry,
    ));
    return;
  }
  if (e.monthsSince(today) > kMaxExpiryMonthsAhead) {
    out.add(GrindingFinding(
      k,
      FindingLevel.missing,
      'Data V ${e.format()} jest dalej niż $kMaxExpiryMonthsAhead mies. od '
          'dziś, a tarcza jest ważna najwyżej 3 lata od produkcji — sprawdź '
          'nadruk.',
      'Date V ${e.format()} is more than $kMaxExpiryMonthsAhead months '
          'ahead, but a disc is valid at most 3 years from manufacture — '
          'check the label.',
      source: kSrcExpiry,
    ));
    return;
  }
  out.add(GrindingFinding(
    k,
    FindingLevel.ok,
    'Ważna do końca ${lastOk.format()} (V ${e.format()}; przyjęto: do '
        'początku miesiąca z nadruku).',
    'Valid until the end of ${lastOk.format()} (V ${e.format()}; taken as: '
        'until the start of the printed month).',
    source: kSrcExpiry,
  ));
}

void _guard(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.guard;
  final t = i.discType;
  if (i.operation != GrindingOperation.cutting) return;
  // Cięcie narzędziem, które do cięcia się nie nadaje, ma już STOP.
  if (t != null && !t.isCutOff && t != DiscType.t27) return;
  switch (i.cuttingGuard) {
    case null:
      out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Cięcie: potwierdź osłonę do cięcia (zamkniętą, typ A) albo osłonę '
            'do szlifowania z nakładką do cięcia.',
        'Cutting: confirm the cutting guard (closed, type A) or the '
            'grinding guard with the cutting cover.',
        source: kSrcBoschCutGuard,
      ));
    case false:
      out.add(const GrindingFinding(
        k,
        FindingLevel.stop,
        'Cięcie bez osłony do cięcia — przy pęknięciu tarczy odłamki '
            'i iskry lecą na operatora. Załóż osłonę do cięcia.',
        'Cutting without the cutting guard — if the disc bursts, fragments '
            'and sparks hit the operator. Fit the cutting guard.',
        source: kSrcBoschCutGuard,
      ));
    case true:
      out.add(const GrindingFinding(
        k,
        FindingLevel.ok,
        'Osłona do cięcia założona.',
        'Cutting guard fitted.',
        source: kSrcBoschCutGuard,
      ));
  }
}

void _material(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.material;
  final m = i.material;
  if (m == null) {
    out.add(const GrindingFinding(k, FindingLevel.missing,
        'Wybierz materiał obrabiany.', 'Choose the workpiece material.'));
    return;
  }
  switch (m) {
    case WorkMaterial.carbonSteel:
      out.add(const GrindingFinding(
          k,
          FindingLevel.ok,
          'Stal węglowa — bez dodatkowych wymagań dla tarczy.',
          'Carbon steel — no extra disc requirements.'));
      return;
    case WorkMaterial.other:
      out.add(const GrindingFinding(
          k,
          FindingLevel.ok,
          'Inny materiał — przeznaczenie tarczy sprawdź na etykiecie.',
          'Other material — check the disc purpose on its label.'));
      return;
    case WorkMaterial.stainless:
      _stainless(i, out);
      return;
    case WorkMaterial.aluminium:
      _aluminium(i, out);
      return;
  }
}

void _stainless(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.material;
  final wire = i.discType == DiscType.wire;
  final before = out.length;
  if (i.usedOnCarbonSteel == true) {
    out.add(const GrindingFinding(
      k,
      FindingLevel.stop,
      'Narzędzie używane na stali węglowej przeniesie żelazo na nierdzewkę '
          '— będą rdzawe naloty. Weź nowe, tylko do nierdzewki.',
      'A tool used on carbon steel carries iron onto stainless — rust '
          'stains will follow. Use a new one, kept for stainless only.',
      appRule: true,
    ));
  } else if (i.usedOnCarbonSteel == null) {
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Nierdzewka: czy to narzędzie było używane na stali węglowej?',
        'Stainless: has this tool been used on carbon steel?'));
  }
  switch (i.markedForMaterial) {
    case null:
      out.add(GrindingFinding(
          k,
          FindingLevel.missing,
          wire
              ? 'Nierdzewka: czy szczotka ma drut ze stali nierdzewnej?'
              : 'Nierdzewka: czy tarcza ma oznaczenie INOX (bez Fe, S, Cl)?',
          wire
              ? 'Stainless: is the brush wire stainless steel?'
              : 'Stainless: is the disc marked INOX (free of Fe, S, Cl)?',
          source: wire ? null : kSrcInox));
    case false when wire:
      out.add(const GrindingFinding(
        k,
        FindingLevel.stop,
        'Szczotka z drutu stalowego (nie nierdzewnego) wciera żelazo '
            'w nierdzewkę — będą rdzawe naloty. Użyj szczotki nierdzewnej.',
        'A carbon-steel wire brush rubs iron into stainless — rust stains '
            'will follow. Use a stainless wire brush.',
        appRule: true,
      ));
    case false:
      out.add(const GrindingFinding(
        k,
        FindingLevel.warn,
        'Tarcza bez oznaczenia INOX może zanieczyścić nierdzewkę (żelazo, '
            'siarka, chlor). Użyj tarczy INOX.',
        'A disc without the INOX mark may contaminate stainless (iron, '
            'sulphur, chlorine). Use an INOX disc.',
        source: kSrcInox,
      ));
    case true:
      break;
  }
  if (out.length == before) {
    out.add(GrindingFinding(
      k,
      FindingLevel.ok,
      '${wire ? 'Szczotka nierdzewna' : 'Tarcza INOX'}, tylko do '
          'nierdzewki. Po pracy zajrzyj do modułów „Przebarwienia” '
          'i „Trawienie i pasywacja”.',
      '${wire ? 'Stainless brush' : 'INOX disc'}, kept for stainless only. '
          'After the job see the “Heat tint” and “Pickling and passivation” '
          'modules.',
      source: wire ? null : kSrcInox,
    ));
  }
}

void _aluminium(GrindingInput i, List<GrindingFinding> out) {
  const k = FindingKind.material;
  final before = out.length;
  if (i.usedOnCarbonSteel == true) {
    out.add(const GrindingFinding(
      k,
      FindingLevel.warn,
      'Aluminium: narzędzie po stali węglowej przenosi żelazo — trzymaj '
          'osobne tarcze i szczotki do aluminium.',
      'Aluminium: a tool used on carbon steel carries iron — keep separate '
          'discs and brushes for aluminium.',
      appRule: true,
    ));
  } else if (i.usedOnCarbonSteel == null) {
    out.add(const GrindingFinding(
        k,
        FindingLevel.missing,
        'Aluminium: czy to narzędzie było używane na stali węglowej?',
        'Aluminium: has this tool been used on carbon steel?'));
  }
  switch (i.markedForMaterial) {
    case null:
      out.add(const GrindingFinding(
          k,
          FindingLevel.missing,
          'Aluminium: czy narzędzie jest przeznaczone do aluminium / metali '
              'nieżelaznych?',
          'Aluminium: is the tool made for aluminium / non-ferrous metals?'));
    case false:
      out.add(const GrindingFinding(
        k,
        FindingLevel.warn,
        'Tarcza nie do aluminium zalepia się i grzeje — użyj tarczy do '
            'aluminium / metali nieżelaznych.',
        'A disc not made for aluminium clogs and overheats — use a disc '
            'for aluminium / non-ferrous metals.',
        appRule: true,
      ));
    case true:
      break;
  }
  if (out.length == before) {
    out.add(const GrindingFinding(
      k,
      FindingLevel.ok,
      'Narzędzie do aluminium, nieużywane na stali.',
      'Tool made for aluminium, not used on steel.',
      appRule: true,
    ));
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

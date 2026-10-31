/// Ferryt: ocena odczytów ferrytomierza (FN albo % objętościowy) względem
/// wymaganego zakresu ze specyfikacji projektu.
///
/// Zasady bezpieczeństwa werdyktu (sprawdzane testami):
///   • FN ≠ % objętościowy — NIE przeliczamy; jednostka odczytów inna niż
///     jednostka wymagania → brak werdyktu;
///   • granice włącznie: odczyt równy min albo max = w zakresie;
///   • odczyt porównywany TAK, JAK WPISANO (pełna precyzja liczby z pola) —
///     29,96 przy min 30 jest poniżej, nigdy „30”; przecinek = kropka;
///   • pusty zakres, min > max, % > 100, liczba ujemna → brak werdyktu;
///   • nieczytelny / ujemny / > 100 % odczyt ≠ OK (brak werdyktu, chyba że
///     inny odczyt jest już poza zakresem — wtedy „poza zakresem”);
///   • reguła „średnia z N”: N ze specyfikacji, mniej odczytów niż N albo
///     nieczytelne N → brak werdyktu;
///   • minimalna liczba odczytów na miejsce (pole protokołu, domyślnie 1,
///     i preset — np. IOGP S-705: ≥ 3; obowiązuje większa): mniej odczytów
///     → brak werdyktu (odczyt poza zakresem i tak daje „poza zakresem”);
///   • preset dla innego miejsca (np. zakres spoiny przy materiale
///     rodzimym) → brak werdyktu dla tego miejsca;
///   • średnia pokazywana obok werdyktu zaokrąglana W STRONĘ werdyktu.
///
/// Czysty Dart (bez Fluttera).
library;

import 'dart:math' as math;

import '../../utils/decimal_parse.dart';

// ═══════════════════════════════════════════════════════════════════════════
// JEDNOSTKI, MIEJSCA, REGUŁY
// ═══════════════════════════════════════════════════════════════════════════

/// Jednostka odczytu / wymagania. FN (Ferrite Number, EN ISO 8249 /
/// AWS A4.2) to umowna skala kalibracji przyrządu magnetycznego, % to udział
/// objętościowy ferrytu (np. metalografia, ASTM E562) — to NIE to samo.
enum FerriteUnit {
  fn,
  percent;

  static FerriteUnit? byName(Object? n) =>
      FerriteUnit.values.where((u) => u.name == n).firstOrNull;
}

extension FerriteUnitInfo on FerriteUnit {
  /// Krótki symbol do liczb: „FN 30” / „30 %”.
  String get symbol => switch (this) {
        FerriteUnit.fn => 'FN',
        FerriteUnit.percent => '%',
      };

  String label({required bool en}) => switch (this) {
        FerriteUnit.fn => 'FN',
        FerriteUnit.percent => en ? '% ferrite (vol.)' : '% ferrytu (obj.)',
      };

  /// Górna granica fizyczna: udział objętościowy nie przekracza 100 %.
  /// Dla FN granicy nie ustalamy (skala umowna) — `null`.
  double? get maxPhysical => switch (this) {
        FerriteUnit.fn => null,
        FerriteUnit.percent => 100,
      };
}

/// Liczba z jednostką: „FN 30” / „30 %” (PL przecinek).
String ferriteValueText(double v, FerriteUnit u, {required bool en}) {
  final n = ferriteExact(v, en: en);
  return u == FerriteUnit.fn ? 'FN $n' : '$n %';
}

/// Miejsce pomiaru.
enum FerriteLocation {
  weld,
  hazA,
  hazB,
  base;

  static FerriteLocation? byName(Object? n) =>
      FerriteLocation.values.where((l) => l.name == n).firstOrNull;

  String label({required bool en}) => switch (this) {
        FerriteLocation.weld => en ? 'Weld metal' : 'Spoina',
        FerriteLocation.hazA => en ? 'HAZ side A' : 'SWC strona A',
        FerriteLocation.hazB => en ? 'HAZ side B' : 'SWC strona B',
        FerriteLocation.base => en ? 'Base metal' : 'Materiał rodzimy',
      };
}

/// Reguła oceny ze specyfikacji.
enum FerriteRule {
  /// Każdy odczyt w zakresie — domyślna, ostrzejsza.
  everyReading,

  /// Średnia z co najmniej N odczytów w zakresie (N ze specyfikacji).
  average;

  static FerriteRule? byName(Object? n) =>
      FerriteRule.values.where((r) => r.name == n).firstOrNull;
}

// ═══════════════════════════════════════════════════════════════════════════
// WYMAGANIE
// ═══════════════════════════════════════════════════════════════════════════

/// Wymagany zakres (granice włącznie). `null` = granica otwarta (np. „FN ≥
/// 3”); co najmniej jedna granica musi być podana.
class FerriteRequirement {
  final double? min;
  final double? max;
  final FerriteUnit unit;

  const FerriteRequirement({this.min, this.max, required this.unit});

  /// Zakres, z którym da się porównywać. Inaczej brak werdyktu.
  bool get isValid {
    final lo = min, hi = max;
    if (lo == null && hi == null) return false;
    bool ok(double? v) {
      if (v == null) return true;
      if (!v.isFinite || v < 0) return false;
      final cap = unit.maxPhysical;
      return cap == null || v <= cap;
    }

    if (!ok(lo) || !ok(hi)) return false;
    return lo == null || hi == null || lo <= hi;
  }

  /// Czy wartość leży w zakresie (granice włącznie). Wymaga [isValid].
  FerriteReadingStatus statusOf(double v) {
    final lo = min, hi = max;
    if (lo != null && v < lo) return FerriteReadingStatus.below;
    if (hi != null && v > hi) return FerriteReadingStatus.above;
    return FerriteReadingStatus.inRange;
  }

  /// „FN 30–70”, „30–70 %”, „FN ≥ 3”, „≤ 0,5 %”.
  String text({required bool en}) {
    final lo = min, hi = max;
    String n(double v) => ferriteExact(v, en: en);
    final core = lo != null && hi != null
        ? '${n(lo)}–${n(hi)}'
        : lo != null
            ? '≥ ${n(lo)}'
            : hi != null
                ? '≤ ${n(hi)}'
                : '—';
    return unit == FerriteUnit.fn ? 'FN $core' : '$core %';
  }
}

/// Grupa presetów — do listy wyboru.
enum FerritePresetGroup { duplex, austenitic, lowFerrite }

/// Typowy zakres z normy / zalecenia — ZAWSZE „typowe, decyduje
/// specyfikacja projektu”. Źródło i wydanie w [sourcePl] / [sourceEn].
class FerritePreset {
  final String id;
  final FerritePresetGroup group;
  final FerriteRequirement requirement;

  /// Miejsca, których dotyczy zakres. Inne miejsce → brak werdyktu.
  final Set<FerriteLocation> appliesTo;
  final String titlePl;
  final String titleEn;
  final String sourcePl;
  final String sourceEn;
  final String notePl;
  final String noteEn;

  /// Minimalna liczba odczytów na miejsce, gdy źródło ją podaje (np. IOGP
  /// S-705 12.13.3: ≥ 3 na spoinę); inaczej 1. Mniej odczytów → brak
  /// werdyktu. Pole „min. odczytów” w protokole może ją tylko podnieść.
  final int minReadings;

  const FerritePreset({
    required this.id,
    required this.group,
    required this.requirement,
    required this.appliesTo,
    required this.titlePl,
    required this.titleEn,
    required this.sourcePl,
    required this.sourceEn,
    this.notePl = '',
    this.noteEn = '',
    this.minReadings = 1,
  });

  String title({required bool en}) => en ? titleEn : titlePl;
  String source({required bool en}) => en ? sourceEn : sourcePl;
  String note({required bool en}) => en ? noteEn : notePl;
}

// ═══════════════════════════════════════════════════════════════════════════
// ODCZYTY I OCENA
// ═══════════════════════════════════════════════════════════════════════════

/// Miejsce pomiaru z odczytami TAK, JAK WPISANO (tekst — przecinek albo
/// kropka). Tekst jest zapisywany, liczba liczona przy ocenie.
class FerriteSite {
  final String id;
  final FerriteLocation location;

  /// Oznaczenie, np. „Spoina 12, lico, godz. 3”.
  final String label;
  final List<String> readings;

  const FerriteSite({
    required this.id,
    required this.location,
    this.label = '',
    this.readings = const [],
  });

  FerriteSite copyWith({
    FerriteLocation? location,
    String? label,
    List<String>? readings,
  }) =>
      FerriteSite(
        id: id,
        location: location ?? this.location,
        label: label ?? this.label,
        readings: readings ?? this.readings,
      );

  bool get isBlank => label.trim().isEmpty && readings.isEmpty;

  Map<String, Object?> toJson() => {
        'id': id,
        'loc': location.name,
        'label': label,
        'readings': readings,
      };

  /// `null` dla wpisu bez id albo z nieznanym miejscem. Odczyty, które nie
  /// są tekstem, pozostają jako „?” (brak werdyktu); liczba uszkodzeń
  /// trafia do raportu odczytu, aby magazyn zachował kopię surowych danych.
  static (FerriteSite?, int) fromJson(Object? raw) {
    if (raw is! Map) return (null, 0);
    final id = raw['id'];
    final loc = FerriteLocation.byName(raw['loc']);
    if (id is! String || id.isEmpty || loc == null) return (null, 0);
    final stored = raw['readings'];
    final list = stored is List
        ? stored
        : stored == null
            ? const []
            : const [null];
    final readings = [
      for (final r in list)
        r is String ? r : '?',
    ];
    return (
      FerriteSite(
        id: id,
        location: loc,
        label: raw['label'] is String ? raw['label'] as String : '',
        readings: readings,
      ),
      list.where((r) => r is! String).length,
    );
  }
}

enum FerriteReadingStatus {
  inRange,
  below,
  above,

  /// Nieczytelny, ujemny albo > 100 % (≠ OK).
  invalid,
}

/// Odczyt jako liczba: `null`, gdy nieczytelny, ujemny albo fizycznie
/// niemożliwy (> 100 %). Przecinek = kropka.
double? parseFerriteReading(String text, FerriteUnit unit) {
  final v = parseDecimal(text);
  if (v == null || v < 0) return null;
  final cap = unit.maxPhysical;
  if (cap != null && v > cap) return null;
  return v;
}

/// Minimalna liczba odczytów N ze specyfikacji — liczba całkowita ≥ 1;
/// inaczej `null` (brak werdyktu).
int? parseFerriteMinCount(String text) {
  final v = parseDecimal(text);
  if (v == null || v < 1 || v != v.roundToDouble() || v > 1000) return null;
  return v.toInt();
}

/// Obowiązująca minimalna liczba odczytów na miejsce: z pola protokołu
/// ([text]) i z presetu ([FerritePreset.minReadings]) — większa z nich
/// (pole może wymaganie tylko podnieść). Reguła „każdy odczyt”: puste pole
/// = 1. Reguła „średnia z N”: N musi być wpisane. Nieczytelne pole →
/// `null` (brak werdyktu).
int? ferriteEffectiveMinCount(String text,
    {required FerriteRule rule, FerritePreset? preset}) {
  final int? own;
  if (text.trim().isEmpty) {
    own = rule == FerriteRule.average ? null : 1;
  } else {
    own = parseFerriteMinCount(text);
  }
  if (own == null) return null;
  final fromPreset = preset?.minReadings ?? 1;
  return own > fromPreset ? own : fromPreset;
}

enum FerriteVerdict {
  /// W zakresie (każdy odczyt albo średnia — wg reguły).
  pass,

  /// Poza zakresem.
  fail,

  /// Brak werdyktu — powód w [FerriteNoVerdict].
  none,
}

enum FerriteNoVerdict {
  /// Brak odczytów.
  noReadings,

  /// Co najmniej jeden odczyt nieczytelny / niefizyczny.
  invalidReading,

  /// Zakres pusty, min > max, ujemny albo > 100 %.
  invalidRequirement,

  /// Preset zniknął z aplikacji (zapis ze starszej / nowszej wersji).
  unknownPreset,

  /// Jednostka odczytów ≠ jednostka wymagania (FN ≠ %).
  unitMismatch,

  /// Pole „min. odczytów / N” nieczytelne (nie liczba całkowita ≥ 1) albo
  /// puste przy regule „średnia z N”.
  invalidCount,

  /// Mniej odczytów niż wymaga specyfikacja / preset / N.
  tooFewReadings,

  /// Preset dotyczy innego miejsca (np. spoina, a pomiar na materiale
  /// rodzimym).
  notForLocation,
}

class FerriteSiteResult {
  final FerriteSite site;

  /// Odczyty jako liczby (`null` — nieczytelny), w kolejności wpisu.
  final List<double?> values;

  /// Status każdego odczytu; `null`, gdy porównanie nie ma sensu (zły
  /// zakres, inna jednostka, preset dla innego miejsca).
  final List<FerriteReadingStatus?> statuses;

  /// Średnia (reguła „średnia z N”, gdy wszystkie odczyty czytelne).
  final double? mean;
  final FerriteVerdict verdict;
  final FerriteNoVerdict? reason;

  /// Obowiązująca minimalna liczba odczytów (pole protokołu / preset /
  /// N), gdy czytelna.
  final int? minCount;

  const FerriteSiteResult({
    required this.site,
    required this.values,
    required this.statuses,
    required this.mean,
    required this.verdict,
    required this.reason,
    this.minCount,
  });

  int get outOfRangeCount => statuses
      .where((s) =>
          s == FerriteReadingStatus.below || s == FerriteReadingStatus.above)
      .length;

  int get invalidCount => values.where((v) => v == null).length;

  int get validCount => values.where((v) => v != null).length;
}

/// Pomocnicze wyrównanie interpolacji PMI do siatki 1e-9: szum
/// zmiennoprzecinkowy (30,000000000000004) nie zamienia „równo z granicą”
/// w „poza zakresem”. Odczyty mają najwyżej kilka miejsc po przecinku.
double ferriteSnap(double x) => (x * 1e9).roundToDouble() / 1e9;

/// Canonical decimal value of an already validated finite double.
(BigInt, int) _decimalParts(double value) {
  final parts = value.toString().split('e');
  final mantissa = parts.first;
  final dot = mantissa.indexOf('.');
  final scale = (dot < 0 ? 0 : mantissa.length - dot - 1) -
      (parts.length == 1 ? 0 : int.parse(parts[1]));
  return (BigInt.parse(mantissa.replaceAll('.', '')), scale);
}

/// Sum decimal readings exactly, then round the rational mean once to double.
/// No fixed decimal grid and no intermediate floating-point sum overflow.
double _ferriteMean(List<double> values) {
  final parts = values.map(_decimalParts).toList();
  final scale = parts.fold<int>(0, (s, p) => math.max(s, p.$2));
  final ten = BigInt.from(10);
  var numerator = BigInt.zero;
  for (final (coefficient, places) in parts) {
    numerator += coefficient * ten.pow(scale - places);
  }
  if (numerator == BigInt.zero) return 0;
  var denominator = ten.pow(scale) * BigInt.from(values.length);

  // Round the binary significand to nearest, ties to even. Clamping the
  // exponent to -1074 also handles subnormal values and underflow to zero.
  var exponent = numerator.bitLength - denominator.bitLength;
  if (exponent >= 0
      ? numerator < denominator << exponent
      : numerator << -exponent < denominator) {
    exponent--;
  }
  final shift = math.max(exponent - 52, -1074);
  if (shift < 0) {
    numerator <<= -shift;
  } else {
    denominator <<= shift;
  }
  var significand = numerator ~/ denominator;
  final twiceRemainder = (numerator % denominator) << 1;
  if (twiceRemainder > denominator ||
      twiceRemainder == denominator && significand.isOdd) {
    significand += BigInt.one;
  }
  return significand.toDouble() * math.pow(2.0, shift);
}

/// Ocena jednego miejsca. [requirement] `null` — preset nieznany (brak
/// werdyktu). [preset] — skąd zakres (`null` = ze specyfikacji, wpisany);
/// preset dla innego miejsca → brak werdyktu.
FerriteSiteResult evaluateFerriteSite(
  FerriteSite site, {
  required FerriteRequirement? requirement,
  required FerriteUnit readingUnit,
  FerriteRule rule = FerriteRule.everyReading,
  String minCountText = '',
  FerritePreset? preset,
}) {
  final values = [
    for (final r in site.readings) parseFerriteReading(r, readingUnit),
  ];
  final n = ferriteEffectiveMinCount(minCountText, rule: rule, preset: preset);

  FerriteSiteResult none(FerriteNoVerdict why,
          {List<FerriteReadingStatus?>? statuses, double? mean}) =>
      FerriteSiteResult(
        site: site,
        values: values,
        statuses: statuses ??
            [
              for (final v in values)
                v == null ? FerriteReadingStatus.invalid : null,
            ],
        mean: mean,
        verdict: FerriteVerdict.none,
        reason: why,
        minCount: n,
      );

  if (requirement == null) return none(FerriteNoVerdict.unknownPreset);
  if (!requirement.isValid) return none(FerriteNoVerdict.invalidRequirement);
  if (preset != null && !preset.appliesTo.contains(site.location)) {
    return none(FerriteNoVerdict.notForLocation);
  }
  if (requirement.unit != readingUnit) {
    return none(FerriteNoVerdict.unitMismatch);
  }
  if (site.readings.isEmpty) return none(FerriteNoVerdict.noReadings);

  final statuses = [
    for (final v in values)
      v == null ? FerriteReadingStatus.invalid : requirement.statusOf(v),
  ];
  final anyInvalid = statuses.contains(FerriteReadingStatus.invalid);

  if (rule == FerriteRule.everyReading) {
    final anyOut = statuses.any((s) =>
        s == FerriteReadingStatus.below || s == FerriteReadingStatus.above);
    if (anyOut) {
      return FerriteSiteResult(
        site: site,
        values: values,
        statuses: statuses,
        mean: null,
        verdict: FerriteVerdict.fail,
        reason: null,
      );
    }
    if (anyInvalid) {
      return none(FerriteNoVerdict.invalidReading, statuses: statuses);
    }
    // Wszystkie w zakresie — ale zielone dopiero przy liczbie odczytów
    // wymaganej przez specyfikację / preset.
    if (n == null) {
      return none(FerriteNoVerdict.invalidCount, statuses: statuses);
    }
    if (values.length < n) {
      return none(FerriteNoVerdict.tooFewReadings, statuses: statuses);
    }
    return FerriteSiteResult(
      site: site,
      values: values,
      statuses: statuses,
      mean: null,
      verdict: FerriteVerdict.pass,
      reason: null,
      minCount: n,
    );
  }

  // Średnia z N: wszystkie odczyty czytelne, co najmniej N.
  if (anyInvalid) {
    return none(FerriteNoVerdict.invalidReading, statuses: statuses);
  }
  final mean = _ferriteMean(values.cast<double>());
  if (n == null) {
    return none(FerriteNoVerdict.invalidCount, statuses: statuses, mean: mean);
  }
  if (values.length < n) {
    return none(FerriteNoVerdict.tooFewReadings,
        statuses: statuses, mean: mean);
  }
  return FerriteSiteResult(
    site: site,
    values: values,
    statuses: statuses,
    mean: mean,
    verdict: requirement.statusOf(mean) == FerriteReadingStatus.inRange
        ? FerriteVerdict.pass
        : FerriteVerdict.fail,
    reason: null,
    minCount: n,
  );
}

/// Werdykt całego protokołu ferrytu: „poza zakresem”, gdy choć jedno
/// miejsce poza; „w zakresie” tylko, gdy KAŻDE miejsce w zakresie; inaczej
/// brak werdyktu (także bez miejsc).
FerriteVerdict ferriteOverall(List<FerriteSiteResult> sites) {
  if (sites.isEmpty) return FerriteVerdict.none;
  if (sites.any((s) => s.verdict == FerriteVerdict.fail)) {
    return FerriteVerdict.fail;
  }
  if (sites.every((s) => s.verdict == FerriteVerdict.pass)) {
    return FerriteVerdict.pass;
  }
  return FerriteVerdict.none;
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE
// ═══════════════════════════════════════════════════════════════════════════

String _sep(String s, bool en) => en ? s : s.replaceAll('.', ',');

/// Liczba „tak jak wpisana” — najkrótszy zapis, bez zaokrąglania.
String ferriteExact(double v, {required bool en}) {
  if (!v.isFinite) return '—';
  final (coefficient, scale) = _decimalParts(v);
  final digits = coefficient.abs().toString();
  final sign = v.isNegative ? '-' : '';
  final String magnitude;
  if (scale <= 0) {
    magnitude = '$digits${'0' * -scale}';
  } else if (digits.length <= scale) {
    magnitude = '0.${'0' * (scale - digits.length)}$digits';
  } else {
    final point = digits.length - scale;
    magnitude = '${digits.substring(0, point)}.${digits.substring(point)}';
  }
  var s = '$sign$magnitude';
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return _sep(s, en);
}

/// Odczyt pokazywany DOKŁADNIE tak, jak wpisano (zera na końcu zostają:
/// „31,0”, „45,50”) — zmienia się tylko separator dziesiętny pod język.
String ferriteRawText(String raw, {required bool en}) {
  final t = raw.replaceAll(RegExp(r'\s'), '');
  return en ? t.replaceAll(',', '.') : t.replaceAll('.', ',');
}

double _round(double v, int decimals, int dir) {
  var f = 1.0;
  for (var i = 0; i < decimals; i++) {
    f *= 10;
  }
  final s = v * f;
  final r = dir < 0
      ? (s + 1e-9).floorToDouble()
      : dir > 0
          ? (s - 1e-9).ceilToDouble()
          : s.roundToDouble();
  return r / f;
}

/// Średnia obok werdyktu: zaokrąglona W STRONĘ werdyktu — poniżej min
/// w dół, powyżej max w górę, w zakresie tak, żeby pokazana liczba nadal
/// leżała w zakresie. 29,96 przy min 30 to „29,9”, nigdy „30,0”.
String ferriteFormatAgainst(double v, FerriteRequirement r,
    {required bool en}) {
  final status = r.statusOf(v);
  final dir = switch (status) {
    FerriteReadingStatus.below => -1,
    FerriteReadingStatus.above => 1,
    _ => 0,
  };
  for (var d = 1; d <= 9; d++) {
    final shown = _round(v, d, dir);
    if (r.statusOf(shown) == status) {
      final s = shown.toStringAsFixed(d);
      return _sep(s, en);
    }
  }
  return ferriteExact(v, en: en);
}

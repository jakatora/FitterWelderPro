/// Akord: ile zarobiłem — zarobek spawacza z dziennika spoin, policzony tak,
/// żeby dało się sprawdzić rozliczenie od firmy spoina po spoinie.
///
/// Reguły (te same na ekranie, w tekście i w PDF):
///
/// * **Spoina** — nieusunięty wpis dziennika z poprawną datą w okresie. Data
///   to dzień z dziennika (`RRRR-MM-DD`, dzień kalendarzowy czasu lokalnego).
///   Status nie ma znaczenia — PENDING też jest zespawana (jak w „Postępie
///   robót"). Wpis bez poprawnej daty nie należy do żadnego okresu; wpis
///   z datą w przyszłości (po końcu okresu i po dziś) też nie — oba trafiają
///   do uwag.
/// * **DI** — [weldDiameterInches] z „Postępu robót": NPS w calach z OD przez
///   tabelę B36.10M/B36.19M; OD spoza tabeli → OD / 25,4, oznaczone „≈"
///   (wliczone, ale wymienione w uwagach). Spoina bez OD w trybie „za DI" jest
///   POMIJANA — lista „uzupełnij wymiar", kwota jej nie zawiera. W trybie „za
///   spoinę" wymiar nie jest potrzebny.
/// * **Podstawa** spoiny = DI × stawka zł/DI (albo stawka za spoinę),
///   zaokrąglona do grosza.
/// * **Dopłaty** — procent od PODSTAWY spoiny; sumują się, nie mnożą:
///   materiał (nierdzewna / inne), pozycja (2G / 5G / 6G), gruba ścianka.
///   Każda zaokrąglana do grosza osobno.
/// * **Spawacz** — stemple spoiny (spawacz, grań, lico). Spoina z kilkoma
///   spawaczami: KAŻDY składnik całej spoiny (podstawa, dopłaty, potrącenie,
///   naprawy) dzielony metodą największej reszty ([splitGrosze]) — suma
///   udziałów = kwota spoiny w widoku brygady co do grosza. „Cała brygada"
///   liczy każdą spoinę raz, w całości.
/// * **Odrzucona spoina** — ma naprawę (R1, R2…) albo teraz status NOK lub
///   wynik NOK któregokolwiek badania (VT, PT, MT, RT, UT). Potrącenie = X %
///   wartości spoiny (podstawa + dopłaty); 100 % = spoina za 0 zł.
/// * **Naprawa płatna osobno** — za każdy rekord naprawy Y % wartości spoiny.
///   Potrącenie i naprawy liczą się w okresie SPOINY (data z dziennika), nie
///   w dniu naprawy.
/// * **Minimum dzienne** — tylko dla jednego spawacza: dzień z policzonymi
///   spoinami, który dał mniej, jest dopłacany do minimum — chyba że tego
///   dnia są spoiny pominięte (bez OD): wtedy dopłaty nie ma, dopóki wymiar
///   nie zostanie uzupełniony (uwaga z datą dnia).
/// * **Grosze** — każda kwota to `int` w groszach; zaokrąglenie połówek od
///   zera na każdej spoinie i każdej dopłacie, podział między spawaczy bez
///   gubienia groszy; suma = suma spoin (bez drugiego zaokrąglania).
///
/// Czysty Dart.
library;

import 'dart:convert';

import '../../data/pipe_schedules.dart';
import '../../utils/decimal_parse.dart';
import '../progress/progress_filter.dart' show DayRange;
import '../progress/progress_report.dart' show dayLabel, progressNum, weldsCount;
import '../progress/weld_progress.dart' show weldDiameterInches;
import '../progress/work_calendar.dart';
import '../quotes/quote_calculator.dart' show formatPln, npsInchesForOd;
import '../weld_journal/weld_dates.dart' show isoDate;
import '../weld_journal/weld_entry.dart';

// ─── Grosze ───────────────────────────────────────────────────────────────

/// Kwota w groszach z wartości w groszach — połówka od zera (0,5 gr → 1 gr).
int roundGrosze(double grosze) => grosze.isFinite ? grosze.round() : 0;

/// [bp] punktów bazowych (1 % = 100) z [grosze], zaokrąglone do grosza,
/// połówka od zera. Liczone na liczbach całkowitych — bez błędów `double`.
int pctOfGrosze(int grosze, int bp) {
  final p = grosze * bp;
  final half = p >= 0 ? 5000 : -5000;
  return (p + half) ~/ 10000;
}

/// [a] ÷ [b] zaokrąglone do całości, połówka od zera; [b] > 0.
int divRoundHalf(int a, int b) {
  assert(b > 0);
  final q = a.abs() * 2 + b;
  final r = q ~/ (2 * b);
  return a < 0 ? -r : r;
}

/// Procent z punktów bazowych: 2000 → „20%", 1250 → „12,5%".
String bpText(int bp, {required bool en}) =>
    '${progressNum(bp / 100, en: en, decimals: 2)}%';

/// Punkty bazowe z procentu (12,5 → 1250), zaokrąglone.
int bpFromPct(double pct) => pct.isFinite ? (pct * 100).round() : 0;

// ─── Stawki ───────────────────────────────────────────────────────────────

enum PieceworkMode {
  /// Za cal-średnicę (zł/DI).
  di('di'),

  /// Za spoinę (zł/szt.).
  weld('weld');

  const PieceworkMode(this.code);
  final String code;

  static PieceworkMode? fromCode(Object? c) {
    for (final m in values) {
      if (m.code == c) return m;
    }
    return null;
  }
}

/// Kiedy ścianka jest „gruba" (dopłata).
enum WallRule {
  none('none'),

  /// Grubość ≥ ścianki Sch 80 dla OD spoiny (B36.10M; nierdzewna 80S).
  sch80('sch80'),

  /// Grubość ≥ progu w mm.
  mm('mm');

  const WallRule(this.code);
  final String code;

  static WallRule? fromCode(Object? c) {
    for (final m in values) {
      if (m.code == c) return m;
    }
    return null;
  }
}

/// Górne granice wartości (zapis spoza nich jest uszkodzony).
const int kPieceworkMaxRateGrosze = 10000000; // 100 000 zł
const int kPieceworkMaxBp = 100000; // 1000 %
const double kPieceworkMaxWallMm = 200;
const double kPieceworkMaxHoursPerDay = 24;

class PieceworkRates {
  /// Wersja formatu JSON (klucz SharedPreferences też ją ma).
  static const int version = 1;

  final PieceworkMode mode;

  /// Stawka podstawowa w groszach: za 1 DI albo za 1 spoinę.
  final int rateGrosze;

  /// Dopłaty materiałowe, punkty bazowe (2000 = +20 %).
  final int stainlessBp;
  final int otherMaterialBp;

  /// Dopłaty za pozycję, punkty bazowe. 1G (PA) bez dopłaty.
  final int pos2gBp;
  final int pos5gBp;
  final int pos6gBp;

  final WallRule wallRule;

  /// Próg grubości dla [WallRule.mm].
  final double wallMm;
  final int wallBp;

  /// Minimum dzienne w groszach; null = bez minimum.
  final int? minDayGrosze;

  /// Potrącenie za odrzuconą spoinę, % wartości spoiny w punktach
  /// bazowych (0…10000; 10000 = spoina za 0 zł).
  final int rejectBp;

  /// Naprawa płatna osobno: za każdy rekord naprawy [repairBp] wartości
  /// spoiny.
  final bool repairPaid;
  final int repairBp;

  /// Godzin pracy dziennie (do zł/h), null = nie podano.
  final double? hoursPerDay;

  const PieceworkRates({
    this.mode = PieceworkMode.di,
    this.rateGrosze = 0,
    this.stainlessBp = 0,
    this.otherMaterialBp = 0,
    this.pos2gBp = 0,
    this.pos5gBp = 0,
    this.pos6gBp = 0,
    this.wallRule = WallRule.none,
    this.wallMm = 10,
    this.wallBp = 0,
    this.minDayGrosze,
    this.rejectBp = 0,
    this.repairPaid = false,
    this.repairBp = 10000,
    this.hoursPerDay,
  });

  int materialBp(PieceworkMaterial m) => switch (m) {
        PieceworkMaterial.stainless => stainlessBp,
        PieceworkMaterial.other => otherMaterialBp,
        PieceworkMaterial.carbon || PieceworkMaterial.unknown => 0,
      };

  int positionBp(PayPosition p) => switch (p) {
        PayPosition.p2g => pos2gBp,
        PayPosition.p5g => pos5gBp,
        PayPosition.p6g => pos6gBp,
        PayPosition.p1g || PayPosition.none || PayPosition.other => 0,
      };

  bool get hasMaterialSurcharge => stainlessBp > 0 || otherMaterialBp > 0;
  bool get hasPositionSurcharge => pos2gBp > 0 || pos5gBp > 0 || pos6gBp > 0;
  bool get hasWallSurcharge => wallRule != WallRule.none && wallBp > 0;

  static const Object _keep = Object();

  PieceworkRates copyWith({
    PieceworkMode? mode,
    int? rateGrosze,
    int? stainlessBp,
    int? otherMaterialBp,
    int? pos2gBp,
    int? pos5gBp,
    int? pos6gBp,
    WallRule? wallRule,
    double? wallMm,
    int? wallBp,
    Object? minDayGrosze = _keep,
    int? rejectBp,
    bool? repairPaid,
    int? repairBp,
    Object? hoursPerDay = _keep,
  }) =>
      PieceworkRates(
        mode: mode ?? this.mode,
        rateGrosze: rateGrosze ?? this.rateGrosze,
        stainlessBp: stainlessBp ?? this.stainlessBp,
        otherMaterialBp: otherMaterialBp ?? this.otherMaterialBp,
        pos2gBp: pos2gBp ?? this.pos2gBp,
        pos5gBp: pos5gBp ?? this.pos5gBp,
        pos6gBp: pos6gBp ?? this.pos6gBp,
        wallRule: wallRule ?? this.wallRule,
        wallMm: wallMm ?? this.wallMm,
        wallBp: wallBp ?? this.wallBp,
        minDayGrosze: identical(minDayGrosze, _keep)
            ? this.minDayGrosze
            : minDayGrosze as int?,
        rejectBp: rejectBp ?? this.rejectBp,
        repairPaid: repairPaid ?? this.repairPaid,
        repairBp: repairBp ?? this.repairBp,
        hoursPerDay: identical(hoursPerDay, _keep)
            ? this.hoursPerDay
            : (hoursPerDay as num?)?.toDouble(),
      );

  Map<String, Object?> toJson() => {
        'v': version,
        'mode': mode.code,
        'rate': rateGrosze,
        'ss': stainlessBp,
        'other': otherMaterialBp,
        'p2g': pos2gBp,
        'p5g': pos5gBp,
        'p6g': pos6gBp,
        'wall': wallRule.code,
        'wallMm': wallMm,
        'wallBp': wallBp,
        'minDay': minDayGrosze,
        'reject': rejectBp,
        'repairPaid': repairPaid,
        'repair': repairBp,
        'hpd': hoursPerDay,
      };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is PieceworkRates && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// Wynik odczytu stawek: stawki i to, czy zapis był nienaruszony.
class PieceworkRatesDecode {
  final PieceworkRates rates;

  /// false — nieczytelny JSON albo któreś pole złego typu / spoza zakresu
  /// (to pole wraca do wartości domyślnej, reszta zostaje).
  final bool intact;

  const PieceworkRatesDecode(this.rates, {required this.intact});
}

/// Stawki z JSON. Brak zapisu = domyślne (nienaruszone). Brakujące pole =
/// domyślne (nienaruszone — starszy zapis). Pole złego typu lub spoza
/// zakresu = domyślne i znacznik uszkodzenia. Nigdy nie rzuca.
PieceworkRatesDecode decodePieceworkRates(String? raw) {
  const d = PieceworkRates();
  if (raw == null || raw.trim().isEmpty) {
    return const PieceworkRatesDecode(d, intact: true);
  }
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return const PieceworkRatesDecode(d, intact: false);
  }
  if (json is! Map) return const PieceworkRatesDecode(d, intact: false);
  final Map<Object?, Object?> map = json;
  var intact = true;

  bool has(String k) => map.containsKey(k);

  int intOf(String k, int def, int max) {
    if (!has(k)) return def;
    final v = map[k];
    if (v is num && v.isFinite && v == v.roundToDouble() && v >= 0 && v <= max) {
      return v.toInt();
    }
    intact = false;
    return def;
  }

  int? intOrNull(String k, int max) {
    if (!has(k) || map[k] == null) return null;
    final v = map[k];
    if (v is num && v.isFinite && v == v.roundToDouble() && v >= 0 && v <= max) {
      return v.toInt();
    }
    intact = false;
    return null;
  }

  double dblOf(String k, double def, double max) {
    if (!has(k)) return def;
    final v = map[k];
    if (v is num && v.isFinite && v > 0 && v <= max) return v.toDouble();
    intact = false;
    return def;
  }

  double? dblOrNull(String k, double max) {
    if (!has(k) || map[k] == null) return null;
    final v = map[k];
    if (v is num && v.isFinite && v > 0 && v <= max) return v.toDouble();
    intact = false;
    return null;
  }

  T enumOf<T>(String k, T def, T? Function(Object?) parse) {
    if (!has(k)) return def;
    final v = parse(map[k]);
    if (v != null) return v;
    intact = false;
    return def;
  }

  bool boolOf(String k, bool def) {
    if (!has(k)) return def;
    final v = map[k];
    if (v is bool) return v;
    intact = false;
    return def;
  }

  if (has('v') && map['v'] != PieceworkRates.version) intact = false;

  final rates = PieceworkRates(
    mode: enumOf('mode', d.mode, PieceworkMode.fromCode),
    rateGrosze: intOf('rate', d.rateGrosze, kPieceworkMaxRateGrosze),
    stainlessBp: intOf('ss', d.stainlessBp, kPieceworkMaxBp),
    otherMaterialBp: intOf('other', d.otherMaterialBp, kPieceworkMaxBp),
    pos2gBp: intOf('p2g', d.pos2gBp, kPieceworkMaxBp),
    pos5gBp: intOf('p5g', d.pos5gBp, kPieceworkMaxBp),
    pos6gBp: intOf('p6g', d.pos6gBp, kPieceworkMaxBp),
    wallRule: enumOf('wall', d.wallRule, WallRule.fromCode),
    wallMm: dblOf('wallMm', d.wallMm, kPieceworkMaxWallMm),
    wallBp: intOf('wallBp', d.wallBp, kPieceworkMaxBp),
    minDayGrosze: intOrNull('minDay', kPieceworkMaxRateGrosze),
    rejectBp: intOf('reject', d.rejectBp, 10000),
    repairPaid: boolOf('repairPaid', d.repairPaid),
    repairBp: intOf('repair', d.repairBp, kPieceworkMaxBp),
    hoursPerDay: dblOrNull('hpd', kPieceworkMaxHoursPerDay),
  );
  return PieceworkRatesDecode(rates, intact: intact);
}

// ─── Klasyfikacja spoiny ──────────────────────────────────────────────────

/// Grupa materiału do dopłaty.
enum PieceworkMaterial {
  carbon,
  stainless,

  /// Stale stopowe Cr-Mo (P11, P22, P91…), nikiel, aluminium, miedź, tytan.
  other,

  /// Puste albo nierozpoznane — bez dopłaty materiałowej (uwaga w raporcie).
  unknown,
}

const List<String> _kStainlessMarkers = [
  'STAINLESS', 'NIERDZ', 'KWASOODP', 'INOX', 'DUPLEX', 'CRNI', 'A312', //
  'A358', 'A376', 'A403', 'A182F3', 'A240',
];

const List<String> _kOtherMarkers = [
  'CRMO', 'A335', 'A387', 'A691', 'INCONEL', 'INCOLOY', 'HASTELLOY', //
  'MONEL', 'NICKEL', 'NIKIEL', 'ALLOY', 'ALUMIN', 'CUNI', 'MIEDZ', 'MIEDŹ',
  'COPPER', 'TITAN',
];

const List<String> _kCarbonMarkers = [
  'CARBON', 'WEGL', 'WĘGL', 'CZARN', 'A106', 'A234', 'A105', 'A53', 'A333', //
  'A350', 'A420', 'A216', 'A516', 'API5L', 'WPB', 'WPL6', 'WPL3', 'GRB',
  'GR.B', 'ST37', 'ST35', 'ST44', 'ST45', 'ST52', 'S235', 'S275', 'S355',
  'P195', 'P235', 'P250', 'P265', 'P275', 'P295', 'P355', 'L235', 'L245',
  'L290', 'L360', 'L415', 'L450', 'L485', 'X42', 'X52', 'X56', 'X60', 'X65',
  'X70', 'R35', 'R45',
];

/// Gatunki AISI 3xx i 904L, także „TP316L", „F304", „WP316".
final RegExp _kStainlessGrade =
    RegExp(r'(?<![0-9])(?:304|309|310|316|317|321|347|904)(?![0-9])');

/// Numery materiałowe 1.40xx–1.48xx (nierdzewne i żaroodporne; 1.49xx to
/// stale do pracy w wysokiej temperaturze, np. P91 = 1.4903 — „inne").
final RegExp _kStainlessWnr = RegExp(r'(?<![0-9.])1\.4[0-8][0-9]{2}(?![0-9])');

final RegExp _kOtherWnr =
    RegExp(r'(?<![0-9.])(?:1\.49[0-9]{2}|1\.7[0-9]{3}|2\.4[0-9]{3})(?![0-9])');

/// Stale Cr-Mo z ASTM: P11, P22, P91, F22, T91, WP11…
final RegExp _kOtherAstm =
    RegExp(r'(?<![A-Z0-9])(?:WP|P|F|T)(?:5|9|11|12|22|91|92)(?![0-9])');

final RegExp _kCarbonWnr = RegExp(r'(?<![0-9.])1\.[01][0-9]{3}(?![0-9])');

final RegExp _kWordSs = RegExp(r'\bSS\b');
final RegExp _kWordCs = RegExp(r'\bCS\b');

/// Grupa materiału z pola „Materiał" dziennika. Nierozpoznany albo pusty →
/// [PieceworkMaterial.unknown] (bez zgadywania).
PieceworkMaterial pieceworkMaterialOf(String material) {
  final upper = material.trim().toUpperCase();
  if (upper.isEmpty) return PieceworkMaterial.unknown;
  final squashed = upper.replaceAll(RegExp(r'[\s\-_/]'), '');
  if (_kStainlessMarkers.any(squashed.contains) ||
      _kStainlessGrade.hasMatch(upper) ||
      _kStainlessWnr.hasMatch(upper) ||
      squashed.contains('2205') ||
      squashed.contains('2507')) {
    return PieceworkMaterial.stainless;
  }
  if (_kOtherMarkers.any(squashed.contains) ||
      _kOtherWnr.hasMatch(upper) ||
      _kOtherAstm.hasMatch(upper)) {
    return PieceworkMaterial.other;
  }
  if (_kCarbonMarkers.any(squashed.contains) || _kCarbonWnr.hasMatch(upper)) {
    return PieceworkMaterial.carbon;
  }
  if (_kWordSs.hasMatch(upper)) return PieceworkMaterial.stainless;
  if (_kWordCs.hasMatch(upper)) return PieceworkMaterial.carbon;
  return PieceworkMaterial.unknown;
}

/// Pozycja do dopłaty.
enum PayPosition {
  /// 1G / PA — obracana, bez dopłaty.
  p1g,
  p2g,
  p5g,
  p6g,

  /// Brak pozycji w dzienniku.
  none,

  /// Inna (pachwinowe 1F–5F, PB, PD, PE…) — bez dopłaty.
  other,
}

/// Pozycja z dziennika → pozycja do dopłaty.
///
/// * 1G, PA → 1G (bez dopłaty);
/// * 2G, PC → 2G;
/// * 5G, PF, PG, PH, PJ → 5G (rura nieobracana, oś pozioma; PF/PG to zapis
///   rur z EN 287-1 / ISO 9606-1:2012, PH/PJ z ISO 6947:2011);
/// * 6G (też 6GR), H-L045, J-L045 → 6G;
/// * reszta → inna, bez dopłaty.
PayPosition payPositionOf(String position) {
  final p = position.trim().toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
  if (p.isEmpty) return PayPosition.none;
  if (p == '1G' || p == 'PA') return PayPosition.p1g;
  if (p == '2G' || p == 'PC') return PayPosition.p2g;
  if (const {'5G', 'PF', 'PG', 'PH', 'PJ'}.contains(p)) return PayPosition.p5g;
  if (p.startsWith('6G') || p == 'HL045' || p == 'JL045') {
    return PayPosition.p6g;
  }
  return PayPosition.other;
}

String payPositionLabel(PayPosition p) => switch (p) {
      PayPosition.p1g => '1G',
      PayPosition.p2g => '2G',
      PayPosition.p5g => '5G',
      PayPosition.p6g => '6G',
      PayPosition.none => '—',
      PayPosition.other => '?',
    };

/// Ścianka Sch 80 (B36.10M; dla nierdzewnej 80S) dla OD spoiny, mm, albo
/// null — OD spoza tabeli.
double? sch80WallMm(double odMm, {bool stainless = false}) {
  for (final row in kPipeWalls) {
    if ((row.od - odMm).abs() <= 0.6) {
      return stainless
          ? (row.walls['80S'] ?? row.walls['80'])
          : (row.walls['80'] ?? row.walls['80S']);
    }
  }
  return null;
}

/// Gruba ścianka wg [rule]: true / false, albo null — nie da się ustalić
/// (brak grubości; przy Sch 80 także OD spoza tabeli).
bool? pieceworkThickWall(
  WeldEntry e, {
  required WallRule rule,
  required double wallMm,
  PieceworkMaterial? material,
}) {
  if (rule == WallRule.none) return false;
  final t = parseDecimal(e.t);
  if (t == null || t <= 0) return null;
  switch (rule) {
    case WallRule.none:
      return false;
    case WallRule.mm:
      return t >= wallMm - 1e-9;
    case WallRule.sch80:
      final od = parseDecimal(e.od);
      if (od == null || od <= 0 || npsInchesForOd(od) == null) return null;
      final m = material ?? pieceworkMaterialOf(e.material);
      final s80 = sch80WallMm(od, stainless: m == PieceworkMaterial.stainless);
      if (s80 == null) return null;
      // Ścianki z tabeli mają dwa miejsca po przecinku — 0,005 mm luzu na
      // zapis „5,5" zamiast „5,54" nie wystarcza i nie ma wystarczać.
      return t >= s80 - 0.005;
  }
}

/// Spoina odrzucona: ma naprawę (R1+) albo teraz status NOK lub wynik NOK
/// któregokolwiek badania.
bool pieceworkRejected(WeldEntry e) =>
    e.repairs.isNotEmpty ||
    e.status.trim().toUpperCase() == WeldStatus.nok ||
    e.ndt.values.any((n) => n.isRejected);

// ─── Okres i spawacz ──────────────────────────────────────────────────────

enum PieceworkPeriod {
  today,

  /// Od poniedziałku do dziś.
  week,

  /// Od 1. do dziś.
  month,

  /// Cały poprzedni miesiąc — typowy okres rozliczenia.
  lastMonth,

  custom,
}

String pieceworkPeriodLabel(PieceworkPeriod p, {required bool en}) =>
    switch (p) {
      PieceworkPeriod.today => en ? 'Today' : 'Dziś',
      PieceworkPeriod.week => en ? 'This week' : 'Ten tydzień',
      PieceworkPeriod.month => en ? 'This month' : 'Ten miesiąc',
      PieceworkPeriod.lastMonth => en ? 'Last month' : 'Poprzedni miesiąc',
      PieceworkPeriod.custom => en ? 'Custom…' : 'Własny…',
    };

/// Zakres dni okresu (włącznie). [now] przeliczane na czas lokalny — dzień
/// spoiny w dzienniku to dzień kalendarzowy telefonu. Własny zakres bez
/// granic = dziś; odwrócony — zamieniony.
DayRange pieceworkRange(
  PieceworkPeriod period,
  DateTime now, {
  DateTime? customFrom,
  DateTime? customTo,
}) {
  final t = dayOnly(now.toLocal());
  switch (period) {
    case PieceworkPeriod.today:
      return DayRange(t, t);
    case PieceworkPeriod.week:
      return DayRange(mondayOf(t), t);
    case PieceworkPeriod.month:
      return DayRange(DateTime(t.year, t.month, 1), t);
    case PieceworkPeriod.lastMonth:
      // Dzień 0 miesiąca = ostatni dzień poprzedniego.
      return DayRange(
          DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 0));
    case PieceworkPeriod.custom:
      final a = customFrom, b = customTo;
      if (a == null || b == null) return DayRange(t, t);
      final from = dayOnly(a), to = dayOnly(b);
      return from.isAfter(to) ? DayRange(to, from) : DayRange(from, to);
  }
}

/// Stemple spawaczy z dziennika (nieusunięte wpisy), pierwsza pisownia,
/// alfabetycznie.
List<String> pieceworkStamps(Iterable<WeldEntry> entries) {
  final seen = <String, String>{};
  for (final e in entries) {
    if (e.isDeleted) continue;
    for (final s in e.stamps) {
      seen.putIfAbsent(s.toLowerCase(), () => s);
    }
  }
  return seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Domyślny spawacz: tożsamość z telefonu („ja"), inaczej jedyny stempel
/// w dzienniku, inaczej null = cała brygada.
String? defaultPieceworkWelder({
  String? identityStamp,
  required List<String> stamps,
}) {
  final me = identityStamp?.trim() ?? '';
  if (me.isNotEmpty) {
    for (final s in stamps) {
      if (s.toLowerCase() == me.toLowerCase()) return s;
    }
    return me;
  }
  if (stamps.length == 1) return stamps.single;
  return null;
}

// ─── Obliczenie ───────────────────────────────────────────────────────────

/// Jedna policzona spoina (udział wybranego spawacza).
class PieceworkLine {
  final WeldEntry weld;
  final DateTime day;

  /// Liczba spawaczy, między których dzielona jest spoina (1 dla brygady).
  final int splitBetween;

  /// DI spoiny (cała spoina) albo null — brak OD (tylko w trybie za spoinę).
  final double? weldDi;
  final bool diApprox;

  final PieceworkMaterial material;
  final PayPosition position;

  /// Gruba ścianka; null = nie dało się ustalić.
  final bool? thickWall;

  final bool rejected;
  final int repairs;

  final int baseGrosze;
  final int materialGrosze;
  final int positionGrosze;
  final int wallGrosze;

  /// Potrącenie (liczba dodatnia — odejmowana).
  final int deductionGrosze;
  final int repairPayGrosze;

  const PieceworkLine({
    required this.weld,
    required this.day,
    required this.splitBetween,
    required this.weldDi,
    required this.diApprox,
    required this.material,
    required this.position,
    required this.thickWall,
    required this.rejected,
    required this.repairs,
    required this.baseGrosze,
    required this.materialGrosze,
    required this.positionGrosze,
    required this.wallGrosze,
    required this.deductionGrosze,
    required this.repairPayGrosze,
  });

  /// Udział w spoinie (1 / n).
  double get share => 1 / splitBetween;

  /// DI przypadające na wybranego spawacza.
  double get diShare => (weldDi ?? 0) / splitBetween;

  /// Wartość spoiny: podstawa + dopłaty.
  int get valueGrosze =>
      baseGrosze + materialGrosze + positionGrosze + wallGrosze;

  /// Do zapłaty za spoinę: wartość − potrącenie + naprawy.
  int get netGrosze => valueGrosze - deductionGrosze + repairPayGrosze;
}

/// Jeden dzień z policzonymi spoinami.
class PieceworkDay {
  final DateTime day;
  final int welds;
  final double di;

  /// Suma spoin dnia (bez dopłaty do minimum).
  final int netGrosze;

  /// Dopłata do minimum dziennego.
  final int topUpGrosze;

  /// Spoiny tego dnia pominięte (bez OD) — dzień nie dostaje dopłaty do
  /// minimum, dopóki wymiar nie zostanie uzupełniony.
  final int skippedWelds;

  const PieceworkDay({
    required this.day,
    required this.welds,
    required this.di,
    required this.netGrosze,
    required this.topUpGrosze,
    this.skippedWelds = 0,
  });
}

class PieceworkResult {
  final DayRange range;

  /// Stempel spawacza albo null — cała brygada.
  final String? welder;
  final PieceworkRates rates;

  /// Policzone spoiny: po dniu, potem w kolejności dziennika.
  final List<PieceworkLine> lines;

  /// Spoiny okresu i spawacza bez OD (tryb DI) — POMINIĘTE, kwota ich nie
  /// zawiera.
  final List<WeldEntry> skippedNoOd;

  final List<PieceworkDay> days;

  /// Spoiny spawacza bez poprawnej daty — nie należą do żadnego okresu.
  final int undatedWelds;

  /// Spoiny okresu BEZ żadnego stempla (liczone tylko przy wybranym
  /// spawaczu) — nie są przypisane nikomu, więc nie ma ich w jego kwocie;
  /// mogą być jego niezapłaconą pracą.
  final int unstampedWelds;

  /// Spoiny spawacza z datą po końcu okresu i po dziś (w przyszłości) —
  /// poza okresem, wymienione w uwagach.
  final int futureWelds;

  /// Dni z pominiętymi spoinami (bez OD), w których minimum dzienne NIE
  /// zostało naliczone; puste, gdy minimum nie obowiązuje.
  final List<DateTime> minDayBlockedDays;

  /// Minimum dzienne nie liczy się dla brygady.
  bool get minDayApplies => welder != null && rates.minDayGrosze != null;

  const PieceworkResult({
    required this.range,
    required this.welder,
    required this.rates,
    required this.lines,
    required this.skippedNoOd,
    required this.days,
    required this.undatedWelds,
    this.unstampedWelds = 0,
    this.futureWelds = 0,
    this.minDayBlockedDays = const [],
  });

  bool get isCrew => welder == null;
  int get welds => lines.length;
  bool get isEmpty => lines.isEmpty;

  /// DI wybranego spawacza (udziały) — suma brygady liczy każdą spoinę raz.
  double get di => lines.fold(0.0, (s, l) => s + l.diShare);
  double get weldsShare => lines.fold(0.0, (s, l) => s + l.share);
  int get approxWelds => lines.where((l) => l.diApprox).length;
  int get sharedWelds => lines.where((l) => l.splitBetween > 1).length;

  int _sum(int Function(PieceworkLine l) f) =>
      lines.fold(0, (s, l) => s + f(l));

  int get baseGrosze => _sum((l) => l.baseGrosze);

  int materialGroszeOf(PieceworkMaterial m) =>
      _sum((l) => l.material == m ? l.materialGrosze : 0);
  int positionGroszeOf(PayPosition p) =>
      _sum((l) => l.position == p ? l.positionGrosze : 0);
  int get materialGrosze => _sum((l) => l.materialGrosze);
  int get positionGrosze => _sum((l) => l.positionGrosze);
  int get wallGrosze => _sum((l) => l.wallGrosze);
  int get deductionGrosze => _sum((l) => l.deductionGrosze);
  int get repairPayGrosze => _sum((l) => l.repairPayGrosze);
  int get topUpGrosze => days.fold(0, (s, d) => s + d.topUpGrosze);
  int get topUpDays => days.where((d) => d.topUpGrosze > 0).length;

  /// Akord brutto: podstawa + dopłaty − potrącenia + naprawy + minimum.
  int get totalGrosze =>
      baseGrosze +
      materialGrosze +
      positionGrosze +
      wallGrosze -
      deductionGrosze +
      repairPayGrosze +
      topUpGrosze;

  int countMaterial(PieceworkMaterial m) =>
      lines.where((l) => l.material == m).length;
  int countPosition(PayPosition p) =>
      lines.where((l) => l.position == p).length;
  int get thickWalls => lines.where((l) => l.thickWall == true).length;
  int get unknownWalls => lines.where((l) => l.thickWall == null).length;
  int get rejectedWelds => lines.where((l) => l.rejected).length;
  int get repairCount => lines.fold(0, (s, l) => s + l.repairs);

  /// Dni z policzonymi spoinami.
  int get daysWorked => days.length;

  /// Średnio na dzień z wpisami, grosze; null bez dni.
  int? get perDayGrosze =>
      daysWorked == 0 ? null : divRoundHalf(totalGrosze, daysWorked);
}

/// Część [i] (0…n−1) kwoty [total] dzielonej na [n] — metoda największej
/// reszty na liczbach całkowitych: `T·(i+1) ~/ n − T·i ~/ n`. Części sumują
/// się DOKŁADNIE do [total] (10,00 zł / 3 = 3,33 + 3,33 + 3,34).
int splitGrosze(int total, int i, int n) {
  assert(n >= 1 && i >= 0 && i < n);
  return total * (i + 1) ~/ n - total * i ~/ n;
}

/// Kwoty CAŁEJ spoiny (jak w widoku brygady), zanim zostaną rozdzielone
/// między spawaczy.
class _WeldAmounts {
  final int base, material, position, wall, deduction, repairPay;
  const _WeldAmounts(this.base, this.material, this.position, this.wall,
      this.deduction, this.repairPay);
}

/// Akord za okres [range] dla spawacza [welder] (null — cała brygada).
///
/// Składniki liczone są dla całej spoiny (podstawa, każda dopłata,
/// potrącenie, naprawy), a dopiero potem każdy rozdzielany między stemple
/// spoiny przez [splitGrosze] — suma udziałów wszystkich spawaczy = kwota
/// tej spoiny w widoku brygady, co do grosza. Kolejność stempli przy
/// podziale: alfabetycznie (bez wielkości liter), niezależnie od tego, czy
/// stempel stoi w polu spawacza, grani czy lica.
///
/// [today] — dzień „dziś" (lokalny): spoiny wybranego spawacza z datą po
/// końcu okresu i po dziś liczone są jako „w przyszłości" (literówka w dacie
/// albo wpis z wyprzedzeniem) i trafiają do uwag.
PieceworkResult computePiecework({
  required Iterable<WeldEntry> entries,
  required PieceworkRates rates,
  required DayRange range,
  String? welder,
  DateTime? today,
}) {
  final key = welder?.trim().toLowerCase() ?? '';
  final crew = key.isEmpty;
  final todayDay = today == null ? null : dayOnly(today);
  final lines = <(int, PieceworkLine)>[];
  final skipped = <WeldEntry>[];
  var undated = 0;
  var unstamped = 0;
  var future = 0;
  var index = 0;

  for (final e in entries) {
    index++;
    if (e.isDeleted) continue;
    final stamps = e.stamps;
    if (!crew && stamps.isEmpty) {
      final d = parseIsoDay(e.date);
      if (d != null && range.contains(d)) unstamped++;
      continue;
    }
    if (!crew && !stamps.any((s) => s.toLowerCase() == key)) continue;
    final day = parseIsoDay(e.date);
    if (day == null) {
      undated++;
      continue;
    }
    if (!range.contains(day)) {
      if (todayDay != null &&
          day.isAfter(range.to) &&
          day.isAfter(todayDay)) {
        future++;
      }
      continue;
    }
    final d = weldDiameterInches(e);
    if (rates.mode == PieceworkMode.di && d == null) {
      skipped.add(e);
      continue;
    }
    final whole = _wholeWeld(e, rates, d?.inches);
    final material = pieceworkMaterialOf(e.material);
    final thick = pieceworkThickWall(e,
        rule: rates.wallRule, wallMm: rates.wallMm, material: material);
    final n = crew ? 1 : stamps.length;
    final order = [for (final s in stamps) s.toLowerCase()]..sort();
    final i = crew ? 0 : order.indexOf(key);
    int part(int total) => splitGrosze(total, i, n);
    lines.add((
      index,
      PieceworkLine(
        weld: e,
        day: day,
        splitBetween: n,
        weldDi: d?.inches,
        diApprox: d?.approx ?? false,
        material: material,
        position: payPositionOf(e.position),
        thickWall: rates.wallRule == WallRule.none ? false : thick,
        rejected: pieceworkRejected(e),
        repairs: e.repairs.length,
        baseGrosze: part(whole.base),
        materialGrosze: part(whole.material),
        positionGrosze: part(whole.position),
        wallGrosze: part(whole.wall),
        deductionGrosze: part(whole.deduction),
        repairPayGrosze: part(whole.repairPay),
      ),
    ));
  }

  lines.sort((a, b) {
    final byDay = a.$2.day.compareTo(b.$2.day);
    return byDay != 0 ? byDay : a.$1.compareTo(b.$1);
  });
  final sorted = [for (final x in lines) x.$2];

  final byDay = <DateTime, List<PieceworkLine>>{};
  for (final l in sorted) {
    byDay.putIfAbsent(l.day, () => []).add(l);
  }
  final skippedByDay = <DateTime, int>{};
  for (final e in skipped) {
    final d = parseIsoDay(e.date)!;
    skippedByDay[d] = (skippedByDay[d] ?? 0) + 1;
  }
  final min = crew ? null : rates.minDayGrosze;
  final days = <PieceworkDay>[];
  for (final e in byDay.entries) {
    final net = e.value.fold(0, (s, l) => s + l.netGrosze);
    final skippedToday = skippedByDay[e.key] ?? 0;
    days.add(PieceworkDay(
      day: e.key,
      welds: e.value.length,
      di: e.value.fold(0.0, (s, l) => s + l.diShare),
      netGrosze: net,
      // Dzień z pominiętą spoiną (bez OD) nie dostaje dopłaty do minimum:
      // dopłata „za" niepoliczoną spoinę zawyżyłaby kwotę przed
      // uzupełnieniem wymiaru.
      topUpGrosze:
          min != null && skippedToday == 0 && net < min ? min - net : 0,
      skippedWelds: skippedToday,
    ));
  }
  days.sort((a, b) => a.day.compareTo(b.day));

  return PieceworkResult(
    range: range,
    welder: crew ? null : welder!.trim(),
    rates: rates,
    lines: sorted,
    skippedNoOd: skipped,
    days: days,
    undatedWelds: undated,
    unstampedWelds: unstamped,
    futureWelds: future,
    minDayBlockedDays: min == null
        ? const []
        : (skippedByDay.keys.toList()..sort()),
  );
}

/// Składniki całej spoiny: podstawa (DI × stawka albo stawka za spoinę),
/// dopłaty od podstawy, potrącenie i naprawy od wartości.
_WeldAmounts _wholeWeld(WeldEntry e, PieceworkRates rates, double? inches) {
  final base = switch (rates.mode) {
    PieceworkMode.di => roundGrosze(inches! * rates.rateGrosze),
    PieceworkMode.weld => rates.rateGrosze,
  };
  final material = pieceworkMaterialOf(e.material);
  final thick = pieceworkThickWall(e,
      rule: rates.wallRule, wallMm: rates.wallMm, material: material);
  final matG = pctOfGrosze(base, rates.materialBp(material));
  final posG = pctOfGrosze(base, rates.positionBp(payPositionOf(e.position)));
  final wallG = rates.wallRule != WallRule.none && thick == true
      ? pctOfGrosze(base, rates.wallBp)
      : 0;
  final value = base + matG + posG + wallG;
  final rejected = pieceworkRejected(e);
  return _WeldAmounts(
    base,
    matG,
    posG,
    wallG,
    rejected ? pctOfGrosze(value, rates.rejectBp) : 0,
    rates.repairPaid ? e.repairs.length * pctOfGrosze(value, rates.repairBp) : 0,
  );
}

// ─── Godziny i porównanie ze stawką godzinową ─────────────────────────────

enum PieceworkHoursSource {
  none,

  /// Wpisane na ekranie dla okresu.
  typed,

  /// Godzin dziennie ze stawek × dni z wpisami.
  perDay,
}

class PieceworkHours {
  final double? hours;
  final PieceworkHoursSource source;
  const PieceworkHours(this.hours, this.source);

  static const PieceworkHours none =
      PieceworkHours(null, PieceworkHoursSource.none);
}

/// Godziny okresu: wpisane mają pierwszeństwo, inaczej godzin dziennie ×
/// dni z wpisami, inaczej brak.
PieceworkHours pieceworkHours({
  double? typed,
  double? perDay,
  required int days,
}) {
  if (typed != null && typed.isFinite && typed > 0) {
    return PieceworkHours(typed, PieceworkHoursSource.typed);
  }
  if (perDay != null && perDay.isFinite && perDay > 0 && days > 0) {
    return PieceworkHours(perDay * days, PieceworkHoursSource.perDay);
  }
  return PieceworkHours.none;
}

/// Zarobek na godzinę w groszach (połówka od zera) albo null bez godzin.
int? pieceworkPerHour(int totalGrosze, double? hours) {
  if (hours == null || !hours.isFinite || hours <= 0) return null;
  return roundGrosze(totalGrosze / hours);
}

// ─── Raport ───────────────────────────────────────────────────────────────

/// Wszystko, co trafia na ekran, do tekstu i do PDF.
class PieceworkReport {
  final PieceworkResult result;
  final PieceworkHours hours;

  /// Minimalna stawka z „Ile brać za godzinę" (zł/h netto) w groszach albo
  /// null — kalkulator nie był zapisany.
  final int? hourlyMinGrosze;
  final DateTime generatedAt;

  const PieceworkReport({
    required this.result,
    this.hours = PieceworkHours.none,
    this.hourlyMinGrosze,
    required this.generatedAt,
  });

  int? get perHourGrosze => pieceworkPerHour(result.totalGrosze, hours.hours);

  String title({required bool en}) =>
      en ? 'Piecework earnings' : 'Akord — zarobek';

  /// „2026-10-14 (śr)" albo „2026-10-01 – 2026-10-17".
  String periodText({required bool en}) {
    final r = result.range;
    if (r.from == r.to) return dayLabel(r.from, en: en);
    return '${isoDate(r.from)} – ${isoDate(r.to)}';
  }

  String welderText({required bool en}) =>
      result.welder ??
      (en ? 'Whole crew (each weld once)' : 'Cała brygada (każda spoina raz)');

  /// Nazwa pliku PDF, np. `Akord_JK-12_2026-10-01_2026-10-17.pdf`.
  String fileName({required bool en}) {
    String safe(String s) => s
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final r = result.range;
    final parts = <String>[
      en ? 'Piecework' : 'Akord',
      safe(result.welder ?? (en ? 'crew' : 'brygada')),
      isoDate(r.from),
      if (r.to != r.from) isoDate(r.to),
    ];
    return '${parts.where((p) => p.isNotEmpty).join('_')}.pdf';
  }
}

/// Jednostka stawki: „zł/DI" / „zł/szt." („zł/weld").
String pieceworkRateUnit(PieceworkMode m, {required bool en}) => switch (m) {
      PieceworkMode.di => 'zł/DI',
      PieceworkMode.weld => en ? 'zł/weld' : 'zł/szt.',
    };

/// „45,00 zł/DI" / „150,00 zł/szt.".
String pieceworkRateText(PieceworkRates r, {required bool en}) =>
    '${formatPln(r.rateGrosze, withUnit: false)} '
    '${pieceworkRateUnit(r.mode, en: en)}';

/// „1 dzień", „2 dni" / „1 day", „2 days".
String daysCount(int n, {required bool en}) {
  if (en) return '$n ${n == 1 ? 'day' : 'days'}';
  return '$n ${n == 1 ? 'dzień' : 'dni'}';
}

/// „1 naprawa", „3 naprawy", „5 napraw" / „1 repair", „3 repairs".
String repairsCount(int n, {required bool en}) {
  if (en) return '$n ${n == 1 ? 'repair' : 'repairs'}';
  if (n == 1) return '1 naprawa';
  final m10 = n % 10, m100 = n % 100;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n naprawy';
  return '$n napraw';
}

/// Liczba DI z „≈", gdy choć jedna spoina miała OD spoza tabeli NPS:
/// „≈ 2,24". Jedno źródło dla ekranu, tekstu i PDF.
String diNumberText(double di, {required bool en, bool approx = false}) =>
    '${approx ? '≈ ' : ''}${progressNum(di, en: en, decimals: 2)}';

String _diText(double di, {required bool en, bool approx = false}) =>
    '${diNumberText(di, en: en, approx: approx)} DI';

/// DI wyniku z jednostką: „≈ 8,24 DI" / „6 DI".
String pieceworkDiText(PieceworkResult r, {required bool en}) =>
    _diText(r.di, en: en, approx: r.approxWelds > 0);

/// Wiersz rozbicia kwoty.
class PieceworkRow {
  /// base, stainless, other, p2g, p5g, p6g, wall, reject, repair, minDay.
  final String id;
  final String label;

  /// Ze znakiem: potrącenie jest ujemne.
  final int grosze;

  const PieceworkRow(this.id, this.label, this.grosze);
}

/// Rozbicie kwoty — podstawa zawsze, reszta tylko niezerowa. Suma wierszy =
/// [PieceworkResult.totalGrosze].
List<PieceworkRow> pieceworkRows(PieceworkResult r, {required bool en}) {
  final rates = r.rates;
  final rate = pieceworkRateText(rates, en: en);
  String welds(int n) => weldsCount(n, en: en);
  final baseLabel = switch (rates.mode) {
    PieceworkMode.di => en
        ? 'Base: ${pieceworkDiText(r, en: en)} × $rate'
        : 'Podstawa: ${pieceworkDiText(r, en: en)} × $rate',
    PieceworkMode.weld => r.sharedWelds == 0
        ? (en ? 'Base: ${welds(r.welds)} × $rate' : 'Podstawa: ${welds(r.welds)} × $rate')
        : (en
            ? 'Base: share ${progressNum(r.weldsShare, en: en, decimals: 2)} of ${welds(r.welds)} × $rate'
            : 'Podstawa: udział ${progressNum(r.weldsShare, en: en, decimals: 2)} z ${welds(r.welds)} × $rate'),
  };
  final rows = <PieceworkRow>[PieceworkRow('base', baseLabel, r.baseGrosze)];

  void add(String id, String label, int grosze) {
    if (grosze != 0) rows.add(PieceworkRow(id, label, grosze));
  }

  final ss = PieceworkMaterial.stainless, other = PieceworkMaterial.other;
  add(
      'stainless',
      en
          ? 'Surcharge: stainless +${bpText(rates.stainlessBp, en: en)} (${welds(r.countMaterial(ss))})'
          : 'Dopłata: stal nierdzewna +${bpText(rates.stainlessBp, en: en)} (${welds(r.countMaterial(ss))})',
      r.materialGroszeOf(ss));
  add(
      'other',
      en
          ? 'Surcharge: other materials +${bpText(rates.otherMaterialBp, en: en)} (${welds(r.countMaterial(other))})'
          : 'Dopłata: inne materiały +${bpText(rates.otherMaterialBp, en: en)} (${welds(r.countMaterial(other))})',
      r.materialGroszeOf(other));
  for (final p in const [PayPosition.p2g, PayPosition.p5g, PayPosition.p6g]) {
    final bp = bpText(rates.positionBp(p), en: en);
    add(
        p.name,
        en
            ? 'Surcharge: position ${payPositionLabel(p)} +$bp (${welds(r.countPosition(p))})'
            : 'Dopłata: pozycja ${payPositionLabel(p)} +$bp (${welds(r.countPosition(p))})',
        r.positionGroszeOf(p));
  }
  final wallWhat = rates.wallRule == WallRule.sch80
      ? '≥ Sch 80'
      : '≥ ${progressNum(rates.wallMm, en: en, decimals: 2)} mm';
  add(
      'wall',
      en
          ? 'Surcharge: heavy wall ($wallWhat) +${bpText(rates.wallBp, en: en)} (${welds(r.thickWalls)})'
          : 'Dopłata: gruba ścianka ($wallWhat) +${bpText(rates.wallBp, en: en)} (${welds(r.thickWalls)})',
      r.wallGrosze);
  add(
      'reject',
      en
          ? 'Deduction: rejected welds −${bpText(rates.rejectBp, en: en)} (${welds(r.rejectedWelds)})'
          : 'Potrącenie: odrzucone spoiny −${bpText(rates.rejectBp, en: en)} (${welds(r.rejectedWelds)})',
      -r.deductionGrosze);
  add(
      'repair',
      en
          ? 'Repairs paid separately: ${repairsCount(r.repairCount, en: en)} × ${bpText(rates.repairBp, en: en)}'
          : 'Naprawy płatne osobno: ${repairsCount(r.repairCount, en: en)} × ${bpText(rates.repairBp, en: en)}',
      r.repairPayGrosze);
  if (r.minDayApplies) {
    final min = formatPln(rates.minDayGrosze!);
    add(
        'minDay',
        en
            ? 'Top-up to the daily minimum $min (${daysCount(r.topUpDays, en: en)})'
            : 'Dopłata do minimum dziennego $min (${daysCount(r.topUpDays, en: en)})',
        r.topUpGrosze);
  }
  return rows;
}

/// Uwagi do wyniku — co liczono inaczej niż „wprost" i czego nie wliczono.
List<String> pieceworkNotes(PieceworkResult r, {required bool en}) {
  final rates = r.rates;
  final out = <String>[];
  String welds(int n) => weldsCount(n, en: en);
  if (rates.rateGrosze == 0) {
    out.add(en
        ? 'The rate is 0 — enter your rate under "Rates".'
        : 'Stawka wynosi 0 — wpisz swoją stawkę w sekcji „Stawki".');
  }
  if (r.approxWelds > 0) {
    out.add(en
        ? '≈ ${welds(r.approxWelds)}: OD outside the NPS table — DI = OD / 25.4. Check how the company counts them.'
        : '≈ ${welds(r.approxWelds)}: OD spoza tabeli NPS — DI = OD / 25,4. Sprawdź, jak liczy je firma.');
  }
  final unknownMat = r.countMaterial(PieceworkMaterial.unknown);
  if (rates.hasMaterialSurcharge && unknownMat > 0) {
    out.add(en
        ? '${welds(unknownMat)}: material empty or not recognised — no material surcharge.'
        : '${welds(unknownMat)}: materiał pusty albo nierozpoznany — bez dopłaty materiałowej.');
  }
  final noPos =
      r.countPosition(PayPosition.none) + r.countPosition(PayPosition.other);
  if (rates.hasPositionSurcharge && noPos > 0) {
    out.add(en
        ? '${welds(noPos)}: no position, or a position without a surcharge (e.g. PB, 2F) — no position surcharge.'
        : '${welds(noPos)}: bez pozycji albo pozycja bez dopłaty (np. PB, 2F) — bez dopłaty za pozycję.');
  }
  if (rates.hasWallSurcharge && r.unknownWalls > 0) {
    out.add(rates.wallRule == WallRule.sch80
        ? (en
            ? '${welds(r.unknownWalls)}: no wall thickness or OD outside the table — no heavy-wall surcharge.'
            : '${welds(r.unknownWalls)}: brak grubości ścianki albo OD spoza tabeli — bez dopłaty za grubość.')
        : (en
            ? '${welds(r.unknownWalls)}: no wall thickness — no heavy-wall surcharge.'
            : '${welds(r.unknownWalls)}: brak grubości ścianki — bez dopłaty za grubość.'));
  }
  if (!r.isCrew && r.sharedWelds > 0) {
    out.add(en
        ? '${welds(r.sharedWelds)} shared with another welder (root / cap) — the amount is split equally.'
        : '${welds(r.sharedWelds)} wspólnych z innym spawaczem (grań / lico) — kwota dzielona po równo.');
  }
  if (r.isCrew && rates.minDayGrosze != null) {
    out.add(en
        ? 'The daily minimum applies to one welder only — pick a welder.'
        : 'Minimum dzienne liczy się tylko dla jednego spawacza — wybierz spawacza.');
  }
  if (r.futureWelds > 0) {
    out.add(en
        ? '${welds(r.futureWelds)} dated after the end of the period (in the future) — not in this amount. Check the date in the journal.'
        : '${welds(r.futureWelds)} z datą po końcu okresu (w przyszłości) — poza tą kwotą. Sprawdź datę w dzienniku.');
  }
  for (final d in r.minDayBlockedDays) {
    out.add(en
        ? 'Day ${isoDate(d)} has skipped welds — daily minimum not added, fill in the OD.'
        : 'Dzień ${isoDate(d)} ma pominięte spoiny — minimum dzienne nie naliczone, uzupełnij OD.');
  }
  if (r.unstampedWelds > 0) {
    out.add(en
        ? '${welds(r.unstampedWelds)} in this period without any welder stamp — assigned to nobody, not in this amount. Check the journal.'
        : '${welds(r.unstampedWelds)} w tym okresie bez stempla spawacza — poza tą kwotą. Sprawdź dziennik.');
  }
  if (r.undatedWelds > 0) {
    out.add(en
        ? '${welds(r.undatedWelds)} without a valid date — outside every period.'
        : '${welds(r.undatedWelds)} bez poprawnej daty — poza każdym okresem.');
  }
  return out;
}

/// Reguły liczenia (stopka ekranu, tekstu i PDF).
List<String> pieceworkDefinitions({required bool en}) => en
    ? const [
        'Weld = a journal entry dated in the period (any status). DI = NPS in inches from the OD (B36.10M/B36.19M), as in "Work progress".',
        'In DI mode a weld without an OD is skipped — the amount does not include it.',
        'Surcharges are % of the weld\'s base and add up (they do not multiply).',
        'Rejected weld = has a repair (R1+) or now NOK. Deduction = % of the weld value (base + surcharges). Repairs and deductions count in the period of the weld.',
        'A weld with two welders: each gets half. Whole crew: each weld once, in full.',
        'Every weld rounded to 1 gr (half away from zero); the total is the sum of the welds. Amounts before tax.',
      ]
    : const [
        'Spoina = wpis dziennika z datą w okresie (każdy status). DI = NPS w calach z OD (B36.10M/B36.19M), jak w „Postępie robót".',
        'W trybie DI spoina bez OD jest pominięta — kwota jej nie zawiera.',
        'Dopłaty to % podstawy spoiny i sumują się (nie mnożą).',
        'Odrzucona spoina = ma naprawę (R1+) albo teraz NOK. Potrącenie = % wartości spoiny (podstawa + dopłaty). Naprawy i potrącenia liczą się w okresie spoiny.',
        'Spoina z dwoma spawaczami: każdy dostaje połowę. Cała brygada: każda spoina raz, w całości.',
        'Każda spoina zaokrąglona do grosza (połówka w górę); suma = suma spoin. Kwoty przed podatkiem.',
      ];

/// „Akord daje 85,00 zł/h, a minimum z „Ile brać za godzinę" to 95,00 zł/h —
/// 10,00 zł/h mniej." albo null, gdy brak godzin albo kalkulatora.
String? hourlyCompareText(PieceworkReport r, {required bool en}) {
  final ph = r.perHourGrosze, min = r.hourlyMinGrosze;
  if (ph == null || min == null) return null;
  final diff = ph - min;
  final have = formatPln(ph), need = formatPln(min);
  final delta = formatPln(diff.abs());
  if (en) {
    final tail = diff == 0
        ? 'exactly the same.'
        : (diff > 0 ? '$delta/h more.' : '$delta/h less.');
    return 'Piecework gives $have/h; the minimum from "What to charge per hour" is $need/h — $tail';
  }
  final tail = diff == 0
      ? 'dokładnie tyle samo.'
      : (diff > 0 ? '$delta/h więcej.' : '$delta/h mniej.');
  return 'Akord daje $have/h, a minimum z „Ile brać za godzinę" to $need/h — $tail';
}

/// Godziny: „80 h (wpisane)" / „80 h (10 h × 8 dni)".
String? hoursText(PieceworkReport r, {required bool en}) {
  final h = r.hours;
  if (h.hours == null) return null;
  final n = progressNum(h.hours!, en: en);
  return switch (h.source) {
    PieceworkHoursSource.typed => en ? '$n h (entered)' : '$n h (wpisane)',
    PieceworkHoursSource.perDay =>
      '$n h (${progressNum(r.result.rates.hoursPerDay ?? 0, en: en)} h × '
          '${daysCount(r.result.daysWorked, en: en)})',
    PieceworkHoursSource.none => null,
  };
}

/// „W-12 · 2026-10-03 · L-12 · Blok 4" — spoina na liście pominiętych.
String skippedWeldLine(WeldEntry e) => [
      e.weldNo.trim().isEmpty ? '?' : e.weldNo.trim(),
      e.date.trim(),
      e.pipeName.trim(),
      e.projectName.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');

/// Zestawienie do wysłania (SMS, WhatsApp, e-mail).
String buildPieceworkText(PieceworkReport report, {required bool en}) {
  final r = report.result;
  final b = StringBuffer()
    ..writeln(
        '${report.title(en: en).toUpperCase()} — ${report.periodText(en: en)}')
    ..writeln('${en ? 'Welder' : 'Spawacz'}: ${report.welderText(en: en)}')
    ..writeln('${en ? 'Rate' : 'Stawka'}: ${pieceworkRateText(r.rates, en: en)}')
    ..writeln('${en ? 'Welds' : 'Spoiny'}: ${weldsCount(r.welds, en: en)} · '
        '${pieceworkDiText(r, en: en)} · '
        '${en ? 'days with entries' : 'dni z wpisami'}: ${r.daysWorked}')
    ..writeln();
  for (final row in pieceworkRows(r, en: en)) {
    b.writeln('${row.label}: ${formatPln(row.grosze)}');
  }
  b.writeln('${en ? 'TOTAL' : 'RAZEM'}: ${formatPln(r.totalGrosze)}');
  final perDay = r.perDayGrosze;
  final perHour = report.perHourGrosze;
  final hours = hoursText(report, en: en);
  if (perDay != null || perHour != null) {
    b.writeln([
      if (perDay != null)
        '${en ? 'Average' : 'Średnio'}: ${formatPln(perDay)}/${en ? 'day' : 'dzień'}',
      if (perHour != null) '${formatPln(perHour)}/h ($hours)',
    ].join(' · '));
  }
  final cmp = hourlyCompareText(report, en: en);
  if (cmp != null) b.writeln(cmp);
  if (r.skippedNoOd.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en
          ? 'SKIPPED — no size (OD), NOT in the amount: ${weldsCount(r.skippedNoOd.length, en: en)}'
          : 'POMINIĘTE — brak wymiaru (OD), kwota ich NIE zawiera: ${weldsCount(r.skippedNoOd.length, en: en)}');
    for (final e in r.skippedNoOd.take(50)) {
      b.writeln('• ${skippedWeldLine(e)}');
    }
    if (r.skippedNoOd.length > 50) {
      b.writeln('• … +${r.skippedNoOd.length - 50}');
    }
  }
  final notes = pieceworkNotes(r, en: en);
  if (notes.isNotEmpty) {
    b
      ..writeln()
      ..writeln(en ? 'Notes:' : 'Uwagi:');
    for (final n in notes) {
      b.writeln('• $n');
    }
  }
  final g = report.generatedAt;
  String two(int v) => v.toString().padLeft(2, '0');
  b
    ..writeln()
    ..write('Fitter Welder Pro · ${isoDate(g)} ${two(g.hour)}:${two(g.minute)} · '
        '${en ? 'from the weld journal' : 'z dziennika spoin'}');
  return b.toString();
}

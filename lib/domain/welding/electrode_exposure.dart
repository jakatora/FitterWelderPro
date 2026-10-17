// Elektrody zasadowe (niskowodorowe): czas na powietrzu po wyjęciu
// z piecyka, powrót do piecyka-przechowalnika, ponowne suszenie i limit
// liczby suszeń. Czyste funkcje, bez Fluttera — zegar zawsze z zewnątrz.
//
// __ŹRÓDŁA__ (normy AWS są płatne — tekst tabeli potwierdzony w przedrukach
// i cytatach; skrót w [kElectrodeSources] idzie do PDF):
//  [S1] AWS/ESAB „Everyday Pocket Handbook for SMAW”, s. 22 — przedruk
//       tabeli „Permissible atmospheric exposure of low-hydrogen
//       electrodes” z AWS D1.1-96 (kolumny A i B, przypis o kołczanach)
//       https://rexresearch1.com/WeldingLibrary/EverydayPocketHandbkShieldedMetalArcWelding.pdf
//  [S2] AWS D1.1/D1.1M:2020, 7.3.2.1–7.3.2.5 i Tabela 7.1 (w 2015: 5.3.2,
//       Tabela 5.1) — brzmienie wg E. Khayer, „How many times baking of
//       low hydrogen electrode allowed?” (2020-05-31)
//       https://www.linkedin.com/pulse/how-many-times-baking-low-hydrogen-electrode-allowed-ebrahim-khayer
//       Aktualne wydanie: D1.1/D1.1M:2025 (https://www.aws.org/about/news/d11-release/);
//       przeglądy zmian 2025 (Fabtech / Welding Journal) nie wymieniają
//       7.3.2 ani Tabeli 7.1 — tekstu 2025 nie widziano (NIEPEWNE).
//  [S3] Lincoln Electric (USA), „Storing and Redrying Electrodes”,
//       MC22-140 12/22 — szafa 120–150 °C, EXX18 R do 9 h, E8018+ max 3
//       suszenia po 1 h.
//  [S4] Lincoln Electric Europe, SAHARA ReadyPack, PC-OP-0005 v1 — 8 h po
//       otwarciu (≤ 35 °C, ≤ 90 % RH), 12 h przy ≤ 27 °C / ≤ 70 % RH;
//       suszenie zasadowych 250–375 °C / 2–6 h, „can be repeated twice”;
//       piecyk 120–180 °C; kołczan do 125 °C, max 10 h.
//       (SAHARA ReadyPack to Lincoln, nie ESAB; ESAB ma VacPac.)
//  [S5] ESAB OK 48.00 (E7018 H4R / E 42 4 B 42 H5), karta 2004-06-07 —
//       suszenie 350 °C, 2 h; liczby suszeń ESAB nie podaje.
//  [S6] voestalpine Böhler, DRY SYSTEM (2021-03-09) — do 9 h po otwarciu.
//  [S7] Kobelco Welding Europe, „Storage & Handling” — próżniowe ok. 8 h
//       (jedna zmiana), niektóre produkty 4 h.
//  [S8] AWS D1.5M/D1.5:2015-AMD1 (bezpłatna nota zmian AWS) — Tabela 4.6
//       (te same limity co D1.1 dla E70XX…E110XX-X), 4.5.2.1 suszenie
//       230–290 °C min. 2 h, 4.5.2.2 reset po ≥ 4 h w piecyku ≥ 120 °C,
//       4.5.2.3 A5.5 z „R” do 9 h. D1.5 bywa więc inny niż D1.1 — dlatego
//       limit partii jest edytowalny.
// EN 1011-1/-2 nie podają czasu na powietrzu — odsyłają do producenta;
// limity klas EN przyjęto ostrożnie przez analogię do AWS tej samej
// wytrzymałości (NIEPEWNE — do nadpisania z karty producenta / WPS).
// Kołczan / termos: wg przypisu do tabeli D1.1 elektrody wydaje się
// w kołczanach lub małych otwartych pojemnikach, „heated containers are
// not mandatory” — czas w kołczanie LICZY SIĘ jako czas na powietrzu.
//
// Model partii:
//  • czas na powietrzu sumuje się z kolejnych wyjść z piecyka;
//  • powrót do piecyka-przechowalnika ZATRZYMUJE licznik. Limit zeruje się
//    dopiero, gdy elektrody przeleżą w piecyku ≥ 120 °C co najmniej 4 h
//    (AWS D1.1 — „after a minimum hold period of four hours … the
//    permissible atmospheric exposure period may be reset”) i wróciły tam
//    PRZED przekroczeniem limitu. Krótszy pobyt w piecyku tylko wstrzymuje
//    licznik — po wyjęciu liczy dalej od tego, co już było;
//  • po przekroczeniu limitu piecyk-przechowalnik nie pomaga — elektrody
//    trzeba ponownie wysuszyć (piec suszarniczy, wyższa temperatura) albo
//    oddać na złom;
//  • ponowne suszenie zeruje licznik i zwiększa licznik suszeń; AWS D1.1
//    pozwala na jedno ponowne suszenie, producenci EN zwykle na kilka —
//    limit suszeń jest edytowalny na partii.

import 'dart:convert';

import '../qualification/reminder_plan.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TABELA LIMITÓW
// ═══════════════════════════════════════════════════════════════════════════

/// Grupa przepisów — decyduje o suszeniu, przechowywaniu i limicie suszeń.
enum ElectrodeFamily {
  /// AWS A5.1 (stal węglowa, E70XX). D1.1:2020 7.3.2.4: min. 2 h w 260–430 °C
  /// [500–800 °F] [S1][S2].
  awsA51(
    redryPl: '260–430 °C, min. 2 h (AWS D1.1, A5.1)',
    redryEn: '260–430 °C (500–800 °F), 2 h min. (AWS D1.1, A5.1)',
    defaultMaxRedries: 1,
    perManufacturer: false,
  ),

  /// AWS A5.5 (niskostopowe, E70XX-X … E110XX-X). D1.1:2020 7.3.2.4: min.
  /// 1 h w 370–430 °C [700–800 °F] [S2].
  awsA55(
    redryPl: '370–430 °C, min. 1 h (AWS D1.1, A5.5)',
    redryEn: '370–430 °C (700–800 °F), 1 h min. (AWS D1.1, A5.5)',
    defaultMaxRedries: 1,
    perManufacturer: false,
  ),

  /// EN ISO 2560-A, otulina zasadowa (B) — przepisy producenta: ESAB
  /// OK 48.00 350 °C / 2 h [S5], Lincoln Europe 250–375 °C / 2–6 h,
  /// suszenie „można powtórzyć dwa razy” [S4]. Opakowanie próżniowe:
  /// SAHARA ReadyPack 8 h po otwarciu (≤ 35 °C, ≤ 90 % RH; 12 h przy
  /// ≤ 27 °C, ≤ 70 % RH) [S4], Böhler DRY SYSTEM 9 h [S6], Kobelco ok. 8 h
  /// (niektóre produkty 4 h) [S7] → domyślnie 8 h.
  enIso2560(
    redryPl: 'zwykle 300–350 °C, 2 h (np. OK 48.00: 350 °C / 2 h) — wg '
        'karty producenta',
    redryEn: 'typically 300–350 °C, 2 h (e.g. OK 48.00: 350 °C / 2 h) — per '
        'manufacturer data sheet',
    defaultMaxRedries: 2,
    perManufacturer: true,
    hermeticPackMinutes: 480,
  ),

  /// EN ISO 18275-A (wysokowytrzymałe, E 55 … E 89, B) — przepisy
  /// producenta jak wyżej; Lincoln US: E8018 i wyżej max 3 suszenia [S3],
  /// Lincoln Europe — 2 [S4] → domyślnie 2. Opakowanie próżniowe ostrożnie
  /// 4 h (Kobelco: niektóre produkty 4 h [S7]).
  enIso18275(
    redryPl: 'zwykle 300–350 °C, 2 h — wg karty producenta',
    redryEn: 'typically 300–350 °C, 2 h — per manufacturer data sheet',
    defaultMaxRedries: 2,
    perManufacturer: true,
    hermeticPackMinutes: 240,
  );

  const ElectrodeFamily({
    required this.redryPl,
    required this.redryEn,
    required this.defaultMaxRedries,
    required this.perManufacturer,
    this.hermeticPackMinutes,
  });

  final String redryPl;
  final String redryEn;

  /// Domyślny limit ponownych suszeń partii (edytowalny). AWS D1.1:
  /// „Electrodes shall be rebaked no more than once” [S2].
  final int defaultMaxRedries;

  /// `true` — limit czasu i suszenia z karty producenta, nie z normy.
  final bool perManufacturer;

  /// Limit po otwarciu opakowania próżniowego [min] wg producentów;
  /// `null` — obowiązuje tabela klasy (AWS D1.1 7.3.2.2 dotyczy też
  /// elektrod z opakowań hermetycznych; próżniowe E7018 to zwykle H4R →
  /// klasa „R”, 9 h).
  final int? hermeticPackMinutes;

  String redry({required bool en}) => en ? redryEn : redryPl;
}

/// Klasyfikacja elektrody + domyślny limit czasu na powietrzu.
///
/// AWS: D1.1 Tabela 7.1 (wyd. 2020; w 2015 — Tabela 5.1), kolumna A
/// [S1][S2]: A5.1 E70XX 4 h, E70XXR / E70XXHZR / E7018M 9 h; A5.5 E70XX-X
/// 4 h, E80XX-X 2 h, E90XX-X 1 h, E100XX-X i E110XX-X ½ h. Kolumna B
/// (dłużej, do 10 / 5 / 4 h) tylko po badaniu wg 7.3.2.3 — nie domyślnie.
/// D1.1 nie ma wierszy A5.5 z „R” (9 h dla nich daje dopiero D1.5).
/// EN: norma nie podaje czasu — limit z kart producentów, domyślnie
/// przez analogię do AWS o tej samej wytrzymałości.
enum ElectrodeClass {
  e7018(
    code: 'E7018',
    descPl: 'AWS A5.1 E70XX (E7016, E7018, E7048)',
    descEn: 'AWS A5.1 E70XX (E7016, E7018, E7048)',
    family: ElectrodeFamily.awsA51,
    limitMinutes: 240,
  ),
  e7018dash1(
    code: 'E7018-1',
    descPl: 'AWS A5.1 E70XX z udarnością -1, bez sufiksu R',
    descEn: 'AWS A5.1 E70XX with -1 toughness, no R suffix',
    family: ElectrodeFamily.awsA51,
    limitMinutes: 240,
  ),
  e7018R(
    code: 'E7018 H4R / H8R',
    descPl: 'AWS A5.1 E70XXR / E70XXHZR (odporne na wilgoć, np. E7018-1 H4R)',
    descEn: 'AWS A5.1 E70XXR / E70XXHZR (moisture resistant, e.g. E7018-1 H4R)',
    family: ElectrodeFamily.awsA51,
    limitMinutes: 540,
  ),
  e7018M(
    code: 'E7018M',
    descPl: 'AWS A5.1 E7018M (wojskowe / sejsmiczne)',
    descEn: 'AWS A5.1 E7018M (military / seismic)',
    family: ElectrodeFamily.awsA51,
    limitMinutes: 540,
  ),
  e7018X(
    code: 'E7018-X',
    descPl: 'AWS A5.5 E70XX-X (np. E7018-A1)',
    descEn: 'AWS A5.5 E70XX-X (e.g. E7018-A1)',
    family: ElectrodeFamily.awsA55,
    limitMinutes: 240,
  ),
  e8018X(
    code: 'E8018-X',
    descPl: 'AWS A5.5 E80XX-X (B2, C1, C3, Ni1, W1…)',
    descEn: 'AWS A5.5 E80XX-X (B2, C1, C3, Ni1, W1…)',
    family: ElectrodeFamily.awsA55,
    limitMinutes: 120,
  ),
  e9018X(
    code: 'E9018-X',
    descPl: 'AWS A5.5 E90XX-X (B3, B9, M, D1…)',
    descEn: 'AWS A5.5 E90XX-X (B3, B9, M, D1…)',
    family: ElectrodeFamily.awsA55,
    limitMinutes: 60,
  ),
  e10018X(
    code: 'E10018-X',
    descPl: 'AWS A5.5 E100XX-X (M, D2…)',
    descEn: 'AWS A5.5 E100XX-X (M, D2…)',
    family: ElectrodeFamily.awsA55,
    limitMinutes: 30,
  ),
  e11018X(
    code: 'E11018-X',
    descPl: 'AWS A5.5 E110XX-X (M)',
    descEn: 'AWS A5.5 E110XX-X (M)',
    family: ElectrodeFamily.awsA55,
    limitMinutes: 30,
  ),
  enIso2560B(
    code: 'EN ISO 2560-A … B H5/H10',
    descPl: 'E 38/42/46/50 x B (np. OK 48.00, FOX EV 50) — wg producenta',
    descEn: 'E 38/42/46/50 x B (e.g. OK 48.00, FOX EV 50) — per manufacturer',
    family: ElectrodeFamily.enIso2560,
    limitMinutes: 240,
  ),
  enIso18275E55(
    code: 'EN ISO 18275-A E 55 … B',
    descPl: 'Wysokowytrzymałe E 55 x B — wg producenta (jak AWS E90XX)',
    descEn: 'High-strength E 55 x B — per manufacturer (as AWS E90XX)',
    family: ElectrodeFamily.enIso18275,
    limitMinutes: 60,
  ),
  enIso18275E62(
    code: 'EN ISO 18275-A E 62/69 … B',
    descPl:
        'Wysokowytrzymałe E 62 / E 69 x B — wg producenta (jak AWS E100/E110)',
    descEn:
        'High-strength E 62 / E 69 x B — per manufacturer (as AWS E100/E110)',
    family: ElectrodeFamily.enIso18275,
    limitMinutes: 30,
  );

  const ElectrodeClass({
    required this.code,
    required this.descPl,
    required this.descEn,
    required this.family,
    required this.limitMinutes,
  });

  /// Krótka nazwa na kartę i do dziennika.
  final String code;
  final String descPl;
  final String descEn;
  final ElectrodeFamily family;

  /// Limit czasu na powietrzu po wyjęciu z piecyka [min].
  final int limitMinutes;

  String desc({required bool en}) => en ? descEn : descPl;
}

/// Skąd elektrody trafiły na stanowisko.
enum ElectrodeSource {
  /// Z piecyka-przechowalnika / termosu — limit z tabeli klasy.
  oven,

  /// Świeżo otwarte opakowanie hermetyczne / próżniowe (Lincoln SAHARA
  /// ReadyPack, ESAB VacPac, Böhler DRY SYSTEM…) — dla klas EN limit
  /// producenta ([ElectrodeFamily.hermeticPackMinutes]), dla AWS tabela.
  hermeticPack,
}

/// Minimalny pobyt w piecyku-przechowalniku ≥ 120 °C, po którym limit
/// czasu na powietrzu zeruje się — D1.1:2020 7.3.2.2: „after a minimum
/// hold period of four hours at 250 °F [120 °C] min. the electrodes may be
/// reissued” [S2]; tak samo D1.5 4.5.2.2 [S8].
const Duration kOvenResetHold = Duration(hours: 4);

/// Minimalna temperatura piecyka-przechowalnika (AWS D1.1: 250 °F).
const int kHoldingOvenMinC = 120;

/// Domyślny limit dla klasy i źródła [min]. Opakowanie próżniowe zmienia
/// limit tylko dla klas „wg producenta” (EN) i nigdy go nie skraca.
int defaultLimitMinutes(ElectrodeClass c, ElectrodeSource s) {
  final pack = c.family.hermeticPackMinutes;
  if (s == ElectrodeSource.oven || pack == null) return c.limitMinutes;
  return pack > c.limitMinutes ? pack : c.limitMinutes;
}

/// Domyślna maksymalna liczba ponownych suszeń.
int defaultMaxRedries(ElectrodeClass c) => c.family.defaultMaxRedries;

/// Ile minut przed końcem limitu ostrzegamy (stan „kończy się” i pierwsze
/// przypomnienie): 30 min dla limitów ≥ 2 h, 15 min dla 1 h, 10 min dla
/// krótszych.
int warnLeadMinutes(int limitMinutes) {
  if (limitMinutes >= 120) return 30;
  if (limitMinutes >= 60) return 15;
  return 10;
}

/// Opisy źródeł (komentarz + stopka PDF).
const List<String> kElectrodeSources = [
  'AWS D1.1/D1.1M:2020 Structural Welding Code — Steel, 7.3.2 i Tabela 7.1 '
      '(Permissible Atmospheric Exposure of Low-Hydrogen Electrodes)',
  'AWS D1.5M/D1.5:2015-AMD1, 4.5.2 i Tabela 4.6',
  'Karty producentów: Lincoln Electric (MC22-140, SAHARA ReadyPack '
      'PC-OP-0005), ESAB OK 48.00, voestalpine Böhler DRY SYSTEM, Kobelco',
];

// ═══════════════════════════════════════════════════════════════════════════
// PARTIA
// ═══════════════════════════════════════════════════════════════════════════

enum BatchEventKind {
  takenOut,
  returnedToOven,
  takenOutAgain,
  redried,
  consumed,
  scrapped,
  limitChanged,
}

/// Wpis dziennika partii.
class BatchEvent {
  final BatchEventKind kind;
  final DateTime at;

  /// Czas na powietrzu w chwili wpisu.
  final Duration exposure;

  /// `takenOutAgain`: czy limit się wyzerował (≥ 4 h w piecyku).
  final bool reset;

  /// `redried`: numer suszenia; `limitChanged`: nowy limit [min].
  final int? value;

  const BatchEvent({
    required this.kind,
    required this.at,
    this.exposure = Duration.zero,
    this.reset = false,
    this.value,
  });

  Map<String, Object?> toJson() => {
        'k': kind.name,
        'at': at.millisecondsSinceEpoch,
        'exp': exposure.inSeconds,
        if (reset) 'reset': true,
        if (value != null) 'v': value,
      };

  static BatchEvent fromJson(Map<String, Object?> j) => BatchEvent(
        kind: BatchEventKind.values.byName(j['k']! as String),
        at: DateTime.fromMillisecondsSinceEpoch((j['at']! as num).toInt()),
        exposure: Duration(seconds: (j['exp'] as num?)?.toInt() ?? 0),
        reset: j['reset'] == true,
        value: (j['v'] as num?)?.toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is BatchEvent &&
      other.kind == kind &&
      other.at == at &&
      other.exposure == exposure &&
      other.reset == reset &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, at, exposure, reset, value);
}

/// Stan partii w danej chwili.
enum ExposureState {
  /// W piecyku-przechowalniku, limit nieprzekroczony — licznik stoi.
  inOven,

  /// Na powietrzu, zapas czasu.
  ok,

  /// Na powietrzu, zostało mniej niż [warnLeadMinutes].
  endingSoon,

  /// Limit przekroczony — do ponownego suszenia albo na złom.
  exceeded,

  /// Zużyte.
  consumed,

  /// Złom.
  scrapped,
}

enum BatchClosure { consumed, scrapped }

class ElectrodeBatch {
  final String id;
  final ElectrodeClass electrode;
  final ElectrodeSource source;

  /// Średnica [mm]; `null` — nie podano.
  final double? diameterMm;

  /// Ilość / notatka („40 szt.”, „pół paczki”).
  final String quantity;
  final String location;

  /// Limit czasu na powietrzu [min] (domyślnie z tabeli, edytowalny).
  final int limitMinutes;

  /// Dopuszczalna liczba ponownych suszeń.
  final int maxRedries;
  final int redryCount;

  /// Pierwsze wyjęcie z piecyka / otwarcie opakowania.
  final DateTime takenOutAt;

  /// Początek bieżącego pobytu na powietrzu; `null` — w piecyku albo
  /// zamknięte.
  final DateTime? exposureStart;

  /// Czas na powietrzu zebrany przed bieżącym pobytem (nie wyzerowany).
  final Duration priorExposure;

  /// Od kiedy w piecyku; `null` — nie w piecyku.
  final DateTime? ovenSince;

  final DateTime? closedAt;
  final BatchClosure? closure;
  final List<BatchEvent> events;

  const ElectrodeBatch({
    required this.id,
    required this.electrode,
    required this.source,
    required this.limitMinutes,
    required this.maxRedries,
    required this.takenOutAt,
    this.diameterMm,
    this.quantity = '',
    this.location = '',
    this.redryCount = 0,
    this.exposureStart,
    this.priorExposure = Duration.zero,
    this.ovenSince,
    this.closedAt,
    this.closure,
    this.events = const [],
  });

  /// Nowa partia „wyjąłem elektrody” o [at]. [limitMinutes] i [maxRedries]
  /// domyślnie z tabeli.
  factory ElectrodeBatch.takenOut({
    required String id,
    required ElectrodeClass electrode,
    required DateTime at,
    ElectrodeSource source = ElectrodeSource.oven,
    double? diameterMm,
    String quantity = '',
    String location = '',
    int? limitMinutes,
    int? maxRedries,
  }) =>
      ElectrodeBatch(
        id: id,
        electrode: electrode,
        source: source,
        diameterMm: diameterMm,
        quantity: quantity.trim(),
        location: location.trim(),
        limitMinutes: (limitMinutes ?? defaultLimitMinutes(electrode, source))
            .clamp(1, 7 * 24 * 60),
        maxRedries: (maxRedries ?? defaultMaxRedries(electrode)).clamp(0, 99),
        takenOutAt: at,
        exposureStart: at,
        events: [BatchEvent(kind: BatchEventKind.takenOut, at: at)],
      );

  Duration get limit => Duration(minutes: limitMinutes);

  bool get isClosed => closure != null;
  bool get isInOven => !isClosed && ovenSince != null;
  bool get isExposed => !isClosed && exposureStart != null;

  /// Czas na powietrzu w chwili [now] (sumarycznie, od ostatniego zerowania).
  Duration exposureAt(DateTime now) {
    final start = exposureStart;
    if (start == null || isClosed) return priorExposure;
    final stint = now.difference(start);
    return priorExposure + (stint.isNegative ? Duration.zero : stint);
  }

  /// Pozostały czas (ujemny po przekroczeniu).
  Duration remainingAt(DateTime now) => limit - exposureAt(now);

  /// Chwila końca limitu dla partii na powietrzu.
  DateTime? get deadline {
    final start = exposureStart;
    if (start == null || isClosed) return null;
    return start.add(limit - priorExposure);
  }

  /// Ułamek limitu zużyty (0…1, obcięty).
  double usedFraction(DateTime now) {
    final used = exposureAt(now).inSeconds / limit.inSeconds;
    return used.clamp(0.0, 1.0);
  }

  /// Czy limit przekroczony (także w piecyku — wtedy piecyk nie pomaga).
  bool exceededAt(DateTime now) => exposureAt(now) > limit;

  /// Wyczerpany limit suszeń — po przekroczeniu czasu tylko złom.
  bool get redryLimitReached => redryCount >= maxRedries;

  /// Suszono więcej razy, niż pozwala limit.
  bool get redryLimitExceeded => redryCount > maxRedries;

  ExposureState stateAt(DateTime now) {
    if (closure == BatchClosure.consumed) return ExposureState.consumed;
    if (closure == BatchClosure.scrapped) return ExposureState.scrapped;
    if (exceededAt(now)) return ExposureState.exceeded;
    if (isInOven) return ExposureState.inOven;
    final lead = Duration(minutes: warnLeadMinutes(limitMinutes));
    return remainingAt(now) <= lead
        ? ExposureState.endingSoon
        : ExposureState.ok;
  }

  /// Ile jeszcze w piecyku do wyzerowania limitu; `Duration.zero` — już
  /// można; `null` — nie w piecyku albo limit przekroczony (zerowanie
  /// tylko przez suszenie).
  Duration? resetRemainingAt(DateTime now) {
    final since = ovenSince;
    if (since == null || isClosed || priorExposure > limit) return null;
    final left = kOvenResetHold - now.difference(since);
    return left.isNegative ? Duration.zero : left;
  }

  /// Ostatnia aktywność (dziennik, sortowanie).
  DateTime get lastEventAt => events.isEmpty ? takenOutAt : events.last.at;

  ElectrodeBatch _copy({
    int? limitMinutes,
    int? maxRedries,
    int? redryCount,
    DateTime? Function()? exposureStart,
    Duration? priorExposure,
    DateTime? Function()? ovenSince,
    DateTime? closedAt,
    BatchClosure? closure,
    BatchEvent? event,
  }) =>
      ElectrodeBatch(
        id: id,
        electrode: electrode,
        source: source,
        diameterMm: diameterMm,
        quantity: quantity,
        location: location,
        limitMinutes: limitMinutes ?? this.limitMinutes,
        maxRedries: maxRedries ?? this.maxRedries,
        redryCount: redryCount ?? this.redryCount,
        takenOutAt: takenOutAt,
        exposureStart:
            exposureStart == null ? this.exposureStart : exposureStart(),
        priorExposure: priorExposure ?? this.priorExposure,
        ovenSince: ovenSince == null ? this.ovenSince : ovenSince(),
        closedAt: closedAt ?? this.closedAt,
        closure: closure ?? this.closure,
        events: event == null ? events : [...events, event],
      );

  /// „Wróciły do piecyka” — licznik staje.
  ElectrodeBatch returnToOven(DateTime at) {
    if (!isExposed) {
      throw StateError('Partia $id nie jest na powietrzu.');
    }
    final exposure = exposureAt(at);
    return _copy(
      priorExposure: exposure,
      exposureStart: () => null,
      ovenSince: () => at,
      event: BatchEvent(
          kind: BatchEventKind.returnedToOven, at: at, exposure: exposure),
    );
  }

  /// „Wyjąłem ponownie” z piecyka-przechowalnika. Po ≥ [hold] w piecyku
  /// (i bez przekroczenia limitu) licznik startuje od zera; krócej —
  /// liczy dalej od zebranego czasu.
  ElectrodeBatch takeOutAgain(DateTime at, {Duration hold = kOvenResetHold}) {
    final since = ovenSince;
    if (!isInOven || since == null) {
      throw StateError('Partia $id nie jest w piecyku.');
    }
    final reset = priorExposure <= limit && at.difference(since) >= hold;
    final prior = reset ? Duration.zero : priorExposure;
    return _copy(
      priorExposure: prior,
      exposureStart: () => at,
      ovenSince: () => null,
      event: BatchEvent(
          kind: BatchEventKind.takenOutAgain,
          at: at,
          exposure: prior,
          reset: reset),
    );
  }

  /// „Ponownie wysuszone” — licznik suszeń +1 i nowy start na powietrzu.
  ElectrodeBatch redried(DateTime at) {
    if (isClosed) throw StateError('Partia $id jest zamknięta.');
    final n = redryCount + 1;
    return _copy(
      redryCount: n,
      priorExposure: Duration.zero,
      exposureStart: () => at,
      ovenSince: () => null,
      event: BatchEvent(
          kind: BatchEventKind.redried,
          at: at,
          exposure: exposureAt(at),
          value: n),
    );
  }

  /// „Zużyte” albo „Złom” — licznik staje na stałe.
  ElectrodeBatch close(DateTime at, BatchClosure how) {
    if (isClosed) throw StateError('Partia $id jest już zamknięta.');
    final exposure = exposureAt(at);
    return _copy(
      priorExposure: exposure,
      exposureStart: () => null,
      ovenSince: () => null,
      closedAt: at,
      closure: how,
      event: BatchEvent(
          kind: how == BatchClosure.consumed
              ? BatchEventKind.consumed
              : BatchEventKind.scrapped,
          at: at,
          exposure: exposure),
    );
  }

  /// Zmiana limitu (WPS / producent ostrzejszy) — z wpisem w dzienniku.
  ElectrodeBatch withLimit(int minutes, DateTime at) {
    final m = minutes.clamp(1, 7 * 24 * 60);
    if (m == limitMinutes) return this;
    return _copy(
      limitMinutes: m,
      event: BatchEvent(
          kind: BatchEventKind.limitChanged,
          at: at,
          exposure: exposureAt(at),
          value: m),
    );
  }

  /// Zmiana dopuszczalnej liczby suszeń (bez wpisu — to ustawienie).
  ElectrodeBatch withMaxRedries(int n) => _copy(maxRedries: n.clamp(0, 99));

  Map<String, Object?> toJson() => {
        'id': id,
        'cls': electrode.name,
        'src': source.name,
        if (diameterMm != null) 'd': diameterMm,
        'qty': quantity,
        'loc': location,
        'lim': limitMinutes,
        'maxR': maxRedries,
        'r': redryCount,
        'out': takenOutAt.millisecondsSinceEpoch,
        if (exposureStart != null)
          'start': exposureStart!.millisecondsSinceEpoch,
        'prior': priorExposure.inSeconds,
        if (ovenSince != null) 'oven': ovenSince!.millisecondsSinceEpoch,
        if (closedAt != null) 'closed': closedAt!.millisecondsSinceEpoch,
        if (closure != null) 'how': closure!.name,
        'ev': [for (final e in events) e.toJson()],
      };

  /// Rzuca przy niepoprawnych danych — [decodeBatches] pomija taki wpis.
  static ElectrodeBatch fromJson(Map<String, Object?> j) {
    DateTime? time(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    final how = j['how'] as String?;
    return ElectrodeBatch(
      id: j['id']! as String,
      electrode: ElectrodeClass.values.byName(j['cls']! as String),
      source: ElectrodeSource.values.byName(j['src'] as String? ?? 'oven'),
      diameterMm: (j['d'] as num?)?.toDouble(),
      quantity: j['qty'] as String? ?? '',
      location: j['loc'] as String? ?? '',
      limitMinutes: (j['lim']! as num).toInt().clamp(1, 7 * 24 * 60),
      maxRedries: (j['maxR'] as num?)?.toInt() ?? 1,
      redryCount: (j['r'] as num?)?.toInt() ?? 0,
      takenOutAt: time(j['out'])!,
      exposureStart: time(j['start']),
      priorExposure: Duration(seconds: (j['prior'] as num?)?.toInt() ?? 0),
      ovenSince: time(j['oven']),
      closedAt: time(j['closed']),
      closure: how == null ? null : BatchClosure.values.byName(how),
      events: [
        for (final e in (j['ev'] as List? ?? const []))
          BatchEvent.fromJson((e as Map).cast<String, Object?>()),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ZAPIS (JSON)
// ═══════════════════════════════════════════════════════════════════════════

/// Wersja formatu w kluczu SharedPreferences.
const String kElectrodeBatchesPrefsKey = 'electrode_batches_v1';

String encodeBatches(List<ElectrodeBatch> batches) => jsonEncode({
      'v': 1,
      'batches': [for (final b in batches) b.toJson()]
    });

/// Odporny odczyt: uszkodzony JSON → pusta lista; uszkodzony wpis →
/// pominięty, reszta zostaje.
List<ElectrodeBatch> decodeBatches(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  Object? root;
  try {
    root = jsonDecode(raw);
  } on FormatException {
    return [];
  }
  final list = switch (root) {
    {'batches': final List l} => l,
    final List l => l,
    _ => const <Object?>[],
  };
  final out = <ElectrodeBatch>[];
  for (final item in list) {
    if (item is! Map) continue;
    try {
      out.add(ElectrodeBatch.fromJson(item.cast<String, Object?>()));
    } catch (_) {
      // Wpis z nieznaną klasą albo bez wymaganych pól — pomijamy.
    }
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════════════
// LISTA, DZIENNIK, PRZYPOMNIENIA
// ═══════════════════════════════════════════════════════════════════════════

/// Aktywne partie: najpierw przekroczone, potem najmniej czasu, piecyk na
/// końcu.
List<ElectrodeBatch> sortActive(Iterable<ElectrodeBatch> all, DateTime now) {
  int rank(ExposureState s) => switch (s) {
        ExposureState.exceeded => 0,
        ExposureState.endingSoon => 1,
        ExposureState.ok => 2,
        ExposureState.inOven => 3,
        _ => 4,
      };
  final out = [
    for (final b in all)
      if (!b.isClosed) b
  ];
  out.sort((a, b) {
    final r = rank(a.stateAt(now)).compareTo(rank(b.stateAt(now)));
    if (r != 0) return r;
    final ra = a.remainingAt(now), rb = b.remainingAt(now);
    if (ra != rb) return ra.compareTo(rb);
    return a.takenOutAt.compareTo(b.takenOutAt);
  });
  return out;
}

enum LogRange { today, week, all }

/// Partie do dziennika: aktywne zawsze, zamknięte — gdy mają wpis
/// w zakresie. Najnowsza aktywność na górze.
List<ElectrodeBatch> batchesForLog(
    Iterable<ElectrodeBatch> all, LogRange range, DateTime now) {
  final from = switch (range) {
    LogRange.today => DateTime(now.year, now.month, now.day),
    LogRange.week => DateTime(now.year, now.month, now.day - 6),
    LogRange.all => null,
  };
  final out = [
    for (final b in all)
      if (from == null ||
          !b.isClosed ||
          b.events.any((e) => !e.at.isBefore(from)))
        b
  ];
  out.sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));
  return out;
}

/// Przypomnienia dla partii na powietrzu: [warnLeadMinutes] przed końcem
/// i w chwili końca — tylko przyszłe. Identyfikatory stabilne (ta sama
/// partia i wyprzedzenie → to samo id), więc przeplanowanie nadpisuje.
List<PlannedReminder> planElectrodeReminders(
  Iterable<ElectrodeBatch> batches, {
  required DateTime now,
  required bool english,
  int maxCount = 16,
}) {
  final out = <PlannedReminder>[];
  for (final b in batches) {
    final end = b.deadline;
    if (end == null || !b.isExposed) continue;
    final lead = warnLeadMinutes(b.limitMinutes);
    final name = b.label(en: english);
    for (final minutesBefore in [lead, 0]) {
      final fireAt = end.subtract(Duration(minutes: minutesBefore));
      if (!fireAt.isAfter(now)) continue;
      out.add(PlannedReminder(
        id: reminderId('electrode:${b.id}', ReminderKind.expiry, minutesBefore),
        fireAt: fireAt,
        certificateId: b.id,
        kind: ReminderKind.expiry,
        daysBefore: 0,
        deadline: end,
        title: minutesBefore == 0
            ? (english
                ? 'Electrodes: exposure limit reached'
                : 'Elektrody: koniec czasu na powietrzu')
            : (english
                ? 'Electrodes: $minutesBefore min left'
                : 'Elektrody: zostało $minutesBefore min'),
        body: minutesBefore == 0
            ? (english
                ? '$name — return to re-drying or scrap. Do not weld with them.'
                : '$name — do ponownego suszenia albo na złom. Nie spawaj nimi.')
            : (english
                ? '$name — limit ends at ${formatHm(end)}. Put them back in the oven.'
                : '$name — limit mija o ${formatHm(end)}. Odłóż do piecyka.'),
      ));
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > maxCount ? out.sublist(0, maxCount) : out;
}

// ═══════════════════════════════════════════════════════════════════════════
// FORMATOWANIE
// ═══════════════════════════════════════════════════════════════════════════

String _two(int v) => v.toString().padLeft(2, '0');

/// `07:05` — zawsze 24 h.
String formatHm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// `2026-10-17`.
String formatYmd(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

/// `3 h 05 min`, `45 min`, `0 min` — wartość bezwzględna, w dół do minuty.
String formatSpan(Duration d) {
  final m = d.abs().inMinutes;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${_two(m % 60)} min';
}

/// Średnica: `3,2` (PL) / `3.2` (EN).
String formatDiameter(double mm, {required bool en}) {
  final s = mm == mm.roundToDouble()
      ? mm.toStringAsFixed(1)
      : mm.toStringAsFixed(mm * 10 == (mm * 10).roundToDouble() ? 1 : 2);
  return en ? s : s.replaceAll('.', ',');
}

extension ElectrodeBatchLabel on ElectrodeBatch {
  /// `E7018 Ø3,2 · 40 szt.`
  String label({required bool en}) => [
        electrode.code,
        if (diameterMm != null) 'Ø${formatDiameter(diameterMm!, en: en)}',
        if (quantity.isNotEmpty) quantity,
      ].join(' · ');
}

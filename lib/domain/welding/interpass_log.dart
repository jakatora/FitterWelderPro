/// Rejestr temperatury podgrzania i międzyściegowej jednej spoiny: limity
/// z WPS, pomiary przed kolejnymi ściegami, ocena każdego pomiaru i werdykt
/// spoiny — dowód dla QC (P91 / Cr-Mo, duplex, nierdzewki, stale o wysokiej
/// wytrzymałości).
///
/// Zasady zapisane w kodzie (i w testach):
/// * pomiar „przed ściegiem 1” ocenia się względem MINIMALNEJ temperatury
///   podgrzania; „przed ściegiem n ≥ 2” — względem MAKSYMALNEJ (i
///   minimalnej, jeśli WPS ją podaje) temperatury międzyściegowej;
/// * NA GRANICY równość = OK: min. — temperatura co najmniej równa limitowi,
///   maks. — nie większa niż limit (WPS podaje wartości graniczne
///   dopuszczalne); tolerancja tylko na szum liczb zmiennoprzecinkowych;
/// * brak limitu w WPS → „brak limitu z WPS” — ani OK, ani błąd;
/// * o ściegu decyduje NAJPÓŹNIEJSZY W CZASIE pomiar przed nim (ponowny
///   pomiar po odczekaniu), nie ostatnio dopisany — wpis wsteczny nie
///   zmienia oceny (lekcja z modułu prac pożarowych);
/// * kredka termometryczna mówi tylko „osiągnięto / nie osiągnięto progu” —
///   gdy próg nie rozstrzyga limitu, pomiar jest „niepotwierdzony”;
/// * zielony werdykt spoiny tylko, gdy wpisano liczbę ściegów, każdy ścieg
///   ma pomiar przed rozpoczęciem, czasy idą zgodnie z numerami ściegów,
///   limity są spójne i każdy decydujący pomiar jest OK;
/// * wartość kanoniczna w °C (zaokrąglona do 0,01 °C); °F to wyłącznie
///   wyświetlanie — przełączenie jednostki nie zmienia danych ani werdyktu.
///
/// Aplikacja NIE podaje „typowych” temperatur — limity wpisuje się z WPS.
///
/// Czysty Dart: bez Fluttera i bez bazy (zapis w SharedPreferences robi
/// warstwa ekranu).
library;

/// Tolerancja porównań — wyłącznie szum liczb zmiennoprzecinkowych, nie
/// „luz” na limicie (wartości są w °C z dokładnością 0,01).
const double kInterpassEpsC = 1e-6;

/// Zakres temperatur, które aplikacja przyjmuje (°C). Ujemne — stal na
/// mrozie przed podgrzaniem; powyżej 1000 °C to literówka.
const double kInterpassMinTempC = -60;
const double kInterpassMaxTempC = 1000;

/// Największy numer ściegu (i liczba ściegów) — więcej to literówka.
const int kInterpassMaxPass = 999;

/// Wpis wsteczny: chwila pomiaru wcześniejsza od chwili wpisania o więcej
/// niż tyle — protokół pokazuje wtedy, kiedy pomiar wpisano.
const Duration kInterpassBackdateAfter = Duration(minutes: 10);

/// Zapas na różnicę zegarów: chwila pomiaru może być do 5 min „w
/// przyszłości” (jak w module prac pożarowych).
const Duration kInterpassFutureSlack = Duration(minutes: 5);

// ── Jednostki ─────────────────────────────────────────────────────────────

enum InterpassUnit {
  c('°C'),
  f('°F');

  const InterpassUnit(this.symbol);
  final String symbol;

  static InterpassUnit? byName(Object? name) {
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

double interpassCToF(double c) => c * 9 / 5 + 32;
double interpassFToC(double f) => (f - 32) * 5 / 9;

/// Wartość kanoniczna: °C zaokrąglone do 0,01.
double interpassRoundC(double c) => (c * 100).roundToDouble() / 100;

/// Liczba wpisana w jednostce [unit] → kanoniczne °C.
double interpassToC(double value, InterpassUnit unit) =>
    interpassRoundC(unit == InterpassUnit.f ? interpassFToC(value) : value);

/// Kanoniczne °C → liczba do wyświetlenia w jednostce [unit].
double interpassFromC(double c, InterpassUnit unit) =>
    unit == InterpassUnit.f ? interpassCToF(c) : c;

/// Temperatura (°C) w zakresie przyjmowanym przez aplikację.
bool interpassTempValid(double c) =>
    c.isFinite && c >= kInterpassMinTempC && c <= kInterpassMaxTempC;

/// `250` → „250”, `121.11` → „121,11” (PL) / „121.11” (EN); do 2 miejsc,
/// bez zbędnych zer — wartość tuż ponad limitem nie może wyglądać jak limit.
String formatInterpassNumber(double v, {required bool en}) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  if (s == '-0') s = '0';
  return en ? s : s.replaceAll('.', ',');
}

/// „250 °C” / „482 °F”.
String formatInterpassTemp(double c, InterpassUnit unit, {required bool en}) =>
    '${formatInterpassNumber(interpassFromC(c, unit), en: en)} ${unit.symbol}';

// ── Metoda i odczyt ───────────────────────────────────────────────────────

/// Metoda pomiaru.
enum InterpassMethod {
  contact(
      'Termometr kontaktowy', 'Contact thermometer', 'termometr', 'contact'),
  crayon('Kredka termometryczna', 'Temperature-indicating crayon', 'kredka',
      'crayon'),
  pyrometer(
      'Pirometr (podczerwień)', 'Infrared pyrometer', 'pirometr', 'pyrometer');

  const InterpassMethod(this.labelPl, this.labelEn, this.shortPl, this.shortEn);
  final String labelPl;
  final String labelEn;
  final String shortPl;
  final String shortEn;

  String label({required bool en}) => en ? labelEn : labelPl;
  String short({required bool en}) => en ? shortEn : shortPl;

  static InterpassMethod? byName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }
}

/// Co mówi odczyt: wartość (termometr, pirometr) albo tylko próg (kredka).
enum InterpassBound {
  /// Temperatura równa wartości.
  exact,

  /// Kredka STOPIŁA SIĘ — temperatura co najmniej równa progowi.
  atLeast,

  /// Kredka NIE stopiła się — temperatura poniżej progu.
  below;

  static InterpassBound? byName(Object? name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return null;
  }
}

/// Jeden pomiar temperatury przed ściegiem [pass].
class InterpassReading {
  /// Numer ściegu, PRZED którym zmierzono (1 = przed pierwszym ściegiem,
  /// czyli podgrzanie).
  final int pass;

  /// Temperatura (°C, kanoniczna) — dla kredki: jej próg.
  final double tempC;
  final InterpassBound bound;
  final InterpassMethod method;

  /// Chwila pomiaru (ms od epoki).
  final int at;

  /// Chwila wpisania do aplikacji (ms od epoki).
  final int recordedAt;
  final String note;

  const InterpassReading({
    required this.pass,
    required this.tempC,
    this.bound = InterpassBound.exact,
    this.method = InterpassMethod.contact,
    required this.at,
    required this.recordedAt,
    this.note = '',
  });

  /// Pomiar wpisany później niż został wykonany (o ponad 10 min).
  bool get backdated =>
      recordedAt - at > kInterpassBackdateAfter.inMilliseconds;

  Map<String, Object?> toJson() => {
        'pass': pass,
        'tempC': tempC,
        'bound': bound.name,
        'method': method.name,
        'at': at,
        'recordedAt': recordedAt,
        'note': note,
      };

  /// `null`, gdy wpis jest uszkodzony (bez temperatury, numeru ściegu,
  /// chwili albo z nieznaną metodą / rodzajem odczytu — kredki nie wolno
  /// pomylić z odczytem wartości).
  static InterpassReading? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pass = raw['pass'];
    final t = raw['tempC'];
    final at = raw['at'];
    final rec = raw['recordedAt'];
    final bound = InterpassBound.byName(raw['bound']);
    final method = InterpassMethod.byName(raw['method']);
    if (pass is! num || !pass.isFinite || pass != pass.roundToDouble()) {
      return null;
    }
    if (pass < 1 || pass > kInterpassMaxPass) return null;
    if (t is! num || !interpassTempValid(t.toDouble())) return null;
    if (at is! num || !at.isFinite) return null;
    if (bound == null || method == null) return null;
    return InterpassReading(
      pass: pass.toInt(),
      tempC: interpassRoundC(t.toDouble()),
      bound: bound,
      method: method,
      at: at.toInt(),
      recordedAt: rec is num && rec.isFinite ? rec.toInt() : at.toInt(),
      note: raw['note'] is String ? raw['note'] as String : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InterpassReading &&
      other.pass == pass &&
      other.tempC == tempC &&
      other.bound == bound &&
      other.method == method &&
      other.at == at &&
      other.recordedAt == recordedAt &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(pass, tempC, bound, method, at, recordedAt, note);
}

// ── Limity i ocena pomiaru ────────────────────────────────────────────────

/// Limity z WPS (°C, kanoniczne); `null` = WPS nie podaje / nie wpisano.
class InterpassLimits {
  final double? preheatMinC;
  final double? interpassMaxC;

  /// Opcjonalna minimalna międzyściegowa (np. P91 — wg WPS).
  final double? interpassMinC;

  const InterpassLimits({
    this.preheatMinC,
    this.interpassMaxC,
    this.interpassMinC,
  });

  bool get isEmpty =>
      preheatMinC == null && interpassMaxC == null && interpassMinC == null;

  /// Sprzeczne limity (literówka): min. międzyściegowa albo min. podgrzanie
  /// wyżej niż maks. międzyściegowa.
  bool get conflict {
    final max = interpassMaxC;
    if (max == null) return false;
    final minI = interpassMinC;
    final minP = preheatMinC;
    return (minI != null && minI > max + kInterpassEpsC) ||
        (minP != null && minP > max + kInterpassEpsC);
  }

  @override
  bool operator ==(Object other) =>
      other is InterpassLimits &&
      other.preheatMinC == preheatMinC &&
      other.interpassMaxC == interpassMaxC &&
      other.interpassMinC == interpassMinC;

  @override
  int get hashCode => Object.hash(preheatMinC, interpassMaxC, interpassMinC);
}

/// Pomiar przed ściegiem 1 to podgrzanie, przed kolejnymi — międzyściegowa.
enum InterpassPhase { preheat, interpass }

InterpassPhase interpassPhaseOf(int pass) =>
    pass <= 1 ? InterpassPhase.preheat : InterpassPhase.interpass;

/// Ocena jednego pomiaru.
enum InterpassCheck {
  /// W limitach (równość z limitem = OK).
  ok,

  /// Poniżej minimum (podgrzania albo międzyściegowej).
  low,

  /// Powyżej maksymalnej międzyściegowej.
  high,

  /// Kredka o tym progu nie rozstrzyga limitu.
  unconfirmed,

  /// Brak limitu z WPS — ani OK, ani błąd.
  noLimit,
}

/// Odczyt względem minimum: temperatura ≥ [min].
InterpassCheck _vsMin(InterpassReading r, double min) {
  switch (r.bound) {
    case InterpassBound.exact:
      return r.tempC >= min - kInterpassEpsC
          ? InterpassCheck.ok
          : InterpassCheck.low;
    case InterpassBound.atLeast:
      // T ≥ próg ≥ min → OK; próg poniżej min nic nie mówi.
      return r.tempC >= min - kInterpassEpsC
          ? InterpassCheck.ok
          : InterpassCheck.unconfirmed;
    case InterpassBound.below:
      // T < próg ≤ min → za zimno; próg powyżej min nic nie mówi.
      return r.tempC <= min + kInterpassEpsC
          ? InterpassCheck.low
          : InterpassCheck.unconfirmed;
  }
}

/// Odczyt względem maksimum: temperatura ≤ [max].
InterpassCheck _vsMax(InterpassReading r, double max) {
  switch (r.bound) {
    case InterpassBound.exact:
      return r.tempC <= max + kInterpassEpsC
          ? InterpassCheck.ok
          : InterpassCheck.high;
    case InterpassBound.below:
      // T < próg ≤ maks → OK; próg powyżej maks nic nie mówi.
      return r.tempC <= max + kInterpassEpsC
          ? InterpassCheck.ok
          : InterpassCheck.unconfirmed;
    case InterpassBound.atLeast:
      // T ≥ próg > maks → za gorąco; kredka o progu = maks się stopiła —
      // temperatura może być równa albo wyższa: nie rozstrzyga.
      return r.tempC > max + kInterpassEpsC
          ? InterpassCheck.high
          : InterpassCheck.unconfirmed;
  }
}

/// Ocena pomiaru: przed ściegiem 1 — względem min. podgrzania; przed
/// kolejnymi — względem maks. (i min., jeśli ustawiona) międzyściegowej.
InterpassCheck interpassCheck(InterpassReading r, InterpassLimits limits) {
  if (interpassPhaseOf(r.pass) == InterpassPhase.preheat) {
    final min = limits.preheatMinC;
    if (min == null) return InterpassCheck.noLimit;
    return _vsMin(r, min);
  }
  final max = limits.interpassMaxC;
  final min = limits.interpassMinC;
  if (max == null && min == null) return InterpassCheck.noLimit;
  final parts = [
    if (min != null) _vsMin(r, min),
    if (max != null) _vsMax(r, max),
  ];
  if (parts.contains(InterpassCheck.low)) return InterpassCheck.low;
  if (parts.contains(InterpassCheck.high)) return InterpassCheck.high;
  if (parts.contains(InterpassCheck.unconfirmed)) {
    return InterpassCheck.unconfirmed;
  }
  // Bez maksimum spełnione minimum nie wystarcza — WPS musi podać maks.
  if (max == null) return InterpassCheck.noLimit;
  return InterpassCheck.ok;
}

// ── Czas pomiaru ──────────────────────────────────────────────────────────

/// Chwila pomiaru o godzinie [hhmm] wpisanej przy [now]: ostatnie takie
/// wystąpienie nie później niż 5 min po [now]. Godzina „z przyszłości” to
/// wczoraj — np. 23:50 wpisane o 00:12 (zmiana nocna). Zła godzina → [now].
/// Te same zasady co `hotWorkMeasurementAt` (prace pożarowe).
DateTime interpassReadingAt(String hhmm, DateTime now) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return now;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return now;
  final today = DateTime(now.year, now.month, now.day, h, min);
  return today.isAfter(now.add(kInterpassFutureSlack))
      ? DateTime(now.year, now.month, now.day - 1, h, min)
      : today;
}

/// Chwila nowego pomiaru z wyborów na ekranie: nic → [now]; sama godzina →
/// najbliższe wcześniejsze wystąpienie ([interpassReadingAt]); data (z
/// godziną albo bez — wtedy godzina z [now]) → dokładnie ta chwila.
DateTime interpassResolveAt({
  DateTime? date,
  String? hhmm,
  required DateTime now,
}) {
  if (date == null) {
    return hhmm == null ? now : interpassReadingAt(hhmm, now);
  }
  var h = now.hour;
  var min = now.minute;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((hhmm ?? '').trim());
  if (m != null) {
    final hh = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2)!);
    if (hh <= 23 && mm <= 59) {
      h = hh;
      min = mm;
    }
  }
  return DateTime(date.year, date.month, date.day, h, min);
}

/// Chwila pomiaru „z przyszłości” (ponad 5 min zapasu) — błąd wpisu.
bool interpassAtInFuture(DateTime at, DateTime now) =>
    at.isAfter(now.add(kInterpassFutureSlack));

/// Pomiary w kolejności czasu (stabilnie — przy tej samej chwili zostaje
/// kolejność wpisów).
List<InterpassReading> interpassChrono(List<InterpassReading> list) {
  final indexed = [...list.indexed]..sort((a, b) {
      final byAt = a.$2.at.compareTo(b.$2.at);
      return byAt != 0 ? byAt : a.$1.compareTo(b.$1);
    });
  return List.unmodifiable([for (final (_, r) in indexed) r]);
}

// ── Werdykt spoiny ────────────────────────────────────────────────────────

/// Stan spoiny — co blokuje zielony werdykt (kolejność = priorytet).
enum InterpassWeldStatus {
  /// Decydujący pomiar któregoś ściegu poza limitem — czerwony.
  outOfLimits,

  /// Limity sprzeczne (min. > maks.) — literówka w ustawieniach.
  limitsConflict,

  /// Brak jakiegokolwiek pomiaru.
  noReadings,

  /// Ściegi bez pomiaru przed rozpoczęciem.
  missingPasses,

  /// Pomiar przed ściegiem o numerze większym niż wpisana liczba ściegów.
  passCountConflict,

  /// Nie wpisano liczby ściegów — nie wiadomo, czy każdy ma pomiar.
  passCountMissing,

  /// Czasy pomiarów nie idą zgodnie z numerami ściegów.
  orderConflict,

  /// Kredka nie rozstrzyga limitu.
  unconfirmed,

  /// Brak limitu z WPS dla któregoś ściegu — neutralnie.
  noLimit,

  /// Każdy ścieg z pomiarem przed rozpoczęciem, wszystko w limitach.
  ok,
}

class InterpassAssessment {
  final InterpassLimits limits;
  final int? passCount;

  /// Wszystkie pomiary od najwcześniejszego.
  final List<InterpassReading> chrono;

  /// Decydujący (najpóźniejszy w czasie) pomiar każdego ściegu.
  final Map<int, InterpassReading> decisive;

  /// Ścieg n ocenia się do n = max(liczba ściegów, najwyższy numer).
  final int lastPass;
  final List<int> missingPasses;
  final List<int> failedPasses;
  final List<int> unconfirmedPasses;
  final List<int> noLimitPasses;

  /// Ściegi, których decydujący pomiar jest PÓŹNIEJSZY niż pomiar
  /// następnego ściegu.
  final List<int> orderConflictPasses;
  final List<int> passesBeyondCount;

  const InterpassAssessment._({
    required this.limits,
    required this.passCount,
    required this.chrono,
    required this.decisive,
    required this.lastPass,
    required this.missingPasses,
    required this.failedPasses,
    required this.unconfirmedPasses,
    required this.noLimitPasses,
    required this.orderConflictPasses,
    required this.passesBeyondCount,
  });

  factory InterpassAssessment.of({
    required List<InterpassReading> readings,
    required InterpassLimits limits,
    int? passCount,
  }) {
    final chrono = interpassChrono(readings);
    final decisive = <int, InterpassReading>{};
    for (final r in chrono) {
      decisive[r.pass] = r; // późniejszy w czasie nadpisuje wcześniejszy
    }
    final passes = decisive.keys.toList()..sort();
    final maxPass = passes.isEmpty ? 0 : passes.last;
    final count = passCount;
    final last = count == null ? maxPass : (count > maxPass ? count : maxPass);
    final failed = <int>[];
    final unconfirmed = <int>[];
    final noLimit = <int>[];
    for (final p in passes) {
      switch (interpassCheck(decisive[p]!, limits)) {
        case InterpassCheck.low:
        case InterpassCheck.high:
          failed.add(p);
        case InterpassCheck.unconfirmed:
          unconfirmed.add(p);
        case InterpassCheck.noLimit:
          noLimit.add(p);
        case InterpassCheck.ok:
          break;
      }
    }
    final order = <int>[
      for (var i = 0; i + 1 < passes.length; i++)
        if (decisive[passes[i]]!.at > decisive[passes[i + 1]]!.at) passes[i],
    ];
    return InterpassAssessment._(
      limits: limits,
      passCount: count,
      chrono: chrono,
      decisive: Map.unmodifiable(decisive),
      lastPass: last,
      missingPasses: List.unmodifiable([
        for (var p = 1; p <= last; p++)
          if (!decisive.containsKey(p)) p,
      ]),
      failedPasses: List.unmodifiable(failed),
      unconfirmedPasses: List.unmodifiable(unconfirmed),
      noLimitPasses: List.unmodifiable(noLimit),
      orderConflictPasses: List.unmodifiable(order),
      passesBeyondCount: List.unmodifiable(
          [if (count != null) ...passes.where((p) => p > count)]),
    );
  }

  /// Ocena dowolnego pomiaru (także zastąpionego).
  InterpassCheck checkOf(InterpassReading r) => interpassCheck(r, limits);

  /// Pomiar decyduje o swoim ściegu (nie został zastąpiony późniejszym).
  bool isDecisive(InterpassReading r) => identical(decisive[r.pass], r);

  /// Pomiary poza limitem zastąpione późniejszym pomiarem przed tym samym
  /// ściegiem (np. za gorąco → odczekano → ponowny pomiar).
  List<InterpassReading> get supersededOutOfLimits => [
        for (final r in chrono)
          if (!isDecisive(r) &&
              const {InterpassCheck.low, InterpassCheck.high}
                  .contains(checkOf(r)))
            r,
      ];

  InterpassWeldStatus get status {
    if (failedPasses.isNotEmpty) return InterpassWeldStatus.outOfLimits;
    if (limits.conflict) return InterpassWeldStatus.limitsConflict;
    if (chrono.isEmpty) return InterpassWeldStatus.noReadings;
    if (missingPasses.isNotEmpty) return InterpassWeldStatus.missingPasses;
    if (passesBeyondCount.isNotEmpty) {
      return InterpassWeldStatus.passCountConflict;
    }
    if (passCount == null) return InterpassWeldStatus.passCountMissing;
    if (orderConflictPasses.isNotEmpty) {
      return InterpassWeldStatus.orderConflict;
    }
    if (unconfirmedPasses.isNotEmpty) return InterpassWeldStatus.unconfirmed;
    if (noLimitPasses.isNotEmpty) return InterpassWeldStatus.noLimit;
    return InterpassWeldStatus.ok;
  }

  bool get ok => status == InterpassWeldStatus.ok;
}

// ── Spoina ────────────────────────────────────────────────────────────────

/// Wartość „bez zmian” dla pól, które mogą być `null` w copyWith.
const Object _keep = Object();

class InterpassWeld {
  final String id;

  /// Numer spoiny (z dziennika albo wpisany).
  final String weldNo;

  /// Opis (linia, izometria, materiał…).
  final String description;

  /// Numer / rewizja WPS (tekst).
  final String wpsRef;

  /// Identyfikator wpisu dziennika spoin, gdy wybrano z dziennika.
  final String journalWeldId;
  final InterpassLimits limits;

  /// Metoda pomiaru — każdy nowy pomiar zapisuje się z tą metodą.
  final InterpassMethod method;

  /// Liczba ściegów spoiny (`null` = nie wpisano).
  final int? passCount;

  /// Pomiary w kolejności czasu.
  final List<InterpassReading> readings;
  final int createdAt;
  final int updatedAt;

  const InterpassWeld({
    required this.id,
    this.weldNo = '',
    this.description = '',
    this.wpsRef = '',
    this.journalWeldId = '',
    this.limits = const InterpassLimits(),
    this.method = InterpassMethod.contact,
    this.passCount,
    this.readings = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory InterpassWeld.blank({required String id, required DateTime now}) =>
      InterpassWeld(
        id: id,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  /// Nic nie wpisano — takiej spoiny nie zapisujemy.
  bool get isBlank =>
      weldNo.trim().isEmpty &&
      description.trim().isEmpty &&
      wpsRef.trim().isEmpty &&
      journalWeldId.isEmpty &&
      limits.isEmpty &&
      passCount == null &&
      readings.isEmpty;

  List<InterpassReading> get readingsChrono => interpassChrono(readings);

  InterpassAssessment assess() => InterpassAssessment.of(
      readings: readings, limits: limits, passCount: passCount);

  /// Dopisuje pomiar — lista zostaje w kolejności czasu.
  InterpassWeld addReading(InterpassReading r) =>
      copyWith(readings: interpassChrono([...readings, r]));

  /// Usuwa pomiar o indeksie [index] listy w kolejności czasu.
  InterpassWeld removeReadingAt(int index) {
    final list = [...readingsChrono];
    if (index < 0 || index >= list.length) return this;
    list.removeAt(index);
    return copyWith(readings: list);
  }

  /// Numer ściegu podpowiadany dla nowego pomiaru: 1 bez pomiarów; ten sam
  /// ścieg, gdy ostatni (w czasie) pomiar nie jest OK (ponowny pomiar po
  /// odczekaniu / dogrzaniu); w pozostałych przypadkach następny.
  int get nextPass {
    final chrono = readingsChrono;
    if (chrono.isEmpty) return 1;
    final last = chrono.last;
    final check = interpassCheck(last, limits);
    final again = check == InterpassCheck.low ||
        check == InterpassCheck.high ||
        check == InterpassCheck.unconfirmed;
    final next = again ? last.pass : last.pass + 1;
    return next > kInterpassMaxPass ? kInterpassMaxPass : next;
  }

  InterpassWeld copyWith({
    String? weldNo,
    String? description,
    String? wpsRef,
    String? journalWeldId,
    InterpassLimits? limits,
    InterpassMethod? method,
    Object? passCount = _keep,
    List<InterpassReading>? readings,
    int? updatedAt,
  }) =>
      InterpassWeld(
        id: id,
        weldNo: weldNo ?? this.weldNo,
        description: description ?? this.description,
        wpsRef: wpsRef ?? this.wpsRef,
        journalWeldId: journalWeldId ?? this.journalWeldId,
        limits: limits ?? this.limits,
        method: method ?? this.method,
        passCount:
            identical(passCount, _keep) ? this.passCount : passCount as int?,
        readings: readings ?? this.readings,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'weldNo': weldNo,
        'description': description,
        'wpsRef': wpsRef,
        'journalWeldId': journalWeldId,
        'preheatMinC': limits.preheatMinC,
        'interpassMaxC': limits.interpassMaxC,
        'interpassMinC': limits.interpassMinC,
        'method': method.name,
        'passCount': passCount,
        'readings': [for (final r in readingsChrono) r.toJson()],
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Odczyt z JSON; `null` dla wpisu bez identyfikatora. Uszkodzone pomiary
  /// są pomijane, limity spoza zakresu — traktowane jak niewpisane.
  static InterpassWeld? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    if (id.isEmpty) return null;
    final count = raw['passCount'];
    return InterpassWeld(
      id: id,
      weldNo: _s(raw['weldNo']),
      description: _s(raw['description']),
      wpsRef: _s(raw['wpsRef']),
      journalWeldId: _s(raw['journalWeldId']),
      limits: InterpassLimits(
        preheatMinC: _temp(raw['preheatMinC']),
        interpassMaxC: _temp(raw['interpassMaxC']),
        interpassMinC: _temp(raw['interpassMinC']),
      ),
      method: InterpassMethod.byName(raw['method']) ?? InterpassMethod.contact,
      passCount: count is num &&
              count.isFinite &&
              count == count.roundToDouble() &&
              count >= 1 &&
              count <= kInterpassMaxPass
          ? count.toInt()
          : null,
      readings: interpassChrono([
        for (final r in _list(raw['readings']))
          if (InterpassReading.fromJson(r) != null)
            InterpassReading.fromJson(r)!,
      ]),
      createdAt: _i(raw['createdAt']),
      updatedAt: _i(raw['updatedAt']),
    );
  }
}

/// Wersja formatu zapisu.
const int kInterpassLogVersion = 1;

/// Cały rejestr do JSON: `{"v": 1, "welds": [...]}`.
Map<String, Object?> interpassLogToJson(List<InterpassWeld> welds) => {
      'v': kInterpassLogVersion,
      'welds': [for (final w in welds) w.toJson()],
    };

/// Wynik odczytu rejestru: spoiny i liczba pominiętych (uszkodzonych)
/// wpisów.
class InterpassLogParse {
  final List<InterpassWeld> welds;
  final int dropped;
  const InterpassLogParse(this.welds, this.dropped);
}

/// Odczyt rejestru. [FormatException], gdy całość jest nieczytelna (nie
/// mapa, brak listy spoin); pojedyncze uszkodzone spoiny są pomijane
/// i liczone w [InterpassLogParse.dropped].
InterpassLogParse interpassLogFromJson(Object? raw) {
  if (raw is! Map) throw const FormatException('interpass log: not a map');
  final list = raw['welds'];
  if (list is! List) throw const FormatException('interpass log: no welds');
  final welds = <InterpassWeld>[];
  var dropped = 0;
  for (final e in list) {
    final w = InterpassWeld.fromJson(e);
    if (w == null) {
      dropped++;
    } else {
      welds.add(w);
    }
  }
  return InterpassLogParse(welds, dropped);
}

/// Najnowsze na górze (ostatnia zmiana).
List<InterpassWeld> sortInterpassWelds(List<InterpassWeld> list) =>
    [...list]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

/// `YYYY-MM-DD HH:mm` (czas lokalny).
String interpassDateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${interpassDate(d)} ${interpassTime(d)}';
}

/// `YYYY-MM-DD`.
String interpassDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// `HH:mm`.
String interpassTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');
String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
List<Object?> _list(Object? v) => v is List ? v : const [];
double? _temp(Object? v) => v is num && interpassTempValid(v.toDouble())
    ? interpassRoundC(v.toDouble())
    : null;

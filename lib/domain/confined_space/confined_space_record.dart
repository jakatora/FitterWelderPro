/// Protokół wejścia i spawania w przestrzeni zamkniętej — dane do zapisu,
/// ocena gotowości i duplikat „jak wczoraj”.
///
/// To POMOC dla spawacza i nadzoru, nie urzędowy dokument: wiąże pisemne
/// pozwolenie wydane przez pracodawcę, instrukcja zakładu i przepisy
/// (zob. [confinedSpaceDisclaimer]).
///
/// Zasady bezpieczeństwa zapisane w kodzie (i w testach):
/// * zielony stan („można wejść”) wymaga odhaczenia wszystkich punktów
///   „przed wejściem” i odczytu KAŻDEGO wymaganego gazu (tlen i palne
///   zawsze; CO i H₂S — chyba że pozwolenie ich nie wymaga), którego
///   NAJPÓŹNIEJSZY odczyt mieści się w progach i jest AKTUALNY (nie
///   starszy niż ważność pomiaru, domyślnie 30 min — wartość przyjęta);
///   brak albo nieaktualny odczyt nigdy nie daje zielonego stanu;
/// * protokół z innego dnia niż dziś nigdy nie jest zielony;
/// * odczyt STOP wpisany PÓŹNIEJ niż najpóźniejszy w czasie blokuje zieleń
///   (wpis z późniejszą godziną nie przykryje świeżego alarmu);
/// * brak progu → ocena względem twardej granicy: przekroczenie = STOP;
/// * tlen poniżej dolnego progu = STOP (niedotlenienie — argon, CO₂, azot
///   wypierają tlen); powyżej górnego = STOP (wzbogacenie tlenem — pożar);
/// * odczyt gazu, którego pozwolenie nie wymaga, też może dać STOP;
/// * „najpóźniejszy” liczy się z dokładnością do minuty: kilka odczytów
///   tego samego gazu z tej samej minuty to remis — decyduje GORSZY
///   (przy równej randze dalej od progu), a ocena zgłasza remis
///   ([CsGasVerdict.tie]);
/// * „nie dotyczy” tylko przy punktach, które na to pozwalają; zaznaczenia
///   nieznanych punktów są pomijane;
/// * duplikat „jak wczoraj” kopiuje dane organizacyjne i progi, NIGDY
///   pomiarów ani zaznaczeń; wymagane gazy wracają do czterech;
/// * pomiary i protokoły nieczytelne przy odczycie są liczone
///   ([ConfinedSpaceParse]) — warstwa zapisu robi kopię surowego tekstu
///   i ekran pokazuje baner.
///
/// Czysty Dart.
library;

import '../hot_work/hot_work_permit.dart' show hotWorkDate;
import 'confined_space_checklist.dart';
import 'confined_space_gas.dart';
import 'confined_space_sources.dart';

/// Rodzaj pracy w środku — wybiera ostrzeżenia dla spawacza.
enum CsProcess {
  tig('TIG (argon)', 'TIG (argon)'),
  migMag('MIG/MAG (Ar, CO₂, mieszanki)', 'MIG/MAG (Ar, CO₂, mixes)'),
  mma('MMA (elektroda otulona)', 'MMA (stick)'),
  purge('Formowanie gazem obojętnym', 'Inert gas purging'),
  oxyFuel('Palnik gazowy (cięcie, grzanie)', 'Oxy-fuel (cutting, heating)'),
  plasma('Plazma / żłobienie', 'Plasma / gouging'),
  grinding('Szlifowanie', 'Grinding'),
  inspection('Tylko wejście (oględziny, montaż)',
      'Entry only (inspection, fitting)');

  const CsProcess(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;
  String label({required bool en}) => en ? labelEn : labelPl;

  static CsProcess? byName(Object? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// Ocena jednego gazu wg jego najpóźniejszych odczytów.
class CsGasVerdict {
  final CsGas gas;

  /// Pozwolenie wymaga odczytu tego gazu.
  final bool isRequired;

  /// Odczyty z najpóźniejszej minuty (pusta lista = brak odczytu).
  final List<CsMeasurement> latest;

  /// Odczyt decydujący (najgorszy z [latest] albo STOP wpisany później)
  /// albo `null`.
  final CsMeasurement? decisive;
  final CsReadingState? state;

  /// Najpóźniejszy odczyt jest starszy niż ważność pomiaru (albo z
  /// przyszłości) — liczy się jak brak pomiaru.
  final bool stale;

  /// Decyduje odczyt STOP wpisany PÓŹNIEJ niż najpóźniejszy w czasie.
  final bool enteredLater;

  const CsGasVerdict({
    required this.gas,
    required this.isRequired,
    required this.latest,
    required this.decisive,
    required this.state,
    this.stale = false,
    this.enteredLater = false,
  });

  bool get missing => decisive == null;
  bool get stop => state?.stop ?? false;
  bool get noLimit => state == CsReadingState.noLimit;

  /// Kilka różnych odczytów z tej samej (najpóźniejszej) minuty — kolejność
  /// nie rozstrzyga; ocena bierze gorszy i mówi to wprost.
  bool get tie {
    if (latest.length < 2) return false;
    final vs = {for (final m in latest) csCanonical(gas, m[gas]!)};
    return vs.length > 1;
  }

  CsQty? get value => decisive?[gas];
}

/// Wynik oceny — co blokuje zielony stan.
enum CsReadiness {
  /// Odczyt gazu poza progiem — NIE wchodzić / wyjść.
  stop,

  /// Protokół z innego dnia niż dziś — nigdy zielony.
  otherDay,

  /// Brak aktualnego odczytu wymaganego gazu (brak albo nieaktualny).
  noMeasurement,

  /// Brak progu dla ocenianego gazu.
  noLimit,

  /// Nie wszystkie punkty „przed wejściem” są odhaczone.
  incomplete,

  /// Przygotowanie kompletne, atmosfera w progach.
  ready,
}

class CsAssessment {
  final List<ConfinedSpaceCheck> openBefore;
  final List<ConfinedSpaceCheck> openDuring;
  final List<ConfinedSpaceCheck> openAfter;

  /// Oceny gazów w kolejności [CsGas.values].
  final List<CsGasVerdict> gases;

  /// Data protokołu i „dziś” w chwili oceny (`YYYY-MM-DD`).
  final String recordDate;
  final String today;

  /// Ważność pomiaru użyta w ocenie (min).
  final int maxAgeMin;

  const CsAssessment({
    required this.openBefore,
    required this.openDuring,
    required this.openAfter,
    required this.gases,
    required this.recordDate,
    required this.today,
    required this.maxAgeMin,
  });

  CsGasVerdict verdict(CsGas g) => gases.firstWhere((v) => v.gas == g);

  /// Protokół z innego dnia niż dziś.
  bool get otherDay => recordDate != today;

  /// Gazy oceniane: wymagane albo z odczytem.
  Iterable<CsGasVerdict> get _evaluated =>
      gases.where((v) => v.isRequired || !v.missing);

  List<CsGasVerdict> get stops => [for (final v in gases) if (v.stop) v];
  List<CsGasVerdict> get missing =>
      [for (final v in gases) if (v.isRequired && v.missing) v];

  /// Wymagane gazy z nieaktualnym (za starym) najpóźniejszym odczytem.
  List<CsGasVerdict> get stale => [
        for (final v in gases)
          if (v.isRequired && !v.missing && !v.stop && v.stale) v,
      ];
  List<CsGasVerdict> get noLimits =>
      [for (final v in _evaluated) if (v.noLimit) v];
  List<CsGasVerdict> get ties => [for (final v in gases) if (v.tie) v];

  CsReadiness get readiness {
    if (stops.isNotEmpty) return CsReadiness.stop;
    if (otherDay) return CsReadiness.otherDay;
    if (missing.isNotEmpty || stale.isNotEmpty) {
      return CsReadiness.noMeasurement;
    }
    if (noLimits.isNotEmpty) return CsReadiness.noLimit;
    if (openBefore.isNotEmpty) return CsReadiness.incomplete;
    return CsReadiness.ready;
  }

  /// Zielony stan: dziś, wszystko „przed wejściem” gotowe i aktualne
  /// odczyty w progach.
  bool get readyToEnter => readiness == CsReadiness.ready;

  /// Praca zamknięta: wszystkie punkty odhaczone, odczyty wymaganych gazów
  /// były w progach (bez STOP). Wiek pomiaru nie ma tu znaczenia — po
  /// wyjściu nikt już nie mierzy; protokół z innego dnia jest zamknięty,
  /// ale „nieaktualny” (nigdy zielony — zob. [otherDay]).
  bool get closed =>
      openBefore.isEmpty &&
      openDuring.isEmpty &&
      openAfter.isEmpty &&
      stops.isEmpty &&
      missing.isEmpty &&
      noLimits.isEmpty;
}

/// Ranga stanu w remisie: STOP przed brakiem progu, brak progu przed OK.
int _rank(CsReadingState s) => switch (s) {
      CsReadingState.low || CsReadingState.high => 2,
      CsReadingState.noLimit => 1,
      CsReadingState.ok => 0,
    };

/// Czy odczyt [a] jest gorszy od [b] (ta sama ranga): dalej od progu —
/// najniższy tlen (przy wzbogaceniu najwyższy), najwyższe DGW / CO / H₂S
/// w jednostce kanonicznej.
bool _worse(CsGas gas, CsMeasurement a, CsReadingState sa, CsMeasurement b,
    CsReadingState sb) {
  if (_rank(sa) != _rank(sb)) return _rank(sa) > _rank(sb);
  final va = csCanonical(gas, a[gas]!);
  final vb = csCanonical(gas, b[gas]!);
  if (gas == CsGas.o2 && sa != CsReadingState.high) return va < vb;
  return va > vb;
}

/// Ocena gazu [gas] na podstawie [measurements] w chwili [now].
CsGasVerdict csGasVerdict(
  CsGas gas,
  List<CsMeasurement> measurements,
  CsLimits limits, {
  required bool isRequired,
  required DateTime now,
  int maxAgeMin = kCsMeasurementMaxAgeMin,
}) {
  final withGas = [for (final m in measurements) if (m[gas] != null) m];
  if (withGas.isEmpty) {
    return CsGasVerdict(
        gas: gas,
        isRequired: isRequired,
        latest: const [],
        decisive: null,
        state: null);
  }
  final last = withGas.map((m) => m.minute).reduce((a, b) => a > b ? a : b);
  final latest = csMeasurementsChrono(
      [for (final m in withGas) if (m.minute == last) m]);
  CsMeasurement decisive = latest.first;
  var state = csReadingState(gas, decisive[gas]!, limits);
  for (final m in latest.skip(1)) {
    final s = csReadingState(gas, m[gas]!, limits);
    if (_worse(gas, m, s, decisive, state)) {
      decisive = m;
      state = s;
    }
  }
  // Odczyt STOP wpisany PÓŹNIEJ niż najpóźniejsze w czasie — np. o 14:00
  // wpis z godziną 14:05 (OK), o 14:02 prawdziwy alarm O₂ 17 %. Zaległy
  // wpis nie może przykryć świeżego alarmu.
  var enteredLater = false;
  if (!state.stop) {
    // Chwila wpisu z przyszłości (przestawiony zegar) nie liczy się — inaczej
    // dobry pomiar z „jutrzejszym” wpisem wyłączyłby tę blokadę.
    final lastEntered = latest
        .map((m) => m.enteredAsOf(now))
        .reduce((a, b) => a > b ? a : b);
    for (final m in withGas) {
      if (m.enteredAsOf(now) <= lastEntered) continue;
      final s = csReadingState(gas, m[gas]!, limits);
      if (!s.stop) continue;
      if (!enteredLater || _worse(gas, m, s, decisive, state)) {
        decisive = m;
        state = s;
        enteredLater = true;
      }
    }
  }
  return CsGasVerdict(
    gas: gas,
    isRequired: isRequired,
    latest: latest,
    decisive: decisive,
    state: state,
    stale: !csMeasurementFresh(latest.first, now, maxAgeMin),
    enteredLater: enteredLater,
  );
}

/// Wartość „bez zmian” dla pól, które mogą być `null` w copyWith.
const Object _keep = Object();

/// Domyślnie wymagane gazy (detektor czterogazowy).
const Set<CsGas> kCsDefaultRequired = {
  CsGas.o2,
  CsGas.lel,
  CsGas.co,
  CsGas.h2s,
};

class ConfinedSpaceRecord {
  final String id;

  /// Numer pozwolenia nadany przez zakład (jeśli jest).
  final String permitNo;

  /// Przestrzeń: zbiornik / aparat / rurociąg / studzienka, właz.
  final String location;
  final String description;
  final Set<CsProcess> processes;

  /// Data `YYYY-MM-DD` i godziny ważności `HH:mm` (puste = nie wpisano).
  final String date;
  final String validFrom;
  final String validTo;

  /// Wchodzący (osoby pracujące w środku).
  final String entrants;

  /// Osoba asekurująca na zewnątrz.
  final String attendant;

  /// Osoba kierująca / nadzór.
  final String supervisor;

  /// Wydający pozwolenie.
  final String issuer;

  /// Plan ratunkowy: kto, czym, jaki numer (np. „straż zakładowa, trójnóg”).
  final String rescue;

  final CsLimits limits;

  /// Ważność pomiaru z pozwolenia (min); `null` = przyjęta w aplikacji
  /// [kCsMeasurementMaxAgeMin]. Wolno tylko skrócić.
  final int? maxAgeMin;

  /// Gazy, których odczyt jest wymagany (tlen i palne zawsze).
  final Set<CsGas> requiredGases;
  final List<CsMeasurement> measurements;

  /// Identyfikatory odhaczonych punktów i punktów „nie dotyczy”.
  final Set<String> checked;
  final Set<String> na;
  final String notes;
  final int createdAt;
  final int updatedAt;

  /// Ile pomiarów tego protokołu odrzucono przy odczycie (nie zapisywane).
  final int droppedOnLoad;

  ConfinedSpaceRecord({
    required this.id,
    this.permitNo = '',
    this.location = '',
    this.description = '',
    this.processes = const {},
    required this.date,
    this.validFrom = '',
    this.validTo = '',
    this.entrants = '',
    this.attendant = '',
    this.supervisor = '',
    this.issuer = '',
    this.rescue = '',
    CsLimits? limits,
    int? maxAgeMin,
    Set<CsGas> requiredGases = kCsDefaultRequired,
    this.measurements = const [],
    this.checked = const {},
    this.na = const {},
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.droppedOnLoad = 0,
  })  : limits = limits ?? CsLimits.defaults,
        maxAgeMin =
            maxAgeMin != null && csMaxAgeValid(maxAgeMin) ? maxAgeMin : null,
        requiredGases = {
          ...requiredGases,
          for (final g in CsGas.values)
            if (g.alwaysRequired) g,
        };

  /// Nowy, pusty protokół na dziś.
  factory ConfinedSpaceRecord.blank(
          {required String id, required DateTime now}) =>
      ConfinedSpaceRecord(
        id: id,
        date: hotWorkDate(now),
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  /// Ważność pomiaru użyta w ocenie (min).
  int get effectiveMaxAgeMin => maxAgeMin ?? kCsMeasurementMaxAgeMin;

  /// Nic nie wpisano ani nie odhaczono — takiego protokołu nie zapisujemy.
  bool get isBlank =>
      permitNo.trim().isEmpty &&
      location.trim().isEmpty &&
      description.trim().isEmpty &&
      processes.isEmpty &&
      validFrom.isEmpty &&
      validTo.isEmpty &&
      entrants.trim().isEmpty &&
      attendant.trim().isEmpty &&
      supervisor.trim().isEmpty &&
      issuer.trim().isEmpty &&
      rescue.trim().isEmpty &&
      limits.isDefault &&
      maxAgeMin == null &&
      requiredGases.length == kCsDefaultRequired.length &&
      measurements.isEmpty &&
      checked.isEmpty &&
      na.isEmpty &&
      notes.trim().isEmpty;

  bool isChecked(ConfinedSpaceCheck c) => checked.contains(c.id);

  /// „Nie dotyczy” — tylko przy punktach, które na to pozwalają.
  bool isNa(ConfinedSpaceCheck c) => c.naAllowed && na.contains(c.id);

  bool isSettled(ConfinedSpaceCheck c) => isChecked(c) || isNa(c);

  /// Pomiary od najwcześniejszego do najpóźniejszego.
  List<CsMeasurement> get measurementsChrono =>
      csMeasurementsChrono(measurements);

  /// Ocena w chwili [now]: wiek pomiarów i data protokołu liczą się
  /// względem tej chwili.
  CsAssessment assess({required DateTime now}) {
    List<ConfinedSpaceCheck> open(ConfinedSpacePhase p) => [
          for (final c in confinedSpaceChecksIn(p))
            if (!isSettled(c)) c,
        ];
    return CsAssessment(
      openBefore: open(ConfinedSpacePhase.before),
      openDuring: open(ConfinedSpacePhase.during),
      openAfter: open(ConfinedSpacePhase.after),
      gases: [
        for (final g in CsGas.values)
          csGasVerdict(g, measurements, limits,
              isRequired: requiredGases.contains(g),
              now: now,
              maxAgeMin: effectiveMaxAgeMin),
      ],
      recordDate: date,
      today: hotWorkDate(now),
      maxAgeMin: effectiveMaxAgeMin,
    );
  }

  /// Przełącza „sprawdzone”; odhaczenie zdejmuje „n/d”.
  ConfinedSpaceRecord toggleChecked(String checkId) {
    if (confinedSpaceCheckById(checkId) == null) return this;
    final c = {...checked};
    final n = {...na};
    if (!c.remove(checkId)) {
      c.add(checkId);
      n.remove(checkId);
    }
    return copyWith(checked: c, na: n);
  }

  /// Przełącza „nie dotyczy” (tylko punkty z naAllowed); „n/d” zdejmuje
  /// odhaczenie.
  ConfinedSpaceRecord toggleNa(String checkId) {
    final check = confinedSpaceCheckById(checkId);
    if (check == null || !check.naAllowed) return this;
    final c = {...checked};
    final n = {...na};
    if (!n.remove(checkId)) {
      n.add(checkId);
      c.remove(checkId);
    }
    return copyWith(checked: c, na: n);
  }

  /// Włącza / wyłącza wymaganie odczytu gazu. Tlenu i palnych nie da się
  /// wyłączyć.
  ConfinedSpaceRecord withRequired(CsGas gas, bool on) {
    if (gas.alwaysRequired) return this;
    final r = {...requiredGases};
    on ? r.add(gas) : r.remove(gas);
    return copyWith(requiredGases: r);
  }

  /// Dopisuje pomiar (lista w kolejności czasu).
  ConfinedSpaceRecord addMeasurement(CsMeasurement m) =>
      copyWith(measurements: csMeasurementsChrono([...measurements, m]));

  /// Przywraca usunięty pomiar („Cofnij”) po IDENTYFIKATORZE — dwa
  /// identyczne odczyty to dwa pomiary. Jeśli pomiar o tym identyfikatorze
  /// już jest — bez zmian (cofnięcie dwa razy nie dubluje).
  ConfinedSpaceRecord restoreMeasurement(CsMeasurement m) {
    if (m.id.isEmpty) return addMeasurement(m);
    return measurements.any((x) => x.id == m.id) ? this : addMeasurement(m);
  }

  /// Usuwa pomiar po identyfikatorze (stare zapisy bez niego — po
  /// tożsamości obiektu).
  ConfinedSpaceRecord removeMeasurement(CsMeasurement m) {
    final i = m.id.isEmpty
        ? measurements.indexWhere((x) => identical(x, m))
        : measurements.indexWhere((x) => x.id == m.id);
    if (i < 0) return this;
    return copyWith(measurements: [...measurements]..removeAt(i));
  }

  /// Kopia na nowy dzień („jak wczoraj”): przestrzeń, opis, rodzaj pracy,
  /// osoby, plan ratunkowy, godziny, progi i ważność pomiaru zostają.
  /// Pomiary, zaznaczenia, numer pozwolenia i uwagi — NIE: atmosfera
  /// i stanowisko sprawdza się na nowo, zakład wydaje nowe pozwolenie.
  /// Wymagane gazy wracają do wszystkich czterech — wyłączenie gazu to
  /// świadoma decyzja na dany dzień.
  ConfinedSpaceRecord duplicateFor(
          {required String newId, required DateTime now}) =>
      ConfinedSpaceRecord(
        id: newId,
        location: location,
        description: description,
        processes: processes,
        date: hotWorkDate(now),
        validFrom: validFrom,
        validTo: validTo,
        entrants: entrants,
        attendant: attendant,
        supervisor: supervisor,
        issuer: issuer,
        rescue: rescue,
        limits: limits,
        maxAgeMin: maxAgeMin,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  ConfinedSpaceRecord copyWith({
    String? permitNo,
    String? location,
    String? description,
    Set<CsProcess>? processes,
    String? date,
    String? validFrom,
    String? validTo,
    String? entrants,
    String? attendant,
    String? supervisor,
    String? issuer,
    String? rescue,
    CsLimits? limits,
    Object? maxAgeMin = _keep,
    Set<CsGas>? requiredGases,
    List<CsMeasurement>? measurements,
    Set<String>? checked,
    Set<String>? na,
    String? notes,
    int? updatedAt,
    Object? droppedOnLoad = _keep,
  }) =>
      ConfinedSpaceRecord(
        id: id,
        permitNo: permitNo ?? this.permitNo,
        location: location ?? this.location,
        description: description ?? this.description,
        processes: processes ?? this.processes,
        date: date ?? this.date,
        validFrom: validFrom ?? this.validFrom,
        validTo: validTo ?? this.validTo,
        entrants: entrants ?? this.entrants,
        attendant: attendant ?? this.attendant,
        supervisor: supervisor ?? this.supervisor,
        issuer: issuer ?? this.issuer,
        rescue: rescue ?? this.rescue,
        limits: limits ?? this.limits,
        maxAgeMin:
            identical(maxAgeMin, _keep) ? this.maxAgeMin : maxAgeMin as int?,
        requiredGases: requiredGases ?? this.requiredGases,
        measurements: measurements ?? this.measurements,
        checked: checked ?? this.checked,
        na: na ?? this.na,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        droppedOnLoad: identical(droppedOnLoad, _keep)
            ? this.droppedOnLoad
            : droppedOnLoad as int,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'permitNo': permitNo,
        'location': location,
        'description': description,
        'processes': [
          for (final p in CsProcess.values)
            if (processes.contains(p)) p.name
        ],
        'date': date,
        'validFrom': validFrom,
        'validTo': validTo,
        'entrants': entrants,
        'attendant': attendant,
        'supervisor': supervisor,
        'issuer': issuer,
        'rescue': rescue,
        'limits': limits.toJson(),
        if (maxAgeMin != null) 'maxAgeMin': maxAgeMin,
        'required': [
          for (final g in CsGas.values)
            if (requiredGases.contains(g)) g.name
        ],
        'measurements': [for (final m in measurements) m.toJson()],
        // Kolejność listy kontrolnej — stabilny zapis i czytelny diff.
        'checked': [
          for (final c in kConfinedSpaceChecks)
            if (checked.contains(c.id)) c.id
        ],
        'na': [
          for (final c in kConfinedSpaceChecks)
            if (na.contains(c.id) && c.naAllowed) c.id
        ],
        'notes': notes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Odczyt z JSON. `null` dla wpisu bez identyfikatora albo daty.
  /// Uszkodzone pomiary — a przy podanym [now] także pomiary z przyszłości
  /// (dalej niż [kCsFutureSlack]) — są pomijane i liczone w
  /// [droppedOnLoad]. Pomiary bez identyfikatora dostają go z pozycji.
  static ConfinedSpaceRecord? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;
    if (raw.containsKey('v') && raw['v'] != 1) return null;
    final id = _s(raw['id']);
    final date = _s(raw['date']);
    if (id.isEmpty || date.isEmpty) return null;
    final rawMeasurements = _list(raw['measurements']);
    final measurements = <CsMeasurement>[];
    for (final (i, e) in rawMeasurements.indexed) {
      final m = CsMeasurement.fromJson(e, now: now);
      if (m == null) continue;
      measurements.add(m.id.isEmpty ? m.withId('$id-m$i') : m);
    }
    final rawRequired = raw['required'];
    final maxAge = raw['maxAgeMin'];
    return ConfinedSpaceRecord(
      id: id,
      permitNo: _s(raw['permitNo']),
      location: _s(raw['location']),
      description: _s(raw['description']),
      processes: {
        for (final n in _list(raw['processes']))
          if (CsProcess.byName(n) != null) CsProcess.byName(n)!,
      },
      date: date,
      validFrom: _s(raw['validFrom']),
      validTo: _s(raw['validTo']),
      entrants: _s(raw['entrants']),
      attendant: _s(raw['attendant']),
      supervisor: _s(raw['supervisor']),
      issuer: _s(raw['issuer']),
      rescue: _s(raw['rescue']),
      limits: CsLimits.fromJson(raw['limits']),
      // Zły zapis ważności → przyjęta w aplikacji (nigdy dłuższa).
      maxAgeMin: maxAge is int ? maxAge : null,
      // Brak listy (uszkodzony zapis) → wszystkie gazy wymagane.
      requiredGases: rawRequired is List
          ? {
              for (final n in rawRequired)
                if (CsGas.byName(n) != null) CsGas.byName(n)!,
            }
          : kCsDefaultRequired,
      measurements: csMeasurementsChrono(measurements),
      checked: {
        for (final c in _list(raw['checked']))
          if (c is String && confinedSpaceCheckById(c) != null) c,
      },
      na: {
        for (final c in _list(raw['na']))
          if (c is String && (confinedSpaceCheckById(c)?.naAllowed ?? false))
            c,
      },
      notes: _s(raw['notes']),
      createdAt: _i(raw['createdAt']),
      updatedAt: _i(raw['updatedAt']),
      droppedOnLoad: rawMeasurements.length - measurements.length,
    );
  }
}

/// Ważność pomiaru (min), którą aplikacja przyjmuje: 1 … przyjęta
/// [kCsMeasurementMaxAgeMin] — dłużej nie wolno.
bool csMaxAgeValid(int min) => min >= 1 && min <= kCsMeasurementMaxAgeMin;

/// Wynik odczytu listy protokołów: ile protokołów i pomiarów odrzucono.
class ConfinedSpaceParse {
  final List<ConfinedSpaceRecord> records;
  final int droppedRecords;
  final int droppedMeasurements;
  const ConfinedSpaceParse(
      this.records, this.droppedRecords, this.droppedMeasurements);

  bool get damaged => droppedRecords > 0 || droppedMeasurements > 0;
}

/// Lista protokołów z JSON (historia). Uszkodzone wpisy i pomiary (także
/// z przyszłości względem [now]) są pomijane, ale LICZONE — zapis robi
/// kopię, ekran pokazuje baner.
ConfinedSpaceParse confinedSpaceRecordsFromJson(Object? raw,
    {DateTime? now}) {
  if (raw is! List) throw const FormatException('not a list');
  final records = <ConfinedSpaceRecord>[];
  var droppedRecords = 0;
  var droppedMeasurements = 0;
  for (final e in raw) {
    final r = ConfinedSpaceRecord.fromJson(e, now: now);
    if (r == null) {
      droppedRecords++;
    } else {
      records.add(r);
      droppedMeasurements += r.droppedOnLoad;
    }
  }
  return ConfinedSpaceParse(records, droppedRecords, droppedMeasurements);
}

List<Map<String, Object?>> confinedSpaceRecordsToJson(
        List<ConfinedSpaceRecord> list) =>
    [for (final r in list) r.toJson()];

String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
List<Object?> _list(Object? v) => v is List ? v : const [];

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
///   NAJPÓŹNIEJSZY odczyt mieści się w progach; brak odczytu nigdy nie
///   daje zielonego stanu;
/// * tlen poniżej dolnego progu = STOP (niedotlenienie — argon, CO₂, azot
///   wypierają tlen); powyżej górnego = STOP (wzbogacenie tlenem — pożar);
/// * odczyt gazu, którego pozwolenie nie wymaga, też może dać STOP;
/// * „najpóźniejszy” liczy się z dokładnością do minuty: kilka odczytów
///   tego samego gazu z tej samej minuty to remis — decyduje GORSZY,
///   a ocena zgłasza remis ([CsGasVerdict.tie]);
/// * „nie dotyczy” tylko przy punktach, które na to pozwalają; zaznaczenia
///   nieznanych punktów są pomijane;
/// * duplikat „jak wczoraj” kopiuje dane organizacyjne i progi, NIGDY
///   pomiarów ani zaznaczeń;
/// * pomiary i protokoły nieczytelne przy odczycie są liczone
///   ([ConfinedSpaceParse]) — warstwa zapisu robi kopię surowego tekstu
///   i ekran pokazuje baner.
///
/// Czysty Dart.
library;

import '../hot_work/hot_work_permit.dart' show hotWorkDate;
import 'confined_space_checklist.dart';
import 'confined_space_gas.dart';

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

  /// Odczyt decydujący (najgorszy z [latest]) albo `null`.
  final CsMeasurement? decisive;
  final CsReadingState? state;

  const CsGasVerdict({
    required this.gas,
    required this.isRequired,
    required this.latest,
    required this.decisive,
    required this.state,
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

  /// Brak odczytu wymaganego gazu.
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

  const CsAssessment({
    required this.openBefore,
    required this.openDuring,
    required this.openAfter,
    required this.gases,
  });

  CsGasVerdict verdict(CsGas g) => gases.firstWhere((v) => v.gas == g);

  /// Gazy oceniane: wymagane albo z odczytem.
  Iterable<CsGasVerdict> get _evaluated =>
      gases.where((v) => v.isRequired || !v.missing);

  List<CsGasVerdict> get stops => [for (final v in gases) if (v.stop) v];
  List<CsGasVerdict> get missing =>
      [for (final v in gases) if (v.isRequired && v.missing) v];
  List<CsGasVerdict> get noLimits =>
      [for (final v in _evaluated) if (v.noLimit) v];
  List<CsGasVerdict> get ties => [for (final v in gases) if (v.tie) v];

  CsReadiness get readiness {
    if (stops.isNotEmpty) return CsReadiness.stop;
    if (missing.isNotEmpty) return CsReadiness.noMeasurement;
    if (noLimits.isNotEmpty) return CsReadiness.noLimit;
    if (openBefore.isNotEmpty) return CsReadiness.incomplete;
    return CsReadiness.ready;
  }

  /// Zielony stan: wszystko „przed wejściem” gotowe i atmosfera w progach.
  bool get readyToEnter => readiness == CsReadiness.ready;

  /// Praca zamknięta: gotowe + odhaczone punkty „w trakcie” i „po”.
  bool get closed =>
      readyToEnter && openDuring.isEmpty && openAfter.isEmpty;
}

/// Ocena gazu [gas] na podstawie [measurements].
CsGasVerdict csGasVerdict(CsGas gas, List<CsMeasurement> measurements,
    CsLimits limits, {required bool isRequired}) {
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
  // Najgorszy z remisu: STOP przed brakiem progu, brak progu przed OK.
  int rank(CsReadingState s) => switch (s) {
        CsReadingState.low || CsReadingState.high => 2,
        CsReadingState.noLimit => 1,
        CsReadingState.ok => 0,
      };
  CsMeasurement decisive = latest.first;
  var state = csReadingState(gas, decisive[gas]!, limits);
  for (final m in latest.skip(1)) {
    final s = csReadingState(gas, m[gas]!, limits);
    if (rank(s) > rank(state)) {
      decisive = m;
      state = s;
    }
  }
  return CsGasVerdict(
    gas: gas,
    isRequired: isRequired,
    latest: latest,
    decisive: decisive,
    state: state,
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
    Set<CsGas> requiredGases = kCsDefaultRequired,
    this.measurements = const [],
    this.checked = const {},
    this.na = const {},
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.droppedOnLoad = 0,
  })  : limits = limits ?? CsLimits.defaults,
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

  CsAssessment assess() {
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
              isRequired: requiredGases.contains(g)),
      ],
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

  /// Przywraca usunięty pomiar („Cofnij”) — jeśli już jest, bez zmian.
  ConfinedSpaceRecord restoreMeasurement(CsMeasurement m) =>
      measurements.contains(m) ? this : addMeasurement(m);

  ConfinedSpaceRecord removeMeasurement(CsMeasurement m) {
    final i = measurements.indexOf(m);
    if (i < 0) return this;
    return copyWith(measurements: [...measurements]..removeAt(i));
  }

  /// Kopia na nowy dzień („jak wczoraj”): przestrzeń, opis, rodzaj pracy,
  /// osoby, plan ratunkowy, godziny, progi i wymagane gazy zostają.
  /// Pomiary, zaznaczenia, numer pozwolenia i uwagi — NIE: atmosfera
  /// i stanowisko sprawdza się na nowo, zakład wydaje nowe pozwolenie.
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
        requiredGases: requiredGases,
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
  /// Uszkodzone pomiary są pomijane i liczone w [droppedOnLoad].
  static ConfinedSpaceRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    final date = _s(raw['date']);
    if (id.isEmpty || date.isEmpty) return null;
    final rawMeasurements = _list(raw['measurements']);
    final measurements = [
      for (final m in rawMeasurements)
        if (CsMeasurement.fromJson(m) != null) CsMeasurement.fromJson(m)!,
    ];
    final rawRequired = raw['required'];
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

/// Wynik odczytu listy protokołów: ile protokołów i pomiarów odrzucono.
class ConfinedSpaceParse {
  final List<ConfinedSpaceRecord> records;
  final int droppedRecords;
  final int droppedMeasurements;
  const ConfinedSpaceParse(
      this.records, this.droppedRecords, this.droppedMeasurements);

  bool get damaged => droppedRecords > 0 || droppedMeasurements > 0;
}

/// Lista protokołów z JSON (historia). Uszkodzone wpisy i pomiary są
/// pomijane, ale LICZONE — zapis robi kopię, ekran pokazuje baner.
ConfinedSpaceParse confinedSpaceRecordsFromJson(Object? raw) {
  if (raw is! List) throw const FormatException('not a list');
  final records = <ConfinedSpaceRecord>[];
  var droppedRecords = 0;
  var droppedMeasurements = 0;
  for (final e in raw) {
    final r = ConfinedSpaceRecord.fromJson(e);
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

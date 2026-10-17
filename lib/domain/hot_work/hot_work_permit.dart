/// Protokół przygotowania stanowiska do prac niebezpiecznych pod względem
/// pożarowym (spawanie, cięcie, szlifowanie…) — dane do zapisu, ocena
/// gotowości i duplikat „jak wczoraj”.
///
/// To POMOC dla spawacza i nadzoru, nie urzędowy dokument: wiążące jest
/// pisemne zezwolenie wystawione przez zakład, jego instrukcja
/// bezpieczeństwa pożarowego i przepisy (zob. [hotWorkDisclaimer]).
///
/// Zasady bezpieczeństwa zapisane w kodzie (i w testach):
/// * zielony stan („gotowe do rozpoczęcia”) wymaga odhaczenia wszystkich
///   punktów „przed rozpoczęciem”, WPISANEGO wyniku pomiaru atmosfery
///   i dopuszczalnego % DGW (domyślnie 10 % — rozp. MSWiA § 36 ust. 2,
///   zob. hot_work_sources.dart; zakład może wymagać mniej) — brak pomiaru
///   nigdy nie daje zielonego stanu;
/// * „nie dotyczy” liczy się tylko przy punktach, które na to pozwalają
///   ([HotWorkCheck.naAllowed]); zapis z innym „n/d” nie zwalnia punktu;
/// * zaznaczenia nieznanych punktów (stary zapis, zmieniona lista) są
///   pomijane — nie mogą udawać odhaczonego punktu;
/// * duplikat „jak wczoraj” kopiuje dane organizacyjne, ale NIGDY
///   zaznaczeń ani pomiarów — stanowisko sprawdza się na nowo.
///
/// Czysty Dart: bez Fluttera i bez bazy (zapis w SharedPreferences robi
/// warstwa ekranu).
library;

import 'hot_work_checklist.dart';
import 'hot_work_sources.dart';

/// Rodzaj pracy z ogniem / iskrą.
enum HotWorkType {
  welding('Spawanie', 'Welding'),
  cutting('Cięcie', 'Cutting'),
  grinding('Szlifowanie', 'Grinding'),
  brazing('Lutowanie', 'Brazing / soldering'),
  other('Inne', 'Other');

  const HotWorkType(this.labelPl, this.labelEn);
  final String labelPl;
  final String labelEn;

  String label({required bool en}) => en ? labelEn : labelPl;

  static HotWorkType? byName(Object? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Jeden pomiar stężenia gazów / par palnych (eksplozymetr).
class HotWorkMeasurement {
  /// Godzina pomiaru `HH:mm`.
  final String time;

  /// Chwila pomiaru (ms od epoki) — o stanie decyduje pomiar
  /// NAJPÓŹNIEJSZY w czasie, nie ostatnio dopisany (zaległy pomiar 0 %
  /// z 09:00 nie może zdjąć STOP-u z pomiaru 15 % z 10:30). `null` tylko
  /// w zapisach sprzed tego pola — wtedy liczy się kolejność wpisów.
  final int? at;

  /// Wynik w % DGW (dolnej granicy wybuchowości, ang. % LEL).
  final double dgwPct;

  /// Miejsce / uwagi (np. „studzienka K-3”, „O₂ 20,9 %”).
  final String note;

  const HotWorkMeasurement({
    required this.time,
    this.at,
    required this.dgwPct,
    this.note = '',
  });

  Map<String, Object?> toJson() => {
        'time': time,
        if (at != null) 'at': at,
        'dgw': dgwPct,
        'note': note,
      };

  /// `null`, gdy wpis jest uszkodzony (bez wyniku albo wynik ujemny).
  static HotWorkMeasurement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['dgw'];
    if (v is! num || !v.isFinite || v < 0) return null;
    final at = raw['at'];
    return HotWorkMeasurement(
      time: _s(raw['time']),
      at: at is num && at.isFinite ? at.toInt() : null,
      dgwPct: v.toDouble(),
      note: _s(raw['note']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HotWorkMeasurement &&
      other.time == time &&
      other.at == at &&
      other.dgwPct == dgwPct &&
      other.note == note;

  @override
  int get hashCode => Object.hash(time, at, dgwPct, note);
}

/// Chwila pomiaru o godzinie [hhmm] wpisanej przy [now]: ostatnie takie
/// wystąpienie nie później niż 5 min po [now] (zapas na różnicę zegarów).
/// Godzina „z przyszłości” to wczoraj — np. 23:50 wpisane o 00:12 (zmiana
/// nocna); godzina tuż po północy wpisana przed północą (00:03 o 23:58)
/// mieści się w zapasie 5 min — to jutro, nie doba wstecz. Zła godzina →
/// [now].
DateTime hotWorkMeasurementAt(String hhmm, DateTime now) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return now;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return now;
  final limit = now.add(const Duration(minutes: 5));
  final tomorrow = DateTime(now.year, now.month, now.day + 1, h, min);
  if (!tomorrow.isAfter(limit)) return tomorrow;
  final today = DateTime(now.year, now.month, now.day, h, min);
  return today.isAfter(limit)
      ? DateTime(now.year, now.month, now.day - 1, h, min)
      : today;
}

/// Pomiary w kolejności czasu (stabilnie). Gdy któryś nie ma chwili
/// pomiaru (stary zapis), zostaje kolejność wpisów.
List<HotWorkMeasurement> hotWorkMeasurementsChrono(
    List<HotWorkMeasurement> list) {
  if (list.any((m) => m.at == null)) return List.unmodifiable(list);
  final indexed = [...list.indexed]..sort((a, b) {
      final byAt = a.$2.at!.compareTo(b.$2.at!);
      return byAt != 0 ? byAt : a.$1.compareTo(b.$1);
    });
  return List.unmodifiable([for (final (_, m) in indexed) m]);
}

/// Dopuszczalne % DGW, które aplikacja przyjmuje: 0–10. Przepis
/// (rozp. MSWiA § 36 ust. 2) nie pozwala na więcej niż 10 % DGW, a zakład
/// może wymagać mniej; wyższa wartość to literówka („100” zamiast „10”)
/// i nie może dawać zielonego stanu.
bool hotWorkLimitValid(double v) =>
    v.isFinite && v >= 0 && v <= kHotWorkDefaultDgwLimitPct;

/// Wynik oceny gotowości — co jeszcze blokuje zielony stan.
enum HotWorkReadiness {
  /// Ostatni pomiar przekracza dopuszczalny % DGW — NIE zaczynać.
  overLimit,

  /// Brak wyniku pomiaru atmosfery.
  noMeasurement,

  /// Brak dopuszczalnego % DGW z zezwolenia — wyniku nie da się ocenić.
  noLimit,

  /// Nie wszystkie punkty „przed rozpoczęciem” są odhaczone.
  incomplete,

  /// Przygotowanie kompletne — można prosić o podpisanie zezwolenia.
  ready,
}

/// Wynik pomiaru mieści się w dopuszczalnym % DGW z zezwolenia.
///
/// Brzmienie jak w rozp. MSWiA z 7.06.2010, § 36 ust. 2: stężenie
/// „nieprzekraczające” progu — wynik równy progowi przechodzi, większy nie.
/// Przy progu 0 % DGW przechodzi tylko wynik 0.
bool hotWorkMeasurementOk(double dgwPct, double limitPct) =>
    dgwPct <= limitPct;

class HotWorkAssessment {
  /// Punkty nieodhaczone (i nie „n/d” tam, gdzie wolno), wg faz.
  final List<HotWorkCheck> openBefore;
  final List<HotWorkCheck> openDuring;
  final List<HotWorkCheck> openAfter;

  /// Najpóźniejszy w czasie pomiar albo `null`.
  final HotWorkMeasurement? lastMeasurement;
  final double? limitPct;

  const HotWorkAssessment({
    required this.openBefore,
    required this.openDuring,
    required this.openAfter,
    required this.lastMeasurement,
    required this.limitPct,
  });

  bool get measurementMissing => lastMeasurement == null;
  bool get limitMissing => limitPct == null;

  bool get overLimit {
    final m = lastMeasurement;
    final l = limitPct;
    if (m == null || l == null) return false;
    return !hotWorkMeasurementOk(m.dgwPct, l);
  }

  HotWorkReadiness get readiness {
    if (overLimit) return HotWorkReadiness.overLimit;
    if (measurementMissing) return HotWorkReadiness.noMeasurement;
    if (limitMissing) return HotWorkReadiness.noLimit;
    if (openBefore.isNotEmpty) return HotWorkReadiness.incomplete;
    return HotWorkReadiness.ready;
  }

  /// Zielony stan: wszystko „przed rozpoczęciem” gotowe i pomiar w normie.
  bool get readyToStart => readiness == HotWorkReadiness.ready;

  /// Praca zamknięta: gotowe + odhaczone punkty „w trakcie” i „po
  /// zakończeniu” (dozór po pracy).
  bool get closed =>
      readyToStart && openDuring.isEmpty && openAfter.isEmpty;
}

/// Wartość „bez zmian” dla pól, które mogą być `null` w [HotWorkPermit.copyWith].
const Object _keep = Object();

class HotWorkPermit {
  final String id;

  /// Numer zezwolenia nadany przez zakład (jeśli jest).
  final String permitNo;
  final String location;
  final String description;
  final Set<HotWorkType> workTypes;

  /// Data pracy `YYYY-MM-DD` i godziny ważności `HH:mm` (puste = nie wpisano).
  final String date;
  final String validFrom;
  final String validTo;

  /// Wykonawca (firma / osoba wykonująca pracę).
  final String contractor;

  /// Osoba odpowiedzialna za zabezpieczenie miejsca pracy.
  final String securedBy;

  /// Dozorujący (fire watch).
  final String fireWatch;

  /// Wystawiający / zatwierdzający zezwolenie.
  final String issuer;

  /// Dopuszczalne % DGW wpisane w zezwoleniu (`null` = nie wpisano).
  final double? dgwLimitPct;
  final List<HotWorkMeasurement> measurements;

  /// Czas dozoru po zakończeniu pracy z zezwolenia, w minutach.
  final int? fireWatchAfterMin;

  /// Identyfikatory odhaczonych punktów i punktów „nie dotyczy”.
  final Set<String> checked;
  final Set<String> na;
  final String notes;
  final int createdAt;
  final int updatedAt;

  const HotWorkPermit({
    required this.id,
    this.permitNo = '',
    this.location = '',
    this.description = '',
    this.workTypes = const {},
    required this.date,
    this.validFrom = '',
    this.validTo = '',
    this.contractor = '',
    this.securedBy = '',
    this.fireWatch = '',
    this.issuer = '',
    this.dgwLimitPct,
    this.measurements = const [],
    this.fireWatchAfterMin,
    this.checked = const {},
    this.na = const {},
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Nowy, pusty protokół na dziś.
  factory HotWorkPermit.blank({required String id, required DateTime now}) =>
      HotWorkPermit(
        id: id,
        date: hotWorkDate(now),
        dgwLimitPct: kHotWorkDefaultDgwLimitPct,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  /// Nic nie wpisano ani nie odhaczono — takiego protokołu nie zapisujemy.
  bool get isBlank =>
      permitNo.trim().isEmpty &&
      location.trim().isEmpty &&
      description.trim().isEmpty &&
      workTypes.isEmpty &&
      validFrom.isEmpty &&
      validTo.isEmpty &&
      contractor.trim().isEmpty &&
      securedBy.trim().isEmpty &&
      fireWatch.trim().isEmpty &&
      issuer.trim().isEmpty &&
      (dgwLimitPct == null || dgwLimitPct == kHotWorkDefaultDgwLimitPct) &&
      measurements.isEmpty &&
      fireWatchAfterMin == null &&
      checked.isEmpty &&
      na.isEmpty &&
      notes.trim().isEmpty;

  bool isChecked(HotWorkCheck c) => checked.contains(c.id);

  /// „Nie dotyczy” — tylko przy punktach, które na to pozwalają.
  bool isNa(HotWorkCheck c) => c.naAllowed && na.contains(c.id);

  bool isSettled(HotWorkCheck c) => isChecked(c) || isNa(c);

  /// Pomiary od najwcześniejszego do najpóźniejszego.
  List<HotWorkMeasurement> get measurementsChrono =>
      hotWorkMeasurementsChrono(measurements);

  HotWorkAssessment assess() {
    List<HotWorkCheck> open(HotWorkPhase p) => [
          for (final c in hotWorkChecksIn(p))
            if (!isSettled(c)) c,
        ];
    final chrono = measurementsChrono;
    final limit = dgwLimitPct;
    return HotWorkAssessment(
      openBefore: open(HotWorkPhase.before),
      openDuring: open(HotWorkPhase.during),
      openAfter: open(HotWorkPhase.after),
      lastMeasurement: chrono.isEmpty ? null : chrono.last,
      limitPct: limit != null && hotWorkLimitValid(limit) ? limit : null,
    );
  }

  /// Przełącza „sprawdzone”; odhaczenie zdejmuje „n/d”.
  HotWorkPermit toggleChecked(String checkId) {
    final c = {...checked};
    final n = {...na};
    if (!c.remove(checkId)) {
      c.add(checkId);
      n.remove(checkId);
    }
    return copyWith(checked: c, na: n);
  }

  /// Przełącza „nie dotyczy” (tylko punkty z [HotWorkCheck.naAllowed]);
  /// „n/d” zdejmuje odhaczenie.
  HotWorkPermit toggleNa(String checkId) {
    final check = hotWorkCheckById(checkId);
    if (check == null || !check.naAllowed) return this;
    final c = {...checked};
    final n = {...na};
    if (!n.remove(checkId)) {
      n.add(checkId);
      c.remove(checkId);
    }
    return copyWith(checked: c, na: n);
  }

  /// Kopia na nowy dzień („jak wczoraj”): miejsce, opis, osoby, godziny
  /// zmiany, rodzaj pracy, dopuszczalne % DGW i czas dozoru zostają.
  /// Zaznaczenia, pomiary, numer zezwolenia i uwagi — NIE: stanowisko
  /// sprawdza się na nowo, a zakład wystawia nowe zezwolenie.
  HotWorkPermit duplicateFor({required String newId, required DateTime now}) =>
      HotWorkPermit(
        id: newId,
        location: location,
        description: description,
        workTypes: workTypes,
        date: hotWorkDate(now),
        validFrom: validFrom,
        validTo: validTo,
        contractor: contractor,
        securedBy: securedBy,
        fireWatch: fireWatch,
        issuer: issuer,
        dgwLimitPct: dgwLimitPct,
        fireWatchAfterMin: fireWatchAfterMin,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
      );

  HotWorkPermit copyWith({
    String? permitNo,
    String? location,
    String? description,
    Set<HotWorkType>? workTypes,
    String? date,
    String? validFrom,
    String? validTo,
    String? contractor,
    String? securedBy,
    String? fireWatch,
    String? issuer,
    Object? dgwLimitPct = _keep,
    List<HotWorkMeasurement>? measurements,
    Object? fireWatchAfterMin = _keep,
    Set<String>? checked,
    Set<String>? na,
    String? notes,
    int? updatedAt,
  }) =>
      HotWorkPermit(
        id: id,
        permitNo: permitNo ?? this.permitNo,
        location: location ?? this.location,
        description: description ?? this.description,
        workTypes: workTypes ?? this.workTypes,
        date: date ?? this.date,
        validFrom: validFrom ?? this.validFrom,
        validTo: validTo ?? this.validTo,
        contractor: contractor ?? this.contractor,
        securedBy: securedBy ?? this.securedBy,
        fireWatch: fireWatch ?? this.fireWatch,
        issuer: issuer ?? this.issuer,
        dgwLimitPct: identical(dgwLimitPct, _keep)
            ? this.dgwLimitPct
            : dgwLimitPct as double?,
        measurements: measurements ?? this.measurements,
        fireWatchAfterMin: identical(fireWatchAfterMin, _keep)
            ? this.fireWatchAfterMin
            : fireWatchAfterMin as int?,
        checked: checked ?? this.checked,
        na: na ?? this.na,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'id': id,
        'permitNo': permitNo,
        'location': location,
        'description': description,
        'workTypes': [for (final t in HotWorkType.values)
          if (workTypes.contains(t)) t.name],
        'date': date,
        'validFrom': validFrom,
        'validTo': validTo,
        'contractor': contractor,
        'securedBy': securedBy,
        'fireWatch': fireWatch,
        'issuer': issuer,
        'dgwLimit': dgwLimitPct,
        'measurements': [for (final m in measurements) m.toJson()],
        'fireWatchAfterMin': fireWatchAfterMin,
        // Kolejność listy kontrolnej — stabilny zapis i czytelny diff.
        'checked': [for (final c in kHotWorkChecks)
          if (checked.contains(c.id)) c.id],
        'na': [for (final c in kHotWorkChecks)
          if (na.contains(c.id) && c.naAllowed) c.id],
        'notes': notes,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Odczyt z JSON. Zwraca `null` dla wpisu bez identyfikatora albo daty.
  /// Nieznane punkty listy i „n/d” przy punktach bez tej opcji są pomijane.
  static HotWorkPermit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = _s(raw['id']);
    final date = _s(raw['date']);
    if (id.isEmpty || date.isEmpty) return null;
    final known = {for (final c in kHotWorkChecks) c.id: c};
    final limit = raw['dgwLimit'];
    final watch = raw['fireWatchAfterMin'];
    return HotWorkPermit(
      id: id,
      permitNo: _s(raw['permitNo']),
      location: _s(raw['location']),
      description: _s(raw['description']),
      workTypes: {
        for (final n in _list(raw['workTypes']))
          if (HotWorkType.byName(n) != null) HotWorkType.byName(n)!,
      },
      date: date,
      validFrom: _s(raw['validFrom']),
      validTo: _s(raw['validTo']),
      contractor: _s(raw['contractor']),
      securedBy: _s(raw['securedBy']),
      fireWatch: _s(raw['fireWatch']),
      issuer: _s(raw['issuer']),
      dgwLimitPct: limit is num && hotWorkLimitValid(limit.toDouble())
          ? limit.toDouble()
          : null,
      measurements: [
        for (final m in _list(raw['measurements']))
          if (HotWorkMeasurement.fromJson(m) != null)
            HotWorkMeasurement.fromJson(m)!,
      ],
      fireWatchAfterMin:
          watch is num && watch.isFinite && watch >= 0 ? watch.toInt() : null,
      checked: {
        for (final c in _list(raw['checked']))
          if (c is String && known.containsKey(c)) c,
      },
      na: {
        for (final c in _list(raw['na']))
          if (c is String && (known[c]?.naAllowed ?? false)) c,
      },
      notes: _s(raw['notes']),
      createdAt: _i(raw['createdAt']),
      updatedAt: _i(raw['updatedAt']),
    );
  }
}

/// Lista protokołów z JSON (historia) — uszkodzone wpisy są pomijane.
List<HotWorkPermit> hotWorkPermitsFromJson(Object? raw) => [
      for (final e in _list(raw))
        if (HotWorkPermit.fromJson(e) != null) HotWorkPermit.fromJson(e)!,
    ];

List<Map<String, Object?>> hotWorkPermitsToJson(List<HotWorkPermit> list) =>
    [for (final p in list) p.toJson()];

/// `YYYY-MM-DD`.
String hotWorkDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// `HH:mm`.
String hotWorkTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// `0.5` → „0,5” (PL) / „0.5” (EN); do 2 miejsc, bez zbędnych zer — wynik
/// 9,96 nie może wyglądać jak 10.
String formatHotWorkNumber(double v, {required bool en}) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return en ? s : s.replaceAll('.', ',');
}

String _two(int v) => v.toString().padLeft(2, '0');
String _s(Object? v) => v is String ? v : '';
int _i(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
List<Object?> _list(Object? v) => v is List ? v : const [];

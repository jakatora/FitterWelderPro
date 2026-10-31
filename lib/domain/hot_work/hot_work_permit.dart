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
///   punktów „przed rozpoczęciem”, WPISANEGO i AKTUALNEGO wyniku pomiaru
///   atmosfery (nie starszego niż ważność pomiaru — domyślnie 30 min,
///   wartość przyjęta w aplikacji) i dopuszczalnego % DGW (domyślnie 10 % —
///   rozp. MSWiA § 36 ust. 2, zob. hot_work_sources.dart; zakład może
///   wymagać mniej) — brak albo nieaktualny pomiar nigdy nie daje zielonego
///   stanu;
/// * protokół z innego dnia niż dziś nigdy nie jest zielony;
/// * pomiar ponad próg wpisany PÓŹNIEJ niż najpóźniejszy w czasie blokuje
///   zieleń (wpis z późniejszą godziną nie przykryje świeżego alarmu);
/// * bez progu z zezwolenia wynik ocenia się względem 10 % DGW z przepisu:
///   więcej = STOP, nie „brak limitu”;
/// * „nie dotyczy” liczy się tylko przy punktach, które na to pozwalają
///   ([HotWorkCheck.naAllowed]); zapis z innym „n/d” nie zwalnia punktu;
/// * zaznaczenia nieznanych punktów (stary zapis, zmieniona lista) są
///   pomijane — nie mogą udawać odhaczonego punktu;
/// * pomiary i protokoły nieczytelne przy odczycie (także pomiary
///   „z przyszłości”) są liczone ([HotWorkParse]) — zapis robi kopię,
///   ekran pokazuje baner;
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
  /// Identyfikator pomiaru (usuwanie i „Cofnij” po identyfikatorze — dwa
  /// identyczne wyniki to dwa pomiary). Pusty w starszych zapisach.
  final String id;

  /// Godzina pomiaru `HH:mm`.
  final String time;

  /// Chwila pomiaru (ms od epoki) — o stanie decyduje pomiar
  /// NAJPÓŹNIEJSZY w czasie, nie ostatnio dopisany (zaległy pomiar 0 %
  /// z 09:00 nie może zdjąć STOP-u z pomiaru 15 % z 10:30). `null` tylko
  /// w zapisach sprzed tego pola — wtedy liczy się kolejność wpisów.
  final int? at;

  /// Chwila WPISANIA do aplikacji (ms od epoki); `null` w starszych
  /// zapisach. Pomiar ponad próg wpisany później niż decydujący blokuje
  /// zieleń.
  final int? enteredAt;

  /// Wynik w % DGW (dolnej granicy wybuchowości, ang. % LEL).
  final double dgwPct;

  /// Miejsce / uwagi (np. „studzienka K-3”, „O₂ 20,9 %”).
  final String note;

  const HotWorkMeasurement({
    this.id = '',
    required this.time,
    this.at,
    this.enteredAt,
    required this.dgwPct,
    this.note = '',
  });

  /// Chwila wpisania ważna względem [now]: wpis „z przyszłości” (dalej niż
  /// [kHotWorkFutureSlack]) — zegar był przestawiony — jest nieważny
  /// i zostaje chwila pomiaru [at]. Bez przycinania do „teraz”.
  int? enteredAsOf(DateTime now) {
    final e = enteredAt;
    if (e == null) return at;
    return e > now.add(kHotWorkFutureSlack).millisecondsSinceEpoch ? at : e;
  }

  Map<String, Object?> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'time': time,
        if (at != null) 'at': at,
        if (enteredAt != null) 'entered': enteredAt,
        'dgw': dgwPct,
        'note': note,
      };

  /// `null`, gdy wpis jest uszkodzony (bez wyniku albo wynik ujemny) albo —
  /// gdy podano [now] — z chwilą pomiaru dalej w przyszłości niż
  /// [kHotWorkFutureSlack] (taki pomiar przykryłby wszystkie prawdziwe).
  static HotWorkMeasurement? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;
    final v = raw['dgw'];
    if (v is! num || !v.isFinite || v < 0) return null;
    final at = raw['at'];
    final atMs = at is num && at.isFinite ? at.toInt() : null;
    if (now != null &&
        atMs != null &&
        atMs > now.add(kHotWorkFutureSlack).millisecondsSinceEpoch) {
      return null;
    }
    final entered = raw['entered'];
    return HotWorkMeasurement(
      id: _s(raw['id']),
      time: _s(raw['time']),
      at: atMs,
      // Chwila wpisu z przyszłości (przestawiony zegar) jest nieważna —
      // zostaje chwila pomiaru; NIE przycinamy jej do „teraz”.
      enteredAt: entered is num &&
              entered.isFinite &&
              (now == null ||
                  entered <=
                      now.add(kHotWorkFutureSlack).millisecondsSinceEpoch)
          ? entered.toInt()
          : null,
      dgwPct: v.toDouble(),
      note: _s(raw['note']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HotWorkMeasurement &&
      other.id == id &&
      other.time == time &&
      other.at == at &&
      other.enteredAt == enteredAt &&
      other.dgwPct == dgwPct &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, time, at, enteredAt, dgwPct, note);
}

/// Chwila pomiaru o godzinie [hhmm] wpisanej przy [now]: ostatnie takie
/// wystąpienie nie później niż 5 min po [now] (zapas na różnicę zegarów).
/// Godzina „z przyszłości” to wczoraj — np. 23:50 wpisane o 00:12 (zmiana
/// nocna); godzina tuż po północy wpisana przed północą (00:03 o 23:58)
/// mieści się w zapasie 5 min — to jutro, nie doba wstecz. Zła godzina →
/// [now]. Ekrany NIE przyjmują wyniku późniejszego niż „teraz” (pomiar
/// z przyszłości przykryłby prawdziwe), a wynik z wczoraj — tylko po
/// potwierdzeniu.
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

/// Chwila pomiaru do oceny wieku: [HotWorkMeasurement.at], a w starych
/// zapisach — godzina na dzień protokołu [recordDate]; `null`, gdy nie da
/// się jej ustalić (taki pomiar jest nieaktualny).
int? hotWorkMeasurementMoment(HotWorkMeasurement m, String recordDate) {
  if (m.at != null) return m.at;
  final d = DateTime.tryParse(recordDate);
  final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(m.time.trim());
  if (d == null || t == null) return null;
  final h = int.parse(t.group(1)!);
  final min = int.parse(t.group(2)!);
  if (h > 23 || min > 59) return null;
  return DateTime(d.year, d.month, d.day, h, min).millisecondsSinceEpoch;
}

/// Data pomiaru `YYYY-MM-DD` (stare zapisy bez chwili — `null`).
String? hotWorkMeasurementDate(HotWorkMeasurement m) => m.at == null
    ? null
    : hotWorkDate(DateTime.fromMillisecondsSinceEpoch(m.at!));

/// Godzina pomiaru do tekstu — z datą, gdy pomiar jest z innego dnia niż
/// [recordDate] („2026-10-16 23:50”).
String hotWorkMeasurementTime(HotWorkMeasurement m, String recordDate) {
  final t = m.time.isEmpty ? '—' : m.time;
  final d = hotWorkMeasurementDate(m);
  return d == null || d == recordDate ? t : '$d $t';
}

/// Dopuszczalne % DGW, które aplikacja przyjmuje: 0–10. Przepis
/// (rozp. MSWiA § 36 ust. 2) nie pozwala na więcej niż 10 % DGW, a zakład
/// może wymagać mniej; wyższa wartość to literówka („100” zamiast „10”)
/// i nie może dawać zielonego stanu.
bool hotWorkLimitValid(double v) =>
    v.isFinite && v >= 0 && v <= kHotWorkDefaultDgwLimitPct;

/// Ważność pomiaru (min), którą aplikacja przyjmuje: 1 … przyjęta
/// [kHotWorkMeasurementMaxAgeMin] — dłużej nie wolno.
bool hotWorkMaxAgeValid(int min) =>
    min >= 1 && min <= kHotWorkMeasurementMaxAgeMin;

/// Wynik oceny gotowości — co jeszcze blokuje zielony stan.
enum HotWorkReadiness {
  /// Pomiar przekracza dopuszczalny % DGW — NIE zaczynać.
  overLimit,

  /// Protokół z innego dnia niż dziś — nigdy zielony.
  otherDay,

  /// Brak aktualnego wyniku pomiaru atmosfery (brak albo nieaktualny).
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

  /// Pomiar decydujący: najpóźniejszy w czasie albo — gdy przekracza próg —
  /// wpisany później niż najpóźniejszy; `null` = brak pomiaru.
  final HotWorkMeasurement? lastMeasurement;

  /// Najpóźniejszy w czasie pomiar (do oceny wieku).
  final HotWorkMeasurement? latestMeasurement;
  final double? limitPct;

  /// Najpóźniejszy pomiar jest starszy niż ważność (albo z przyszłości).
  final bool measurementStale;

  /// Decyduje pomiar ponad próg wpisany później niż najpóźniejszy.
  final bool enteredLater;

  /// Różne wyniki z tej samej (najpóźniejszej) minuty — kolejność nie
  /// rozstrzyga, decyduje gorszy (jak w module przestrzeni zamkniętej).
  final bool tie;

  /// Data protokołu i „dziś” w chwili oceny (`YYYY-MM-DD`).
  final String recordDate;
  final String today;

  /// Ważność pomiaru użyta w ocenie (min).
  final int maxAgeMin;

  const HotWorkAssessment({
    required this.openBefore,
    required this.openDuring,
    required this.openAfter,
    required this.lastMeasurement,
    required this.limitPct,
    this.latestMeasurement,
    this.measurementStale = false,
    this.enteredLater = false,
    this.tie = false,
    this.recordDate = '',
    this.today = '',
    this.maxAgeMin = kHotWorkMeasurementMaxAgeMin,
  });

  bool get measurementMissing => lastMeasurement == null;
  bool get limitMissing => limitPct == null;

  /// Próg użyty w ocenie: z zezwolenia, a bez niego — 10 % DGW z przepisu
  /// (przekroczenie przepisu to STOP, nie „brak limitu”).
  double get effectiveLimitPct => limitPct ?? kHotWorkDefaultDgwLimitPct;

  /// Protokół z innego dnia niż dziś.
  bool get otherDay => recordDate != today;

  bool get overLimit {
    final m = lastMeasurement;
    if (m == null) return false;
    return !hotWorkMeasurementOk(m.dgwPct, effectiveLimitPct);
  }

  HotWorkReadiness get readiness {
    if (overLimit) return HotWorkReadiness.overLimit;
    if (otherDay) return HotWorkReadiness.otherDay;
    if (measurementMissing || measurementStale) {
      return HotWorkReadiness.noMeasurement;
    }
    if (limitMissing) return HotWorkReadiness.noLimit;
    if (openBefore.isNotEmpty) return HotWorkReadiness.incomplete;
    return HotWorkReadiness.ready;
  }

  /// Zielony stan: dziś, wszystko „przed rozpoczęciem” gotowe i aktualny
  /// pomiar w normie.
  bool get readyToStart => readiness == HotWorkReadiness.ready;

  /// Praca zamknięta: wszystkie punkty odhaczone (też dozór po pracy),
  /// pomiar był w normie, próg wpisany. Wiek pomiaru nie ma tu znaczenia
  /// (po pracy nikt już nie mierzy); protokół z innego dnia jest zamknięty,
  /// ale „nieaktualny” (nigdy zielony — zob. [otherDay]).
  bool get closed =>
      openBefore.isEmpty &&
      openDuring.isEmpty &&
      openAfter.isEmpty &&
      !measurementMissing &&
      !overLimit &&
      !limitMissing;
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

  /// Ważność pomiaru z zezwolenia (min); `null` = przyjęta w aplikacji
  /// [kHotWorkMeasurementMaxAgeMin]. Wolno tylko skrócić.
  final int? measurementMaxAgeMin;

  /// Czas dozoru po zakończeniu pracy z zezwolenia, w minutach.
  final int? fireWatchAfterMin;

  /// Identyfikatory odhaczonych punktów i punktów „nie dotyczy”.
  final Set<String> checked;
  final Set<String> na;
  final String notes;
  final int createdAt;
  final int updatedAt;

  /// Ile pomiarów tego protokołu odrzucono przy odczycie (nie zapisywane).
  final int droppedOnLoad;

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
    this.measurementMaxAgeMin,
    this.fireWatchAfterMin,
    this.checked = const {},
    this.na = const {},
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.droppedOnLoad = 0,
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

  /// Ważność pomiaru użyta w ocenie (min) — zapis spoza zakresu nigdy nie
  /// wydłuża ważności.
  int get effectiveMaxAgeMin {
    final v = measurementMaxAgeMin;
    return v != null && hotWorkMaxAgeValid(v)
        ? v
        : kHotWorkMeasurementMaxAgeMin;
  }

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
      measurementMaxAgeMin == null &&
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

  /// Ocena w chwili [now]: wiek pomiaru i data protokołu liczą się względem
  /// tej chwili.
  HotWorkAssessment assess({required DateTime now}) {
    List<HotWorkCheck> open(HotWorkPhase p) => [
          for (final c in hotWorkChecksIn(p))
            if (!isSettled(c)) c,
        ];
    final chrono = measurementsChrono;
    final limit = dgwLimitPct;
    final validLimit = limit != null && hotWorkLimitValid(limit) ? limit : null;
    final effLimit = validLimit ?? kHotWorkDefaultDgwLimitPct;
    final latest = chrono.isEmpty ? null : chrono.last;
    // Najpóźniejsza MINUTA (tyle widać na ekranie): kilka wyników z tej
    // samej minuty to remis — decyduje gorszy (wyższy % DGW), nie
    // milisekunda wpisu. Stare zapisy bez chwili — ostatni wpis.
    final List<HotWorkMeasurement> group;
    if (latest == null) {
      group = const [];
    } else if (chrono.every((m) => m.at != null)) {
      final minute = latest.at! ~/ 60000;
      group = [for (final m in chrono) if (m.at! ~/ 60000 == minute) m];
    } else {
      group = [latest];
    }
    var decisive = group.isEmpty
        ? null
        : group.reduce((a, b) => b.dgwPct > a.dgwPct ? b : a);
    final tie = {for (final m in group) m.dgwPct}.length > 1;
    var enteredLater = false;
    if (decisive != null &&
        hotWorkMeasurementOk(decisive.dgwPct, effLimit)) {
      // Pomiar ponad próg wpisany PÓŹNIEJ niż najpóźniejszy w czasie — np.
      // o 14:00 wpis z godziną 14:05 (0 %), o 14:02 prawdziwy wynik 15 %.
      // Chwila wpisu z przyszłości (przestawiony zegar) się nie liczy.
      int? lastEntered;
      for (final m in group) {
        final e = m.enteredAsOf(now);
        if (e != null && (lastEntered == null || e > lastEntered)) {
          lastEntered = e;
        }
      }
      if (lastEntered != null) {
        for (final m in measurements) {
          final e = m.enteredAsOf(now);
          if (e == null || e <= lastEntered) continue;
          if (hotWorkMeasurementOk(m.dgwPct, effLimit)) continue;
          if (!enteredLater || m.dgwPct > decisive!.dgwPct) {
            decisive = m;
            enteredLater = true;
          }
        }
      }
    }
    var stale = false;
    if (latest != null) {
      final t = now.millisecondsSinceEpoch;
      final moment = hotWorkMeasurementMoment(latest, date);
      stale = moment == null ||
          moment > t + kHotWorkFutureSlack.inMilliseconds ||
          t - moment > effectiveMaxAgeMin * 60000;
    }
    return HotWorkAssessment(
      openBefore: open(HotWorkPhase.before),
      openDuring: open(HotWorkPhase.during),
      openAfter: open(HotWorkPhase.after),
      lastMeasurement: decisive,
      latestMeasurement: latest,
      limitPct: validLimit,
      measurementStale: stale,
      enteredLater: enteredLater,
      tie: tie,
      recordDate: date,
      today: hotWorkDate(now),
      maxAgeMin: effectiveMaxAgeMin,
    );
  }

  /// Dopisuje pomiar (lista w kolejności czasu).
  HotWorkPermit addMeasurement(HotWorkMeasurement m) => copyWith(
      measurements: hotWorkMeasurementsChrono([...measurements, m]));

  /// Usuwa pomiar po identyfikatorze (stare zapisy bez niego — po
  /// tożsamości obiektu).
  HotWorkPermit removeMeasurement(HotWorkMeasurement m) {
    final i = m.id.isEmpty
        ? measurements.indexWhere((x) => identical(x, m))
        : measurements.indexWhere((x) => x.id == m.id);
    if (i < 0) return this;
    return copyWith(measurements: [...measurements]..removeAt(i));
  }

  /// Przywraca usunięty pomiar („Cofnij”) po identyfikatorze; jeśli już
  /// jest — bez zmian (cofnięcie dwa razy nie dubluje).
  HotWorkPermit restoreMeasurement(HotWorkMeasurement m) {
    final present = m.id.isEmpty
        ? measurements.contains(m)
        : measurements.any((x) => x.id == m.id);
    return present ? this : addMeasurement(m);
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
  /// zmiany, rodzaj pracy, dopuszczalne % DGW, ważność pomiaru i czas
  /// dozoru zostają. Zaznaczenia, pomiary, numer zezwolenia i uwagi — NIE:
  /// stanowisko sprawdza się na nowo, a zakład wystawia nowe zezwolenie.
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
        measurementMaxAgeMin: measurementMaxAgeMin,
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
    Object? measurementMaxAgeMin = _keep,
    Object? fireWatchAfterMin = _keep,
    Set<String>? checked,
    Set<String>? na,
    String? notes,
    int? updatedAt,
    Object? droppedOnLoad = _keep,
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
        measurementMaxAgeMin: identical(measurementMaxAgeMin, _keep)
            ? this.measurementMaxAgeMin
            : measurementMaxAgeMin as int?,
        fireWatchAfterMin: identical(fireWatchAfterMin, _keep)
            ? this.fireWatchAfterMin
            : fireWatchAfterMin as int?,
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
        if (measurementMaxAgeMin != null) 'maxAgeMin': measurementMaxAgeMin,
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
  /// Uszkodzone pomiary — a przy podanym [now] także pomiary z przyszłości
  /// — są pomijane i liczone w [droppedOnLoad].
  static HotWorkPermit? fromJson(Object? raw, {DateTime? now}) {
    if (raw is! Map) return null;
    if (raw.containsKey('v') && raw['v'] != 1) return null;
    final id = _s(raw['id']);
    final date = _s(raw['date']);
    if (id.isEmpty || date.isEmpty) return null;
    final known = {for (final c in kHotWorkChecks) c.id: c};
    final limit = raw['dgwLimit'];
    final watch = raw['fireWatchAfterMin'];
    final maxAge = raw['maxAgeMin'];
    final rawMeasurements = _list(raw['measurements']);
    final measurements = [
      for (final m in rawMeasurements)
        if (HotWorkMeasurement.fromJson(m, now: now) != null)
          HotWorkMeasurement.fromJson(m, now: now)!,
    ];
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
      measurements: measurements,
      measurementMaxAgeMin:
          maxAge is int && hotWorkMaxAgeValid(maxAge) ? maxAge : null,
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
      droppedOnLoad: rawMeasurements.length - measurements.length,
    );
  }
}

/// Wynik odczytu listy protokołów: ile protokołów i pomiarów odrzucono.
class HotWorkParse {
  final List<HotWorkPermit> permits;
  final int droppedPermits;
  final int droppedMeasurements;
  const HotWorkParse(
      this.permits, this.droppedPermits, this.droppedMeasurements);

  bool get damaged => droppedPermits > 0 || droppedMeasurements > 0;
}

/// Lista protokołów z JSON (historia). Uszkodzone wpisy i pomiary (także
/// z przyszłości względem [now]) są pomijane, ale LICZONE — zapis robi
/// kopię, ekran pokazuje baner.
HotWorkParse hotWorkPermitsParse(Object? raw, {DateTime? now}) {
  if (raw is! List) throw const FormatException('not a list');
  final permits = <HotWorkPermit>[];
  var droppedPermits = 0;
  var droppedMeasurements = 0;
  for (final e in raw) {
    final p = HotWorkPermit.fromJson(e, now: now);
    if (p == null) {
      droppedPermits++;
    } else {
      permits.add(p);
      droppedMeasurements += p.droppedOnLoad;
    }
  }
  return HotWorkParse(permits, droppedPermits, droppedMeasurements);
}

/// Lista protokołów z JSON (historia) — uszkodzone wpisy są pomijane.
/// Do zapisu historii używaj [hotWorkPermitsParse] (liczy pominięte).
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

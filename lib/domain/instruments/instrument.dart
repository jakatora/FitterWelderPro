/// Rejestr przyrządów i kalibracji — tabela `instruments` (v27).
///
/// Po co: system jakości spawalniczej (EN ISO 3834-2 §12) wymaga, żeby
/// sprzęt do pomiarów, kontroli i badań — oraz źródła prądu w zakresie
/// wskazań — był kalibrowany / walidowany, a termin był pod kontrolą.
/// W brygadzie pilnuje się tego zeszytem; manometr po terminie wychodzi
/// dopiero przy odbiorze próby ciśnieniowej.
///
/// Interwały domyślne to TYPOWE wartości (procedura firmy / producent
/// decyduje). Jedyny wyjątek z normy: klucz dynamometryczny — ISO 6789
/// zaleca ponowne wzorcowanie po 12 miesiącach albo 5000 cyklach,
/// cokolwiek nastąpi pierwsze.
///
/// Daty `yyyy-MM-dd` (dzień kalendarzowy), jak w rejestrze uprawnień.
/// Czysty Dart.
library;

import '../qualification/qualification_dates.dart';
import '../qualification/reminder_plan.dart';

enum InstrumentKind {
  weldingMachine(
      'WELDER',
      'Spawarka / źródło prądu',
      'Welding power source',
      12,
      'Walidacja wskazań wg EN IEC 60974-14',
      'Validation of readings per EN IEC 60974-14'),
  pressureGauge(
      'GAUGE',
      'Manometr',
      'Pressure gauge',
      12,
      'Do prób ciśnieniowych — świadectwo wzorcowania z numerem',
      'For pressure tests — numbered calibration certificate'),
  thermometer(
      'THERMO',
      'Termometr / pirometr',
      'Thermometer / pyrometer',
      12,
      'Podgrzewanie i temperatura międzyściegowa',
      'Preheat and interpass temperature'),
  clampMeter(
      'CLAMP',
      'Miernik cęgowy (prąd, napięcie)',
      'Clamp meter (current, voltage)',
      12,
      'Pomiar parametrów do energii liniowej',
      'Measuring parameters for heat input'),
  oxygenAnalyser('O2', 'Analizator tlenu', 'Oxygen analyser', 12,
      'Formowanie grani — ppm O₂', 'Root purging — ppm O₂'),
  flowmeter(
      'FLOW',
      'Rotametr / reduktor z przepływomierzem',
      'Flowmeter / regulator',
      12,
      'Przepływ gazu osłonowego i formującego',
      'Shielding and backing gas flow'),
  weldGauge(
      'WGAUGE',
      'Szablon spawalniczy / suwmiarka',
      'Weld gauge / calliper',
      12,
      'Wymiar a, nadlew, podtopienia (ISO 5817)',
      'Throat, reinforcement, undercut (ISO 5817)'),
  torqueWrench(
      'TORQUE',
      'Klucz dynamometryczny',
      'Torque wrench',
      12,
      'ISO 6789: co 12 mies. albo 5000 cykli — co pierwsze',
      'ISO 6789: every 12 months or 5000 cycles — whichever first'),
  other('OTHER', 'Inny przyrząd', 'Other instrument', 12, '', '');

  const InstrumentKind(this.code, this.labelPl, this.labelEn,
      this.defaultIntervalMonths, this.hintPl, this.hintEn);

  final String code;
  final String labelPl;
  final String labelEn;
  final int defaultIntervalMonths;
  final String hintPl;
  final String hintEn;

  static InstrumentKind fromCode(Object? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return other;
  }
}

/// Stan terminu kalibracji na dany dzień.
enum InstrumentStatus {
  /// Brak daty ostatniej kalibracji i brak terminu.
  unknown,
  ok,

  /// Termin w ciągu [kInstrumentDueSoonDays] dni.
  dueSoon,
  overdue,
}

const int kInstrumentDueSoonDays = 30;

String _s(Object? v) => v is String ? v : '';
int? _i(Object? v) => v is num ? v.toInt() : null;

class Instrument {
  final String id;
  final InstrumentKind kind;

  /// Nazwa / model, np. „Kemppi Master M 323”.
  final String name;
  final String serialNo;

  /// Gdzie / u kogo (brygada, kontener, osoba).
  final String location;

  /// Data ostatniej kalibracji / walidacji `yyyy-MM-dd` (puste = brak).
  final String lastCalibration;
  final int intervalMonths;

  /// Termin ręczny `yyyy-MM-dd` (ze świadectwa) — ma pierwszeństwo przed
  /// ostatnią kalibracją + interwał.
  final String dueOverride;
  final String certificateNo;
  final String calibratedBy;
  final String notes;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const Instrument({
    required this.id,
    this.kind = InstrumentKind.other,
    this.name = '',
    this.serialNo = '',
    this.location = '',
    this.lastCalibration = '',
    this.intervalMonths = 12,
    this.dueOverride = '',
    this.certificateNo = '',
    this.calibratedBy = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  /// „Kemppi Master M 323 (nr 12345)” albo nazwa rodzaju.
  String displayName({required bool en}) {
    final base =
        name.trim().isEmpty ? (en ? kind.labelEn : kind.labelPl) : name.trim();
    return serialNo.trim().isEmpty ? base : '$base (${serialNo.trim()})';
  }

  /// Termin następnej kalibracji albo `null`.
  DateTime? get dueDate {
    final manual = parseFlexibleDate(dueOverride);
    if (manual != null) return manual;
    final last = parseFlexibleDate(lastCalibration);
    if (last == null || intervalMonths <= 0) return null;
    return addMonthsClamped(last, intervalMonths);
  }

  /// Dni do terminu (ujemne = po terminie) albo `null`.
  int? daysLeft(DateTime today) {
    final due = dueDate;
    return due == null ? null : calendarDaysBetween(today, due);
  }

  InstrumentStatus statusOn(DateTime today) {
    final d = daysLeft(today);
    if (d == null) return InstrumentStatus.unknown;
    if (d < 0) return InstrumentStatus.overdue;
    if (d <= kInstrumentDueSoonDays) return InstrumentStatus.dueSoon;
    return InstrumentStatus.ok;
  }

  Instrument copyWith({
    InstrumentKind? kind,
    String? name,
    String? serialNo,
    String? location,
    String? lastCalibration,
    int? intervalMonths,
    String? dueOverride,
    String? certificateNo,
    String? calibratedBy,
    String? notes,
    int? updatedAt,
    int? Function()? deletedAt,
  }) =>
      Instrument(
        id: id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        serialNo: serialNo ?? this.serialNo,
        location: location ?? this.location,
        lastCalibration: lastCalibration ?? this.lastCalibration,
        intervalMonths: intervalMonths ?? this.intervalMonths,
        dueOverride: dueOverride ?? this.dueOverride,
        certificateNo: certificateNo ?? this.certificateNo,
        calibratedBy: calibratedBy ?? this.calibratedBy,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
      );

  /// „Skalibrowane dziś”: ostatnia = [today], termin ręczny kasowany
  /// (nowy liczy się z interwału).
  Instrument calibratedOn(DateTime today, {String certificateNo = ''}) =>
      copyWith(
        lastCalibration: formatIsoDate(today),
        dueOverride: '',
        certificateNo:
            certificateNo.trim().isEmpty ? this.certificateNo : certificateNo,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'kind': kind.code,
        'name': name,
        'serial_no': serialNo,
        'location': location,
        'last_calibration': lastCalibration,
        'interval_months': intervalMonths,
        'due_override': dueOverride,
        'certificate_no': certificateNo,
        'calibrated_by': calibratedBy,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
      };

  static Instrument fromRow(Map<String, Object?> r) => Instrument(
        id: _s(r['id']),
        kind: InstrumentKind.fromCode(r['kind']),
        name: _s(r['name']),
        serialNo: _s(r['serial_no']),
        location: _s(r['location']),
        lastCalibration: _s(r['last_calibration']),
        intervalMonths: (_i(r['interval_months']) ?? 12).clamp(0, 240),
        dueOverride: _s(r['due_override']),
        certificateNo: _s(r['certificate_no']),
        calibratedBy: _s(r['calibrated_by']),
        notes: _s(r['notes']),
        createdAt: _i(r['created_at']) ?? 0,
        updatedAt: _i(r['updated_at']) ?? 0,
        deletedAt: _i(r['deleted_at']),
      );
}

/// Kolejność listy: po terminie, wkrótce, brak danych, w porządku; w grupie
/// — najbliższy termin pierwszy.
List<Instrument> sortForRegister(Iterable<Instrument> list, DateTime today) {
  int rank(InstrumentStatus s) => switch (s) {
        InstrumentStatus.overdue => 0,
        InstrumentStatus.dueSoon => 1,
        InstrumentStatus.unknown => 2,
        InstrumentStatus.ok => 3,
      };
  final out = [...list];
  out.sort((a, b) {
    final r = rank(a.statusOn(today)).compareTo(rank(b.statusOn(today)));
    if (r != 0) return r;
    final da = a.daysLeft(today), db = b.daysLeft(today);
    if (da != null && db != null && da != db) return da.compareTo(db);
    return a.displayName(en: false).compareTo(b.displayName(en: false));
  });
  return out;
}

/// Przypomnienia 30 i 7 dni przed terminem, o 9:00 — tylko przyszłe, ten
/// sam limit liczby co uprawnienia (iOS: 64 na aplikację, dzielone).
List<PlannedReminder> planInstrumentReminders(
  Iterable<Instrument> instruments, {
  required DateTime now,
  required bool english,
  List<int> leadDays = kReminderLeadDays,
  int hour = kReminderHour,
  int maxCount = 16,
}) {
  final out = <PlannedReminder>[];
  for (final i in instruments) {
    if (i.isDeleted) continue;
    final due = i.dueDate;
    if (due == null) continue;
    for (final lead in leadDays) {
      final day = due.subtract(Duration(days: lead));
      final fireAt = DateTime(day.year, day.month, day.day, hour);
      if (!fireAt.isAfter(now)) continue;
      final name = i.displayName(en: english);
      out.add(PlannedReminder(
        id: reminderId('instrument:${i.id}', ReminderKind.expiry, lead),
        fireAt: fireAt,
        certificateId: i.id,
        kind: ReminderKind.expiry,
        daysBefore: lead,
        deadline: due,
        title: english
            ? 'Calibration due in $lead days'
            : 'Kalibracja za $lead dni',
        body: english
            ? '$name — due ${formatIsoDate(due)}.'
            : '$name — termin ${formatIsoDate(due)}.',
      ));
    }
  }
  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.length > maxCount ? out.sublist(0, maxCount) : out;
}

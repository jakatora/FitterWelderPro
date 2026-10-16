/// Prognoza końca pakietu / projektu: zakres (liczba spoin albo DI do
/// wykonania) wpisany przez brygadzistę, % wykonania, data końca przy
/// obecnym tempie i tempo potrzebne, żeby zdążyć na termin.
///
/// Dzień dzisiejszy liczy się tak samo jak w tempie ([computePace]): jeśli
/// dziś są już wpisy, dzisiejsza praca jest w „wykonane" i w tempie, a
/// liczenie dni do końca zaczyna się jutro; jeśli wpisów jeszcze nie ma,
/// dziś (dzień roboczy) jest pierwszym dniem do pracy.
///
/// Czysty Dart.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../weld_journal/weld_dates.dart';
import 'work_calendar.dart';

/// W czym brygadzista podał zakres.
enum ScopeUnit { welds, di }

/// Zakres pracy zapamiętany dla projektu (i pakietu).
class ProgressScope {
  final ScopeUnit unit;

  /// Ile spoin / DI jest do wykonania w całym zakresie; null = nie podano.
  final double? total;

  /// Termin `RRRR-MM-DD` albo pusty.
  final String due;

  /// Brygada pracuje w soboty.
  final bool saturdays;

  const ProgressScope({
    this.unit = ScopeUnit.di,
    this.total,
    this.due = '',
    this.saturdays = false,
  });

  /// Klucz zapisu: projekt i pakiet, bez wielkości liter i spacji na brzegach.
  static String keyFor(String project, String testPackage) =>
      '${project.trim().toLowerCase()}|${testPackage.trim().toLowerCase()}';

  bool get hasTotal => total != null && total! > 0;

  DateTime? get dueDate => parseIsoDay(due);

  WorkWeek get week => WorkWeek(saturdays: saturdays);

  Map<String, Object?> toJson() => {
        'unit': unit.name,
        if (total != null) 'total': total,
        if (due.isNotEmpty) 'due': due,
        if (saturdays) 'saturdays': true,
      };

  static ProgressScope fromJson(Object? json) {
    if (json is! Map) return const ProgressScope();
    final t = json['total'];
    final total = t is num && t.isFinite && t > 0 ? t.toDouble() : null;
    final due = json['due'];
    return ProgressScope(
      unit: json['unit'] == ScopeUnit.welds.name ? ScopeUnit.welds : ScopeUnit.di,
      total: total,
      due: due is String && isIsoWeldDate(due) ? due : '',
      saturdays: json['saturdays'] == true,
    );
  }

  String encode() => jsonEncode(toJson());

  static ProgressScope decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const ProgressScope();
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      return const ProgressScope();
    }
  }

  static const Object _keep = Object();

  ProgressScope copyWith({
    ScopeUnit? unit,
    Object? total = _keep,
    String? due,
    bool? saturdays,
  }) =>
      ProgressScope(
        unit: unit ?? this.unit,
        total: identical(total, _keep) ? this.total : total as double?,
        due: due ?? this.due,
        saturdays: saturdays ?? this.saturdays,
      );
}

class ProgressForecast {
  final ScopeUnit unit;
  final double done;
  final double total;

  /// Obecne tempo w jednostce [unit] na dzień roboczy; null = brak danych.
  final double? pacePerDay;

  /// Pierwszy dzień, od którego liczy się pozostałą pracę.
  final DateTime firstDay;

  /// Dni robocze potrzebne przy obecnym tempie; null, gdy gotowe albo tempa
  /// brak.
  final int? workingDaysNeeded;

  /// Szacowany ostatni dzień pracy; null jak wyżej.
  final DateTime? finish;

  final DateTime? due;

  /// Dni robocze od [firstDay] do [due] włącznie; null bez terminu.
  final int? workingDaysToDue;

  /// Ile trzeba robić dziennie, żeby zdążyć; null bez terminu, po terminie
  /// albo gdy gotowe.
  final double? requiredPerDay;

  const ProgressForecast({
    required this.unit,
    required this.done,
    required this.total,
    required this.pacePerDay,
    required this.firstDay,
    required this.workingDaysNeeded,
    required this.finish,
    required this.due,
    required this.workingDaysToDue,
    required this.requiredPerDay,
  });

  bool get isDone => total > 0 && done >= total - 1e-9;
  double get remaining => math.max(0, total - done);

  /// % wykonania (może przekroczyć 100, gdy zakres był za mały).
  double get pct => total <= 0 ? 0 : done * 100 / total;

  /// Termin minął (albo nie zostały dni robocze), a praca nie jest skończona.
  bool get dueMissed =>
      due != null && !isDone && (workingDaysToDue ?? 0) == 0;

  /// Obecne tempo wystarcza na termin.
  bool? get onTrack {
    final need = requiredPerDay, pace = pacePerDay;
    if (need == null || pace == null) return null;
    return pace + 1e-9 >= need;
  }
}

ProgressForecast computeForecast({
  required ScopeUnit unit,
  required double done,
  required double total,
  required double? pacePerDay,
  required DateTime today,
  required bool todayLogged,
  required WorkWeek week,
  DateTime? due,
}) {
  final t = dayOnly(today);
  final firstDay = todayLogged ? addDays(t, 1) : t;
  final remaining = math.max(0.0, total - done);
  final finished = total > 0 && remaining <= 1e-9;
  final pace = pacePerDay != null && pacePerDay > 0 ? pacePerDay : null;

  int? needed;
  DateTime? finish;
  if (!finished && pace != null) {
    needed = math.max(1, (remaining / pace - 1e-9).ceil());
    finish = week.nthWorkingDayAfter(addDays(firstDay, -1), needed);
  }

  int? toDue;
  double? required;
  final dueDay = due == null ? null : dayOnly(due);
  if (dueDay != null) {
    toDue = week.countWorkingDays(firstDay, dueDay);
    if (!finished && toDue > 0) required = remaining / toDue;
  }

  return ProgressForecast(
    unit: unit,
    done: done,
    total: total,
    pacePerDay: pacePerDay,
    firstDay: firstDay,
    workingDaysNeeded: needed,
    finish: finish,
    due: dueDay,
    workingDaysToDue: toDue,
    requiredPerDay: required,
  );
}

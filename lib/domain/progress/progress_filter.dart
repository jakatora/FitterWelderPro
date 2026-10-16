/// Co liczy ekran „Postęp robót": projekt, pakiet testowy, warsztat / obiekt
/// i okres.
///
/// Projekt i daty idą przez filtr dziennika ([WeldJournalFilter]) — ta sama
/// reguła co na liście dziennika i w jego eksporcie: projekt bez rozróżniania
/// wielkości liter, daty włącznie, wpis bez poprawnej daty NIE trafia do
/// okresu z granicami (nie da się wykazać, że w nim jest). Usunięte wpisy
/// nie liczą się nigdy.
///
/// Czysty Dart.
library;

import '../weld_journal/weld_dates.dart';
import '../weld_journal/weld_entry.dart';
import '../weld_journal/weld_filter.dart';
import 'work_calendar.dart';

enum ProgressPeriod {
  /// Dziś.
  today,

  /// Ten tydzień: od poniedziałku do dziś.
  week,

  /// Ten miesiąc: od 1. do dziś.
  month,

  /// Bez granic dat (cały projekt / pakiet).
  all,

  /// Własny zakres [ProgressFilter.customFrom]..[ProgressFilter.customTo].
  custom,
}

/// Warsztat (prefabrykacja) / obiekt (montaż) — pole „SHOP / FIELD" spoiny.
enum ProgressLocation { all, shop, field }

/// Zakres dat włącznie.
class DayRange {
  final DateTime from;
  final DateTime to;
  const DayRange(this.from, this.to);

  String get fromIso => isoDate(from);
  String get toIso => isoDate(to);

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  /// Dni kalendarzowe w zakresie.
  int get days => to.difference(from).inDays.abs() + 1;

  @override
  bool operator ==(Object other) =>
      other is DayRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class ProgressFilter {
  /// Nazwa projektu z dziennika; pusta = wszystkie projekty.
  final String project;

  /// Pakiet testowy; pusty = wszystkie.
  final String testPackage;

  final ProgressLocation location;
  final ProgressPeriod period;

  /// Granice okresu [ProgressPeriod.custom] (włącznie).
  final DateTime? customFrom;
  final DateTime? customTo;

  const ProgressFilter({
    this.project = '',
    this.testPackage = '',
    this.location = ProgressLocation.all,
    this.period = ProgressPeriod.today,
    this.customFrom,
    this.customTo,
  });

  /// Zakres dat okresu albo null dla [ProgressPeriod.all] (i niepełnego
  /// własnego zakresu).
  DayRange? rangeFor(DateTime today) {
    final t = dayOnly(today);
    switch (period) {
      case ProgressPeriod.today:
        return DayRange(t, t);
      case ProgressPeriod.week:
        return DayRange(mondayOf(t), t);
      case ProgressPeriod.month:
        return DayRange(DateTime(t.year, t.month, 1), t);
      case ProgressPeriod.all:
        return null;
      case ProgressPeriod.custom:
        final a = customFrom, b = customTo;
        if (a == null || b == null) return null;
        final from = dayOnly(a), to = dayOnly(b);
        return from.isAfter(to) ? DayRange(to, from) : DayRange(from, to);
    }
  }

  /// Wpis należy do zakresu pracy (projekt, pakiet, miejsce) — bez dat.
  /// Na tym liczy się % wykonania i tempo: postęp pakietu nie zależy od tego,
  /// jaki okres akurat oglądam.
  bool matchesScope(WeldEntry e) {
    // Projekt i „nieusunięty" — reguła dziennika.
    if (!WeldJournalFilter(project: project).matches(e)) return false;
    final pkg = testPackage.trim().toLowerCase();
    if (pkg.isNotEmpty && e.testPackage.trim().toLowerCase() != pkg) {
      return false;
    }
    switch (location) {
      case ProgressLocation.all:
        return true;
      case ProgressLocation.shop:
        return e.shopField.trim().toUpperCase() == WeldLocation.shop;
      case ProgressLocation.field:
        return e.shopField.trim().toUpperCase() == WeldLocation.field;
    }
  }

  /// Wpis należy do zakresu pracy i do okresu.
  bool matches(WeldEntry e, DateTime today) {
    if (!matchesScope(e)) return false;
    final r = rangeFor(today);
    if (r == null) return true;
    return WeldJournalFilter(dateFrom: r.fromIso, dateTo: r.toIso).matches(e);
  }

  /// Wpisy zakresu pracy (bez dat).
  List<WeldEntry> scopeOf(Iterable<WeldEntry> entries) =>
      entries.where(matchesScope).toList();

  /// Wpisy zakresu pracy w okresie.
  List<WeldEntry> apply(Iterable<WeldEntry> entries, DateTime today) =>
      entries.where((e) => matches(e, today)).toList();

  static const Object _keep = Object();

  ProgressFilter copyWith({
    String? project,
    String? testPackage,
    ProgressLocation? location,
    ProgressPeriod? period,
    Object? customFrom = _keep,
    Object? customTo = _keep,
  }) =>
      ProgressFilter(
        project: project ?? this.project,
        testPackage: testPackage ?? this.testPackage,
        location: location ?? this.location,
        period: period ?? this.period,
        customFrom: identical(customFrom, _keep)
            ? this.customFrom
            : customFrom as DateTime?,
        customTo:
            identical(customTo, _keep) ? this.customTo : customTo as DateTime?,
      );

  /// Opis zakresu do nagłówka raportu, np.
  /// „Projekt: Blok 4 · Pakiet: TP-03 · Obiekt".
  String describeScope({required bool en}) {
    final parts = <String>[
      project.trim().isEmpty
          ? (en ? 'All projects' : 'Wszystkie projekty')
          : '${en ? 'Project' : 'Projekt'}: ${project.trim()}',
      if (testPackage.trim().isNotEmpty)
        '${en ? 'Test package' : 'Pakiet'}: ${testPackage.trim()}',
      if (location != ProgressLocation.all)
        progressLocationLabel(location, en: en),
    ];
    return parts.join(' · ');
  }
}

String progressLocationLabel(ProgressLocation l, {required bool en}) =>
    switch (l) {
      ProgressLocation.all => en ? 'Shop + field' : 'Warsztat + obiekt',
      ProgressLocation.shop => en ? 'Shop (prefab)' : 'Warsztat (prefabrykacja)',
      ProgressLocation.field => en ? 'Field (site)' : 'Obiekt (montaż)',
    };

String progressPeriodLabel(ProgressPeriod p, {required bool en}) => switch (p) {
      ProgressPeriod.today => en ? 'Today' : 'Dziś',
      ProgressPeriod.week => en ? 'This week' : 'Ten tydzień',
      ProgressPeriod.month => en ? 'This month' : 'Ten miesiąc',
      ProgressPeriod.all => en ? 'Everything' : 'Całość',
      ProgressPeriod.custom => en ? 'Custom…' : 'Własny…',
    };

/// Projekty z dziennika (nieusunięte wpisy), pierwsza pisownia, alfabetycznie.
List<String> progressProjects(Iterable<WeldEntry> entries) =>
    _distinct(entries.where((e) => !e.isDeleted).map((e) => e.projectName));

/// Pakiety testowe projektu [project] (pusty = wszystkich projektów).
List<String> progressPackages(Iterable<WeldEntry> entries, String project) {
  final p = project.trim().toLowerCase();
  return _distinct(entries
      .where((e) =>
          !e.isDeleted &&
          (p.isEmpty || e.projectName.trim().toLowerCase() == p))
      .map((e) => e.testPackage));
}

List<String> _distinct(Iterable<String> values) {
  final seen = <String, String>{};
  for (final v in values) {
    final t = v.trim();
    if (t.isEmpty) continue;
    seen.putIfAbsent(t.toLowerCase(), () => t);
  }
  final out = seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return out;
}

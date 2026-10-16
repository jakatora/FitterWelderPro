/// Kalendarz dni roboczych dla postępu robót: poniedziałek–piątek, opcjonalnie
/// sobota. Bez świąt — budowa ma własny kalendarz, a aplikacja nie zgaduje,
/// w jakim kraju i według jakiej umowy pracuje brygada.
///
/// Daty to dni kalendarzowe (północ czasu lokalnego). Dodawanie dni idzie
/// przez `DateTime(y, m, d + n)`, nie przez `Duration(days: n)` — przy
/// zmianie czasu letni/zimowy doba ma 23 albo 25 godzin i „+24 h" potrafi
/// trafić w ten sam dzień.
///
/// Czysty Dart.
library;

import '../weld_journal/weld_dates.dart';

/// Sam dzień (północ) z [d].
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] przesunięte o [n] dni kalendarzowych.
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Dzień z tekstu `RRRR-MM-DD` albo null (pusty, błędny, nieistniejący).
DateTime? parseIsoDay(String s) {
  final t = s.trim();
  if (!isIsoWeldDate(t)) return null;
  return DateTime(
    int.parse(t.substring(0, 4)),
    int.parse(t.substring(5, 7)),
    int.parse(t.substring(8, 10)),
  );
}

/// Poniedziałek tygodnia, w którym leży [d].
DateTime mondayOf(DateTime d) => addDays(dayOnly(d), 1 - d.weekday);

/// Tydzień pracy brygady.
class WorkWeek {
  /// Sobota jest dniem roboczym.
  final bool saturdays;

  const WorkWeek({this.saturdays = false});

  bool isWorkingDay(DateTime d) =>
      d.weekday <= DateTime.friday ||
      (saturdays && d.weekday == DateTime.saturday);

  /// Dni robocze w [from]..[to] włącznie; 0, gdy [to] jest przed [from].
  int countWorkingDays(DateTime from, DateTime to) {
    var d = dayOnly(from);
    final end = dayOnly(to);
    var n = 0;
    while (!d.isAfter(end)) {
      if (isWorkingDay(d)) n++;
      d = addDays(d, 1);
    }
    return n;
  }

  /// [n]-ty dzień roboczy PO [from] (sam [from] się nie liczy); [n] ≥ 1.
  DateTime nthWorkingDayAfter(DateTime from, int n) {
    assert(n >= 1);
    var d = dayOnly(from);
    var left = n;
    while (left > 0) {
      d = addDays(d, 1);
      if (isWorkingDay(d)) left--;
    }
    return d;
  }

  /// Najpóźniejszy dzień roboczy ≤ [d].
  DateTime workingDayOnOrBefore(DateTime d) {
    var x = dayOnly(d);
    while (!isWorkingDay(x)) {
      x = addDays(x, -1);
    }
    return x;
  }

  /// Początek okna, które kończy się w [end] i zawiera [n] dni roboczych
  /// (n ≥ 1). [end] nie musi być dniem roboczym (sobota z nadgodzinami) —
  /// wtedy okno sięga [n] dni roboczych wstecz od niego.
  DateTime windowStart(DateTime end, int n) {
    assert(n >= 1);
    var d = dayOnly(end);
    var left = n;
    while (true) {
      if (isWorkingDay(d)) {
        left--;
        if (left == 0) return d;
      }
      d = addDays(d, -1);
    }
  }
}

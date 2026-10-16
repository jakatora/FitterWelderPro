// Prognoza końca pakietu: dni robocze pn–pt (opcja soboty), dzisiejszy dzień
// liczony tak samo jak w tempie, tempo potrzebne na termin, zakres
// zapamiętany w JSON.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/progress/progress_forecast.dart';
import 'package:cut_list_app/domain/progress/work_calendar.dart';

void main() {
  group('kalendarz dni roboczych', () {
    const week = WorkWeek();
    const sat = WorkWeek(saturdays: true);
    final mon = DateTime(2026, 10, 12);
    final fri = DateTime(2026, 10, 16);
    final sun = DateTime(2026, 10, 18);

    test('pn–nd = 5 dni roboczych, z sobotą 6', () {
      expect(week.countWorkingDays(mon, sun), 5);
      expect(sat.countWorkingDays(mon, sun), 6);
      expect(week.countWorkingDays(sun, mon), 0);
    });

    test('następny dzień roboczy po piątku to poniedziałek (sobota z opcją)',
        () {
      expect(week.nthWorkingDayAfter(fri, 1), DateTime(2026, 10, 19));
      expect(sat.nthWorkingDayAfter(fri, 1), DateTime(2026, 10, 17));
      expect(week.nthWorkingDayAfter(fri, 6), DateTime(2026, 10, 26));
    });

    test('okno wstecz od niedzieli zaczyna się w ostatni dzień roboczy', () {
      expect(week.windowStart(sun, 1), fri);
      expect(week.windowStart(DateTime(2026, 10, 14), 3), mon);
      expect(week.workingDayOnOrBefore(sun), fri);
    });

    test('zmiana czasu (25.10.2026) nie gubi ani nie dubluje dnia', () {
      final d = DateTime(2026, 10, 23); // piątek przed zmianą czasu
      expect(week.nthWorkingDayAfter(d, 1), DateTime(2026, 10, 26));
      expect(addDays(DateTime(2026, 10, 25), 1), DateTime(2026, 10, 26));
      expect(week.countWorkingDays(DateTime(2026, 10, 19), DateTime(2026, 11, 1)),
          10);
    });
  });

  group('prognoza z weekendami', () {
    // Piątek 2026-10-16.
    final fri = DateTime(2026, 10, 16, 17);

    test('dziś z wpisami → liczenie od jutra, weekend pominięty', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
      );
      expect(f.pct, 80);
      expect(f.remaining, 30);
      expect(f.firstDay, DateTime(2026, 10, 17));
      expect(f.workingDaysNeeded, 3);
      // pn 19, wt 20, śr 21.
      expect(f.finish, DateTime(2026, 10, 21));
      expect(f.isDone, isFalse);
    });

    test('z sobotami koniec dzień wcześniej', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(saturdays: true),
      );
      // sob 17, pn 19, wt 20.
      expect(f.finish, DateTime(2026, 10, 20));
    });

    test('dziś bez wpisów → dziś jest pierwszym dniem pracy', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: false,
        week: const WorkWeek(),
      );
      // pt 16, pn 19, wt 20.
      expect(f.firstDay, DateTime(2026, 10, 16));
      expect(f.finish, DateTime(2026, 10, 20));
    });

    test('ułamek dnia zaokrąglany w górę', () {
      final f = computeForecast(
        unit: ScopeUnit.welds,
        done: 10,
        total: 31,
        pacePerDay: 4,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
      );
      // 21 / 4 = 5,25 → 6 dni roboczych: pn 19 … pn 26.
      expect(f.workingDaysNeeded, 6);
      expect(f.finish, DateTime(2026, 10, 26));
    });

    test('ile dziennie na termin i czy obecne tempo wystarcza', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 23),
      );
      // pn 19 … pt 23 = 5 dni roboczych → 30 / 5.
      expect(f.workingDaysToDue, 5);
      expect(f.requiredPerDay, 6);
      expect(f.onTrack, isTrue);
      expect(f.dueMissed, isFalse);

      final slow = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 5,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 21),
      );
      expect(slow.workingDaysToDue, 3);
      expect(slow.requiredPerDay, 10);
      expect(slow.onTrack, isFalse);
    });

    test('termin dziś po dzisiejszej pracy → brak dni roboczych', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 120,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 16),
      );
      expect(f.workingDaysToDue, 0);
      expect(f.requiredPerDay, isNull);
      expect(f.dueMissed, isTrue);
    });

    test('termin w niedzielę liczy dni do piątku', () {
      final f = computeForecast(
        unit: ScopeUnit.welds,
        done: 0,
        total: 20,
        pacePerDay: null,
        today: DateTime(2026, 10, 12),
        todayLogged: false,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 18),
      );
      expect(f.workingDaysToDue, 5);
      expect(f.requiredPerDay, 4);
      // Bez tempa nie ma daty końca, a termin i tak się liczy.
      expect(f.finish, isNull);
      expect(f.workingDaysNeeded, isNull);
      expect(f.onTrack, isNull);
    });

    test('zakres wykonany: 100% i więcej, bez daty i bez wymaganego tempa', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 160,
        total: 150,
        pacePerDay: 10,
        today: fri,
        todayLogged: true,
        week: const WorkWeek(),
        due: DateTime(2026, 10, 23),
      );
      expect(f.isDone, isTrue);
      expect(f.pct, closeTo(106.67, 0.01));
      expect(f.remaining, 0);
      expect(f.finish, isNull);
      expect(f.requiredPerDay, isNull);
      expect(f.dueMissed, isFalse);
    });

    test('tempo zero = brak tempa', () {
      final f = computeForecast(
        unit: ScopeUnit.di,
        done: 0,
        total: 100,
        pacePerDay: 0,
        today: fri,
        todayLogged: false,
        week: const WorkWeek(),
      );
      expect(f.finish, isNull);
      expect(f.pct, 0);
    });
  });

  group('zakres zapamiętany per projekt', () {
    test('klucz: projekt i pakiet bez wielkości liter i spacji', () {
      expect(ProgressScope.keyFor(' Blok 4 ', 'TP-03'),
          ProgressScope.keyFor('blok 4', 'tp-03 '));
      expect(ProgressScope.keyFor('Blok 4', ''),
          isNot(ProgressScope.keyFor('Blok 4', 'TP-03')));
    });

    test('JSON w obie strony; śmieci dają pusty zakres', () {
      const s = ProgressScope(
          unit: ScopeUnit.welds, total: 240, due: '2026-12-18', saturdays: true);
      final back = ProgressScope.decode(s.encode());
      expect(back.unit, ScopeUnit.welds);
      expect(back.total, 240);
      expect(back.due, '2026-12-18');
      expect(back.dueDate, DateTime(2026, 12, 18));
      expect(back.saturdays, isTrue);
      expect(back.week.isWorkingDay(DateTime(2026, 10, 17)), isTrue);

      for (final raw in [null, '', '{', '[]', '{"total": -5, "due": "2026-13-01"}']) {
        final x = ProgressScope.decode(raw);
        expect(x.hasTotal, isFalse, reason: raw);
        expect(x.due, '', reason: raw);
        expect(x.unit, ScopeUnit.di, reason: raw);
      }
    });
  });
}

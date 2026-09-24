import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/qualification/qualification_dates.dart';

void main() {
  group('addMonthsClamped', () {
    for (final (from, months, expected) in <(DateTime, int, DateTime)>[
      (DateTime(2026, 3, 15), 6, DateTime(2026, 9, 15)),
      (DateTime(2026, 9, 15), 6, DateTime(2027, 3, 15)),
      // Koniec miesiąca przycięty, nie przelany na następny miesiąc.
      (DateTime(2026, 8, 31), 6, DateTime(2027, 2, 28)),
      (DateTime(2027, 8, 31), 6, DateTime(2028, 2, 29)),
      (DateTime(2026, 12, 31), 6, DateTime(2027, 6, 30)),
      (DateTime(2026, 1, 31), 1, DateTime(2026, 2, 28)),
      (DateTime(2026, 7, 1), 6, DateTime(2027, 1, 1)),
    ]) {
      test('$from + $months mies. = $expected', () {
        expect(addMonthsClamped(from, months), expected);
      });
    }
  });

  group('calendarDaysBetween', () {
    test('godziny nie mają znaczenia', () {
      expect(
        calendarDaysBetween(
            DateTime(2026, 9, 10, 23, 59), DateTime(2026, 9, 11, 0, 1)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 9, 10, 18), DateTime(2026, 9, 10, 1)),
        0,
      );
      expect(calendarDaysBetween(DateTime(2026, 9, 11), DateTime(2026, 9, 10)),
          -1);
    });

    test('przez zmianę czasu (DST) — pełne dni kalendarzowe', () {
      // Ostatnia niedziela października i marca w Europie.
      expect(calendarDaysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)),
          2);
      expect(calendarDaysBetween(DateTime(2027, 3, 27), DateTime(2027, 3, 29)),
          2);
    });
  });

  group('parseFlexibleDate — daty z wolnego tekstu dziennika', () {
    for (final (raw, expected) in <(String?, DateTime?)>[
      ('2026-09-10', DateTime(2026, 9, 10)),
      ('2026-9-1', DateTime(2026, 9, 1)),
      ('2026-09-10T08:30:00', DateTime(2026, 9, 10)),
      ('2026-09-10 08:30', DateTime(2026, 9, 10)),
      ('2026.09.10', DateTime(2026, 9, 10)),
      ('10.09.2026', DateTime(2026, 9, 10)),
      ('1.9.2026', DateTime(2026, 9, 1)),
      ('10-09-2026', DateTime(2026, 9, 10)),
      ('10/09/2026', DateTime(2026, 9, 10)),
      ('  2026-09-10  ', DateTime(2026, 9, 10)),
      // Niepoprawne → null (pominięte, nie zgadywane).
      ('2026-02-30', null),
      ('31.04.2026', null),
      ('2026-13-01', null),
      ('10.09.26', null),
      ('jutro', null),
      ('', null),
      (null, null),
      ('1899-01-01', null),
    ]) {
      test('"$raw" → $expected', () {
        expect(parseFlexibleDate(raw), expected);
      });
    }
  });

  test('formatIsoDate', () {
    expect(formatIsoDate(DateTime(2026, 9, 1)), '2026-09-01');
  });
}

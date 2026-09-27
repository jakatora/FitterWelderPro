import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_dates.dart';

/// Pole daty w dzienniku było wolnym tekstem bez walidacji: "2026-0" albo
/// "30.02" trafiały do bazy, a potem wypadały z zakresu dat w PDF i z filtra.
void main() {
  test('poprawna data ISO zostaje bez zmian', () {
    expect(normalizeWeldDate('2026-09-24'), '2026-09-24');
    expect(normalizeWeldDate('  2026-09-24 '), '2026-09-24');
  });

  test('polski zapis DD.MM.RRRR zamieniany na ISO', () {
    expect(normalizeWeldDate('24.09.2026'), '2026-09-24');
    expect(normalizeWeldDate('4.9.2026'), '2026-09-04');
  });

  test('brakujące zera w ISO są uzupełniane', () {
    expect(normalizeWeldDate('2026-9-4'), '2026-09-04');
  });

  test('pusta data jest dozwolona (pole nieobowiązkowe)', () {
    expect(normalizeWeldDate(''), '');
    expect(normalizeWeldDate('   '), '');
  });

  test('nieistniejące i śmieciowe daty są odrzucane', () {
    expect(normalizeWeldDate('2026-02-30'), isNull);
    expect(normalizeWeldDate('2026-13-01'), isNull);
    expect(normalizeWeldDate('2026-0'), isNull);
    expect(normalizeWeldDate('wczoraj'), isNull);
    expect(normalizeWeldDate('31.04.2026'), isNull);
  });

  test('isIsoWeldDate przepuszcza tylko pełną, istniejącą datę', () {
    expect(isIsoWeldDate('2026-09-24'), isTrue);
    expect(isIsoWeldDate('2026-02-29'), isFalse);
    expect(isIsoWeldDate('2028-02-29'), isTrue);
    expect(isIsoWeldDate('24.09.2026'), isFalse);
    expect(isIsoWeldDate(''), isFalse);
  });

  test('rok spoza zakresu 2000..(dziś+1) to literówka, nie data', () {
    final today = DateTime(2026, 9, 26);
    expect(normalizeWeldDate('2062-09-01', today: today), isNull);
    expect(normalizeWeldDate('0026-09-01', today: today), isNull);
    expect(normalizeWeldDate('01.09.1999', today: today), isNull);
    expect(normalizeWeldDate('2000-01-01', today: today), '2000-01-01');
    expect(normalizeWeldDate('2027-12-31', today: today), '2027-12-31');
    expect(normalizeWeldDate('2028-01-01', today: today), isNull);
  });

  test('data z przyszłości jest rozpoznawana (ostrzeżenie, nie blokada)', () {
    final today = DateTime(2026, 9, 26, 23, 59);
    expect(isFutureWeldDate('2026-09-27', today: today), isTrue);
    expect(isFutureWeldDate('2026-09-26', today: today), isFalse);
    expect(isFutureWeldDate('', today: today), isFalse);
  });
}

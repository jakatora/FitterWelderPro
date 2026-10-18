// Jednostki „Tolerancji spoola”: mm kanoniczne, cale z ułamkami, kierunek
// zaokrągleń (tolerancja w dół, odchyłka w górę), odczyt i formatowanie pól.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/spool_check/spool_units.dart';

void main() {
  test('cale: ułamki do 1/64″ przeliczają się dokładnie (1/16″ = 1,5875 mm, '
      '1/8″ = 3,175 mm, 1/32″ = 0,79375 mm)', () {
    expect(spoolToleranceFromInch(1 / 16), 1.5875);
    expect(spoolToleranceFromInch(1 / 8), 3.175);
    expect(spoolToleranceFromInch(3 / 16), 4.7625);
    expect(spoolToleranceFromInch(1 / 32), 0.79375);
    expect(spoolToleranceFromInch(1 / 64), 0.396875);
    // Odchyłka liczona z długości w calach trafia w tę samą wartość.
    expect(spoolDeviationMm(100.125 * 25.4, 100 * 25.4), 3.175);
    expect(spoolDeviationMm(100 * 25.4, 100.0625 * 25.4), 1.5875);
  });

  test('tolerancja z cali w dół, odchyłka w górę — wartości spoza siatki',
      () {
    // 0,1234567″ = 3,13580018 mm → tolerancja 3,135800, odchyłka 3,135801.
    const inch = 0.1234567;
    final tol = spoolToleranceToMm(inch, SpoolUnit.inch);
    final dev = spoolCeilMm(inch * 25.4);
    expect(tol, 3.1358);
    expect(dev, 3.135801);
    expect(tol, lessThan(inch * 25.4));
    expect(dev, greaterThan(inch * 25.4));
    // Ta sama liczba jako tolerancja i jako odchyłka — ostrzej: poza.
    expect(spoolWithin(dev, tol), isFalse);
    // Wartości w mm wpisane wprost nie zmieniają się.
    expect(spoolToleranceToMm(3, SpoolUnit.mm), 3);
    expect(spoolDeviationMm(1253.5, 1250), 3.5);
    expect(spoolDeviationMm(2543.2, 2540), 3.2);
  });

  test('granica włącznie: odchyłka = tolerancja → w tolerancji; o krok siatki '
      'więcej → poza', () {
    expect(spoolWithin(3.0, 3.0), isTrue);
    expect(spoolWithin(spoolDeviationMm(1253, 1250), 3.0), isTrue);
    expect(spoolWithin(3.000001, 3.0), isFalse);
    expect(spoolWithin(spoolDeviationMm(1253.001, 1250), 3.0), isFalse);
    // Duże długości (20 m) — błąd double nie przesuwa granicy.
    expect(spoolWithin(spoolDeviationMm(20003, 20000), 3.0), isTrue);
    expect(spoolWithin(spoolDeviationMm(20000, 20003.175), 3.175), isTrue);
  });

  test('odczyt cali: 98 1/2, 98-1/2, 3/16, 8\' 2 1/2", 1,5 — i odrzucenie '
      '1/0 oraz tekstu', () {
    expect(parseSpoolInches('98 1/2'), 98.5);
    expect(parseSpoolInches('98-1/2'), 98.5);
    expect(parseSpoolInches('98 1/2"'), 98.5);
    expect(parseSpoolInches('98 1/2″'), 98.5);
    expect(parseSpoolInches('3/16'), 3 / 16);
    expect(parseSpoolInches('1,5'), 1.5);
    expect(parseSpoolInches('1.5 in'), 1.5);
    expect(parseSpoolInches("8' 2 1/2\""), 98.5);
    expect(parseSpoolInches("8'-2 1/2"), 98.5);
    expect(parseSpoolInches("8'"), 96);
    expect(parseSpoolInches('1/0'), isNull);
    expect(parseSpoolInches('abc'), isNull);
    expect(parseSpoolInches('1 1/'), isNull);
    expect(parseSpoolInches(''), isNull);
    // Długość z cali — dokładny iloczyn (bez zaokrąglania wartości).
    expect(parseSpoolLength('98 1/2', SpoolUnit.inch), closeTo(2501.9, 1e-9));
  });

  test('odczyt mm: przecinek i kropka; ujemne, puste i nieczytelne → null '
      '(nie zero)', () {
    expect(parseSpoolLength('1253,5', SpoolUnit.mm), 1253.5);
    expect(parseSpoolLength('1253.5', SpoolUnit.mm), 1253.5);
    expect(parseSpoolLength('1253,5 mm', SpoolUnit.mm), 1253.5);
    expect(parseSpoolLength('-3', SpoolUnit.mm), isNull);
    expect(parseSpoolLength('', SpoolUnit.mm), isNull);
    expect(parseSpoolLength('12a', SpoolUnit.mm), isNull);
    expect(parseSpoolLength('-1/8', SpoolUnit.inch), isNull);
  });

  test('formatowanie: ułamek do 1/64, inaczej ≈ dziesiętnie; PL przecinek, '
      'EN kropka', () {
    expect(spoolFormatLength(2501.9, SpoolUnit.inch, en: false), '98 1/2″');
    expect(spoolFormatLength(3.175, SpoolUnit.inch, en: false), '1/8″');
    expect(spoolFormatLength(3, SpoolUnit.inch, en: false), '≈0,118″');
    expect(spoolFormatLength(3, SpoolUnit.inch, en: true), '≈0.118″');
    expect(spoolFormatLength(0.79375, SpoolUnit.mm, en: false), '0,79375 mm');
    expect(spoolFormatBoth(3.175, SpoolUnit.mm, en: false), '3,175 mm (1/8″)');
    expect(spoolFormatBoth(3.175, SpoolUnit.inch, en: true), '1/8″ (3.175 mm)');
    expect(spoolFormatSigned(-3.5, SpoolUnit.mm, en: false), '−3,5 mm');
    expect(spoolFormatSigned(3.175, SpoolUnit.inch, en: false), '+1/8″');
    expect(spoolFieldText(2501.9, SpoolUnit.inch, en: false), '98 1/2');
    expect(spoolFieldText(1250, SpoolUnit.inch, en: false), '49,212598');
    expect(spoolFieldText(1253.5, SpoolUnit.mm, en: false), '1253,5');
    expect(spoolFieldText(null, SpoolUnit.mm, en: false), '');
  });
}

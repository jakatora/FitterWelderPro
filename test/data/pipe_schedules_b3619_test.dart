// Ścianki stali nierdzewnej wg ASME B36.19M (5S, 10S, 40S, 80S) — przypięte
// wartość po wartości. Źródła (sprawdzone 2026-09-26):
//  • Wikipedia „Nominal Pipe Size”, tabele Sch 5S/10S/40S/80S (B36.19);
//  • projectmaterials.com „Pipe dimensions ASME B36.10 / B36.19”: „At NPS 12,
//    Sch 40 is 10.31 mm wall per B36.10, but Sch 40S is only 9.53 mm”,
//    NPS 10: 80 = 15.09 / 80S = 12.70; NPS 12: 80 = 17.48 / 80S = 12.70.
// Różnice względem B36.10M: 40S od NPS 12 = 9,53; 80S od NPS 10 = 12,70.
//
// Masa SS: ρ 316/316L = 8,0 kg/dm³ (EN 10088-1). 12" 40S:
//   π·(323,8 − 9,53)·9,53·8,0·10⁻³ = 75,27 kg/m
//   (aplikacja przed poprawką przy SS pokazywała „40” = 10,31 mm).
// ID = OD − 2t: NPS 2 Sch 40 → 60,3 − 2·3,91 = 52,48 mm.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/pipe_schedules.dart';

/// DN → (5S, 10S, 40S, 80S) mm.
const Map<int, (double, double, double, double)> _b3619 = {
  15: (1.65, 2.11, 2.77, 3.73),
  20: (1.65, 2.11, 2.87, 3.91),
  25: (1.65, 2.77, 3.38, 4.55),
  32: (1.65, 2.77, 3.56, 4.85),
  40: (1.65, 2.77, 3.68, 5.08),
  50: (1.65, 2.77, 3.91, 5.54),
  65: (2.11, 3.05, 5.16, 7.01),
  80: (2.11, 3.05, 5.49, 7.62),
  100: (2.11, 3.05, 6.02, 8.56),
  125: (2.77, 3.40, 6.55, 9.53),
  150: (2.77, 3.40, 7.11, 10.97),
  200: (2.77, 3.76, 8.18, 12.70),
  250: (3.40, 4.19, 9.27, 12.70),
  300: (3.96, 4.57, 9.53, 12.70),
  350: (3.96, 4.78, 9.53, 12.70),
  400: (4.19, 4.78, 9.53, 12.70),
  450: (4.19, 4.78, 9.53, 12.70),
  500: (4.78, 5.54, 9.53, 12.70),
  600: (5.54, 6.35, 9.53, 12.70),
};

PipeRow _row(int dn) => kPipeWalls.firstWhere((r) => r.dn == dn);

void main() {
  test('kolumny SS = B36.19M, CS = B36.10M', () {
    expect(kSchedulesStainless, ['5S', '10S', '40S', '80S']);
    expect(kSchedulesCarbon, ['STD', '40', '80', '160', 'XS', 'XXS']);
    expect(schedulesFor(stainless: true), kSchedulesStainless);
    expect(schedulesFor(stainless: false), kSchedulesCarbon);
  });

  for (final e in _b3619.entries) {
    test('DN${e.key}: 5S ${e.value.$1} / 10S ${e.value.$2} / '
        '40S ${e.value.$3} / 80S ${e.value.$4}', () {
      final w = _row(e.key).walls;
      expect(w['5S'], e.value.$1);
      expect(w['10S'], e.value.$2);
      expect(w['40S'], e.value.$3);
      expect(w['80S'], e.value.$4);
    });
  }

  test('NPS 10/12: 40S i 80S różne od Sch 40 / 80 (B36.10M)', () {
    expect(_row(300).walls['40'], 10.31);
    expect(_row(300).walls['40S'], 9.53);
    expect(_row(250).walls['80'], 15.09);
    expect(_row(250).walls['80S'], 12.70);
    expect(_row(300).walls['80'], 17.48);
    expect(_row(300).walls['80S'], 12.70);
  });

  test('ID = OD − 2t: NPS 2 Sch 40 → 52,48 mm', () {
    expect(insideDiameterMm(_row(50), '40'), closeTo(52.48, 1e-9));
    expect(insideDiameterMm(_row(600), 'XXS'), isNull);
  });

  test('masa SS liczona dla ρ 8,0 (316/316L)', () {
    expect(kDensityStainless, 8.0);
    expect(massPerMeter(_row(300), '40S', stainless: true),
        closeTo(75.27, 0.01));
  });
}

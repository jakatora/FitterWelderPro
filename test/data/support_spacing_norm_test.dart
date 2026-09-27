// Rozstaw podpór rury stalowej — przypięcie KAŻDEJ wartości do normy.
//
// Źródła (sprawdzone 2026-09-26):
//  • ANSI/MSS SP-58-2018 Tab. 4 (dawniej MSS SP-69 Tab. 3) „Maximum horizontal
//    pipe hanger and support spacing”, rura stalowa ścianka standard,
//    kolumny „water service” i „vapor service” w ft i m:
//      – PHD Mfg „Steel pipe data / Spacing of hangers for steel pipe”
//        (Taken from ANSI/MSS SP-58), kolumna woda: 7 7 7 7 9 10 11 12 13 14
//        16 17 19 22 23 25 27 28 30 32 ft dla NPS 1/2 … 24;
//      – HardHat Engineer „MSS SP-69 span chart” (woda i para, ft/m);
//      – Engineers Edge „Pipe support hanger spacing” (adapted from MSS SP-69).
//  • ASME B31.1 Tab. 121.5 (wermac.org): NPS 1/2/3/4/6/8/12/16/20/24 —
//    woda 2,1/3,0/3,7/4,3/5,2/5,8/7,0/8,2/9,1/9,8 m, para/gaz/powietrze
//    2,7/4,0/4,6/5,2/6,4/7,3/9,1/10,7/11,9/12,8 m. Tabela zakłada rurę
//    IZOLOWANĄ wypełnioną wodą (lub równoważny ciężar dla pary) i ugięcie
//    2,5 mm; nie dotyczy obciążeń skupionych (zawory, kołnierze).
// Wartości metryczne = kolumna „m” normy (ft × 0,3048 zaokrąglone do 0,1 m).
// Obie normy są zgodne tam, gdzie obie podają rozmiar.
//
// Poprzednio aplikacja: DN20 i DN32 ciecz 2,4 m (norma 2,1 — strona
// niebezpieczna), od DN250 ciecz o wiersz niżej, od DN150 gaz 10–40 % poniżej
// normy, a do tego nienormowe −12 % „za izolację”.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/support_spacing.dart';

/// DN → (woda/ciecz mm, para/gaz mm) wg MSS SP-58 Tab. 4.
const Map<int, (int, int)> _norm = {
  15: (2100, 2400), //   1/2": 7 ft / 8 ft
  20: (2100, 2700), //   3/4": 7 ft / 9 ft
  25: (2100, 2700), //   1":   7 ft / 9 ft   (B31.1: 2,1 / 2,7)
  32: (2100, 2700), // 1 1/4": 7 ft / 9 ft
  40: (2700, 3700), // 1 1/2": 9 ft / 12 ft
  50: (3000, 4000), //   2":  10 ft / 13 ft  (B31.1: 3,0 / 4,0)
  65: (3400, 4300), // 2 1/2": 11 ft / 14 ft
  80: (3700, 4600), //   3":  12 ft / 15 ft  (B31.1: 3,7 / 4,6)
  90: (4000, 4900), // 3 1/2": 13 ft / 16 ft
  100: (4300, 5200), //  4":  14 ft / 17 ft  (B31.1: 4,3 / 5,2)
  125: (4900, 5800), //  5":  16 ft / 19 ft
  150: (5200, 6400), //  6":  17 ft / 21 ft  (B31.1: 5,2 / 6,4)
  200: (5800, 7300), //  8":  19 ft / 24 ft  (B31.1: 5,8 / 7,3)
  250: (6700, 7900), // 10":  22 ft / 26 ft
  300: (7000, 9100), // 12":  23 ft / 30 ft  (B31.1: 7,0 / 9,1)
  350: (7600, 9800), // 14":  25 ft / 32 ft
  400: (8200, 10700), // 16": 27 ft / 35 ft  (B31.1: 8,2 / 10,7)
  450: (8500, 11300), // 18": 28 ft / 37 ft
  500: (9100, 11900), // 20": 30 ft / 39 ft  (B31.1: 9,1 / 11,9)
  600: (9800, 12800), // 24": 32 ft / 42 ft  (B31.1: 9,8 / 12,8)
};

void main() {
  test('tabela ma dokładnie wiersze normy DN15…DN600 (z DN90 i DN125)', () {
    expect(kSupportSpans.map((s) => s.dn).toList(), _norm.keys.toList());
  });

  for (final e in _norm.entries) {
    test('DN${e.key}: ciecz ${e.value.$1} mm, gaz/para ${e.value.$2} mm', () {
      final s = supportSpanForDn(e.key)!;
      expect(s.waterMm, e.value.$1, reason: 'woda DN${e.key}');
      expect(s.vaporMm, e.value.$2, reason: 'para DN${e.key}');
      expect(maxSupportSpacingMm(e.key, liquidFilled: true), e.value.$1);
      expect(maxSupportSpacingMm(e.key, liquidFilled: false), e.value.$2);
    });
  }

  test('DN20 i DN32 dla cieczy to 2,1 m, nie 2,4 m', () {
    expect(maxSupportSpacingMm(20, liquidFilled: true), 2100);
    expect(maxSupportSpacingMm(32, liquidFilled: true), 2100);
  });

  test('bez nienormowego −12 %: domyślnie brak żadnej obniżki', () {
    // B31.1 Tab. 121.5 jest już liczona dla rury izolowanej.
    expect(maxSupportSpacingMm(100, liquidFilled: true), 4300);
  });

  test('zapas własny to jawna opcja użytkownika w %, nie domyślna', () {
    expect(maxSupportSpacingMm(100, liquidFilled: true, ownMarginPct: 10),
        3870); // 4300 × 0,90
    expect(maxSupportSpacingMm(50, liquidFilled: false, ownMarginPct: 0),
        4000);
  });

  test('NPS w tabeli zgodne z DN', () {
    expect(supportSpanForDn(90)!.nps, '3 1/2');
    expect(supportSpanForDn(125)!.nps, '5');
  });
}

// Ciśnienie próby — czyste funkcje z lib/domain/pressure_test/test_pressure.dart.
//
// Źródła wzorów (zweryfikowane 2026-09-24):
//  * ASME B31.3 §345.4.2 — próba hydrostatyczna: Pt = 1,5 · P · ST/S,
//    ST/S ≤ 6,5 (B31.3: „the value of ST/S shall not exceed 6.5”).
//    §345.2.1(a) (w starszych wydaniach §345.4.2(c)) — Pt można obniżyć, gdy
//    naprężenie obwodowe przekroczyłoby granicę plastyczności w temp. próby.
//    §345.2.2(a) — ciśnienie próby utrzymywać co najmniej 10 min.
//    Źródło: G. Antaki, „PRE-L-02 Assessment of Safety Equivalency
//    EN 13480 – ASME B31.3”, US DOE, 2024 (cytuje §345.2.1(a), §345.2.2(a)).
//  * ASME B31.3 §345.5.4 — próba pneumatyczna: Pt ≥ 1,1 · P, nie więcej niż
//    mniejsza z: 1,33 · P albo ciśnienie dające 90 % Re.
//  * ASME B31.1 §137.4.5 — próba hydrostatyczna: Pt ≥ 1,5 · P (bez ST/S).
//  * EN 13480-5 (§9.3.2) / PED 2014/68/UE zał. I pkt 7.4 — większa z:
//    1,25 · PS · f_test/f  albo  1,43 · PS; czas trzymania 30 min.
//  * ASME VIII-1 UG-99(b) — Pt = 1,3 · MAWP · LSR.
//
// Ręczne przeliczenia w komentarzach przy przypadkach.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pressure_test/test_pressure.dart';

void main() {
  group('computeTestPressure — tabela przypadków', () {
    // (preset, P [bar], stosunek naprężeń, oczekiwane Pt [bar], opis)
    const cases = <(PressureTestPreset, double, double, double, String)>[
      // B31.3 hydro: 1,5 · 10 · 1,0 = 15,0
      (PressureTestPreset.b313Hydro, 10, 1.0, 15.0, 'B31.3 ST/S = 1'),
      // B31.3 hydro: 1,5 · 10 · 1,2 = 18,0 (dotąd ekran dawał 15,0)
      (PressureTestPreset.b313Hydro, 10, 1.2, 18.0, 'B31.3 ST/S = 1,2'),
      // B31.3 hydro: ST/S = 8 → ograniczone do 6,5 → 1,5 · 10 · 6,5 = 97,5
      (PressureTestPreset.b313Hydro, 10, 8.0, 97.5, 'B31.3 ST/S > 6,5'),
      // B31.3 pneumatyczna: 1,1 · 10 = 11,0 (stosunek ignorowany)
      (PressureTestPreset.b313Pneumatic, 10, 1.2, 11.0, 'B31.3 pneu'),
      // B31.1 hydro: 1,5 · 10 = 15,0 (bez korekty temperaturowej)
      (PressureTestPreset.b311Hydro, 10, 1.2, 15.0, 'B31.1'),
      // EN 13480-5: max(1,25 · 10 · 1,0; 1,43 · 10) = max(12,5; 14,3) = 14,3
      (PressureTestPreset.en13480Hydro, 10, 1.0, 14.3, 'EN 13480 f/f = 1'),
      // EN 13480-5: max(1,25 · 10 · 1,2; 14,3) = max(15,0; 14,3) = 15,0
      (PressureTestPreset.en13480Hydro, 10, 1.2, 15.0, 'EN 13480 f/f = 1,2'),
      // ASME VIII-1 UG-99(b): 1,3 · 10 · 1,0 = 13,0
      (PressureTestPreset.asmeVIII1Hydro, 10, 1.0, 13.0, 'VIII-1 LSR = 1'),
      // ASME VIII-1 UG-99(b): 1,3 · 10 · 1,25 = 16,25
      (PressureTestPreset.asmeVIII1Hydro, 10, 1.25, 16.25, 'VIII-1 LSR 1,25'),
    ];
    for (final (preset, p, ratio, expected, label) in cases) {
      test('$label: P = $p bar, stosunek $ratio → Pt = $expected bar', () {
        final r = computeTestPressure(
            preset: preset, designBar: p, stressRatio: ratio);
        expect(r.testPressureBar, closeTo(expected, 1e-9));
        expect(r.effectiveFactor, closeTo(expected / p, 1e-9));
      });
    }
  });

  test('B31.3: P = 10 bar, ST/S = 1,2 daje 18 bar, nie 15 (brak korekty)', () {
    final r = computeTestPressure(
        preset: PressureTestPreset.b313Hydro, designBar: 10, stressRatio: 1.2);
    expect(r.testPressureBar, closeTo(18.0, 1e-9));
    expect(r.testPressureBar, isNot(closeTo(15.0, 1e-6)));
    expect(r.ratioApplied, 1.2);
    expect(r.ratioCapped, isFalse);
  });

  test('B31.3: ST/S powyżej 6,5 jest obcinane i to jest zgłaszane', () {
    final r = computeTestPressure(
        preset: PressureTestPreset.b313Hydro, designBar: 10, stressRatio: 7);
    expect(r.ratioApplied, 6.5);
    expect(r.ratioCapped, isTrue);
  });

  test('EN 13480: informuje, który człon max() rządzi', () {
    final low = computeTestPressure(
        preset: PressureTestPreset.en13480Hydro, designBar: 10);
    expect(low.floorGoverns, isTrue); // 1,43 · PS
    final high = computeTestPressure(
        preset: PressureTestPreset.en13480Hydro,
        designBar: 10,
        stressRatio: 1.2);
    expect(high.floorGoverns, isFalse); // 1,25 · PS · f_test/f
  });

  test('B31.3 pneumatyczna: górna granica 1,33 · P', () {
    final r = computeTestPressure(
        preset: PressureTestPreset.b313Pneumatic, designBar: 10);
    // 1,33 · 10 = 13,3
    expect(r.maxTestPressureBar, closeTo(13.3, 1e-9));
    expect(
        computeTestPressure(
                preset: PressureTestPreset.b313Hydro, designBar: 10)
            .maxTestPressureBar,
        isNull);
  });

  test('presety bez stosunku naprężeń ignorują wpisaną wartość', () {
    for (final p in [
      PressureTestPreset.b313Pneumatic,
      PressureTestPreset.b311Hydro,
    ]) {
      expect(p.ratioSymbol, isNull, reason: p.id);
      expect(
          computeTestPressure(preset: p, designBar: 10, stressRatio: 3)
              .ratioApplied,
          1.0,
          reason: p.id);
    }
  });

  test('współczynniki, paragrafy i minimalne czasy trzymania presetów', () {
    expect(PressureTestPreset.b313Hydro.factor, 1.5);
    expect(PressureTestPreset.b313Hydro.clause, '§345.4.2');
    expect(PressureTestPreset.b313Hydro.minHoldMinutes, 10);
    expect(PressureTestPreset.b313Hydro.holdClause, contains('§345.2.2(a)'));
    expect(PressureTestPreset.b313Pneumatic.factor, 1.1);
    expect(PressureTestPreset.b313Pneumatic.method,
        PressureTestMethod.pneumatic);
    expect(PressureTestPreset.b313Pneumatic.clause, '§345.5.4');
    expect(PressureTestPreset.b311Hydro.factor, 1.5);
    expect(PressureTestPreset.b311Hydro.clause, '§137.4.5');
    expect(PressureTestPreset.en13480Hydro.factor, 1.25);
    expect(PressureTestPreset.en13480Hydro.floorFactor, 1.43);
    expect(PressureTestPreset.en13480Hydro.minHoldMinutes, 30);
    expect(PressureTestPreset.asmeVIII1Hydro.factor, 1.3);
    expect(PressureTestPreset.asmeVIII1Hydro.clause, 'UG-99(b)');
    // Id są zapisywane w bazie — nie wolno ich zmieniać.
    for (final p in PressureTestPreset.values) {
      expect(PressureTestPreset.fromId(p.id), p);
    }
    expect(PressureTestPreset.fromId('nieznany'), isNull);
    expect(PressureTestPreset.fromId(null), isNull);
  });

  test('błędne wejście rzuca ArgumentError', () {
    expect(
        () => computeTestPressure(
            preset: PressureTestPreset.b313Hydro, designBar: 0),
        throwsArgumentError);
    expect(
        () => computeTestPressure(
            preset: PressureTestPreset.b313Hydro,
            designBar: 10,
            stressRatio: 0),
        throwsArgumentError);
    expect(
        () => computeTestPressure(
            preset: PressureTestPreset.b313Hydro,
            designBar: double.nan),
        throwsArgumentError);
  });

  group('naprężenie obwodowe przy ciśnieniu próby (§345.2.1(a))', () {
    test('Barlow: σ = P·D/(2t)', () {
      // 60,3 × 3,91 mm, 150 bar = 15 MPa: σ = 15 · 60,3 / (2 · 3,91)
      //   = 904,5 / 7,82 = 115,665 MPa
      expect(
          hoopStressMpa(pressureBar: 150, odMm: 60.3, wallMm: 3.91),
          closeTo(115.665, 1e-3));
    });

    test('ciśnienie dające naprężenie równe Re', () {
      // Re = 240 MPa: P = 2 · 3,91 · 240 / 60,3 = 31,124 MPa = 311,24 bar
      expect(
          pressureAtHoopStressBar(stressMpa: 240, odMm: 60.3, wallMm: 3.91),
          closeTo(311.24, 0.01));
    });

    test('geometria spoza dziedziny rzuca ArgumentError', () {
      expect(() => hoopStressMpa(pressureBar: 10, odMm: 60.3, wallMm: 0),
          throwsArgumentError);
      expect(() => hoopStressMpa(pressureBar: 10, odMm: 6, wallMm: 3),
          throwsArgumentError);
    });
  });
}

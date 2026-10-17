// Stopień zaciemnienia filtra: wiersze kontrolne EN 169 i ANSI Z49.1 / OSHA
// dla każdego procesu, granice przedziałów (na granicy wyższy; tabele gazowe
// EN — jawnie „q ≤ …”), wartości poza tabelą, bezpieczny wybór, walidacja,
// tekst do udostępnienia. Wartości i źródła: lib/domain/welding/shade_number.dart.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/shade_number.dart';

ShadeLookup _en(ShadeProcess p, double v) => en169Table(p).lookup(v);
ShadeLookup _ansi(ShadeProcess p, double v) => ansiTable(p).lookup(v);

ShadeAdvice _arc(ShadeProcess p, double a) =>
    computeShade(ShadeInput(process: p, currentA: a))!;

/// (minimum OSHA, zalecany od, zalecany do).
(int, int?, int?) _ansiRow(ShadeProcess p, double v) {
  final l = _ansi(p, v);
  return (l.shade, l.band.suggestedLow, l.band.suggestedHigh);
}

void main() {
  group('EN 169 — wiersze kontrolne', () {
    test('elektrody otulone: 8 do 60 A, 9, 10, 11, 12, 13, 14 od 450 A', () {
      const p = ShadeProcess.mma;
      expect(_en(p, 1).shade, 8);
      expect(_en(p, 59.9).shade, 8);
      expect(_en(p, 80).shade, 9);
      expect(_en(p, 120).shade, 10);
      expect(_en(p, 180).shade, 11);
      expect(_en(p, 250).shade, 12);
      expect(_en(p, 400).shade, 13);
      expect(_en(p, 500).shade, 14);
    });

    test('MAG: 8 do 70 A … 12 do 400 A, 13, 14 od 550 A', () {
      const p = ShadeProcess.mag;
      expect(_en(p, 50).shade, 8);
      expect(_en(p, 90).shade, 9);
      expect(_en(p, 120).shade, 10);
      expect(_en(p, 200).shade, 11);
      expect(_en(p, 300).shade, 12);
      expect(_en(p, 549).shade, 13);
      expect(_en(p, 580).shade, 14);
    });

    test('TIG: od 10 A — 8, 9, 10, 11, 12, 13 do 350 A', () {
      const p = ShadeProcess.tig;
      expect(_en(p, 20).shade, 8);
      expect(_en(p, 50).shade, 9);
      expect(_en(p, 100).shade, 10);
      expect(_en(p, 150).shade, 11);
      expect(_en(p, 250).shade, 12);
      expect(_en(p, 320).shade, 13);
    });

    test('MIG na metalach ciężkich: 70–500 A, 9 … 14', () {
      const p = ShadeProcess.migHeavy;
      expect(_en(p, 100).shade, 9);
      expect(_en(p, 150).shade, 10);
      expect(_en(p, 200).shade, 11);
      expect(_en(p, 300).shade, 12);
      expect(_en(p, 400).shade, 13);
      expect(_en(p, 480).shade, 14);
    });

    test('MIG na stopach lekkich: 125–500 A — do 1 stopnia ciemniej niż stal',
        () {
      const p = ShadeProcess.migLight;
      expect(_en(p, 150).shade, 10);
      expect(_en(p, 200).shade, 11);
      expect(_en(p, 240).shade, 12);
      expect(_en(p, 240).shade - _en(ShadeProcess.migHeavy, 240).shade, 1);
      expect(_en(p, 320).shade, 13);
      expect(_en(p, 420).shade, 14);
    });

    test('żłobienie łukowo-powietrzne: 10 do 175 A … 15 od 450 A', () {
      const p = ShadeProcess.arcGouging;
      expect(_en(p, 100).shade, 10);
      expect(_en(p, 180).shade, 11);
      expect(_en(p, 220).shade, 12);
      expect(_en(p, 300).shade, 13);
      expect(_en(p, 400).shade, 14);
      expect(_en(p, 500).shade, 15);
    });

    test('cięcie plazmowe: 100–400 A, 9, 10, 11, 12, 13', () {
      const p = ShadeProcess.plasmaCutting;
      expect(_en(p, 110).shade, 9);
      expect(_en(p, 140).shade, 10);
      expect(_en(p, 160).shade, 11);
      expect(_en(p, 200).shade, 12);
      expect(_en(p, 300).shade, 13);
    });

    test('spawanie (mikro)plazmowe: 1,5–300 A, 4 … 12', () {
      const p = ShadeProcess.plasmaWelding;
      expect(_en(p, 3).shade, 4);
      expect(_en(p, 10).shade, 5);
      expect(_en(p, 20).shade, 6);
      expect(_en(p, 50).shade, 7);
      expect(_en(p, 80).shade, 8);
      expect(_en(p, 110).shade, 9);
      expect(_en(p, 150).shade, 10);
      expect(_en(p, 200).shade, 11);
      expect(_en(p, 260).shade, 12);
    });

    test('spawanie gazowe po przepływie acetylenu: 4, 5, 6, 7', () {
      const p = ShadeProcess.gasWelding;
      expect(_en(p, 50).shade, 4);
      expect(_en(p, 150).shade, 5);
      expect(_en(p, 500).shade, 6);
      expect(_en(p, 1200).shade, 7);
    });

    test('cięcie tlenowe po przepływie tlenu: 900–8000 l/h → 5, 6, 7', () {
      const p = ShadeProcess.oxyCutting;
      expect(_en(p, 1500).shade, 5);
      expect(_en(p, 3000).shade, 6);
      expect(_en(p, 6000).shade, 7);
    });
  });

  group('ANSI Z49.1 / OSHA — wiersze kontrolne', () {
    test(
        'SMAW: < 60 min 7 bez zalecenia; 60–160 8/10; 160–250 10/12; '
        '250–550 11/14', () {
      const p = ShadeProcess.mma;
      expect(_ansiRow(p, 40), (7, null, null));
      expect(_ansiRow(p, 120), (8, 10, 10));
      expect(_ansiRow(p, 200), (10, 12, 12));
      expect(_ansiRow(p, 400), (11, 14, 14));
    });

    test('GMAW / FCAW dla MAG i obu MIG: 60–160 10/11, 250–500 10/14', () {
      for (final p in [
        ShadeProcess.mag,
        ShadeProcess.migHeavy,
        ShadeProcess.migLight
      ]) {
        expect(_ansiRow(p, 40), (7, null, null), reason: p.name);
        expect(_ansiRow(p, 100), (10, 11, 11), reason: p.name);
        expect(_ansiRow(p, 200), (10, 12, 12), reason: p.name);
        expect(_ansiRow(p, 300), (10, 14, 14), reason: p.name);
      }
    });

    test('GTAW: < 50 8/10; 50–150 8/12; 150–500 10/14', () {
      const p = ShadeProcess.tig;
      expect(_ansiRow(p, 20), (8, 10, 10));
      expect(_ansiRow(p, 100), (8, 12, 12));
      expect(_ansiRow(p, 200), (10, 14, 14));
    });

    test('CAC-A: < 500 10/12; 500–1000 11/14', () {
      const p = ShadeProcess.arcGouging;
      expect(_ansiRow(p, 300), (10, 12, 12));
      expect(_ansiRow(p, 800), (11, 14, 14));
    });

    test('PAW: < 20 6/6–8; 20–100 8/10; 100–400 10/12; 400–800 11/14', () {
      const p = ShadeProcess.plasmaWelding;
      expect(_ansiRow(p, 10), (6, 6, 8));
      expect(_ansiRow(p, 50), (8, 10, 10));
      expect(_ansiRow(p, 200), (10, 12, 12));
      expect(_ansiRow(p, 600), (11, 14, 14));
    });

    test('PAC: < 300 8/9; 300–400 9/12; 400–800 10/14', () {
      const p = ShadeProcess.plasmaCutting;
      expect(_ansiRow(p, 40), (8, 9, 9));
      expect(_ansiRow(p, 350), (9, 12, 12));
      expect(_ansiRow(p, 600), (10, 14, 14));
    });

    test(
        'spawanie gazowe po grubości: < 3,2 4/4–5; 3,2–12,7 5/5–6; '
        '> 12,7 6/6–8', () {
      const p = ShadeProcess.gasWelding;
      expect(_ansiRow(p, 2), (4, 4, 5));
      expect(_ansiRow(p, 8), (5, 5, 6));
      expect(_ansiRow(p, 20), (6, 6, 8));
    });

    test('cięcie tlenowe po grubości: < 25 3/3–4; 25–150 4/4–5; > 150 5/5–6',
        () {
      const p = ShadeProcess.oxyCutting;
      expect(_ansiRow(p, 10), (3, 3, 4));
      expect(_ansiRow(p, 100), (4, 4, 5));
      expect(_ansiRow(p, 200), (5, 5, 6));
    });
  });

  group('granice przedziałów', () {
    test('wykres EN 169: wartość na kresce → wyższy stopień', () {
      expect(_en(ShadeProcess.mma, 60).shade, 9);
      expect(_en(ShadeProcess.mma, 100).shade, 10);
      expect(_en(ShadeProcess.mma, 99.9).shade, 9);
      expect(_en(ShadeProcess.mag, 70).shade, 9);
      expect(_en(ShadeProcess.mag, 550).shade, 14);
      expect(_en(ShadeProcess.tig, 30).shade, 9);
      expect(_en(ShadeProcess.tig, 125).shade, 11);
      expect(_en(ShadeProcess.migHeavy, 125).shade, 10);
      expect(_en(ShadeProcess.arcGouging, 175).shade, 11);
      expect(_en(ShadeProcess.arcGouging, 174.9).shade, 10);
      expect(_en(ShadeProcess.plasmaCutting, 150).shade, 11);
      expect(_en(ShadeProcess.plasmaWelding, 6).shade, 5);
    });

    test('dolny i górny koniec tabeli należą do tabeli', () {
      expect(_en(ShadeProcess.tig, 10).range, ShadeRange.within);
      expect(_en(ShadeProcess.tig, 10).shade, 8);
      expect(_en(ShadeProcess.tig, 350).range, ShadeRange.within);
      expect(_en(ShadeProcess.tig, 350).shade, 13);
      expect(_en(ShadeProcess.migHeavy, 70).shade, 9);
      expect(_en(ShadeProcess.migHeavy, 500).shade, 14);
      expect(_en(ShadeProcess.migLight, 125).shade, 10);
      expect(_en(ShadeProcess.plasmaCutting, 100).shade, 9);
      expect(_en(ShadeProcess.plasmaCutting, 400).shade, 13);
      expect(_en(ShadeProcess.plasmaWelding, 1.5).shade, 4);
      expect(_en(ShadeProcess.plasmaWelding, 300).shade, 12);
      expect(_en(ShadeProcess.mma, 600).range, ShadeRange.within);
      expect(_en(ShadeProcess.mma, 600).shade, 14);
    });

    test(
        'ANSI/OSHA: 160 A w obu przedziałach „60-160” i „160-250” → '
        'wyższy', () {
      expect(_ansiRow(ShadeProcess.mma, 159.9), (8, 10, 10));
      expect(_ansiRow(ShadeProcess.mma, 160), (10, 12, 12));
      expect(_ansiRow(ShadeProcess.mma, 60), (8, 10, 10));
      expect(_ansiRow(ShadeProcess.mag, 250), (10, 14, 14));
      expect(_ansiRow(ShadeProcess.tig, 50), (8, 12, 12));
      expect(_ansiRow(ShadeProcess.tig, 150), (10, 14, 14));
      expect(_ansiRow(ShadeProcess.arcGouging, 500), (11, 14, 14));
      expect(_ansiRow(ShadeProcess.plasmaCutting, 300), (9, 12, 12));
      expect(_ansiRow(ShadeProcess.gasWelding, 3.2), (5, 5, 6));
      expect(_ansiRow(ShadeProcess.gasWelding, 12.7), (6, 6, 8));
      expect(_ansiRow(ShadeProcess.oxyCutting, 25), (4, 4, 5));
    });

    test(
        'tabele gazowe EN 169 jawnie „q ≤”: 70 → 4, 70,1 → 5; 900 → 5; '
        '2000 → 5, 2001 → 6', () {
      expect(_en(ShadeProcess.gasWelding, 70).shade, 4);
      expect(_en(ShadeProcess.gasWelding, 70.1).shade, 5);
      expect(_en(ShadeProcess.gasWelding, 200).shade, 5);
      expect(_en(ShadeProcess.gasWelding, 800).shade, 6);
      expect(_en(ShadeProcess.gasWelding, 800.1).shade, 7);
      expect(_en(ShadeProcess.oxyCutting, 900).shade, 5);
      expect(_en(ShadeProcess.oxyCutting, 900).range, ShadeRange.within);
      expect(_en(ShadeProcess.oxyCutting, 2000).shade, 5);
      expect(_en(ShadeProcess.oxyCutting, 2001).shade, 6);
      expect(_en(ShadeProcess.oxyCutting, 8000).shade, 7);
      expect(_en(ShadeProcess.oxyCutting, 8000).range, ShadeRange.within);
    });
  });

  group('poza tabelą — bez zgadywania w dół', () {
    test('TIG 5 A: poniżej tabeli → 8 z najniższego przedziału', () {
      final l = _en(ShadeProcess.tig, 5);
      expect(l.range, ShadeRange.below);
      expect(l.shade, 8);
      expect(formatShade(l), '8');
    });

    test('TIG 400 A: powyżej tabeli → co najmniej 13', () {
      final l = _en(ShadeProcess.tig, 400);
      expect(l.range, ShadeRange.above);
      expect(l.shade, 13);
      expect(formatShade(l), '≥ 13');
    });

    test('MIG aluminium 100 A → poniżej (od 125 A): 10', () {
      final l = _en(ShadeProcess.migLight, 100);
      expect(l.range, ShadeRange.below);
      expect(l.shade, 10);
    });

    test('mikroplazma 1 A → 4; 310 A → co najmniej 12', () {
      expect(_en(ShadeProcess.plasmaWelding, 1).range, ShadeRange.below);
      expect(_en(ShadeProcess.plasmaWelding, 1).shade, 4);
      expect(_en(ShadeProcess.plasmaWelding, 310).range, ShadeRange.above);
      expect(_en(ShadeProcess.plasmaWelding, 310).shade, 12);
    });

    test(
        'cięcie plazmowe 40 A: EN poniżej → 9; ANSI 8/9 → stopień 9, '
        'nie jaśniej', () {
      final a = _arc(ShadeProcess.plasmaCutting, 40);
      expect(a.en!.range, ShadeRange.below);
      expect(a.en!.shade, 9);
      expect(a.startShade, 9);
      // Poza tabelą EN bez „−1”: nie jaśniej niż 9.
      expect(a.floorShade, 9);
      expect(a.outsideTable, isTrue);
    });

    test('MMA 700 A: EN ≥ 14, ANSI ≥ 11 / ≥ 14 → co najmniej 14', () {
      final a = _arc(ShadeProcess.mma, 700);
      expect(a.en!.range, ShadeRange.above);
      expect(a.ansi!.range, ShadeRange.above);
      expect(formatShade(a.en!), '≥ 14');
      expect(formatAnsiSuggested(a.ansi!), '≥ 14');
      expect(formatShade(a.ansi!), '≥ 11');
      expect(a.startShade, 14);
      expect(a.floorShade, 14);
    });

    test('ANSI GMAW kończy się na 500 A; CAC-A na 1000 A', () {
      expect(_ansi(ShadeProcess.mag, 500).range, ShadeRange.within);
      expect(_ansi(ShadeProcess.mag, 501).range, ShadeRange.above);
      expect(_ansi(ShadeProcess.arcGouging, 1001).range, ShadeRange.above);
    });

    test('cięcie tlenowe 500 l/h → poniżej: 5; 9000 l/h → co najmniej 7', () {
      final lo = _en(ShadeProcess.oxyCutting, 500);
      expect(lo.range, ShadeRange.below);
      expect(lo.shade, 5);
      final hi = _en(ShadeProcess.oxyCutting, 9000);
      expect(hi.range, ShadeRange.above);
      expect(formatShade(hi), '≥ 7');
    });

    test('tabele bez górnej granicy nigdy nie są „powyżej”', () {
      expect(_en(ShadeProcess.gasWelding, 1e6).range, ShadeRange.within);
      expect(_ansi(ShadeProcess.oxyCutting, 1e4).range, ShadeRange.within);
    });
  });

  group('bezpieczny wybór: ciemniej z obu, nie poniżej minimum', () {
    test('MMA 120 A: EN 10, ANSI 8/10 → zacznij od 10, nie jaśniej niż 9', () {
      final a = _arc(ShadeProcess.mma, 120);
      expect(a.en!.shade, 10);
      expect(a.oshaMinimum, 8);
      expect(a.ansiSuggestedHigh, 10);
      expect(a.startShade, 10);
      expect(a.floorShade, 9);
      expect(a.outsideTable, isFalse);
    });

    test('TIG 100 A: EN 10, ANSI 8/12 → zacznij od 12, nie jaśniej niż 9', () {
      final a = _arc(ShadeProcess.tig, 100);
      expect(a.en!.shade, 10);
      expect(a.startShade, 12);
      expect(a.floorShade, 9);
    });

    test('MAG 200 A: EN 11, ANSI 10/12 → 12, nie jaśniej niż 10', () {
      final a = _arc(ShadeProcess.mag, 200);
      expect(a.startShade, 12);
      expect(a.floorShade, 10);
    });

    test('MMA 40 A: ANSI bez zalecenia (min 7), EN 8 → 8, nie jaśniej niż 7',
        () {
      final a = _arc(ShadeProcess.mma, 40);
      expect(formatAnsiSuggested(a.ansi!), '—');
      expect(a.ansiSuggestedHigh, 7);
      expect(a.startShade, 8);
      expect(a.floorShade, 7);
    });

    test('PAW 10 A: zalecany 6–8 → zacznij od ciemniejszego końca, 8', () {
      final a = _arc(ShadeProcess.plasmaWelding, 10);
      expect(a.en!.shade, 5);
      expect(formatAnsiSuggested(a.ansi!), '6–8');
      expect(a.startShade, 8);
      expect(a.floorShade, 6);
    });

    test('gaz — tylko grubość 8 mm: ANSI 5/5–6 → 6, nie jaśniej niż 5', () {
      final a = computeShade(
          const ShadeInput(process: ShadeProcess.gasWelding, thicknessMm: 8))!;
      expect(a.en, isNull);
      expect(a.startShade, 6);
      expect(a.floorShade, 5);
    });

    test(
        'gaz — przepływ 150 l/h i grubość 2 mm: EN 5, ANSI 4/4–5 → 5, '
        'nie jaśniej niż 4', () {
      final a = computeShade(const ShadeInput(
          process: ShadeProcess.gasWelding, gasFlowLh: 150, thicknessMm: 2))!;
      expect(a.en!.shade, 5);
      expect(a.startShade, 5);
      expect(a.floorShade, 4);
    });

    test(
        'start nigdy nie jaśniejszy niż „nie jaśniej niż” — wszystkie '
        'procesy, prądy 1–1200 A', () {
      for (final p in ShadeProcess.values.where((p) => !p.isGas)) {
        for (var i = 1.0; i <= 1200; i += 0.5) {
          final a = _arc(p, i);
          expect(a.startShade, greaterThanOrEqualTo(a.floorShade),
              reason: '${p.name} $i A');
          expect(a.floorShade, greaterThanOrEqualTo(a.oshaMinimum!),
              reason: '${p.name} $i A');
          expect(a.startShade, greaterThanOrEqualTo(a.en!.shade),
              reason: '${p.name} $i A');
        }
      }
    });
  });

  group('walidacja', () {
    test('proces łukowy, puste pole → komunikat, brak wyniku', () {
      const i = ShadeInput(process: ShadeProcess.tig);
      expect(shadeProblems(i), [ShadeProblem.currentMissing]);
      expect(computeShade(i), isNull);
    });

    test('nieczytelne, 0, ujemne, nieskończone → błąd, brak wyniku', () {
      for (final v in [double.nan, 0.0, -50.0, double.infinity]) {
        final i = ShadeInput(process: ShadeProcess.mma, currentA: v);
        expect(shadeProblems(i), [ShadeProblem.currentInvalid], reason: '$v');
        expect(computeShade(i), isNull, reason: '$v');
      }
    });

    test('gaz: oba pola puste → komunikat; zły przepływ nie psuje grubości',
        () {
      const none = ShadeInput(process: ShadeProcess.oxyCutting);
      expect(shadeProblems(none), [ShadeProblem.gasInputMissing]);
      expect(computeShade(none), isNull);

      const badFlow = ShadeInput(
          process: ShadeProcess.oxyCutting, gasFlowLh: 0, thicknessMm: 30);
      expect(shadeProblems(badFlow), [ShadeProblem.flowInvalid]);
      final a = computeShade(badFlow)!;
      expect(a.en, isNull);
      expect(a.ansi!.shade, 4);

      const badBoth = ShadeInput(
          process: ShadeProcess.gasWelding,
          gasFlowLh: double.nan,
          thicknessMm: -1);
      expect(shadeProblems(badBoth),
          [ShadeProblem.flowInvalid, ShadeProblem.thicknessInvalid]);
      expect(computeShade(badBoth), isNull);
    });

    test('proces łukowy ignoruje pola gazowe', () {
      const i = ShadeInput(
          process: ShadeProcess.mma, currentA: 120, gasFlowLh: double.nan);
      expect(shadeProblems(i), isEmpty);
      expect(computeShade(i)!.en!.shade, 10);
    });
  });

  group('tabele', () {
    test('granice rosną, stopnie nie maleją, zalecany ≥ minimum', () {
      for (final p in ShadeProcess.values) {
        for (final t in [en169Table(p), ansiTable(p)]) {
          var last = t.from;
          var shade = 0;
          for (final b in t.bands) {
            expect(b.upTo, greaterThan(last), reason: p.name);
            expect(b.shade, greaterThanOrEqualTo(shade), reason: p.name);
            if (b.suggestedLow != null) {
              expect(b.suggestedLow, greaterThanOrEqualTo(b.shade),
                  reason: p.name);
              expect(b.suggestedHigh, greaterThanOrEqualTo(b.suggestedLow!),
                  reason: p.name);
            }
            last = b.upTo;
            shade = b.shade;
          }
        }
      }
    });

    test('jednostki: łukowe w A, gazowe EN w l/h i ANSI w mm', () {
      for (final p in ShadeProcess.values) {
        expect(en169Table(p).unit,
            p.isGas ? ShadeUnit.litresPerHour : ShadeUnit.amp,
            reason: p.name);
        expect(ansiTable(p).unit, p.isGas ? ShadeUnit.mm : ShadeUnit.amp,
            reason: p.name);
      }
    });
  });

  group('formatowanie', () {
    test('przedziały słownie', () {
      expect(formatBand(_en(ShadeProcess.mma, 120), en: false), '100–150 A');
      expect(formatBand(_en(ShadeProcess.mma, 30), en: false), '< 60 A');
      expect(
          formatBand(_en(ShadeProcess.plasmaWelding, 3), en: false), '1,5–6 A');
      expect(
          formatBand(_en(ShadeProcess.plasmaWelding, 3), en: true), '1.5–6 A');
      expect(
          formatBand(_en(ShadeProcess.gasWelding, 50), en: false), '≤ 70 l/h');
      expect(formatBand(_en(ShadeProcess.gasWelding, 900), en: false),
          '> 800 l/h');
      expect(formatBand(_ansi(ShadeProcess.gasWelding, 20), en: false),
          '≥ 12,7 mm');
      expect(formatTableRange(kEn169Tig, en: false), '10–350 A');
      expect(formatTableRange(kEn169Mma, en: false), '≤ 600 A');
    });

    test('poza tabelą przedział mówi, gdzie leży wartość', () {
      expect(formatBand(_en(ShadeProcess.tig, 5), en: false), '< 10 A');
      expect(formatBand(_en(ShadeProcess.tig, 400), en: false), '> 350 A');
      expect(formatBand(_ansi(ShadeProcess.mma, 700), en: false), '> 550 A');
    });

    test('wartość wpisana bez zaokrąglenia: 87,5; 99,96; 100', () {
      expect(formatShadeValue(87.5, en: false), '87,5');
      expect(formatShadeValue(99.96, en: false), '99,96');
      expect(formatShadeValue(100, en: false), '100');
      expect(formatShadeValue(87.5, en: true), '87.5');
    });
  });

  group('tekst do udostępnienia', () {
    test('PL: TIG 100 A — liczby jak na ekranie', () {
      final text = shadeShareText(_arc(ShadeProcess.tig, 100), en: false);
      expect(text, contains('Proces: 141 TIG'));
      expect(text, contains('Prąd: 100 A'));
      expect(text, contains('EN 169: 10 (70–125 A; ±1 zależnie od warunków)'));
      expect(
          text,
          contains(
              'ANSI Z49.1 (GTAW): zalecany 12 · minimum OSHA 8 (50–150 A)'));
      expect(text, contains('zacznij od 12'));
      expect(text, contains('nie jaśniej niż 9'));
      expect(text, isNot(contains('poza tabelą')));
    });

    test('EN: poza tabelą — „at least” i ostrzeżenie', () {
      final text = shadeShareText(_arc(ShadeProcess.tig, 400), en: true);
      expect(text, contains('Current: 400 A'));
      expect(text, contains('EN 169: ≥ 13'));
      expect(text, contains('above the table — at least'));
      expect(text, contains('outside the table'));
    });

    test('gaz: przepływ i grubość w osobnych liniach', () {
      final a = computeShade(const ShadeInput(
          process: ShadeProcess.gasWelding, gasFlowLh: 150, thicknessMm: 2.5))!;
      final text = shadeShareText(a, en: false);
      expect(text, contains('Przepływ acetylenu: 150 l/h'));
      expect(text, contains('Grubość: 2,5 mm'));
      expect(text, contains('EN 169: 5 (70–200 l/h'));
      expect(text, contains('zalecany 4–5'));
    });
  });
}

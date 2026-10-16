// Odczyt symbolu spoiny po ludzku (PL / EN), przelicznik a ↔ z i układ
// linii odniesienia w systemach A i B (EN ISO 2553:2019).
//
// a ↔ z ręcznie (pachwina równoramienna, złącze 90°):
//   a = z / √2;  z = a · √2;  √2 = 1,414214
//   a5  → z = 7,0711 mm      z7  → a = 4,9497 mm
//   a10 → z = 14,1421 mm     z10 → a = 7,0711 mm

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_symbols/fillet_throat.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol.dart';
import 'package:cut_list_app/domain/weld_symbols/weld_symbol_description.dart';

void main() {
  group('a ↔ z', () {
    test('a5 → z ≈ 7,07; z7 → a ≈ 4,95; z10 → a ≈ 7,07', () {
      expect(legFromThroat(5), closeTo(7.0711, 1e-4));
      expect(throatFromLeg(7), closeTo(4.9497, 1e-4));
      expect(throatFromLeg(10), closeTo(7.0711, 1e-4));
      expect(legFromThroat(10), closeTo(14.1421, 1e-4));
    });

    test('tam i z powrotem daje ten sam wymiar', () {
      for (final a in <double>[2.5, 3, 4, 5, 6, 8, 12.5]) {
        expect(throatFromLeg(legFromThroat(a)!), closeTo(a, 1e-9));
      }
    });

    test('a ≈ 0,7 · z (dokładnie 0,7071)', () {
      expect(throatFromLeg(1), closeTo(0.70711, 1e-5));
    });

    test('zero, ujemne i NaN — brak wyniku zamiast liczby', () {
      expect(throatFromLeg(0), isNull);
      expect(legFromThroat(-3), isNull);
      expect(throatFromLeg(double.nan), isNull);
      expect(legFromThroat(double.infinity), isNull);
    });

    test('format: przecinek po polsku, kropka po angielsku, bez „,0”', () {
      expect(formatWeldMm(5, en: false), '5');
      expect(formatWeldMm(7.0711, en: false), '7,1');
      expect(formatWeldMm(7.0711, en: true), '7.1');
      expect(formatWeldMm(4.9497, en: false), '4,9');
      expect(formatWeldMm(3.96, en: false), '4');
      expect(formatWeldMmPrecise(4.9497, en: false), '4,95');
      expect(formatWeldMmPrecise(7.0711, en: true), '7.07');
    });
  });

  group('układ linii odniesienia — strona', () {
    test('system A: strona strzałki = symbol na linii ciągłej', () {
      final l = referenceLayout(SymbolSystem.a, WeldSide.arrow);
      expect(l.dashedLine, isTrue);
      expect(l.placements.single.line, RefLine.continuous);
      expect(l.placements.single.side, WeldSide.arrow);
    });

    test('system A: strona przeciwna = symbol na linii przerywanej', () {
      final l = referenceLayout(SymbolSystem.a, WeldSide.other);
      expect(l.dashedLine, isTrue);
      expect(l.placements.single.line, RefLine.dashed);
      expect(l.placements.single.side, WeldSide.other);
    });

    test('system A: spoina symetryczna — bez linii przerywanej, dwa symbole',
        () {
      final l = referenceLayout(SymbolSystem.a, WeldSide.both);
      expect(l.dashedLine, isFalse);
      expect(l.placements.map((p) => p.line).toSet(), {RefLine.continuous});
      expect(l.placements.map((p) => p.position).toSet(),
          {RefPosition.above, RefPosition.below});
    });

    test('system B (jak AWS): pod linią = strzałka, nad = przeciwna', () {
      final arrow = referenceLayout(SymbolSystem.b, WeldSide.arrow);
      final other = referenceLayout(SymbolSystem.b, WeldSide.other);
      expect(arrow.dashedLine, isFalse);
      expect(other.dashedLine, isFalse);
      expect(arrow.placements.single.position, RefPosition.below);
      expect(other.placements.single.position, RefPosition.above);
      final both = referenceLayout(SymbolSystem.b, WeldSide.both);
      expect(
          both.placements,
          containsAll(const [
            SymbolPlacement(
                RefLine.continuous, RefPosition.below, WeldSide.arrow),
            SymbolPlacement(
                RefLine.continuous, RefPosition.above, WeldSide.other),
          ]));
    });

    test('etykiety „co widać na rysunku” zależą od systemu', () {
      expect(sideAsDrawn(SymbolSystem.a, WeldSide.other, en: false),
          'Na linii przerywanej');
      expect(
          sideAsDrawn(SymbolSystem.b, WeldSide.arrow, en: false), 'Pod linią');
      expect(sideAsDrawn(SymbolSystem.b, WeldSide.other, en: true),
          'Above the line');
    });

    test('ta sama strona w A i B daje to samo zdanie', () {
      const a = WeldSymbolSpec(size: 4, side: WeldSide.other);
      final b = a.copyWith(system: SymbolSystem.b);
      expect(describeWeldSymbol(a, en: false).sentence,
          describeWeldSymbol(b, en: false).sentence);
      expect(describeWeldSymbol(a, en: false).sentence,
          'Spoina pachwinowa a4 po stronie przeciwnej.');
    });
  });

  group('zdanie po ludzku', () {
    const example = WeldSymbolSpec(
      kind: WeldKind.fillet,
      side: WeldSide.arrow,
      size: 5,
      intermittent: true,
      count: 3,
      elementLength: 50,
      gap: 100,
      allAround: true,
      fieldWeld: true,
    );

    test('przykład z rysunku — PL', () {
      expect(
          describeWeldSymbol(example, en: false).sentence,
          'Spoina pachwinowa a5 po stronie strzałki, przerywana 3 × 50 (100), '
          'dookoła, montażowa.');
    });

    test('przykład z rysunku — EN', () {
      expect(
          describeWeldSymbol(example, en: true).sentence,
          'Fillet weld a5 on the arrow side, intermittent 3 × 50 (100), '
          'all around, field weld.');
    });

    test('kółko „dookoła” przy spoinie nieciągłej — ostrzeżenie', () {
      final r = describeWeldSymbol(example, en: false);
      expect(r.warnings.single, contains('nieciągłej'));
      final ok =
          describeWeldSymbol(example.copyWith(intermittent: false), en: false);
      expect(ok.sentence,
          'Spoina pachwinowa a5 po stronie strzałki, dookoła, montażowa.');
      expect(ok.warnings, isEmpty);
    });

    test('najprostszy: pachwina a5 po stronie strzałki', () {
      const s = WeldSymbolSpec(size: 5);
      final r = describeWeldSymbol(s, en: false);
      expect(r.sentence, 'Spoina pachwinowa a5 po stronie strzałki.');
      expect(r.warnings, isEmpty);
      // Objaśnienie a → z.
      expect(r.notes.any((n) => n.contains('z ≈ 7,1 mm')), isTrue);
      // Brak długości = na całej długości.
      expect(r.notes.any((n) => n.contains('na całej długości')), isTrue);
    });

    test('z zamiast a: z7 i objaśnienie a ≈ 4,9', () {
      const s = WeldSymbolSpec(size: 7, filletSize: FilletSize.leg);
      final r = describeWeldSymbol(s, en: false);
      expect(r.sentence, 'Spoina pachwinowa z7 po stronie strzałki.');
      expect(r.notes.any((n) => n.contains('a ≈ 4,9 mm')), isTrue);
    });

    test('V dwustronna 8, lico płaskie, proces i WPS — PL i EN', () {
      const s = WeldSymbolSpec(
        kind: WeldKind.singleV,
        side: WeldSide.both,
        size: 8,
        contour: WeldContour.flat,
        process: '141',
        reference: 'WPS-01',
      );
      expect(
          describeWeldSymbol(s, en: false).sentence,
          'Spoina na V po obu stronach, głębokość wtopienia 8 mm, lico '
          'płaskie, proces 141 (TIG), wg WPS-01.');
      expect(
          describeWeldSymbol(s, en: true).sentence,
          'Single-V butt weld on both sides, penetration depth 8 mm, flat '
          '(flush) face, process 141 (GTAW), see WPS-01.');
      final notes = describeWeldSymbol(s, en: false).notes;
      expect(notes.any((n) => n.contains('spoina na X')), isTrue);
      // EN ISO 2553:2013/2019: przy czołowej sama liczba, bez litery s.
      expect(notationFor(s, en: false).size, '8');
      expect(notes.any((n) => n.contains('zapis s8')), isTrue);
    });

    test('½V na podkładce stałej, długość 300, przecinek w wymiarze', () {
      const s = WeldSymbolSpec(
        kind: WeldKind.singleBevel,
        size: 6.5,
        length: 300,
        backing: BackingStrip.permanent,
      );
      expect(
          describeWeldSymbol(s, en: false).sentence,
          'Spoina na ½V po stronie strzałki, głębokość wtopienia 6,5 mm, '
          'długość 300 mm, na podkładce stałej (M).');
      expect(
          describeWeldSymbol(s, en: true).sentence,
          'Single-bevel butt weld on the arrow side, penetration depth '
          '6.5 mm, length 300 mm, on a permanent backing strip (M).');
      // Jeden brzeg ukosowany — strzałka wskazuje element do ukosowania.
      expect(s.oneMemberPrepared, isTrue);
      expect(
          describeWeldSymbol(s, en: false)
              .notes
              .any((n) => n.contains('strzałka (łamana)')),
          isTrue);
    });

    test('przestawna: tylko pachwina po obu stronach i przerywana', () {
      const s = WeldSymbolSpec(
        side: WeldSide.both,
        size: 4,
        intermittent: true,
        count: 4,
        elementLength: 60,
        gap: 120,
        staggered: true,
      );
      final pl = describeWeldSymbol(s, en: false);
      expect(
          pl.sentence,
          'Spoina pachwinowa a4 po obu stronach, przerywana przestawna '
          '4 × 60 (120).');
      expect(pl.warnings, isEmpty);
      expect(pl.notes.any((n) => n.contains('Znak Z')), isTrue);
      final n = notationFor(s, en: false);
      expect(n.rightLead, '4 × 60');
      expect(n.rightGap, '(120)');
      expect(describeWeldSymbol(s, en: true).sentence,
          'Fillet weld a4 on both sides, staggered intermittent 4 × 60 (120).');

      // Ta sama spoina tylko po stronie strzałki — przestawienie nie ma sensu.
      final one =
          describeWeldSymbol(s.copyWith(side: WeldSide.arrow), en: false);
      expect(one.sentence,
          'Spoina pachwinowa a4 po stronie strzałki, przerywana 4 × 60 (120).');
      expect(one.warnings, hasLength(1));
    });

    test('niepełna przerywana: ostrzeżenie, bez zmyślonych liczb', () {
      const s = WeldSymbolSpec(size: 5, intermittent: true, count: 3);
      final r = describeWeldSymbol(s, en: false);
      expect(
          r.sentence, 'Spoina pachwinowa a5 po stronie strzałki, przerywana.');
      expect(r.warnings.single, contains('l i e'));
      expect(notationFor(s, en: false).right, isEmpty);
    });

    test('przerywana bez n: l (e) na całej długości złącza', () {
      const s = WeldSymbolSpec(
          size: 5, intermittent: true, elementLength: 50, gap: 100);
      final r = describeWeldSymbol(s, en: false);
      expect(r.sentence,
          'Spoina pachwinowa a5 po stronie strzałki, przerywana 50 (100).');
      expect(r.warnings, isEmpty);
      expect(r.notes.any((n) => n.contains('na całej długości')), isTrue);
      expect(describeWeldSymbol(s, en: true).sentence,
          'Fillet weld a5 on the arrow side, intermittent 50 (100).');
    });

    test('czołowa bez liczby — pełny przetop, bez wymiaru na rysunku', () {
      const s = WeldSymbolSpec(kind: WeldKind.singleU);
      expect(describeWeldSymbol(s, en: false).sentence,
          'Spoina na U po stronie strzałki, pełny przetop.');
      expect(describeWeldSymbol(s, en: true).sentence,
          'Single-U butt weld on the arrow side, full penetration.');
      expect(notationFor(s, en: false).size, isEmpty);
    });

    test('J po polsku to ½U, strona przeciwna w systemie B', () {
      const s = WeldSymbolSpec(
          kind: WeldKind.singleJ, side: WeldSide.other, system: SymbolSystem.b);
      expect(describeWeldSymbol(s, en: false).sentence,
          'Spoina na ½U (J) po stronie przeciwnej, pełny przetop.');
      expect(describeWeldSymbol(s, en: false).notes.first,
          contains('nad linią = strona przeciwna'));
    });

    test('podkładka przy pachwinie — nie trafia do zdania, jest ostrzeżenie',
        () {
      const s = WeldSymbolSpec(size: 3, backing: BackingStrip.removable);
      final r = describeWeldSymbol(s, en: false);
      expect(r.sentence, 'Spoina pachwinowa a3 po stronie strzałki.');
      expect(r.warnings, hasLength(1));
    });

    test('odmiana „odcinek / odcinki / odcinków”', () {
      expect(segmentsPl(1), 'odcinek');
      expect(segmentsPl(3), 'odcinki');
      expect(segmentsPl(5), 'odcinków');
      expect(segmentsPl(12), 'odcinków');
      expect(segmentsPl(22), 'odcinki');
    });

    test('zapis na rysunku: a5, 3 × 50 (100), ogon 111/WPS-01', () {
      final n = notationFor(
          example.copyWith(process: '111', reference: 'WPS-01'),
          en: false);
      expect(n.size, 'a5');
      expect(n.right, '3 × 50 (100)');
      expect(n.tail, '111/WPS-01');
    });
  });
}

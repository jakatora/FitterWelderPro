// Dobór spoiwa — tabela reguł. Oczekiwania z kart producentów i norm
// klasyfikacji spoiw (źródła: lib/domain/filler/filler_catalog.dart):
//   CS + 304L → 309L (ER309L / W 23 12 L, MIG ER309LSi / G 23 12 L Si);
//   316L + 316L → 316L; 321 → 347; 2205 → 2209; 2507 → 2594;
//   2205 + 2507 → 2594 (IMOA tab. 16); P91 → CrMo91 / B9 (B91);
//   P11 → CrMo1Si / ER80S-B2; P22 → CrMo2Si / ER90S-B3;
//   5083 → 5183; 6061/6082 → 4043 albo 5356; aluminium + stal → nie spawa się
//   łukowo.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/filler/filler_catalog.dart';
import 'package:cut_list_app/domain/filler/filler_selector.dart';

const _all = BaseMaterial.values;

String _aws(FillerRecommendation r, FillerProcess p) =>
    r.forProcess(p)!.consumables.map((c) => c.awsDesignation).join(' | ');

String _iso(FillerRecommendation r, FillerProcess p) =>
    r.forProcess(p)!.consumables.map((c) => c.isoDesignation).join(' | ');

void main() {
  group('każda kombinacja', () {
    test('zwraca wynik z uzasadnieniem; typowy dobór ma spoiwo', () {
      for (final a in _all) {
        for (final b in _all) {
          final r = selectFiller(a, b);
          expect(r.summary.pl, isNotEmpty, reason: '$a + $b');
          expect(r.summary.en, isNotEmpty, reason: '$a + $b');
          if (r.verdict == FillerVerdict.typical) {
            expect(r.family, isNotNull, reason: '$a + $b');
            expect(r.availableProcesses, isNotEmpty, reason: '$a + $b');
          } else {
            expect(r.family, isNull, reason: '$a + $b');
            expect(r.availableProcesses, isEmpty, reason: '$a + $b');
          }
        }
      }
    });

    test('ten sam materiał zawsze ma typowe spoiwo jednoimienne', () {
      for (final m in _all) {
        final r = selectFiller(m, m);
        expect(r.verdict, FillerVerdict.typical, reason: '$m');
        expect(r.sameMaterial, isTrue);
      }
    });

    test('symetria: A + B == B + A', () {
      for (final a in _all) {
        for (final b in _all) {
          final ab = selectFiller(a, b);
          final ba = selectFiller(b, a);
          final why = '$a + $b';
          expect(ba.verdict, ab.verdict, reason: why);
          expect(ba.family?.id, ab.family?.id, reason: why);
          expect(ba.summary, same(ab.summary), reason: why);
          expect(ba.backing, ab.backing, reason: why);
          expect(ba.backingGases, ab.backingGases, reason: why);
          expect(ba.warnings, ab.warnings, reason: why);
          expect(ba.seeAlso, ab.seeAlso, reason: why);
          for (final p in FillerProcess.values) {
            expect(identical(ba.forProcess(p), ab.forProcess(p)), isTrue,
                reason: '$why, $p');
          }
        }
      }
    });

    test('oznaczenia EN ISO i AWS niepuste, z nazwą normy', () {
      for (final a in _all) {
        for (final b in _all) {
          final r = selectFiller(a, b);
          for (final p in r.availableProcesses) {
            final f = r.forProcess(p)!;
            expect(f.consumables, isNotEmpty, reason: '$a + $b, $p');
            for (final c in f.consumables) {
              final why = '$a + $b, $p: ${c.awsDesignation}';
              expect(c.isoStandard, startsWith('EN ISO '), reason: why);
              expect(c.isoDesignation.trim(), isNotEmpty, reason: why);
              expect(c.awsStandard, startsWith('AWS A5.'), reason: why);
              expect(c.awsDesignation.trim(), isNotEmpty, reason: why);
            }
            if (p == FillerProcess.mma) {
              expect(f.shielding, isEmpty, reason: 'MMA bez gazu: $a + $b');
            } else {
              expect(f.shielding, isNotEmpty, reason: '$a + $b, $p');
            }
          }
          for (final w in [...r.warnings, ...r.seeAlso, r.summary]) {
            expect(w.pl.trim(), isNotEmpty);
            expect(w.en.trim(), isNotEmpty);
          }
        }
      }
    });

    test('gaz formujący: jest, gdy formowanie potrzebne; bez wodoru przy '
        'dupleksie i stali ferrytycznej', () {
      for (final a in _all) {
        for (final b in _all) {
          final r = selectFiller(a, b);
          final why = '$a + $b';
          if (r.backing == BackingNeed.notNeeded) {
            expect(r.backingGases, isEmpty, reason: why);
            continue;
          }
          expect(r.backingGases, contains(GasSymbol.i1), reason: why);
          final noHydrogen =
              [a, b].any((m) => m.isDuplex || m.isFerritic);
          if (noHydrogen) {
            expect(r.backingGases.where((g) => g.containsHydrogen), isEmpty,
                reason: why);
          }
        }
      }
    });
  });

  group('dobór konkretny', () {
    test('stal węglowa + nierdzewna → 309L, formowanie wymagane', () {
      for (final ss in [
        BaseMaterial.ss304L,
        BaseMaterial.ss316L,
        BaseMaterial.ss321,
      ]) {
        final r = selectFiller(BaseMaterial.carbonSteel, ss);
        expect(r.verdict, FillerVerdict.typical);
        expect(r.family!.id, '309L', reason: '$ss');
        expect(_aws(r, FillerProcess.tig), 'ER309L');
        expect(_iso(r, FillerProcess.tig), 'W 23 12 L');
        expect(_aws(r, FillerProcess.mig), 'ER309LSi');
        expect(_iso(r, FillerProcess.mig), 'G 23 12 L Si');
        expect(_aws(r, FillerProcess.mma), 'E309L-16');
        expect(_iso(r, FillerProcess.mma), 'E 23 12 L R');
        expect(_aws(r, FillerProcess.fcaw), contains('E309LT1'));
        expect(r.backing, BackingNeed.required);
        expect(r.backingGases, [GasSymbol.i1]);
        // Ostrzeżenie o spoiwie niklowym powyżej ok. 315–370 °C.
        expect(r.warnings.map((w) => w.pl).join(' '), contains('ERNiCr-3'));
      }
    });

    test('316L + 316L → 316L', () {
      final r = selectFiller(BaseMaterial.ss316L, BaseMaterial.ss316L);
      expect(r.family!.id, '316L');
      expect(_aws(r, FillerProcess.tig), 'ER316L');
      expect(_iso(r, FillerProcess.tig), 'W 19 12 3 L');
      expect(_aws(r, FillerProcess.mma), 'E316L-16');
      expect(r.forProcess(FillerProcess.tig)!.shielding, [GasSymbol.i1]);
      expect(r.forProcess(FillerProcess.mig)!.shielding,
          [GasSymbol.m12, GasSymbol.m13]);
      expect(r.backing, BackingNeed.required);
      expect(r.backingGases, containsAll([GasSymbol.i1, GasSymbol.n5]));
    });

    test('304L → 308L, 321 → 347', () {
      expect(selectFiller(BaseMaterial.ss304L, BaseMaterial.ss304L).family!.id,
          '308L');
      final r = selectFiller(BaseMaterial.ss321, BaseMaterial.ss321);
      expect(r.family!.id, '347');
      expect(_aws(r, FillerProcess.tig), 'ER347');
      expect(_iso(r, FillerProcess.mma), 'E 19 9 Nb R');
    });

    test('P91 → 9CrMoV (CrMo91 / B9), PWHT w ostrzeżeniach', () {
      final r = selectFiller(BaseMaterial.p91, BaseMaterial.p91);
      expect(r.family!.id, 'crmo91');
      expect(r.family!.name.pl, contains('9CrMoV'));
      for (final p in [
        FillerProcess.tig,
        FillerProcess.mig,
        FillerProcess.mma,
      ]) {
        expect(_iso(r, p), contains('CrMo91'), reason: '$p');
        expect(_aws(r, p), contains('B9'), reason: '$p');
      }
      expect(r.forProcess(FillerProcess.fcaw), isNull);
      expect(r.backing, BackingNeed.required);
      expect(r.backingGases, [GasSymbol.i1]);
      expect(r.warnings.map((w) => w.pl).join(' '), contains('PWHT'));
    });

    test('Cr-Mo: P11 → B2, P22 → B3; formowanie od 2,25 % Cr', () {
      final p11 = selectFiller(BaseMaterial.crMo1, BaseMaterial.crMo1);
      expect(_aws(p11, FillerProcess.tig), 'ER80S-B2');
      expect(_iso(p11, FillerProcess.tig), 'W CrMo1Si');
      expect(_aws(p11, FillerProcess.mma), 'E8018-B2');
      expect(p11.backing, BackingNeed.notNeeded);

      final p22 = selectFiller(BaseMaterial.crMo2, BaseMaterial.crMo2);
      expect(_aws(p22, FillerProcess.tig), 'ER90S-B3');
      expect(_iso(p22, FillerProcess.mma), 'E CrMo2 B');
      expect(p22.backing, BackingNeed.required);
    });

    test('dwie stale Cr-Mo → spoiwo słabiej stopowanej', () {
      expect(selectFiller(BaseMaterial.crMo2, BaseMaterial.p91).family!.id,
          'crmo2');
      expect(selectFiller(BaseMaterial.crMo1, BaseMaterial.crMo2).family!.id,
          'crmo1');
      expect(selectFiller(BaseMaterial.carbonSteel, BaseMaterial.crMo1)
          .family!
          .id, 'carbon');
    });

    test('P91 ze stalą węglową — połączenie specjalne, bez spoiwa', () {
      final r = selectFiller(BaseMaterial.carbonSteel, BaseMaterial.p91);
      expect(r.verdict, FillerVerdict.specialist);
      expect(r.forProcess(FillerProcess.tig), isNull);
    });

    test('stal węglowa: G3Si1 / ER70S-6, E7018 i celulozowa E6010 do grani',
        () {
      final r =
          selectFiller(BaseMaterial.carbonSteel, BaseMaterial.carbonSteel);
      expect(_aws(r, FillerProcess.tig), 'ER70S-6');
      expect(_iso(r, FillerProcess.mig), 'G3Si1');
      expect(_aws(r, FillerProcess.mma), 'E7018 | E6010');
      expect(_aws(r, FillerProcess.fcaw), 'E71T-1M');
      expect(r.backing, BackingNeed.notNeeded);
      // Celulozowa tylko w rurociągu węglowym — nie przy Cr-Mo.
      expect(
          _aws(selectFiller(BaseMaterial.carbonSteel, BaseMaterial.crMo1),
              FillerProcess.mma),
          'E7018');
    });

    test('niskotemperaturowa (także z węglową) → 1 % Ni', () {
      for (final other in [
        BaseMaterial.lowTempSteel,
        BaseMaterial.carbonSteel,
      ]) {
        final r = selectFiller(BaseMaterial.lowTempSteel, other);
        expect(_aws(r, FillerProcess.tig), 'ER80S-Ni1');
        expect(_iso(r, FillerProcess.tig), 'W3Ni1');
        expect(_aws(r, FillerProcess.mma), 'E8018-C3');
      }
    });

    test('dupleks: 2205 → 2209, 2507 → 2594, 2205 + 2507 → 2594', () {
      final d = selectFiller(BaseMaterial.duplex2205, BaseMaterial.duplex2205);
      expect(_aws(d, FillerProcess.tig), 'ER2209');
      expect(_iso(d, FillerProcess.tig), 'W 22 9 3 N L');
      expect(d.forProcess(FillerProcess.tig)!.shielding,
          [GasSymbol.i1, GasSymbol.n2]);
      final warnings = d.warnings.map((w) => w.pl).join(' ');
      expect(warnings, contains('0,5–2,5 kJ/mm'));
      expect(warnings, contains('150 °C'));

      final s = selectFiller(
          BaseMaterial.superDuplex2507, BaseMaterial.superDuplex2507);
      expect(_aws(s, FillerProcess.mma), 'E2594-16');
      expect(s.warnings.map((w) => w.pl).join(' '), contains('100 °C'));

      expect(
          selectFiller(BaseMaterial.duplex2205, BaseMaterial.superDuplex2507)
              .family!
              .id,
          '2594');
    });

    test('nierdzewna + dupleks → 309LMo; węglowa + dupleks → 309L', () {
      expect(
          selectFiller(BaseMaterial.ss316L, BaseMaterial.duplex2205)
              .family!
              .id,
          '309LMo');
      expect(
          selectFiller(BaseMaterial.carbonSteel, BaseMaterial.duplex2205)
              .family!
              .id,
          '309L');
      expect(
          selectFiller(BaseMaterial.crMo2, BaseMaterial.duplex2205).verdict,
          FillerVerdict.specialist);
    });

    test('Cr-Mo + nierdzewna → spoiwo niklowe ERNiCr-3', () {
      final r = selectFiller(BaseMaterial.p91, BaseMaterial.ss304L);
      expect(r.family!.id, 'nicr3');
      expect(_aws(r, FillerProcess.tig), 'ERNiCr-3');
      expect(_iso(r, FillerProcess.tig), 'S Ni 6082 (NiCr20Mn3Nb)');
      expect(_aws(r, FillerProcess.mma), 'ENiCrFe-3');
    });

    test('aluminium: 5083 → 5183, 6xxx → 4043 albo 5356, tylko TIG i MIG',
        () {
      final a = selectFiller(BaseMaterial.al5083, BaseMaterial.al5083);
      expect(_aws(a, FillerProcess.tig), 'ER5183');
      expect(a.availableProcesses, [FillerProcess.tig, FillerProcess.mig]);
      expect(a.backing, BackingNeed.notNeeded);

      final b = selectFiller(BaseMaterial.al6xxx, BaseMaterial.al6xxx);
      final mig = b.forProcess(FillerProcess.mig)!;
      expect(mig.consumables.map((c) => c.awsDesignation),
          ['ER4043', 'ER5356']);
      // Każde z dwóch spoiw ma opis kompromisu.
      for (final c in mig.consumables) {
        expect(c.use, isNotNull);
      }
      expect(b.warnings.map((w) => w.pl).join(' '), contains('pęka na gorąco'));
    });

    test('aluminium ze stalą albo miedzioniklem — nie spawa się łukowo', () {
      for (final m in _all.where((m) => !m.isAluminium)) {
        for (final al in [BaseMaterial.al5083, BaseMaterial.al6xxx]) {
          final r = selectFiller(al, m);
          expect(r.verdict, FillerVerdict.notArcWeldable, reason: '$al + $m');
          expect(r.warnings, isEmpty);
          expect(r.backing, BackingNeed.notNeeded);
        }
      }
    });

    test('miedzionikiel: 70/30 (ERCuNi), ze stalą węglową NiCu-7', () {
      final c = selectFiller(BaseMaterial.cuNi9010, BaseMaterial.cuNi9010);
      expect(_aws(c, FillerProcess.tig), 'ERCuNi');
      expect(_iso(c, FillerProcess.tig), 'S Cu 7158 (CuNi30Mn1FeTi)');
      final s = selectFiller(BaseMaterial.carbonSteel, BaseMaterial.cuNi9010);
      expect(_aws(s, FillerProcess.tig), 'ERNiCu-7');
      expect(selectFiller(BaseMaterial.ss316L, BaseMaterial.cuNi9010).verdict,
          FillerVerdict.specialist);
    });
  });

  test('symbole gazów wg EN ISO 14175 mają opis PL i EN', () {
    for (final g in GasSymbol.values) {
      expect(g.code, matches(RegExp(r'^[ICMNR]\d{1,2}$')));
      expect(g.description.pl, isNotEmpty);
      expect(g.description.en, isNotEmpty);
    }
    expect(GasSymbol.values.where((g) => g.containsHydrogen), [GasSymbol.n5]);
  });
}

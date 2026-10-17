// Wady spoin — logika: filtrowanie po procesie / materiale / pozycji,
// kolejność przyczyn, wyszukiwarka, powiązania z ISO 5817, tekst
// do udostępnienia.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/weld_defects.dart';
import 'package:cut_list_app/domain/defects/defect_advice.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_table.dart';

WeldDefect _d(String id) => weldDefectById(id)!;

List<String> _ids(String q) => [for (final d in searchDefects(q)) d.id];

void main() {
  group('proces', () {
    test('wada spoza procesu → null; wtrącenie wolframu tylko w TIG', () {
      final w = _d('tungsten');
      expect(defectAdvice(w, DefectProcess.mag135), isNull);
      expect(defectAdvice(w, DefectProcess.mma111), isNull);
      expect(defectAdvice(w, DefectProcess.tig141)!.causes, isNotEmpty);
      expect(defectsForProcess(DefectProcess.mag135).map((d) => d.id),
          isNot(contains('tungsten')));
      expect(defectsForProcess(DefectProcess.tig141).map((d) => d.id),
          contains('tungsten'));
    });

    test('każda przyczyna w wyniku dotyczy wybranego procesu', () {
      for (final d in kWeldDefects) {
        for (final p in d.processes) {
          final a = defectAdvice(d, p)!;
          for (final c in a.causes) {
            expect(c.processes, contains(p), reason: '${d.id}/${c.id}');
          }
          for (final s in [...a.repair, ...a.checklist]) {
            expect(s.processes.isEmpty || s.processes.contains(p), isTrue,
                reason: '${d.id}/${s.id}');
          }
        }
      }
    });

    test('porowatość: MAG ma przepływ gazu, MMA wilgotne elektrody, '
        'SAW wilgotny topnik — przyczyny nie mieszają się', () {
      final p = _d('porosity');
      final mag = defectAdvice(p, DefectProcess.mag135)!.causes;
      final mma = defectAdvice(p, DefectProcess.mma111)!.causes;
      final saw = defectAdvice(p, DefectProcess.saw121)!.causes;
      final tig = defectAdvice(p, DefectProcess.tig141)!.causes;
      expect(mag.map((c) => c.id), contains('mag-gas-flow'));
      expect(mma.map((c) => c.id), contains('mma-wet-electrode'));
      expect(saw.map((c) => c.id), contains('saw-wet-flux'));
      expect(tig.map((c) => c.id), contains('tig-post-flow'));
      expect(mma.map((c) => c.id), isNot(contains('mag-gas-flow')));
      expect(tig.map((c) => c.id), isNot(contains('mma-wet-electrode')));
      expect(mag.map((c) => c.id), isNot(contains('saw-wet-flux')));
    });

    test('114 samoosłonowy nie dostaje przyczyn przepływu gazu', () {
      for (final d in kWeldDefects) {
        if (!d.processes.contains(DefectProcess.fcaw114)) continue;
        for (final c in defectAdvice(d, DefectProcess.fcaw114)!.causes) {
          expect(c.id.contains('gas-flow'), isFalse, reason: '${d.id}/${c.id}');
        }
      }
    });
  });

  group('materiał', () {
    test('bez materiału — wszystkie przyczyny; z materiałem — tylko pasujące',
        () {
      final p = _d('porosity');
      final all = defectAdvice(p, DefectProcess.tig141)!.causes;
      final al = defectAdvice(p, DefectProcess.tig141,
              material: DefectMaterial.aluminium)!
          .causes;
      final ss = defectAdvice(p, DefectProcess.tig141,
              material: DefectMaterial.stainless)!
          .causes;
      expect(all.length, greaterThanOrEqualTo(al.length));
      expect(all.length, greaterThan(ss.length));
      for (final c in al) {
        expect(c.materials.isEmpty || c.materials.contains(DefectMaterial.aluminium),
            isTrue,
            reason: c.id);
      }
      for (final c in ss) {
        expect(c.materials.isEmpty || c.materials.contains(DefectMaterial.stainless),
            isTrue,
            reason: c.id);
      }
      expect(al.map((c) => c.id), contains('al-hydrogen'));
      expect(ss.map((c) => c.id), isNot(contains('al-hydrogen')));
    });

    test('131 MIG Al narzuca aluminium; materiał spoza procesu ignorowany', () {
      final p = _d('porosity');
      expect(effectiveMaterial(p, DefectProcess.mig131, null),
          DefectMaterial.aluminium);
      expect(effectiveMaterial(p, DefectProcess.mig131, DefectMaterial.carbon),
          DefectMaterial.aluminium);
      expect(effectiveMaterial(p, DefectProcess.mma111, DefectMaterial.aluminium),
          isNull);
      expect(defectAdvice(p, DefectProcess.mig131)!.material,
          DefectMaterial.aluminium);
    });

    test('pęknięcia wodorowe dotyczą stali węglowej — materiał narzucony', () {
      final c = _d('crack_cold');
      for (final p in c.processes) {
        expect(c.materialsFor(p), [DefectMaterial.carbon], reason: p.name);
        expect(defectAdvice(c, p)!.material, DefectMaterial.carbon);
      }
    });
  });

  group('kolejność', () {
    test('bez pozycji — rangi niemalejące (najczęstsze / najprostsze najpierw)',
        () {
      for (final d in kWeldDefects) {
        for (final p in d.processes) {
          final ranks = [for (final c in defectAdvice(d, p)!.causes) c.rank];
          final sorted = [...ranks]..sort();
          expect(ranks, sorted, reason: '${d.id}/${p.name}');
        }
      }
    });

    test('remis rang → kolejność z danych', () {
      for (final d in kWeldDefects) {
        for (final p in d.processes) {
          final causes = defectAdvice(d, p)!.causes;
          for (var i = 1; i < causes.length; i++) {
            if (causes[i].rank != causes[i - 1].rank) continue;
            expect(d.causes.indexOf(causes[i]),
                greaterThan(d.causes.indexOf(causes[i - 1])),
                reason: '${d.id}/${p.name}');
          }
        }
      }
    });

    test('wybrana pozycja: przyczyny typowe dla niej idą na początek', () {
      final d = _d('sagging');
      final pc = defectAdvice(d, DefectProcess.mag135,
          position: DefectPosition.pc)!;
      expect(pc.causes.first.positions, contains(DefectPosition.pc));
      // Bez pozycji ta sama przyczyna nie musi być pierwsza, ale jest.
      final any = defectAdvice(d, DefectProcess.mag135)!;
      expect(any.causes.map((c) => c.id), contains(pc.causes.first.id));
    });

    test('wybrana pozycja odrzuca przyczyny innych pozycji', () {
      for (final d in kWeldDefects) {
        for (final p in d.processes) {
          for (final pos in DefectPosition.values) {
            final a = defectAdvice(d, p, position: pos)!;
            for (final c in a.causes) {
              expect(c.positions.isEmpty || c.positions.contains(pos), isTrue,
                  reason: '${d.id}/${p.name}/${pos.name}/${c.id}');
            }
            // Pasujące do pozycji przed resztą.
            var seenGeneral = false;
            for (final c in a.causes) {
              if (c.positions.contains(pos)) {
                expect(seenGeneral, isFalse,
                    reason: '${d.id}/${p.name}/${pos.name}/${c.id}');
              } else {
                seenGeneral = true;
              }
            }
          }
        }
      }
    });

    test('podtopienie MAG w PC: przyczyna dla górnego brzegu na początku', () {
      final a = defectAdvice(_d('undercut'), DefectProcess.mag135,
          position: DefectPosition.pc)!;
      expect(a.causes.first.positions, contains(DefectPosition.pc));
    });
  });

  group('wyszukiwarka', () {
    test('numer ISO 6520-1', () {
      expect(_ids('5011').first, 'undercut');
      expect(_ids('5013').first, 'undercut');
      expect(_ids('3041').first, 'tungsten');
      expect(_ids('2017').first, 'porosity');
      expect(_ids('509').first, 'sagging');
      expect(_ids('104').first, 'crack_crater');
    });

    test('nazwa PL z polskimi znakami i bez, EN, wielkość liter', () {
      expect(_ids('porowatość').first, 'porosity');
      expect(_ids('porowatosc').first, 'porosity');
      expect(_ids('PODTOPIENIE').first, 'undercut');
      expect(_ids('undercut').first, 'undercut');
      expect(_ids('porosity').first, 'porosity');
      expect(_ids('wolfram'), contains('tungsten'));
      expect(_ids('zwis').first, 'sagging');
      expect(_ids('cukrowanie'), contains('root_oxidation'));
    });

    test('puste i bez trafień', () {
      expect(_ids(''), isEmpty);
      expect(_ids('   '), isEmpty);
      expect(_ids('xyzqq'), isEmpty);
    });

    test('każde słowo zapytania musi pasować', () {
      expect(_ids('podtopienie ciągłe').first, 'undercut');
      expect(_ids('podtopienie wolfram'), isEmpty);
    });
  });

  group('ISO 5817', () {
    List<String> labels(String id) =>
        [for (final l in iso5817LinksForDefect(_d(id))) l.label];
    List<String> ids(String id) =>
        [for (final i in iso5817ItemsForDefect(_d(id))) i.id];
    List<int> uncovered(String id) =>
        [for (final r in iso5817UncoveredRefs(_d(id))) r.code];

    test('podtopienie → poz. 1.7 i 1.8; wolfram i żużel → brak', () {
      expect(labels('undercut'), ['1.7 (5011, 5012)', '1.8 (5013)']);
      expect(uncovered('undercut'), isEmpty);
      expect(iso5817ItemsForDefect(_d('tungsten')), isEmpty);
      expect(uncovered('tungsten'), [3041]);
      expect(iso5817ItemsForDefect(_d('slag')), isEmpty);
      expect(uncovered('slag'), [301, 302]);
      expect(ids('sagging'), ['1.14']);
      // 3.1 blachy i rury — dwa warianty, oba zostają.
      expect(ids('misalignment'), ['3.1-5071', '3.1-5072']);
      expect(labels('misalignment'), ['3.1 (507, 5071)', '3.1 (507, 5072)']);
    });

    test('porowatość: poz. 1.3 tylko dla porów powierzchniowych (2017)', () {
      expect(ids('porosity'), ['1.3-butt']);
      expect(labels('porosity'), ['1.3 (2017)']);
      expect(uncovered('porosity'), [2011, 2012, 2013, 2014, 2016]);
    });

    test('podgrupy: 101 / 102 → 1.1; 104 tylko 1.2; 4011–4013 → 1.5', () {
      expect(labels('crack_cold'), ['1.1 (100, 101, 102)']);
      expect(labels('crack_crater'), ['1.2 (104)']);
      expect(labels('lack_of_fusion'), ['1.5 (401, 4011, 4012, 4013)']);
      // 402 nie ma pozycji VT (1.6 to tylko 4021).
      expect(labels('lack_of_penetration'), ['1.6 (4021)']);
      expect(uncovered('lack_of_penetration'), [402]);
    });

    test('bliźniacze pozycje: pachwina → wariant pachwinowy, nadlew → '
        'czołowy', () {
      expect(ids('fillet_shape'), ['1.10', '1.12-fillet', '1.16', '1.20', '1.21']);
      expect(ids('excess_weld_metal'), ['1.9', '1.12-butt']);
    });

    test('każde id z linków otwiera się w Iso5817Page (istnieje w tabeli)',
        () {
      for (final d in kWeldDefects) {
        for (final l in iso5817LinksForDefect(d)) {
          expect(iso5817ItemById(l.item.id), isNotNull, reason: d.id);
          expect(l.refs, isNotEmpty);
        }
        // Każdy numer wady jest albo w pozycji, albo na liście bez pozycji.
        final inLinks = {
          for (final l in iso5817LinksForDefect(d)) ...l.refs.map((r) => r.code)
        };
        expect({...inLinks, ...uncovered(d.id)}, d.codes.toSet(),
            reason: d.id);
      }
    });
  });

  group('udostępnianie', () {
    test('PL: wada, kody, proces, przyczyny, naprawa, odhaczenia, ISO 5817',
        () {
      final a = defectAdvice(_d('undercut'), DefectProcess.mag135,
          material: DefectMaterial.carbon, position: DefectPosition.pc)!;
      final first = a.checklist.first;
      final t = buildDefectShareText(a, en: false, checked: {first.id});
      expect(t, startsWith('Wada spoiny: ${a.defect.title.pl}'));
      expect(t, contains('5011 Podtopienie ciągłe'));
      expect(t, contains('Proces: 135/138 MAG · Materiał: Stal węglowa · '
          'Pozycja: PC'));
      expect(t, contains('Przyczyny (sprawdzaj po kolei):'));
      expect(t, contains('1. ${a.causes.first.cause.pl}'));
      expect(t, contains('   Sprawdź: ${a.causes.first.check.pl}'));
      expect(t, contains('[x] ${first.text.pl}'));
      expect(t, contains('Do wycięcia: '));
      expect(t,
          contains('Limity: EN ISO 5817, tablica 1 poz. 1.7 (5011, 5012), '
              '1.8 (5013)'));
      expect(t, endsWith(defectDisclaimer(en: false)));
    });

    test('BHP w tekście do udostępnienia (PL i EN)', () {
      final a = defectAdvice(_d('crack_cold'), DefectProcess.mma111)!;
      final pl = buildDefectShareText(a, en: false);
      final en = buildDefectShareText(a, en: true);
      expect(a.defect.safety, isNotEmpty);
      expect(pl, contains('\nBHP:\n'));
      expect(en, contains('\nSafety:\n'));
      for (final s in a.defect.safety) {
        expect(pl, contains('- ${s.pl}'));
        expect(en, contains('- ${s.en}'));
      }
    });

    test('limity: porowatość — tylko VT dla 2017; wolfram — brak pozycji', () {
      final p = buildDefectShareText(
          defectAdvice(_d('porosity'), DefectProcess.mag135)!,
          en: false);
      expect(p, contains('Limity: EN ISO 5817, tablica 1 poz. 1.3 (2017)'));
      expect(p,
          contains('2011, 2012, 2013, 2014, 2016: Aplikacja zawiera tylko '
              'pozycje do odbioru wizualnego (VT)'));
      final w = buildDefectShareText(
          defectAdvice(_d('tungsten'), DefectProcess.tig141)!,
          en: false);
      expect(w, contains('Limity: Aplikacja zawiera tylko pozycje do odbioru '
          'wizualnego (VT); limity niezgodności wewnętrznych — pełna norma / '
          'specyfikacja RT / UT.'));
      expect(w, isNot(contains('tablica 1 poz.')));
    });

    test('EN: bez polskich nagłówków', () {
      final a = defectAdvice(_d('porosity'), DefectProcess.tig141)!;
      final t = buildDefectShareText(a, en: true);
      expect(t, startsWith('Weld defect: ${a.defect.title.en}'));
      expect(t, contains('Causes (check in this order):'));
      expect(t, contains('Before the next run:'));
      for (final pl in ['Przyczyny', 'Sprawdź', 'Naprawa', 'Wiążące']) {
        expect(t, isNot(contains(pl)), reason: pl);
      }
    });
  });
}

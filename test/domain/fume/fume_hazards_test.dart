// Zagrożenia wg materiału i procesu, NDS (tylko potwierdzone wartości,
// stan prawny Dz.U. 2026 poz. 447), minimalna ŚOI.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/fume/fume_hazards.dart';
import 'package:cut_list_app/domain/fume/fume_sources.dart';

Set<FumeAgent> _agents(FumeMaterial m, FumeProcess p) =>
    fumeHazards(m, p).map((h) => h.agent).toSet();

bool _emph(FumeMaterial m, FumeProcess p, FumeAgent a) =>
    fumeHazards(m, p).firstWhere((h) => h.agent == a).emphasised;

void main() {
  group('składniki dymu', () {
    test('nierdzewka: Cr(VI), Ni, Mn — Cr(VI) szczególnie przy MMA i FCAW', () {
      final a = _agents(FumeMaterial.stainless, FumeProcess.mma);
      expect(a, containsAll([FumeAgent.crVI, FumeAgent.ni, FumeAgent.mn]));
      expect(_emph(FumeMaterial.stainless, FumeProcess.mma, FumeAgent.crVI),
          isTrue);
      expect(_emph(FumeMaterial.stainless, FumeProcess.fcaw, FumeAgent.crVI),
          isTrue);
      // TIG nadal ma Cr(VI) na liście — tylko bez wyróżnienia.
      expect(_agents(FumeMaterial.stainless, FumeProcess.tig),
          contains(FumeAgent.crVI));
      expect(_emph(FumeMaterial.stainless, FumeProcess.tig, FumeAgent.crVI),
          isFalse);
    });

    test('ocynk → ZnO (gorączka metaliczna), mosiądz też', () {
      expect(_agents(FumeMaterial.galvanised, FumeProcess.migMag),
          contains(FumeAgent.znO));
      expect(_emph(FumeMaterial.galvanised, FumeProcess.migMag, FumeAgent.znO),
          isTrue);
      expect(_agents(FumeMaterial.copper, FumeProcess.tig),
          containsAll([FumeAgent.cu, FumeAgent.znO]));
      expect(FumeAgent.znO.effectPl, contains('Gorączka metaliczna'));
    });

    test('powłoki → Pb, Cd, produkty rozkładu', () {
      expect(_agents(FumeMaterial.coated, FumeProcess.cutting),
          containsAll([FumeAgent.pb, FumeAgent.cd, FumeAgent.coatingOrganics]));
    });

    test('ozon przy TIG i MIG — wyróżniony na aluminium', () {
      expect(_agents(FumeMaterial.aluminium, FumeProcess.migMag),
          contains(FumeAgent.o3));
      expect(_agents(FumeMaterial.aluminium, FumeProcess.tig),
          contains(FumeAgent.o3));
      expect(
          _emph(FumeMaterial.aluminium, FumeProcess.tig, FumeAgent.o3), isTrue);
      expect(_emph(FumeMaterial.carbonSteel, FumeProcess.tig, FumeAgent.o3),
          isFalse);
      expect(_agents(FumeMaterial.aluminium, FumeProcess.mma),
          isNot(contains(FumeAgent.o3)));
    });

    test('cięcie → NOx (wyróżnione) i CO; MAG → CO', () {
      final a = _agents(FumeMaterial.carbonSteel, FumeProcess.cutting);
      expect(a, containsAll([FumeAgent.nox, FumeAgent.co]));
      expect(
          _emph(FumeMaterial.carbonSteel, FumeProcess.cutting, FumeAgent.nox),
          isTrue);
      expect(_agents(FumeMaterial.carbonSteel, FumeProcess.migMag),
          contains(FumeAgent.co));
    });

    test('materiał nieznany → „skład nieznany”, nie pusta lista', () {
      for (final p in FumeProcess.values) {
        final a = _agents(FumeMaterial.other, p);
        expect(a, contains(FumeAgent.unknown), reason: p.name);
      }
    });

    test('bez powtórzeń; każda para materiał–proces ma składniki', () {
      for (final m in FumeMaterial.values) {
        for (final p in FumeProcess.values) {
          final list = fumeHazards(m, p).map((h) => h.agent).toList();
          expect(list, isNotEmpty);
          expect(list.toSet().length, list.length, reason: '$m $p');
        }
      }
    });
  });

  group('NDS — tylko wartości potwierdzone w rozporządzeniu', () {
    test('kluczowe substancje mają wartości z Dz.U. 2026 poz. 447', () {
      expect(FumeAgent.mn.nds!.map((n) => n.nds), [0.2, 0.05]);
      expect(FumeAgent.crVI.nds!.single.nds, 0.005);
      expect(FumeAgent.ni.nds!.map((n) => n.nds), [0.05, 0.01]);
      expect(FumeAgent.znO.nds!.single.nds, 5);
      expect(FumeAgent.znO.nds!.single.ndsch, 10);
      expect(FumeAgent.pb.nds!.single.nds, 0.03);
      expect(FumeAgent.o3.nds!.single.nds, 0.15);
      expect(FumeAgent.cd.nds!.single.nds, 0.001);
      expect(FumeAgent.nox.nds!.map((n) => n.nds), [0.7, 2.5]);
    });

    test('niepotwierdzone — bez liczby (ekran: „sprawdź aktualny wykaz”)', () {
      for (final a in [
        FumeAgent.al,
        FumeAgent.cu,
        FumeAgent.coatingOrganics,
        FumeAgent.dust,
        FumeAgent.unknown,
      ]) {
        expect(a.nds, isNull, reason: a.name);
      }
    });

    test('stan prawny i uwagi przejściowe w tekstach', () {
      expect(kFumeNdsLegalPl, contains('Dz.U. 2026 poz. 447'));
      expect(kFumeNdsLegalPl, contains('18.10.2026'));
      expect(kFumeCrViNotePl, contains('17.01.2025'));
      expect(kFumeCrViNotePl, contains('0,025'));
      expect(kFumeCrViNotePl, contains('0,005'));
      expect(kFumeCdNotePl, contains('11.07.2027'));
    });
  });

  group('minimalna ochrona dróg oddechowych', () {
    test('nierdzewka, ocynk, powłoki, miedź, nieznany — P3 albo TH3 zawsze',
        () {
      for (final m in [
        FumeMaterial.stainless,
        FumeMaterial.galvanised,
        FumeMaterial.coated,
        FumeMaterial.copper,
        FumeMaterial.other,
      ]) {
        for (final lev in [true, false]) {
          expect(fumeRpeRequirement(m, levEffective: lev),
              FumeRpeRequirement.p3OrTh3,
              reason: '$m $lev');
        }
      }
    });

    test(
        'stal węglowa / aluminium: bez sprawdzonego odciągu P3/TH3, z nim '
        'APF ≥ 20', () {
      for (final m in [FumeMaterial.carbonSteel, FumeMaterial.aluminium]) {
        expect(fumeRpeRequirement(m, levEffective: false),
            FumeRpeRequirement.p3OrTh3);
        expect(fumeRpeRequirement(m, levEffective: true),
            FumeRpeRequirement.apf20);
      }
    });

    test('FFP2 i TH1 nigdy nie wystarczają; TH2 tylko przy APF 20', () {
      for (final req in FumeRpeRequirement.values) {
        expect(fumeRpeMeets(FumeRpe.none, req), isFalse);
        expect(fumeRpeMeets(FumeRpe.p2, req), isFalse);
        expect(fumeRpeMeets(FumeRpe.th1, req), isFalse);
        expect(fumeRpeMeets(FumeRpe.p3, req), isTrue);
        expect(fumeRpeMeets(FumeRpe.th3, req), isTrue);
      }
      expect(fumeRpeMeets(FumeRpe.th2, FumeRpeRequirement.apf20), isTrue);
      expect(fumeRpeMeets(FumeRpe.th2, FumeRpeRequirement.p3OrTh3), isFalse);
    });

    test('tabela APF zgodna z regułą: przyjęte klasy mają HSE ≥ 20', () {
      for (final row in kFumeApf) {
        final accepted = fumeRpeMeets(row.rpe, FumeRpeRequirement.apf20);
        expect(accepted, row.hse! >= 20, reason: row.rpe.name);
      }
      final th1 = kFumeApf.firstWhere((r) => r.rpe == FumeRpe.th1);
      expect(th1.dguv, 5);
      final th3 = kFumeApf.firstWhere((r) => r.rpe == FumeRpe.th3);
      expect(th3.hse, 40);
      expect(th3.dguv, 100);
    });
  });

  group('prędkość uchwycenia wg procesu', () {
    test('spawanie i cięcie 0,5 m/s, szlifowanie 2,5 m/s', () {
      for (final p in FumeProcess.values) {
        expect(fumeCaptureMinFor(p), p == FumeProcess.grinding ? 2.5 : 0.5,
            reason: p.name);
      }
      expect(kFumeWeldingRangeMs, (0.5, 1.0));
    });

    test('procesy w osłonie gazowej: MIG/MAG, FCAW, TIG', () {
      expect(FumeProcess.values.where((p) => p.gasShielded).toSet(),
          {FumeProcess.migMag, FumeProcess.fcaw, FumeProcess.tig});
    });
  });

  test('PL i EN: teksty niepuste dla każdego składnika i procesu', () {
    for (final a in FumeAgent.values) {
      expect(a.title(en: false), isNotEmpty);
      expect(a.title(en: true), isNotEmpty);
      expect(a.effect(en: false), isNotEmpty);
      expect(a.effect(en: true), isNotEmpty);
    }
    for (final p in FumeProcess.values) {
      final (pl, en) = fumeProcessNote(p);
      expect(pl, isNotEmpty);
      expect(en, isNotEmpty);
    }
  });

  test(
      'gazy, których filtr P nie zatrzymuje: TIG/MIG (ozon), plazma (NOx, '
      'CO), powłoki (opary)', () {
    expect(kFumeGasAgents,
        {FumeAgent.o3, FumeAgent.nox, FumeAgent.co, FumeAgent.coatingOrganics});
    expect(fumeHasGasHazard(FumeMaterial.aluminium, FumeProcess.tig), isTrue);
    expect(
        fumeHasGasHazard(FumeMaterial.aluminium, FumeProcess.migMag), isTrue);
    expect(fumeHasGasHazard(FumeMaterial.carbonSteel, FumeProcess.cutting),
        isTrue);
    expect(fumeHasGasHazard(FumeMaterial.coated, FumeProcess.mma), isTrue);
    expect(
        fumeHasGasHazard(FumeMaterial.carbonSteel, FumeProcess.mma), isFalse);
    expect(fumeHasGasHazard(FumeMaterial.stainless, FumeProcess.grinding),
        isFalse);
  });
}

// Grupa spoiwa FM (ISO 9606-1 tab. 2) z oznaczenia spoiwa z dziennika.
// Każde oznaczenie z katalogu spoiw aplikacji (ISO i AWS) musi trafić do
// grupy swojej rodziny albo do „nie wiadomo” — nigdy do innej grupy.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/filler/filler_catalog.dart';
import 'package:cut_list_app/domain/qualification/filler_fm_group.dart';

void main() {
  test('katalog spoiw: każde oznaczenie → grupa swojej rodziny', () {
    const expected = <FillerFamily, String?>{
      kFillerCarbon: 'FM1',
      kFillerCarbonPipeline: 'FM1',
      kFillerNi1: 'FM1',
      kFillerMo: 'FM3',
      kFillerCrMo1: 'FM3',
      kFillerCrMo2: 'FM3',
      kFillerCrMo91: 'FM4',
      kFiller308L: 'FM5',
      kFiller316L: 'FM5',
      kFiller347: 'FM5',
      kFiller309L: 'FM5',
      kFiller309LMo: 'FM5',
      kFiller2209: 'FM5',
      kFiller2594: 'FM5',
      kFillerNiCr3: 'FM6',
      kFillerNiCu7: 'FM6',
      // Nie stal — poza ISO 9606-1.
      kFillerCuNi30: null,
      kFiller5183: null,
      kFiller6xxx: null,
    };
    var checked = 0;
    for (final e in expected.entries) {
      for (final pf in e.key.processes.values) {
        for (final c in pf.consumables) {
          for (final d in [c.isoDesignation, c.awsDesignation]) {
            expect(fmGroupOfFillerClass(d), e.value,
                reason: '${e.key.id}: $d');
            checked++;
          }
        }
      }
    }
    expect(checked, greaterThan(80));
  });

  test('ISO system A / B i prefiksy norm', () {
    expect(fmGroupOfFillerClass('E 42 3 B 32 H5'), 'FM1');
    expect(fmGroupOfFillerClass('EN ISO 2560-A: E 38 0 RC 11'), 'FM1');
    expect(fmGroupOfFillerClass('ISO 14341-A G 42 4 M21 3Si1'), 'FM1');
    expect(fmGroupOfFillerClass('E4918'), 'FM1');
    expect(fmGroupOfFillerClass('E 55 4 Mn1NiMo B'), 'FM2');
    expect(fmGroupOfFillerClass('G 69 4 M21 Mn3Ni1CrMo'), 'FM2');
    expect(fmGroupOfFillerClass('W CrMo1Si'), 'FM3');
    expect(fmGroupOfFillerClass('E CrMo5 B'), 'FM4');
    expect(fmGroupOfFillerClass('W 19 12 3 L'), 'FM5');
    expect(fmGroupOfFillerClass('E19 9 L R'), 'FM5');
    expect(fmGroupOfFillerClass('S Ni6082'), 'FM6');
  });

  test('AWS: klasy węglowe, niskostopowe, wysokiej wytrzymałości', () {
    expect(fmGroupOfFillerClass('E7018-1 H4R'), 'FM1');
    expect(fmGroupOfFillerClass('AWS A5.18: ER70S-6'), 'FM1');
    expect(fmGroupOfFillerClass('E70C-6M'), 'FM1');
    expect(fmGroupOfFillerClass('E8018-B2L'), 'FM3');
    expect(fmGroupOfFillerClass('E9018-B9'), 'FM4');
    expect(fmGroupOfFillerClass('E10018-M'), 'FM2');
    expect(fmGroupOfFillerClass('ER100S-1'), 'FM2');
    expect(fmGroupOfFillerClass('ER2209'), 'FM5');
    expect(fmGroupOfFillerClass('E410-15'), 'FM5');
    expect(fmGroupOfFillerClass('ERNiCrMo-3'), 'FM6');
  });

  test('niejednoznaczne, nazwy handlowe, nie stal → null (nie zgadujemy)', () {
    for (final d in [
      null,
      '',
      'OK 48.00',
      'Böhler FOX EV 50',
      'E9018-G',
      'ER80S-D2',
      'E8018-G',
      'ENiFe-CI',
      'ER4043',
      'ER5356',
      'ER70S-6 / ER308L', // dwie różne grupy
      'ER70S-6 / coś',
    ]) {
      expect(fmGroupOfFillerClass(d), isNull, reason: '$d');
    }
    // Kilka spoiw jednej grupy — ta grupa.
    expect(fmGroupOfFillerClass('ER70S-6 + E7018'), 'FM1');
  });
}

// Operacje lokalne asystenta: odczyt „Moich parametrów" (query_my_params) i
// szkic wpisu do dziennika spoin (add_weld_journal_entry). Czyste funkcje.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/assistant_local_ops.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/weld_param.dart';

WeldParam _p(String id, String method, String material, double wall,
        double amps, {double diameter = 0, int updated = 0}) =>
    WeldParam(
      id: id,
      method: method,
      baseMaterial: material,
      welderModel: null,
      diameterMm: diameter,
      wallThicknessMm: wall,
      electrodeMm: 0,
      torchGasLpm: 8,
      nozzleType: null,
      nozzleSize: null,
      purgeLpm: 0,
      amps: amps,
      outletHoles: null,
      tempo: null,
      note: null,
      createdAt: updated,
      updatedAt: updated,
    );

WeldEntry _weld(String no, String project, {int? deletedAt}) => WeldEntry(
      id: 'id-$no-$project',
      weldNo: no,
      projectName: project,
      pipeName: '',
      material: '',
      od: '',
      t: '',
      method: '',
      welder: '',
      date: '2026-09-01',
      notes: '',
      status: WeldStatus.pending,
      deletedAt: deletedAt,
    );

void main() {
  final all = [
    _p('a', 'TIG_AUTOGEN', 'SS', 2.0, 60, updated: 1),
    _p('b', 'TIG_WIRE', 'SS', 2.0, 75, diameter: 60.3, updated: 3),
    _p('c', 'MAG', 'CS', 5.0, 160, updated: 2),
    _p('d', 'TIG_AUTOGEN', 'SS', 2.77, 70, updated: 4),
  ];

  group('findMyWeldParams', () {
    test('nierdzewka 2 mm → oba TIG-i, najnowszy pierwszy', () {
      final r = findMyWeldParams(all, {'material': 'SS', 'wall_mm': 2.0});
      expect(r.map((p) => p.id), ['b', 'a']);
    });
    test('TIG bez drutu → tylko TIG_AUTOGEN', () {
      final r = findMyWeldParams(all, {'process': 'TIG', 'filler': false});
      expect(r.map((p) => p.id), ['d', 'a']);
    });
    test('MAG na czarną', () {
      expect(findMyWeldParams(all, {'process': 'MIG_MAG', 'material': 'CS'})
          .single.id, 'c');
    });
    test('średnica z tolerancją 0,5 mm', () {
      expect(findMyWeldParams(all, {'diameter_mm': 60.0}).single.id, 'b');
    });
    test('brak dopasowań → pusto; brak kryteriów → wszystkie', () {
      expect(findMyWeldParams(all, {'material': 'DUPLEX'}), isEmpty);
      expect(findMyWeldParams(all, {}), hasLength(4));
    });
    test('linia wyniku i opis kryteriów', () {
      expect(myWeldParamLine(all[1], AppLanguage.pl),
          'TIG z drutem · SS · t 2 mm · Ø 60,3 · 75 A · 8 l/min');
      expect(
          describeMyParamsQuery(
              {'material': 'SS', 'process': 'TIG', 'wall_mm': 2.0},
              AppLanguage.pl),
          'SS · TIG · t 2 mm');
    });
  });

  group('dziennik', () {
    test('numer zajęty w projekcie (także przez usunięty wpis)', () {
      final journal = [
        _weld('12', 'Blok 4'),
        _weld('13', 'Blok 4', deletedAt: 5),
      ];
      expect(isWeldNoTaken(journal, project: 'blok 4', weldNo: '12'), isTrue);
      expect(isWeldNoTaken(journal, project: 'Blok 4', weldNo: '13'), isTrue);
      expect(isWeldNoTaken(journal, project: 'Blok 5', weldNo: '12'), isFalse);
      expect(canonicalJournalProject(journal, 'blok 4'), 'Blok 4');
      expect(canonicalJournalProject(journal, 'Nowy'), 'Nowy');
    });

    test('szkic → WeldEntry: spawacz = stempel, PENDING, data, WPS', () {
      final e = buildAssistantWeldEntry(
        const WeldJournalDraft(weldNo: 'W-12', project: 'Blok 4', wps: '141-01'),
        id: 'x',
        stamp: ' JK-07 ',
        at: DateTime(2026, 9, 25, 14, 3),
        byVoice: true,
        lang: AppLanguage.pl,
      );
      expect(e.weldNo, 'W-12');
      expect(e.projectName, 'Blok 4');
      expect(e.welder, 'JK-07');
      expect(e.wpsRef, '141-01');
      expect(e.status, WeldStatus.pending);
      expect(e.date, '2026-09-25');
      expect(e.notes, 'Asystent (głosowo), 2026-09-25 14:03');
      expect(e.material, isEmpty, reason: 'nic nie jest zgadywane');
    });
  });
}

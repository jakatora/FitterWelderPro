// Import spoin do wyceny: mapowanie rodzaju i pozycji, grupowanie,
// pominięte bez wymiaru, sumy; dziennik spoin (filtr projekt / pakiet);
// mapa spoin zapisanego skanu ze złotego zestawu skanera.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/quotes/quote_import.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_quote_import.dart';

WeldEntry _entry(
  String no, {
  String project = 'Rafineria',
  String package = '',
  String type = 'BW',
  String od = '114.3',
  String t = '6.02',
  String position = '',
  String shopField = '',
  String date = '',
  String welder = '',
  int? deletedAt,
}) =>
    WeldEntry(
      id: 'id-$no-$project-$package',
      weldNo: no,
      projectName: project,
      pipeName: '',
      material: '',
      od: od,
      t: t,
      method: '',
      welder: welder,
      date: date,
      notes: '',
      status: WeldStatus.pending,
      testPackage: package,
      jointType: type,
      position: position,
      shopField: shopField,
      deletedAt: deletedAt,
    );

AiScanResult _golden(String id) {
  final raw = jsonDecode(File('test/golden_iso/$id.json').readAsStringSync())
      as Map<String, dynamic>;
  return AiScanResult.fromEnvelope(
      (raw['envelope'] as Map).cast<String, dynamic>());
}

int _ids = 0;
String _newId() => 'j${++_ids}';

void main() {
  group('mapowanie rodzaju złącza', () {
    test('BW / SW / FW / BR i brak oznaczenia', () {
      expect(quoteKindForJointType('BW'),
          (kind: JointKind.pipeButt, assumed: false));
      expect(quoteKindForJointType('sw'),
          (kind: JointKind.pipeFillet, assumed: false));
      expect(quoteKindForJointType('FW'),
          (kind: JointKind.pipeFillet, assumed: false));
      expect(quoteKindForJointType(' BR '),
          (kind: JointKind.branch, assumed: false));
      expect(quoteKindForJointType(''),
          (kind: JointKind.pipeButt, assumed: true));
      expect(quoteKindForJointType('XYZ'),
          (kind: JointKind.pipeButt, assumed: true));
    });

    test('grubość a mufy: 0,77 × ścianka w górę do 0,5, min. 3', () {
      expect(socketWeldThroatMm(4.55), 4.0); // DN25 Sch 80: 3,50 → 4,0
      expect(socketWeldThroatMm(6.02), 5.0); // 4,64 → 5,0
      expect(socketWeldThroatMm(2.77), 3.0); // 2,13 → 2,5 → min. 3
    });
  });

  group('mapowanie pozycji', () {
    test('kody ISO 6947 i ASME IX', () {
      for (final c in ['PA', '1G', 'pa', ' 1g ']) {
        expect(quotePositionForCode(c), WeldPosition.pa, reason: c);
      }
      for (final c in ['PC', '2G', 'PB', '2F']) {
        expect(quotePositionForCode(c), WeldPosition.pc, reason: c);
      }
      for (final c in ['PF', 'PH', 'PG', '5G', '5g']) {
        expect(quotePositionForCode(c), WeldPosition.pf, reason: c);
      }
      for (final c in ['H-L045', 'HL045', 'J-L045', '6G']) {
        expect(quotePositionForCode(c), WeldPosition.hl045, reason: c);
      }
      for (final c in ['PE', '4G', 'PD']) {
        expect(quotePositionForCode(c), WeldPosition.pe, reason: c);
      }
      expect(quotePositionForCode(''), isNull);
      expect(quotePositionForCode('ZZ'), isNull);
    });

    test('domyślna pozycja z wyceny: warsztat PA, obiekt PF', () {
      expect(defaultImportPosition(QuoteSite.shop), WeldPosition.pa);
      expect(defaultImportPosition(QuoteSite.field), WeldPosition.pf);
      expect(defaultImportPosition(QuoteSite.difficult), WeldPosition.pf);
    });
  });

  group('etykieta rozmiaru', () {
    test('DN + Sch z tabeli, typowe dla materiału', () {
      expect(pipeSizeLabel(114.3, 6.02), 'DN100 Sch 40');
      expect(pipeSizeLabel(114.3, 3.05, stainless: true), 'DN100 Sch 10S');
      expect(pipeSizeLabel(114.3, 6.02, stainless: true), 'DN100 Sch 40S');
      expect(pipeSizeLabel(114.3, 5.0), 'DN100');
      expect(pipeSizeLabel(100, 5.0), '');
    });
  });

  group('grupowanie', () {
    final welds = [
      for (var i = 1; i <= 8; i++)
        ImportWeld(
            ref: '$i',
            jointType: 'BW',
            odMm: 114.3,
            wallMm: 6.02,
            position: '5G',
            location: ImportLocation.shop),
      for (var i = 9; i <= 12; i++)
        ImportWeld(
            ref: 'FW$i',
            jointType: 'BW',
            odMm: 114.3,
            wallMm: 6.02,
            position: 'PF',
            location: ImportLocation.field),
      // Ten sam rozmiar, inna pozycja → osobna grupa.
      const ImportWeld(
          ref: '13', jointType: 'BW', odMm: 114.3, wallMm: 6.02, position: '6G'),
      // Mufy DN25 Sch 80 bez pozycji → pozycja z wyceny.
      for (var i = 14; i <= 17; i++)
        ImportWeld(ref: '$i', jointType: 'SW', odMm: 33.4, wallMm: 4.55),
      // Odgałęzienie DN25 na DN100.
      const ImportWeld(
          ref: '18',
          jointType: 'BR',
          odMm: 33.4,
          wallMm: 3.38,
          headerOdMm: 114.3,
          position: 'PF'),
      // Bez rodzaju — doczołowa jako założenie.
      const ImportWeld(ref: '19', odMm: 168.3, wallMm: 7.11, position: 'PA'),
      // Bez wymiaru — pominięte, nie zgadywane.
      const ImportWeld(ref: '20', jointType: 'BW', wallMm: 6.02),
      const ImportWeld(ref: '21', jointType: 'BW', odMm: 114.3),
      const ImportWeld(ref: '22', jointType: 'BR', headerOdMm: 114.3),
      // Literówka: ścianka większa niż promień.
      const ImportWeld(ref: '23', jointType: 'BW', odMm: 6.02, wallMm: 114.3),
    ];
    final plan =
        planQuoteImport(welds, defaultPosition: WeldPosition.pa);

    test('grupy po rodzaju, wymiarze i pozycji; sumy', () {
      expect(plan.totalCount, welds.length);
      expect(plan.weldCount, 19);
      expect(plan.skippedCount, 4);
      expect(plan.skippedFor(ImportSkipReason.noSize), 3);
      expect(plan.skippedFor(ImportSkipReason.badSize), 1);
      expect(plan.skipped.map((s) => s.weld.ref), ['20', '21', '22', '23']);
      expect(plan.groups.map((g) => (g.kind, g.count, g.position)), [
        (JointKind.pipeButt, 12, WeldPosition.pf),
        (JointKind.pipeButt, 1, WeldPosition.hl045),
        (JointKind.pipeButt, 1, WeldPosition.pa),
        (JointKind.pipeFillet, 4, WeldPosition.pa),
        (JointKind.branch, 1, WeldPosition.pf),
      ]);
    });

    test('warsztat / obiekt to informacja, nie osobna grupa', () {
      final g = plan.groups.first;
      expect(g.shopCount, 8);
      expect(g.fieldCount, 4);
      expect(g.unknownLocationCount, 0);
      expect(g.sizeLabel, 'DN100 Sch 40');
      expect(g.refs.first, '1');
      expect(g.refs.last, 'FW12');
      expect(g.positionAssumedCount, 0);
      expect(g.kindAssumedCount, 0);
    });

    test('mufa: pachwina, a z ścianki; pozycja z wyceny jako założenie', () {
      final g = plan.groups.firstWhere((g) => g.kind == JointKind.pipeFillet);
      expect(g.throatMm, 4.0);
      expect(g.positionAssumedCount, 4);
      expect(g.sizeLabel, 'DN25 Sch 80');
    });

    test('odgałęzienie: OD króćca i rury głównej, faza 45°', () {
      final g = plan.groups.firstWhere((g) => g.kind == JointKind.branch);
      final j = g.toJoint(id: 'x');
      expect(j.odMm, 33.4);
      expect(j.wallMm, 3.38);
      expect(j.headerOdMm, 114.3);
      expect(j.angleDeg, 45);
      expect(j.isValid, isTrue);
    });

    test('brak rodzaju: doczołowa, oznaczona jako przyjęta', () {
      final g = plan.groups.firstWhere((g) => g.odMm == 168.3);
      expect(g.kind, JointKind.pipeButt);
      expect(g.kindAssumedCount, 1);
      expect(g.sizeLabel, 'DN150 Sch 40');
    });

    test('pozycje wyceny z zaznaczonych grup, ze zmianą pozycji i etykietą',
        () {
      final keys = {plan.groups[0].key, plan.groups[3].key};
      final joints = quoteJointsFromImport(
        plan,
        selected: keys,
        positions: {plan.groups[3].key: WeldPosition.pc},
        label: 'TP-03',
        newId: _newId,
      );
      expect(joints, hasLength(2));
      expect(joints[0].kind, JointKind.pipeButt);
      expect(joints[0].count, 12);
      expect(joints[0].odMm, 114.3);
      expect(joints[0].wallMm, 6.02);
      expect(joints[0].sizeLabel, 'DN100 Sch 40');
      expect(joints[0].position, WeldPosition.pf);
      expect(joints[0].label, 'TP-03');
      expect(joints[0].angleDeg, 60);
      expect(joints[1].kind, JointKind.pipeFillet);
      expect(joints[1].throatMm, 4.0);
      expect(joints[1].position, WeldPosition.pc);
      expect(joints.map((j) => j.id).toSet(), hasLength(2));
      expect(joints.every((j) => j.isValid), isTrue);
      // Wycena z importu liczy się jak z pozycji wpisanych ręcznie.
      final q = WeldQuote(
          id: 'q',
          joints: joints,
          createdAt: 0,
          updatedAt: 0);
      final r = computeQuote(q);
      expect(r.invalidJointCount, 0);
      expect(r.netGrosze, greaterThan(0));
    });

    test('etykieta przycięta do 80 znaków', () {
      final joints = quoteJointsFromImport(plan,
          selected: {plan.groups.first.key},
          label: 'x' * 120,
          newId: _newId);
      expect(joints.single.label.length, kImportLabelMaxLength);
    });

    test('nic nie zaznaczone → nic do dodania', () {
      expect(
          quoteJointsFromImport(plan, selected: const {}, newId: _newId),
          isEmpty);
    });
  });

  group('dziennik spoin', () {
    final journal = [
      _entry('1', package: 'TP-03', position: 'PF', shopField: 'FIELD'),
      _entry('2', package: 'TP-03', position: '5G', shopField: 'FIELD',
          date: '2026-10-01', welder: 'S-07'),
      _entry('3', package: 'TP-03', od: 'Ø114,3', t: '6,02 mm',
          position: 'PF', shopField: 'SHOP'),
      _entry('4', package: 'TP-03', type: 'SW', od: '33,4', t: '4.55'),
      _entry('5', package: 'TP-03', od: 'DN100'),
      _entry('6', package: 'TP-03', od: ''),
      _entry('7', package: 'TP-03', deletedAt: 1),
      _entry('8', package: 'TP-04', od: '168.3', t: '7.11'),
      _entry('9', package: ''),
      _entry('1', project: 'Inny', package: 'TP-01'),
      _entry('2', project: ''),
    ];

    test('wymiar: liczba z Ø / mm, DN to nie średnica', () {
      expect(parseJournalDimensionMm('114,3'), 114.3);
      expect(parseJournalDimensionMm('Ø 114.3'), 114.3);
      expect(parseJournalDimensionMm('6,02 mm'), 6.02);
      expect(parseJournalDimensionMm('DN100'), isNull);
      expect(parseJournalDimensionMm(''), isNull);
      expect(parseJournalDimensionMm('0'), isNull);
    });

    test('projekty i pakiety: posortowane, puste na końcu, bez usuniętych',
        () {
      expect(journalImportProjects(journal), ['Inny', 'Rafineria', '']);
      expect(journalImportPackages(journal, project: 'Rafineria'),
          ['TP-03', 'TP-04', '']);
      expect(journalImportPackages(journal), ['TP-01', 'TP-03', 'TP-04', '']);
    });

    test('pakiet TP-03: grupy, pominięte bez wymiaru, etykieta', () {
      const f = JournalImportFilter(project: 'Rafineria', testPackage: 'TP-03');
      final entries = journalEntriesForImport(journal, f);
      expect(entries.map((e) => e.weldNo), ['1', '2', '3', '4', '5', '6']);
      final plan = planQuoteImport(entries.map(importWeldFromJournal),
          defaultPosition: WeldPosition.pa);
      expect(plan.weldCount, 4);
      expect(plan.skippedFor(ImportSkipReason.noSize), 2); // „DN100” i puste
      final butt = plan.groups.first;
      expect(butt.kind, JointKind.pipeButt);
      expect(butt.count, 3);
      expect(butt.position, WeldPosition.pf);
      expect(butt.fieldCount, 2);
      expect(butt.shopCount, 1);
      final socket = plan.groups.last;
      expect(socket.kind, JointKind.pipeFillet);
      expect(socket.count, 1);
      expect(socket.position, WeldPosition.pa); // brak w dzienniku
      expect(journalImportLabel(f), 'TP-03');
    });

    test('tylko niewykonane: bez daty i stempla', () {
      const f = JournalImportFilter(
          project: 'Rafineria', testPackage: 'TP-03', onlyOpen: true);
      expect(journalEntriesForImport(journal, f).map((e) => e.weldNo),
          ['1', '3', '4', '5', '6']);
    });

    test('cały projekt, wpisy bez pakietu i bez projektu', () {
      expect(
          journalEntriesForImport(
                  journal, const JournalImportFilter(project: 'Rafineria'))
              .length,
          8);
      expect(
          journalEntriesForImport(journal,
                  const JournalImportFilter(project: 'Rafineria', testPackage: ''))
              .map((e) => e.weldNo),
          ['9']);
      expect(
          journalEntriesForImport(journal, const JournalImportFilter(project: ''))
              .map((e) => e.weldNo),
          ['2']);
      expect(journalImportLabel(const JournalImportFilter(project: 'Rafineria')),
          'Rafineria');
      expect(journalImportLabel(const JournalImportFilter()), '');
    });
  });

  group('skan ISO — złoty zestaw', () {
    test('17: sześć spoin z rysunku, 4 warsztatowe + 2 montażowe', () {
      final scan = _golden('17-spoole-spoiny-montazowe');
      final welds = importWeldsFromScan(scan);
      expect(welds.map((w) => w.ref), ['1', '2', 'FW1', '3', '4', 'FW2']);
      final plan =
          planQuoteImport(welds, defaultPosition: WeldPosition.pa);
      expect(plan.skippedCount, 0);
      expect(plan.groups, hasLength(1));
      final g = plan.groups.single;
      expect(g.count, 6);
      expect(g.kind, JointKind.pipeButt);
      expect(g.kindAssumedCount, 6); // rysunek nie podaje rodzaju
      expect(g.odMm, 114.3);
      expect(g.wallMm, 6.02);
      expect(g.shopCount, 4);
      expect(g.fieldCount, 2);
      expect(g.position, WeldPosition.pa);
      expect(g.positionAssumedCount, 6);
      expect(scanImportLabel(scan), 'ISO-P-3001 rev A');
    });

    test('19: mufy SW DN25 Sch 80 → pachwina a = 4', () {
      final plan = planQuoteImport(
          importWeldsFromScan(_golden('19-sw-dn25')),
          defaultPosition: WeldPosition.pf);
      expect(plan.skippedCount, 0);
      final g = plan.groups.single;
      expect(g.kind, JointKind.pipeFillet);
      expect(g.count, 4);
      expect(g.odMm, 33.4);
      expect(g.wallMm, 4.55);
      expect(g.throatMm, 4.0);
      expect(g.position, WeldPosition.pf);
    });

    test('13: weldolet DN100×25 — króciec DN25 na rurze głównej Ø114,3', () {
      final plan = planQuoteImport(
          importWeldsFromScan(_golden('13-olet-luka')),
          defaultPosition: WeldPosition.pa);
      // Rura DN25 do oletu (doczołowa) + olet do rury głównej (króciec).
      expect(plan.weldCount, 2);
      expect(plan.skippedCount, 0);
      final butt = plan.groups.firstWhere((g) => g.kind == JointKind.pipeButt);
      expect((butt.odMm, butt.wallMm), (33.4, 3.38));
      final branch =
          plan.groups.where((g) => g.kind == JointKind.branch).toList();
      expect(branch, hasLength(1));
      expect(branch.single.count, 1);
      expect(branch.single.odMm, 33.4);
      expect(branch.single.headerOdMm, 114.3);
      expect(branch.single.toJoint(id: 'b').isValid, isTrue);
      // Nic nie jest liczone jako króciec Ø114,3 (rozmiar rury głównej).
      expect(
          plan.groups.where(
              (g) => g.kind == JointKind.branch && g.odMm == 114.3),
          isEmpty);
    });

    test('10: rysunek bez DN — spoiny bez wymiaru nie wchodzą do wyceny', () {
      final plan = planQuoteImport(
          importWeldsFromScan(_golden('10-brak-dn')),
          defaultPosition: WeldPosition.pa);
      expect(plan.groups, isEmpty);
      // Cztery spoiny z trasy, wszystkie bez OD i ścianki.
      expect(plan.totalCount, 4);
      expect(plan.skippedFor(ImportSkipReason.noSize), 4);
    });
  });
}

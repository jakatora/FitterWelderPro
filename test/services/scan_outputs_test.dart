// Wyniki skanu ISO „wszystko" (etap 4): co można zapisać (blokada tylko
// swojego cięcia), mapa spoin (z rysunku albo W-001…), spoole, BOM ze skanu
// porównany z tabelą rysunku i wpisy dziennika spoin bez duplikatów.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_outputs.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

AiTitleBlock _tb() => AiTitleBlock(
      drawingNumber: 'ISO-P-2001',
      revision: 'C',
      lineNumber: 'DN100-P-2001-A1A',
      material: 'A312 TP316L',
      schedule: 'Sch 40',
      pipeClass: 'CL150',
    );

AiSegment _seg(String id, String? from, String? to, double mm,
        {String? spool, AiConfidence conf = AiConfidence.high}) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: mm,
      rawDimension: mm.toStringAsFixed(0),
      confidence: conf,
      spoolId: spool,
    );

AiComponent _c(String id, String type, {String? bomItem, String? spool}) =>
    AiComponent(
      id: id,
      type: type,
      bomItem: bomItem,
      spoolId: spool,
      confidence: AiConfidence.high,
    );

/// Otwarty koniec → E1 → E2 → E3 → otwarty koniec; spool SP1 = s1,s2,
/// SP2 = s3,s4 (spoina montażowa na E2… nie — na granicy spooli przy E2).
AiScanResult _route({
  List<AiWeld> welds = const [],
  List<AiBomItem> bom = const [],
  AiConfidence s3conf = AiConfidence.high,
}) =>
    AiScanResult(
      schemaVersion: 2,
      sizeNotation: 'DN',
      titleBlock: _tb(),
      segments: [
        _seg('s1', null, 'E1', 1000, spool: 'SP1'),
        _seg('s2', 'E1', 'E2', 800, spool: 'SP1'),
        _seg('s3', 'E2', 'E3', 700, spool: 'SP2', conf: s3conf),
        _seg('s4', 'E3', null, 500, spool: 'SP2'),
      ],
      components: [
        _c('E1', 'elbow90', bomItem: '2'),
        _c('E2', 'elbow90', bomItem: '2'),
        _c('E3', 'elbow90', bomItem: '2'),
      ],
      weldMarks: welds,
      spools: [AiSpool(id: 'SP1', label: 'SP-1'), AiSpool(id: 'SP2', label: 'SP-2')],
      billOfMaterials: bom,
    );

ScanReviewGate _gate(ScanPlan plan) => evaluateReview(
      plan: plan,
      segments: plan.segments,
      materialGroup: plan.project.materialGroup,
      headerComplete: plan.project.isComplete,
    );

void main() {
  group('blokada tylko swojego cięcia', () {
    test('niepewny wymiar blokuje jedno cięcie, reszta się zapisuje', () {
      final plan = planFromScan(_route(s3conf: AiConfidence.low));
      final gate = _gate(plan);
      expect(gate.canSaveProject, isTrue);
      expect(gate.savesEverything, isFalse);
      expect(gate.blocked.map((s) => s.sourceId), ['s3']);
      expect(gate.savable.map((s) => s.sourceId), ['s1', 's2', 's4']);
      expect(gate.projectGaps, isEmpty);
    });

    test('brak materiału blokuje cały projekt', () {
      final plan = planFromScan(_route());
      final gate = evaluateReview(
        plan: plan,
        segments: plan.segments,
        materialGroup: null,
        headerComplete: false,
      );
      expect(gate.canSaveProject, isFalse);
    });
  });

  group('mapa spoin', () {
    test('bez oznaczeń na rysunku: po jednej na złączu rura–kształtka, W-001…',
        () {
      final plan = planFromScan(_route());
      final welds = buildWeldMap(_route(), plan.segments);
      expect(welds.map((w) => w.number).toList(),
          ['W-001', 'W-002', 'W-003', 'W-004', 'W-005', 'W-006']);
      expect(welds.every((w) => w.numberAssigned), isTrue);
      expect(welds.every((w) => w.jointType == WeldJointType.butt), isTrue);
      // E2 łączy SP1 (s2) i SP2 (s3) — granica spooli = spoina montażowa.
      final atE2 = welds.where((w) => w.componentId == 'E2').toList();
      expect(atE2.map((w) => w.location).toSet(), {'field'});
      final atE1 = welds.where((w) => w.componentId == 'E1').toList();
      expect(atE1.map((w) => w.location).toSet(), {'shop'});
      expect(welds.first.dn, 100);
      expect(welds.first.odMm, closeTo(114.3, 1e-9));
      expect(welds.first.wallMm, closeTo(6.02, 1e-9));
    });

    test('numery i typ z rysunku; brakujący numer dostaje W-…', () {
      final scan = _route(welds: [
        AiWeld(id: 'a', number: '1', location: 'shop', betweenIds: ['s1', 'E1']),
        AiWeld(
            id: 'b',
            number: 'FW2',
            location: 'field',
            jointType: 'BW',
            betweenIds: ['E2', 's3'],
            nde: 'RT',
            confidence: AiConfidence.high),
        AiWeld(id: 'c', betweenIds: ['s4', 'E3']),
      ]);
      final plan = planFromScan(scan);
      final welds = buildWeldMap(scan, plan.segments);
      expect(welds.map((w) => w.number).toList(), ['1', 'FW2', 'W-001']);
      expect(welds[1].isField, isTrue);
      expect(welds[1].segmentIds, ['s3']);
      expect(welds[2].numberAssigned, isTrue);
      expect(welds[0].source, WeldSource.drawing);
    });
  });

  test('spoole: odcinki i spoiny pogrupowane jak na rysunku', () {
    final scan = _route();
    final plan = planFromScan(scan);
    final welds = buildWeldMap(scan, plan.segments);
    final spools = buildSpools(scan, plan.segments, welds);
    expect(spools.map((s) => s.label).toList(), ['SP-1', 'SP-2']);
    expect(spools[0].segments.map((s) => s.sourceId), ['s1', 's2']);
    expect(spools[0].knownCutMm, closeTo(848 + 496, 1e-9));
    expect(spools[1].segments.map((s) => s.label), ['SP-2/1', 'SP-2/2']);
  });

  group('BOM ze skanu vs tabela rysunku', () {
    test('pozycja z bomItem: 3 kolana na trasie, 4 w tabeli = rozbieżność', () {
      final scan = _route(bom: [
        AiBomItem(item: '1', description: 'PIPE SMLS', quantity: 3.2, unit: 'M',
            size: 'DN100'),
        AiBomItem(item: '2', description: 'ELBOW 90 LR', quantity: 4,
            size: 'DN100'),
        AiBomItem(item: '3', description: 'GASKET SPW', quantity: 2),
      ]);
      final plan = planFromScan(scan);
      final lines = compareBom(scan, plan.segments);
      final elbow = lines.singleWhere((l) => l.bomItem == '2');
      expect(elbow.status, BomLineStatus.mismatch);
      expect(elbow.scanQty, 3);
      expect(elbow.drawingQty, 4);
      final gasket = lines.singleWhere((l) => l.bomItem == '3');
      expect(gasket.status, BomLineStatus.notCompared);
      final pipe = lines.singleWhere((l) => l.labelPl.startsWith('Rura'));
      // Cięcia: 848 + 496 + 396 + 348 = 2088 mm; tabela 3,2 m > +10 %.
      expect(pipe.scanQty, closeTo(2.088, 1e-9));
      expect(pipe.status, BomLineStatus.mismatch);
    });

    test('rura w granicach zapasu i kolana bez bomItem po rodzaju i DN — OK', () {
      final base = _route(bom: [
        AiBomItem(item: '1', description: 'PIPE SMLS BE', quantity: 2.2,
            unit: 'M', size: 'DN100'),
        AiBomItem(item: '2', description: 'ELBOW 90 LR BW', quantity: 3,
            size: 'DN100'),
      ]);
      final scan = base.copyWith(components: [
        for (final c in base.components) _c(c.id, c.type),
      ]);
      final plan = planFromScan(scan);
      final lines = compareBom(scan, plan.segments);
      final elbow = lines.singleWhere((l) => l.labelPl.startsWith('Kolano 90'));
      expect(elbow.status, BomLineStatus.ok, reason: elbow.notePl);
      final pipe = lines.singleWhere((l) => l.labelPl.startsWith('Rura'));
      expect(pipe.status, BomLineStatus.ok, reason: pipe.notePl);
    });

    test('rura bez jednostki w tabeli — nie porównuję', () {
      final scan = _route(bom: [
        AiBomItem(item: '1', description: 'PIPE', quantity: 3),
      ]);
      final plan = planFromScan(scan);
      final pipe = compareBom(scan, plan.segments)
          .singleWhere((l) => l.labelPl.startsWith('Rura'));
      expect(pipe.status, BomLineStatus.notCompared);
    });
  });

  group('dziennik spoin', () {
    test('wpisy Oczekuje, powiązane z projektem; ponowny import bez duplikatów',
        () {
      final scan = _route(welds: [
        AiWeld(
            id: 'b',
            number: 'FW2',
            location: 'field',
            jointType: 'BW',
            betweenIds: ['E2', 's3'],
            nde: 'RT',
            position: 'PC',
            pwht: false),
        AiWeld(id: 'a', number: '1', location: 'shop', betweenIds: ['s1', 'E1']),
      ]);
      final plan = planFromScan(scan);
      final welds = buildWeldMap(scan, plan.segments);
      var n = 0;
      final first = weldJournalEntries(
        welds: welds,
        scan: scan,
        projectId: 'p1',
        projectName: 'Linia 2001',
        savedSegmentIds: plan.segments.map((s) => s.sourceId).toSet(),
        existing: const [],
        newId: () => 'w${++n}',
        spoolLabels: const {'SP2': 'SP-2'},
      );
      expect(first.toInsert, hasLength(2));
      final fw = first.toInsert.first;
      expect(fw.weldNo, 'FW2');
      expect(fw.status, WeldStatus.pending);
      expect(fw.projectId, 'p1');
      expect(fw.projectName, 'Linia 2001');
      expect(fw.isoDrawing, 'ISO-P-2001');
      expect(fw.isoRev, 'C');
      expect(fw.pipeName, 'DN100-P-2001-A1A');
      expect(fw.spool, 'SP-2');
      expect(fw.shopField, WeldLocation.field);
      expect(fw.jointType, WeldJointType.butt);
      expect(fw.position, 'PC');
      expect(fw.material, 'A312 TP316L');
      expect(fw.od, '114.3');
      expect(fw.t, '6.02');
      expect(fw.pwhtRequired, isFalse);
      expect(fw.ndtOf(NdtMethod.rt).scope, NdtScope.required);

      final again = weldJournalEntries(
        welds: welds,
        scan: scan,
        projectId: 'p2',
        projectName: 'Linia 2001',
        savedSegmentIds: plan.segments.map((s) => s.sourceId).toSet(),
        existing: first.toInsert,
        newId: () => 'x${++n}',
      );
      expect(again.toInsert, isEmpty);
      expect(again.skipped, ['FW2', '1']);
    });

    test('spoina na niezapisanym cięciu nie trafia do dziennika', () {
      final scan = _route(welds: [
        AiWeld(id: 'b', number: '5', betweenIds: ['E2', 's3']),
      ]);
      final plan = planFromScan(scan);
      final welds = buildWeldMap(scan, plan.segments);
      final r = weldJournalEntries(
        welds: welds,
        scan: scan,
        projectId: 'p',
        projectName: 'x',
        savedSegmentIds: const {'s1', 's2'},
        existing: const <WeldEntry>[],
        newId: () => 'id',
      );
      expect(r.toInsert, isEmpty);
    });
  });
}

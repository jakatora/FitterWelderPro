// Planista skanu ISO jako GRAF (etap 2): trójniki i olety z przelotem i
// odgałęzieniem, zespoły skręcane, średnica KAŻDEGO odcinka (z odczytu albo
// przeniesiona przez redukcje) i take-outy dla tej średnicy, końce SW i
// gwintowane, odniesienia wymiaru z rysunku, spoole.
//
// Wartości normowe w komentarzach: ASME B16.9 (kolana, trójniki, trójnik
// redukcyjny M), B16.11-2011 tab. 1 (SW), B16.5 (WN Y), B16.10 (zawory).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

AiTitleBlock _tb() => AiTitleBlock(
      lineNumber: 'DN100-P-1001-A1A',
      material: 'A312 TP316L',
      schedule: 'Sch 40',
      pipeClass: 'CL150',
    );

AiScanResult _scan(List<AiSegment> segments, List<AiComponent> components,
        {List<AiSpool> spools = const []}) =>
    AiScanResult(
      schemaVersion: 2,
      sizeNotation: 'DN',
      titleBlock: _tb(),
      segments: segments,
      components: components,
      spools: spools,
    );

AiSegment _seg(String id, String? from, String? to, double mm,
        {int? dn,
        Object? dir,
        String? refFrom,
        String? refTo,
        String? spool,
        AiConfidence conf = AiConfidence.high}) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: mm,
      rawDimension: mm.toStringAsFixed(0),
      confidence: conf,
      dn: dn,
      direction: dir,
      refFrom: refFrom,
      refTo: refTo,
      spoolId: spool,
    );

AiComponent _c(String id, String type,
        {String? label,
        String? large,
        String? small,
        List<String> runIds = const [],
        String? branchId,
        List<String> connectedTo = const [],
        String? endType,
        String? rating,
        String? valveType,
        String? flangeType}) =>
    AiComponent(
      id: id,
      type: type,
      label: label,
      sizeLarge: large,
      sizeSmall: small,
      runIds: runIds,
      branchId: branchId,
      connectedTo: connectedTo,
      endType: endType,
      rating: rating,
      valveType: valveType,
      flangeType: flangeType,
      confidence: AiConfidence.high,
    );

PlannedSegment _byId(ScanPlan plan, String id) =>
    plan.segments.singleWhere((s) => s.sourceId == id);

Set<ScanIssueCode> _gapCodes(ScanPlan plan, [String? segmentId]) => plan.gaps
    .where((g) => segmentId == null || g.segmentId == segmentId)
    .map((g) => g.code)
    .toSet();

void main() {
  group('trójnik redukcyjny', () {
    test('runIds/branchId: przelot C=105, odgałęzienie M=98 (DN100×80)', () {
      final plan = planFromScan(_scan([
        _seg('s1', null, 'T1', 800),
        _seg('s2', 'T1', null, 600),
        _seg('s3', 'T1', null, 500),
      ], [
        _c('T1', 'tee',
            large: 'DN100', small: 'DN80', runIds: ['s1', 's2'], branchId: 's3'),
      ]));
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      final s1 = _byId(plan, 's1');
      final s3 = _byId(plan, 's3');
      expect(s1.dn, 100);
      expect(s3.dn, 80, reason: 'odgałęzienie ma rozmiar wylotu');
      expect(s3.diameterMm, closeTo(88.9, 1e-9));
      expect(s3.wallThicknessMm, closeTo(5.49, 1e-9), reason: 'DN80 Sch 40');
      expect(s1.end.takeoutMm, 105, reason: 'B16.9 C NPS 4');
      expect(s3.start.takeoutMm, 98, reason: 'B16.9 M NPS 4×3');
      expect(s3.start.role, PortRole.branch);
      expect(s3.start.takeoutNote, contains('M'));
      expect(s1.cutMm, closeTo(695, 1e-9));
      expect(_byId(plan, 's2').cutMm, closeTo(495, 1e-9));
      expect(s3.cutMm, closeTo(402, 1e-9), reason: '500 − 98');
      // Przelot przed odgałęzieniem w kolejności.
      expect(plan.segments.map((s) => s.sourceId).toList(), ['s1', 's2', 's3']);
    });

    test('kierunki rozpoznają przelot bez runIds', () {
      final plan = planFromScan(_scan([
        _seg('s1', null, 'T1', 800, dir: 'E'),
        _seg('s3', 'T1', null, 500, dir: 'UP'),
        _seg('s2', 'T1', null, 600, dir: 'E'),
      ], [
        _c('T1', 'tee', label: 'RED TEE DN100x80'),
      ]));
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      expect(_byId(plan, 's3').start.takeoutMm, 98);
      expect(_byId(plan, 's2').start.takeoutMm, 105);
      expect(plan.segments.map((s) => s.sourceId).toList(), ['s1', 's2', 's3'],
          reason: 'przelot (s2) przed odgałęzieniem (s3)');
    });

    test('bez ról i kierunków — blokada tylko trzech cięć przy trójniku', () {
      final plan = planFromScan(_scan([
        _seg('s0', null, 'E1', 900, dn: 100),
        _seg('s1', 'E1', 'T1', 800),
        _seg('s2', 'T1', null, 600),
        _seg('s3', 'T1', null, 500),
      ], [
        _c('E1', 'elbow90'),
        _c('T1', 'tee', large: 'DN100', small: 'DN80'),
      ]));
      for (final id in ['s1', 's2', 's3']) {
        expect(_gapCodes(plan, id), contains(ScanIssueCode.branchAmbiguous),
            reason: id);
      }
      expect(_gapCodes(plan, 's0'), isEmpty,
          reason: 'odcinek poza trójnikiem liczy się dalej');
      expect(_byId(plan, 's0').cutMm, isNotNull);
    });

    test('trójnik bez rozmiaru: ostrzeżenie o przyjęciu równoprzelotowego', () {
      final plan = planFromScan(_scan([
        _seg('s1', null, 'T1', 800),
        _seg('s2', 'T1', null, 600),
        _seg('s3', 'T1', null, 500),
      ], [
        _c('T1', 'tee'),
      ]));
      expect(plan.has(ScanIssueCode.teeAssumedEqual), isTrue);
      expect(_byId(plan, 's3').cutMm, closeTo(395, 1e-9));
    });
  });

  group('średnica odcinka przez redukcję', () {
    test('kolano za redukcją dostaje take-out DN80 (A=114), nie DN100', () {
      final plan = planFromScan(_scan([
        _seg('s1', null, 'R1', 1000, dn: 100, refTo: 'EOP'),
        _seg('s2', 'R1', 'E1', 700, refFrom: 'EOP'),
        _seg('s3', 'E1', null, 400),
      ], [
        _c('R1', 'reducer', large: 'DN100', small: 'DN80'),
        _c('E1', 'elbow90'),
      ]));
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      final s2 = _byId(plan, 's2');
      expect(s2.dn, 80);
      expect(s2.dnNote, contains('redukcj'));
      expect(s2.end.takeoutMm, 114, reason: 'B16.9 90° LR NPS 3');
      expect(s2.cutMm, closeTo(586, 1e-9), reason: '700 − 0 − 114');
      expect(_byId(plan, 's3').cutMm, closeTo(286, 1e-9), reason: '400 − 114');
      expect(_byId(plan, 's1').cutMm, closeTo(1000, 1e-9));
    });

    test('bez żadnego DN odcinka — blokada, a odpowiedź montera przenosi się',
        () {
      final scan = _scan([
        _seg('s1', null, 'R1', 1000),
        _seg('s2', 'R1', 'E1', 700),
        _seg('s3', 'E1', null, 400),
      ], [
        _c('R1', 'reducer', label: 'CONC RED DN100x80'),
        _c('E1', 'elbow90'),
      ]);
      final before = planFromScan(scan);
      expect(_gapCodes(before, 's3'),
          contains(ScanIssueCode.missingSegmentDiameter));
      final after = planFromScan(scan,
          fitter: const ScanFitterInput(segmentDn: {'s3': 80}));
      expect(_byId(after, 's1').dn, 100);
      expect(_byId(after, 's2').dn, 80);
      expect(_byId(after, 's3').cutMm, closeTo(286, 1e-9));
      expect(_gapCodes(after, 's3'), isEmpty);
    });

    test('inny DN bez schedule odcinka i bez schedule projektu → ścianka od '
        'montera', () {
      final scan = AiScanResult(
        sizeNotation: 'DN',
        titleBlock: AiTitleBlock(material: 'A312 TP316L', pipeClass: 'CL150'),
        segments: [
          _seg('s1', null, 'R1', 1000, dn: 100),
          _seg('s2', 'R1', null, 700, dn: 80),
        ],
        components: [_c('R1', 'reducer', large: 'DN100', small: 'DN80')],
      );
      final plan =
          planFromScan(scan, diameterMm: 114.3, wallThicknessMm: 3.05);
      expect(_gapCodes(plan, 's2'), contains(ScanIssueCode.missingSegmentWall));
      final fixed = planFromScan(scan,
          diameterMm: 114.3,
          wallThicknessMm: 3.05,
          fitter: const ScanFitterInput(segmentWallMm: {'s2': 3.05}));
      expect(_gapCodes(fixed, 's2'), isNot(contains(ScanIssueCode.missingSegmentWall)));
      expect(_byId(fixed, 's2').wallThicknessMm, 3.05);
    });
  });

  group('zespół skręcany (zawór między kołnierzami)', () {
    test('connectedTo spina trasę w jeden ciąg', () {
      final plan = planFromScan(_scan([
        _seg('s0', null, 'E1', 1200),
        _seg('s1', 'E1', 'F1', 1000),
        _seg('s2', 'F2', 'E2', 700),
      ], [
        _c('E1', 'elbow90'),
        _c('F1', 'flange', flangeType: 'WN', connectedTo: ['V1']),
        _c('V1', 'valve', valveType: 'gate', connectedTo: ['F1', 'F2']),
        _c('F2', 'flange', flangeType: 'WN', connectedTo: ['V1']),
        _c('E2', 'elbow90'),
      ]));
      expect(plan.runCount, 1);
      expect(plan.has(ScanIssueCode.routeNotContinuous), isFalse);
      expect(plan.segments.map((s) => s.sourceId).toList(), ['s0', 's1', 's2']);
      expect(plan.segments.any((s) => s.startsNewRun), isFalse);
    });
  });

  group('olet', () {
    AiScanResult oletScan() => _scan([
          _seg('h1', null, 'O1', 800, dir: 'E'),
          _seg('h2', 'O1', null, 600, dir: 'E'),
          _seg('b1', 'O1', null, 300, dir: 'UP'),
        ], [
          _c('O1', 'weldolet', large: 'DN100', small: 'DN25'),
        ]);

    test('rura główna nie jest cięta na olecie: jeden odcinek 800+600', () {
      final plan = planFromScan(oletScan());
      final header = _byId(plan, 'h1+h2');
      expect(header.isoMm, 1400);
      expect(header.sourceParts, ['h1', 'h2']);
      expect(header.cutMm, closeTo(1400, 1e-9));
      expect(header.dn, 100);
      final branch = _byId(plan, 'b1');
      expect(branch.dn, 25);
      expect(branch.diameterMm, closeTo(33.4, 1e-9));
      expect(branch.cutMm, isNull);
      final gap = plan.gaps.singleWhere((g) =>
          g.segmentId == 'b1' && g.code == ScanIssueCode.missingTakeout);
      expect(gap.pl, contains('MSS SP-97'));
    });

    test('take-out oletu wpisany przez montera odblokowuje odgałęzienie', () {
      final plan = planFromScan(oletScan(),
          fitter: const ScanFitterInput(
              takeoutMm: {'O1@b1': 95}));
      final branch = _byId(plan, 'b1');
      expect(branch.start.fromFitter, isTrue);
      expect(branch.start.takeoutNote, 'wpisane przez montera');
      expect(branch.cutMm, closeTo(205, 1e-9), reason: '300 − 95');
      expect(_gapCodes(plan, 'b1'), isEmpty);
    });
  });

  group('końce SW i gwintowane', () {
    test('kolano SW kl. 3000 DN25: A 22,5 + luz 1,6 = 24,1', () {
      final scan = AiScanResult(
        sizeNotation: 'DN',
        titleBlock: AiTitleBlock(
            lineNumber: 'DN25-P-2', material: 'A106 GR.B', schedule: 'Sch 80'),
        segments: [
          _seg('s1', null, 'E1', 500),
          _seg('s2', 'E1', 'E2', 400),
        ],
        components: [
          _c('E1', 'elbow90', endType: 'SW', rating: '3000'),
          _c('E2', 'elbow90', label: '90° SW 3000#'),
        ],
      );
      final plan = planFromScan(scan);
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      final s2 = _byId(plan, 's2');
      expect(s2.start.takeoutMm, closeTo(24.1, 1e-9));
      expect(s2.start.takeoutNote, contains('B16.11'));
      expect(s2.cutMm, closeTo(351.8, 1e-9), reason: '400 − 2 × 24,1');
      // Zapisany wiersz odtwarza to samo CUT.
      final row = segmentRowFor(s2,
          id: 'x', projectId: 'p', diameterMm: 33.4, wallThicknessMm: 4.55,
          nowMs: 0)!;
      expect(
          PrefabEngine.storedSegmentCutMm(
            isoMm: row['iso_mm'] as double,
            isoRef: row['iso_ref'] as String,
            startKind: row['start_kind'] as String,
            startValueMm: row['start_value_mm'] as double,
            endKind: row['end_kind'] as String,
            endValueMm: row['end_value_mm'] as double,
            gapMm: 0,
          ),
          closeTo(351.8, 1e-9));
    });

    test('SW bez klasy — jawna luka z wartościami obu klas', () {
      final plan = planFromScan(AiScanResult(
        sizeNotation: 'DN',
        titleBlock: _tb(),
        segments: [_seg('s1', 'E1', null, 400, dn: 25)],
        components: [_c('E1', 'elbow90', endType: 'SW')],
      ));
      final gap = plan.gaps
          .singleWhere((g) => g.code == ScanIssueCode.missingTakeout);
      expect(gap.pl, contains('kl. 3000: 24.1'));
      expect(gap.pl, contains('kl. 6000: 28.6'));
    });

    test('gwint — jawna luka, nic nie jest odejmowane po cichu', () {
      final plan = planFromScan(_scan([
        _seg('s1', 'E1', null, 400),
      ], [
        _c('E1', 'elbow90', endType: 'THD'),
      ]));
      expect(_byId(plan, 's1').cutMm, isNull);
      expect(plan.gaps.single.pl, contains('gwint'));
    });
  });

  group('odniesienie wymiaru z rysunku', () {
    test('FACE przy kołnierzu WN (pewny odczyt) = do przylgi, bez pytania', () {
      final plan = planFromScan(_scan([
        _seg('s1', 'E1', 'F1', 1000, refFrom: 'CL', refTo: 'FACE'),
      ], [
        _c('E1', 'elbow90'),
        _c('F1', 'flange', flangeType: 'WN'),
      ]));
      final s1 = plan.segments.single;
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      expect(s1.refSource, ScanRefSource.drawing);
      expect(s1.cutMm, closeTo(772, 1e-9), reason: '1000 − 152 − 76');
    });

    test('ten sam odczyt ze średnią pewnością — monter potwierdza', () {
      final plan = planFromScan(_scan([
        _seg('s1', 'E1', 'F1', 1000,
            refFrom: 'CL', refTo: 'FACE', conf: AiConfidence.medium),
      ], [
        _c('E1', 'elbow90'),
        _c('F1', 'flange', flangeType: 'WN'),
      ]));
      expect(_gapCodes(plan), contains(ScanIssueCode.dimensionReferenceUnknown));
    });
  });

  test('element, który nie jest trójnikiem, z trzema odcinkami — blokada', () {
    final plan = planFromScan(_scan([
      _seg('s1', null, 'E1', 800),
      _seg('s2', 'E1', null, 600),
      _seg('s3', 'E1', null, 500),
    ], [
      _c('E1', 'elbow90'),
    ]));
    for (final id in ['s1', 's2', 's3']) {
      expect(_gapCodes(plan, id), contains(ScanIssueCode.branchAmbiguous));
    }
  });

  test('spoole: kolejność i etykiety jak na rysunku', () {
    final plan = planFromScan(_scan([
      _seg('a', null, 'E1', 900, spool: 'SP2'),
      _seg('b', 'E1', 'E2', 800, spool: 'SP1'),
      _seg('c', 'E2', null, 700, spool: 'SP1'),
    ], [
      _c('E1', 'elbow90'),
      _c('E2', 'elbow90'),
    ], spools: [
      AiSpool(id: 'SP1', label: 'SPOOL-1'),
      AiSpool(id: 'SP2', label: 'SPOOL-2'),
    ]));
    expect(plan.segments.map((s) => s.sourceId).toList(), ['b', 'c', 'a']);
    expect(plan.segments.map((s) => s.label).toList(),
        ['SPOOL-1/1', 'SPOOL-1/2', 'SPOOL-2/1']);
    expect(plan.segments.map((s) => s.seqNo).toList(), [1, 2, 3]);
  });
}

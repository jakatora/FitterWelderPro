// Geometria 3D skanu ISO (etap 3): kierunki, offsety i rolling offsety z
// rzutów, kąty kolan wobec kierunków, zamknięcie łańcucha wymiarów
// (pętla, wymiar całkowity, rzędne EL).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_geometry.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

AiScanResult _scan(List<AiSegment> segments, List<AiComponent> components,
        {List<AiOverallDimension> overall = const [],
        List<Map<String, String>> elevations = const []}) =>
    AiScanResult(
      schemaVersion: 2,
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-P-1',
        material: 'A312 TP316L',
        schedule: 'Sch 40',
        pipeClass: 'CL150',
      ),
      segments: segments,
      components: components,
      overallDimensions: overall,
      elevations: elevations,
    );

AiSegment _seg(String id, String? from, String? to,
        {double? mm, Object? dir, Map<String, double> proj = const {}}) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: mm,
      rawDimension: mm?.toStringAsFixed(0),
      confidence: AiConfidence.high,
      direction: dir,
      projections: proj,
    );

AiComponent _c(String id, String type) =>
    AiComponent(id: id, type: type, confidence: AiConfidence.high);

PlannedSegment _byId(ScanPlan p, String id) =>
    p.segments.singleWhere((s) => s.sourceId == id);

void main() {
  group('wektory i rzędne', () {
    test('osie rysunku i rzuty', () {
      expect(axisVector('E')!.x, 1);
      expect(axisVector('down')!.z, -1);
      expect(axisVector('NE'), isNull);
      final v = projectionVector({'E': 500, 'N': 300, 'UP': 400})!;
      expect(v.length, closeTo(707.1068, 1e-4));
      expect(v.isAxial, isFalse);
      expect(skewLengthMm({'E': 500, 'N': 300, 'UP': 400}), 707.1);
      expect(skewFormula({'E': 500, 'N': 300, 'UP': 400}),
          '√(500² + 300² + 400²) = 707.1');
      expect(projectionVector({'E': 500, 'XX': 3}), isNull,
          reason: 'rzutu, którego nie da się umieścić, nie gubimy po cichu');
    });

    test('rzędne: tylko jednoznaczne zapisy', () {
      expect(parseElevationMm('EL +3.250'), 3250);
      expect(parseElevationMm('EL. -0.500'), -500);
      expect(parseElevationMm('EL 102450'), 102450);
      expect(parseElevationMm("EL 10'-6\""), closeTo(3200.4, 1e-9));
      expect(parseElevationMm('EL 3.25'), isNull);
      expect(parseElevationMm('EL 12'), isNull);
    });
  });

  group('offset z rzutów', () {
    AiScanResult rolling({double? printed}) => _scan([
          _seg('s1', null, 'E1', mm: 1000, dir: 'E'),
          _seg('s2', 'E1', 'E2',
              mm: printed, proj: {'E': 500, 'N': 300, 'UP': 400}),
          _seg('s3', 'E2', null, mm: 800, dir: 'E'),
        ], [
          _c('E1', 'elbow45'),
          _c('E2', 'elbow45'),
        ]);

    test('rolling offset 45°: długość skośna z rzutów, kąty kolan zgodne', () {
      final plan = planFromScan(rolling());
      expect(plan.gaps, isEmpty, reason: plan.gaps.join('\n'));
      final s2 = _byId(plan, 's2');
      expect(s2.isoMm, 707.1);
      expect(s2.isoNote, contains('√'));
      expect(s2.cutMm, closeTo(579.1, 1e-9), reason: '707,1 − 64 − 64');
      expect(plan.has(ScanIssueCode.dimensionFromProjections), isTrue);
      expect(plan.has(ScanIssueCode.offsetInRoute), isTrue);
      expect(
          plan.warnings
              .firstWhere((w) => w.code == ScanIssueCode.offsetInRoute)
              .pl,
          contains('rolling offset'));
      expect(plan.has(ScanIssueCode.elbowAngleMismatch), isFalse);
    });

    test('wydrukowana długość skośna zgodna z rzutami — bez uwag', () {
      final plan = planFromScan(rolling(printed: 707));
      expect(plan.has(ScanIssueCode.offsetDimensionMismatch), isFalse);
      expect(_byId(plan, 's2').cutMm, closeTo(579, 1e-9));
    });

    test('wydrukowana długość sprzeczna z rzutami — blokada tego cięcia', () {
      final plan = planFromScan(rolling(printed: 750));
      final gap = plan.gaps.singleWhere(
          (g) => g.code == ScanIssueCode.offsetDimensionMismatch);
      expect(gap.segmentId, 's2');
      expect(gap.pl, contains('707.1'));
      expect(plan.gaps.where((g) => g.segmentId != 's2'), isEmpty);
    });

    test('kolano 90° w offsecie 45° — blokada obu odcinków przy kolanie', () {
      final plan = planFromScan(_scan([
        _seg('s1', null, 'E1', mm: 1000, dir: 'E'),
        _seg('s2', 'E1', null, proj: {'E': 400, 'N': 400}),
      ], [
        _c('E1', 'elbow90'),
      ]));
      final ids = plan.gaps
          .where((g) => g.code == ScanIssueCode.elbowAngleMismatch)
          .map((g) => g.segmentId)
          .toSet();
      expect(ids, {'s1', 's2'});
      // Take-out wpisany przez montera zdejmuje blokadę z jego końca.
      final fixed = planFromScan(
        _scan([
          _seg('s1', null, 'E1', mm: 1000, dir: 'E'),
          _seg('s2', 'E1', null, proj: {'E': 400, 'N': 400}),
        ], [
          _c('E1', 'elbow90'),
        ]),
        fitter: const ScanFitterInput(
            takeoutMm: {'E1@s1': 64, 'E1@s2': 64}),
      );
      expect(fixed.has(ScanIssueCode.elbowAngleMismatch), isFalse);
    });
  });

  group('zamknięcie wymiarów', () {
    List<AiSegment> uShape({double back = 1000}) => [
          _seg('s1', 'A', 'E1', mm: 1000, dir: 'E'),
          _seg('s2', 'E1', 'E2', mm: 600, dir: 'UP'),
          _seg('s3', 'E2', 'B', mm: back, dir: 'W'),
        ];
    final comps = [
      _c('A', 'flange'),
      _c('E1', 'elbow90'),
      _c('E2', 'elbow90'),
      _c('B', 'flange'),
    ];

    test('wymiar całkowity zgodny z sumą — bez ostrzeżeń', () {
      final plan = planFromScan(_scan(uShape(), comps, overall: [
        AiOverallDimension(fromId: 'A', toId: 'E2', axis: 'E', valueMm: 1000),
      ], elevations: [
        {'atId': 'E1', 'value': 'EL +1.000'},
        {'atId': 'E2', 'value': 'EL +1.600'},
      ]));
      expect(plan.has(ScanIssueCode.closureMismatch), isFalse);
    });

    test('wymiar całkowity niezgodny — ostrzeżenie z liczbami', () {
      final plan = planFromScan(_scan(uShape(), comps, overall: [
        AiOverallDimension(
            fromId: 'A', toId: 'E1', axis: 'E', valueMm: 1010, raw: '1010'),
      ]));
      final w = plan.warnings
          .singleWhere((w) => w.code == ScanIssueCode.closureMismatch);
      expect(w.blocking, isFalse);
      expect(w.pl, contains('1010'));
      expect(w.pl, contains('1000'));
    });

    test('rzędne EL niezgodne z pionem — ostrzeżenie', () {
      final plan = planFromScan(_scan(uShape(), comps, elevations: [
        {'atId': 'E1', 'value': 'EL +1.000'},
        {'atId': 'E2', 'value': 'EL +1.650'},
      ]));
      expect(plan.has(ScanIssueCode.closureMismatch), isTrue);
    });

    test('pętla, która się nie zamyka — ostrzeżenie', () {
      final plan = planFromScan(_scan([
        _seg('s1', 'A', 'B', mm: 1000, dir: 'E'),
        _seg('s2', 'B', 'C', mm: 500, dir: 'N'),
        _seg('s3', 'C', 'D', mm: 990, dir: 'W'),
        _seg('s4', 'D', 'A', mm: 500, dir: 'S'),
      ], [
        _c('A', 'elbow90'),
        _c('B', 'elbow90'),
        _c('C', 'elbow90'),
        _c('D', 'elbow90'),
      ]));
      expect(plan.has(ScanIssueCode.closureMismatch), isTrue);
    });
  });
}

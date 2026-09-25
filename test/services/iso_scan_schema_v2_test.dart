// Schemat odczytu skanera ISO v2 — parser.
//
// Odczyt v1 (sprzed promptu v2) musi dalej działać bez zmian, a v2 dokłada
// pola, które planista wykorzystuje do grafu trasy, średnic odcinków,
// geometrii 3D, spoin, spooli i porównania z BOM. Model nie zawsze trzyma
// się typów — liczba jako tekst, numer spoiny jako liczba — więc parser jest
// tolerancyjny: zły typ = „nie odczytano" (null), nie wyjątek.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/iso_scanner_ai.dart';

Map<String, dynamic> _envelope(Map<String, dynamic> result) =>
    {'result': result, 'tookMs': 1234, 'model': 'claude-sonnet-5'};

void main() {
  test('odczyt v1 parsuje się jak dotąd: schemaVersion 1, puste listy v2', () {
    final scan = AiScanResult.fromEnvelope(_envelope({
      'drawingStandard': 'ISO',
      'sizeNotation': 'DN',
      'segments': [
        {
          'id': 's1',
          'fromId': null,
          'toId': 'E1',
          'dimensionMm': 1200,
          'rawDimension': '1200',
          'auxiliary': false,
          'confidence': 'high',
        }
      ],
      'components': [
        {'id': 'E1', 'type': 'elbow90', 'label': '90° LR', 'weldNo': 7}
      ],
      'elevations': [
        {'atId': 'E1', 'value': 'EL +3.250'}
      ],
      'billOfMaterials': [
        {'item': 1, 'quantity': 6, 'description': 'PIPE', 'size': 'DN100'}
      ],
    }));

    expect(scan.schemaVersion, 1);
    expect(scan.segments.single.dimensionMm, 1200);
    expect(scan.segments.single.dn, isNull);
    expect(scan.segments.single.projections, isEmpty);
    expect(scan.segments.single.userConfirmed, isFalse);
    expect(scan.components.single.weldNo, '7');
    expect(scan.components.single.connectedTo, isEmpty);
    expect(scan.weldMarks, isEmpty);
    expect(scan.spools, isEmpty);
    expect(scan.overallDimensions, isEmpty);
    expect(scan.billOfMaterials.single.item, '1');
    expect(scan.billOfMaterials.single.unit, isNull);
    expect(scan.elevationPoints.single.elevationMm, isNull);
    expect(scan.elevationPoints.single.value, 'EL +3.250');
  });

  test('odczyt v2: wszystkie nowe pola segmentu, komponentu, spoin i spooli', () {
    final scan = AiScanResult.fromEnvelope(_envelope({
      'schemaVersion': 2,
      'sizeNotation': 'DN',
      'segments': [
        {
          'id': 's1',
          'fromId': 'T1',
          'toId': 'E1',
          'dimensionMm': 800,
          'dn': 80,
          'nps': '3"',
          'schedule': 'Sch 40',
          'direction': 'e',
          'refFrom': 'cl',
          'refTo': 'FACE',
          'spoolId': 'SP1',
          'slope': '1:100',
          'confidence': 'medium',
        },
        {
          'id': 's2',
          'fromId': 'E1',
          'toId': 'E2',
          'direction': {'x': 1, 'y': 0.6, 'z': 0.8},
          'projections': {'E': 500, 'N': '300', 'UP': 400, 'bad': 'x'},
        },
      ],
      'components': [
        {
          'id': 'T1',
          'type': 'tee',
          'sizeLarge': 'DN100',
          'sizeSmall': 80,
          'endType': 'bw',
          'runIds': ['s0', 's3'],
          'branchId': 's1',
          'bomItem': 3,
          'spoolId': 'SP1',
        },
        {
          'id': 'V1',
          'type': 'valve',
          'valveType': 'gate',
          'connectedTo': ['F1', 'F2'],
          'flangeType': 'wn',
          'rating': 150,
          'facing': 'rf',
          'angleDeg': '60',
        },
      ],
      'welds': [
        {
          'id': 'w1',
          'number': 12,
          'type': 'FIELD',
          'jointType': 'bw',
          'betweenIds': ['s1', 'T1'],
          'spoolId': 'SP1',
          'nde': 'RT',
          'pwht': false,
          'confidence': 'high',
        },
        {'id': 'w2', 'number': 'W-02', 'type': 'shop'},
      ],
      'spools': [
        {'id': 'SP1', 'label': 'SPOOL 1'},
        {'label': 'bez id — pominięty'},
      ],
      'overallDimensions': [
        {'fromId': 'A', 'toId': 'B', 'axis': 'e', 'valueMm': 2500},
        {'fromId': '', 'toId': 'B', 'valueMm': 1},
      ],
      'elevations': [
        {'atId': 'E1', 'value': 'EL +3.250', 'elevationMm': 3250},
      ],
      'billOfMaterials': [
        {'item': '1', 'quantity': '6,2', 'unit': 'm', 'description': 'PIPE'},
      ],
    }));

    expect(scan.schemaVersion, 2);

    final s1 = scan.segments[0];
    expect(s1.dn, 80);
    expect(s1.nps, '3"');
    expect(s1.schedule, 'Sch 40');
    expect(s1.direction, 'e');
    expect(s1.refFrom, 'CL');
    expect(s1.refTo, 'FACE');
    expect(s1.spoolId, 'SP1');
    expect(s1.slope, '1:100');
    expect(s1.confidence, AiConfidence.medium);

    final s2 = scan.segments[1];
    expect(s2.direction, {'x': 1.0, 'y': 0.6, 'z': 0.8});
    expect(s2.projections, {'E': 500.0, 'N': 300.0, 'UP': 400.0});
    expect(s2.dimensionMm, isNull);

    final t1 = scan.components[0];
    expect(t1.sizeLarge, 'DN100');
    expect(t1.sizeSmall, '80');
    expect(t1.endType, 'BW');
    expect(t1.runIds, ['s0', 's3']);
    expect(t1.branchId, 's1');
    expect(t1.bomItem, '3');
    expect(t1.spoolId, 'SP1');

    final v1 = scan.components[1];
    expect(v1.connectedTo, ['F1', 'F2']);
    expect(v1.flangeType, 'WN');
    expect(v1.rating, '150');
    expect(v1.facing, 'RF');
    expect(v1.angleDeg, 60);

    expect(scan.weldMarks, hasLength(2));
    expect(scan.weldMarks[0].number, '12');
    expect(scan.weldMarks[0].isField, isTrue);
    expect(scan.weldMarks[0].jointType, 'BW');
    expect(scan.weldMarks[0].betweenIds, ['s1', 'T1']);
    expect(scan.weldMarks[0].pwht, isFalse);
    expect(scan.weldMarks[1].location, 'shop');

    expect(scan.spools.map((s) => s.display), ['SPOOL 1']);
    expect(scan.overallDimensions, hasLength(1));
    expect(scan.overallDimensions.single.axis, 'E');
    expect(scan.overallDimensions.single.valueMm, 2500);
    expect(scan.elevationPoints.single.elevationMm, 3250);
    expect(scan.billOfMaterials.single.quantity, closeTo(6.2, 1e-9));
    expect(scan.billOfMaterials.single.unit, 'M');
  });

  test('złe typy pól v2 dają null, nie wyjątek', () {
    final scan = AiScanResult.fromEnvelope(_envelope({
      'schemaVersion': 'dwa',
      'segments': [
        {
          'id': 7,
          'dn': 'DN100',
          'dimensionMm': 'abc',
          'projections': [1, 2],
          'direction': 12,
        }
      ],
      'components': [
        {'id': 'X', 'connectedTo': 'F1', 'runIds': 5, 'angleDeg': {}}
      ],
      'welds': [
        {'betweenIds': 'T1'}
      ],
    }));
    expect(scan.schemaVersion, 1);
    final s = scan.segments.single;
    expect(s.id, '7');
    expect(s.dn, isNull, reason: 'tekst "DN100" to nie liczba DN');
    expect(s.dimensionMm, isNull);
    expect(s.projections, isEmpty);
    expect(s.direction, isNull);
    final c = scan.components.single;
    expect(c.type, 'other');
    expect(c.connectedTo, ['F1']);
    expect(c.runIds, isEmpty);
    expect(c.angleDeg, isNull);
    expect(scan.weldMarks.single.betweenIds, ['T1']);
  });

  test('copyWith segmentu i skanu nie gubi pól v2', () {
    final scan = AiScanResult.fromEnvelope(_envelope({
      'schemaVersion': 2,
      'segments': [
        {
          'id': 's1',
          'dimensionMm': 500,
          'dn': 50,
          'direction': 'N',
          'projections': {'E': 1},
          'refTo': 'CL',
          'spoolId': 'A',
        }
      ],
      'welds': [
        {'id': 'w', 'number': '1'}
      ],
      'spools': [
        {'id': 'A'}
      ],
    }));
    final s = scan.segments.single.copyWith(
      dimensionMm: 510.0,
      rawDimension: '510',
      confidence: AiConfidence.high,
      userConfirmed: true,
    );
    expect(s.dimensionMm, 510);
    expect(s.dn, 50);
    expect(s.direction, 'N');
    expect(s.projections, {'E': 1.0});
    expect(s.refTo, 'CL');
    expect(s.spoolId, 'A');
    expect(s.userConfirmed, isTrue);

    final copy = scan.copyWith(segments: [s]);
    expect(copy.schemaVersion, 2);
    expect(copy.weldMarks.single.number, '1');
    expect(copy.spools.single.id, 'A');
    expect(copy.segments.single.dimensionMm, 510);
  });
}

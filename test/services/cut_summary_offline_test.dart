// Druga część kroku „Test głównego przebiegu bez sieci”.
//
// Po wyliczeniu CUT (patrz builder_cut_offline_test.dart) trzy segmenty DN100
// trafiają do podsumowania: rozkład na sztangi (nestCutsToBars — ta sama
// funkcja, której używa CutListSummaryScreen) i lista materiałowa
// (MaterialListBuilder.countComponentInstances). Wszystko przy transporcie
// HTTP, który rzuca błąd i liczy każdą próbę połączenia.
//
// Oczekiwane liczby policzone ręcznie (sztanga 6000 mm, rzaz 3 mm):
//   sztanga 1: 3293 + 2500 = 5793, 2 cięcia → 6000 − 5793 − 6 = 201 mm
//   sztanga 2: 1200, 1 cięcie → 6000 − 1200 − 3 = 4797 mm
//   odpad: 201 + 4797 = 4998 mm z 12000 mm = 41,65 %

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/bar_nesting.dart';
import 'package:cut_list_app/services/iso_parser.dart';
import 'package:cut_list_app/services/material_list_builder.dart';

class _OfflineHttpOverrides extends HttpOverrides {
  int connectionAttempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    connectionAttempts++;
    throw const SocketException('offline test: network access is forbidden');
  }
}

const _elbow = 'elb90-lr-dn100';
const _flange = 'flange-wn-dn100';

Segment _seg(int seqNo, double cutMm, String? startId, String? endId) {
  return Segment(
    id: 'seg-$seqNo',
    projectId: 'project-dn100',
    seqNo: seqNo,
    diameterMm: 114.3,
    wallThicknessMm: 6.02,
    startKind: 'COMPONENT',
    startLibraryId: startId,
    startValueMm: 0,
    endKind: 'COMPONENT',
    endLibraryId: endId,
    endValueMm: 0,
    isoRef: 'AXIS',
    isoExpr: '',
    isoMm: 0,
    cutMm: cutMm,
    createdAt: 0,
    updatedAt: 0,
  );
}

double _firstCut() {
  final takeout = closestByDn(100).lr90.toDouble();
  final iso = parseIsoExpression('3000+525-80').toDouble();
  return builderCutMm(
    isoMm: iso,
    startRef: IsoRefPoint.axis,
    startOffsetMm: takeout,
    endRef: IsoRefPoint.faceNear,
    endOffsetMm: 0,
    gapMm: 0,
    welds: 2,
  );
}

void main() {
  late _OfflineHttpOverrides offline;
  HttpOverrides? previous;

  setUp(() {
    previous = HttpOverrides.current;
    offline = _OfflineHttpOverrides();
    HttpOverrides.global = offline;
  });

  tearDown(() {
    HttpOverrides.global = previous;
  });

  group('DN100: 3 segmenty → podsumowanie, bez sieci', () {
    test('pierwszy segment ma CUT 3293 mm', () {
      expect(_firstCut(), closeTo(3293.0, 1e-9));
      expect(offline.connectionAttempts, 0);
    });

    test('3 segmenty dają 2 sztangi i 4998 mm odpadu', () {
      final cuts = [_firstCut(), 2500.0, 1200.0];
      final plans = nestCutsToBars(
        cutsMm: cuts,
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );

      expect(plans, hasLength(2));

      expect(plans[0].piecesMm, hasLength(2));
      expect(plans[0].piecesMm[0], closeTo(3293.0, 1e-9));
      expect(plans[0].piecesMm[1], closeTo(2500.0, 1e-9));
      expect(plans[0].cutsCount, 2);
      expect(plans[0].remainingMm, closeTo(201.0, 1e-9));

      expect(plans[1].piecesMm, hasLength(1));
      expect(plans[1].piecesMm[0], closeTo(1200.0, 1e-9));
      expect(plans[1].cutsCount, 1);
      expect(plans[1].remainingMm, closeTo(4797.0, 1e-9));

      final wasteMm = plans.fold<double>(0, (s, b) => s + b.remainingMm);
      expect(wasteMm, closeTo(4998.0, 1e-9));
      final wastePct = wasteMm / (plans.length * 6000) * 100;
      expect(wastePct, closeTo(41.65, 1e-9));

      final netMm = plans.fold<double>(
          0, (s, b) => s + b.piecesMm.fold<double>(0, (a, v) => a + v));
      expect(netMm, closeTo(6993.0, 1e-9));

      expect(offline.connectionAttempts, 0);
    });

    test('kolejność segmentów nie zmienia rozkładu', () {
      final plans = nestCutsToBars(
        cutsMm: [1200.0, _firstCut(), 2500.0],
        stockLengthMm: 6000,
        sawKerfMm: 3,
      );
      expect(plans, hasLength(2));
      expect(plans[0].remainingMm, closeTo(201.0, 1e-9));
      expect(plans[1].remainingMm, closeTo(4797.0, 1e-9));
      expect(offline.connectionAttempts, 0);
    });

    test('lista materiałowa: 3 kolana i 1 kołnierz', () {
      final segs = [
        _seg(1, _firstCut(), _elbow, _elbow),
        _seg(2, 2500, _elbow, _elbow),
        _seg(3, 1200, _elbow, _flange),
      ];
      expect(MaterialListBuilder.countComponentInstances(segs),
          {_elbow: 3, _flange: 1});
      expect(
          MaterialListBuilder.countComponentInstances(segs.reversed.toList()),
          {_elbow: 3, _flange: 1});
      expect(offline.connectionAttempts, 0);
    });

    test('dziura w numeracji seqNo nie rozbija złączy', () {
      final segs = [
        _seg(1, 3293, _elbow, _elbow),
        _seg(2, 2500, _elbow, _elbow),
        _seg(5, 1200, _elbow, _flange),
      ];
      expect(MaterialListBuilder.countComponentInstances(segs),
          {_elbow: 3, _flange: 1});
      expect(offline.connectionAttempts, 0);
    });
  });

  group('rozkład na sztangi: przypadki brzegowe', () {
    test('sztanga o długości 0 daje pusty plan', () {
      expect(
        nestCutsToBars(cutsMm: [1000], stockLengthMm: 0, sawKerfMm: 3),
        isEmpty,
      );
    });

    test('cięcie równe sztandze: 0 cięć i 0 odpadu', () {
      final plans =
          nestCutsToBars(cutsMm: [6000], stockLengthMm: 6000, sawKerfMm: 3);
      expect(plans, hasLength(1));
      expect(plans[0].cutsCount, 0);
      expect(plans[0].remainingMm, 0);
    });

    test('cięcie 7000 mm zajmuje dwie sztangi', () {
      final plans =
          nestCutsToBars(cutsMm: [7000], stockLengthMm: 6000, sawKerfMm: 3);
      expect(plans, hasLength(2));
      expect(plans[0].piecesMm, [6000.0]);
      expect(plans[0].cutsCount, 0);
      expect(plans[1].piecesMm, [1000.0]);
      expect(plans[1].cutsCount, 1);
      expect(plans[1].remainingMm, closeTo(4997.0, 1e-9));
      expect(offline.connectionAttempts, 0);
    });
  });
}

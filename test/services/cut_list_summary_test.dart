// Czwarta część kroku „Test głównego przebiegu bez sieci”: sumy, które
// PdfExportService wpisuje w blok podsumowania PDF (summarizeCutList).
// Test działa przy transporcie HTTP, który rzuca błąd i liczy próby połączenia.
//
// Oczekiwane liczby policzone ręcznie (sztanga 6000 mm, rzaz 3 mm):
//   sztanga 1: 3293 + 2500, 2 cięcia → 6000 − 5793 − 6 = 201 mm
//   sztanga 2: 1200, 1 cięcie → 6000 − 1200 − 3 = 4797 mm
//   odpad: 4998 mm z 12000 mm = 41,65 %, netto 6993 mm

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/cut_list_summary.dart';
import 'package:cut_list_app/services/iso_parser.dart';

class _OfflineHttpOverrides extends HttpOverrides {
  int connectionAttempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    connectionAttempts++;
    throw const SocketException('offline test: network access is forbidden');
  }
}

Segment _seg(int seqNo, double cutMm,
    {double diameterMm = 114.3, double wallMm = 6.02}) {
  return Segment(
    id: 'seg-$seqNo',
    projectId: 'project-dn100',
    seqNo: seqNo,
    diameterMm: diameterMm,
    wallThicknessMm: wallMm,
    startKind: 'COMPONENT',
    startLibraryId: null,
    startValueMm: 0,
    endKind: 'COMPONENT',
    endLibraryId: null,
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

  test('3 segmenty DN100: 2 sztangi, 6993 mm netto, 41,65 % odpadu', () {
    final s = summarizeCutList(
      segments: [_seg(1, _firstCut()), _seg(2, 2500), _seg(3, 1200)],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );

    expect(s.segmentCount, 3);
    expect(s.groups, hasLength(1));
    expect(s.groups[0].diameterMm, 114.3);
    expect(s.groups[0].wallMm, 6.02);
    expect(s.groups[0].cutsMm, hasLength(3));
    expect(s.groups[0].cutsMm[0], closeTo(3293.0, 1e-9));
    expect(s.groups[0].cutsMm[1], closeTo(2500.0, 1e-9));
    expect(s.groups[0].cutsMm[2], closeTo(1200.0, 1e-9));

    expect(s.totalBars, 2);
    expect(s.totalNetMm, closeTo(6993.0, 1e-9));
    expect(s.totalWasteMm, closeTo(4998.0, 1e-9));
    expect(s.wastePct, closeTo(41.65, 1e-9));
    expect(offline.connectionAttempts, 0);
  });

  test('druga średnica tworzy osobną grupę w kolejności pojawienia się', () {
    final s = summarizeCutList(
      segments: [
        _seg(1, 3293),
        _seg(2, 700, diameterMm: 60.3, wallMm: 3.91),
        _seg(3, 1200),
        _seg(4, 2500),
      ],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );

    expect(s.segmentCount, 4);
    expect(s.groups, hasLength(2));
    expect(s.groups[0].diameterMm, 114.3);
    expect(s.groups[0].cutsMm, [3293.0, 2500.0, 1200.0]);
    expect(s.groups[0].plans, hasLength(2));
    expect(s.groups[1].diameterMm, 60.3);
    expect(s.groups[1].wallMm, 3.91);
    expect(s.groups[1].cutsMm, [700.0]);
    expect(s.groups[1].plans, hasLength(1));
    expect(s.groups[1].plans[0].remainingMm, closeTo(5297.0, 1e-9));

    expect(s.totalBars, 3);
    expect(s.totalNetMm, closeTo(7693.0, 1e-9));
    expect(s.totalWasteMm, closeTo(10295.0, 1e-9));
    expect(s.wastePct, closeTo(10295.0 / 18000.0 * 100, 1e-9));
    expect(offline.connectionAttempts, 0);
  });

  test('pusty projekt: 0 sztang i 0 % odpadu', () {
    final s = summarizeCutList(
      segments: const [],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );
    expect(s.segmentCount, 0);
    expect(s.groups, isEmpty);
    expect(s.totalBars, 0);
    expect(s.totalNetMm, 0);
    expect(s.totalWasteMm, 0);
    expect(s.wastePct, 0);
  });

  test('sztanga o długości 0 nie dzieli przez zero', () {
    final s = summarizeCutList(
      segments: [_seg(1, 1200)],
      stockLengthMm: 0,
      sawKerfMm: 3,
    );
    expect(s.segmentCount, 1);
    expect(s.groups, hasLength(1));
    expect(s.groups[0].plans, isEmpty);
    expect(s.totalBars, 0);
    expect(s.wastePct, 0);
    expect(s.wastePct.isNaN, isFalse);
  });
}

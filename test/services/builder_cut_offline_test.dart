// Pierwsza część kroku „Test głównego przebiegu bez sieci”.
//
// Ścieżka monterska DN100: kolano 90° LR (wymiar od osi) → rura → kołnierz
// (czoło bliskie), ISO z rysunku wpisane jako wyrażenie 3000+525-80.
// Liczone tymi samymi funkcjami, których używa SegmentBuilderScreen, przy
// transporcie HTTP, który rzuca błąd i liczy każdą próbę połączenia.
// Wartość takeoutu bierzemy niezależnie z tabeli ASME B16.9, a nie z silnika.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/iso_parser.dart';
import 'package:cut_list_app/services/prefab_engine.dart';

class _OfflineHttpOverrides extends HttpOverrides {
  int connectionAttempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    connectionAttempts++;
    throw const SocketException('offline test: network access is forbidden');
  }
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

  group('DN100: kolano 90° LR + 3000+525-80 + kołnierz, bez sieci', () {
    // ASME B16.9, DN100 LR 90°: centre-to-end 152 mm.
    final takeout = closestByDn(100).lr90.toDouble();

    test('tabela takeoutów daje 152 mm dla DN100 LR 90°', () {
      expect(takeout, 152.0);
    });

    test('wyrażenie ISO liczy się do 3445 mm', () {
      expect(parseIsoExpression('3000+525-80'), closeTo(3445.0, 1e-9));
      expect(offline.connectionAttempts, 0);
    });

    test('punkty odniesienia mapują się na właściwe zatrzymania', () {
      expect(stopForRefPoint(IsoRefPoint.axis), SideStop.centre);
      expect(stopForRefPoint(IsoRefPoint.faceNear), SideStop.face);
    });

    test('CUT bez szczeliny = 3445 − 152 = 3293 mm', () {
      final iso = parseIsoExpression('3000+525-80').toDouble();
      final cut = builderCutMm(
        isoMm: iso,
        startRef: IsoRefPoint.axis,
        startOffsetMm: takeout,
        endRef: IsoRefPoint.faceNear,
        endOffsetMm: 0,
        gapMm: 0,
        welds: 2,
      );
      expect(cut, closeTo(3293.0, 1e-9));
      expect(offline.connectionAttempts, 0,
          reason: 'wyliczenie CUT nie może dotykać sieci');
    });

    test('CUT ze szczeliną 2 mm na 2 spoinach = 3289 mm', () {
      final iso = parseIsoExpression('3000+525-80').toDouble();
      final cut = builderCutMm(
        isoMm: iso,
        startRef: IsoRefPoint.axis,
        startOffsetMm: takeout,
        endRef: IsoRefPoint.faceNear,
        endOffsetMm: 0,
        gapMm: 2,
        welds: 2,
      );
      expect(cut, closeTo(3289.0, 1e-9));
      expect(offline.connectionAttempts, 0);
    });

    test('ISO krótsze niż takeout nie daje długości do cięcia', () {
      final cut = builderCutMm(
        isoMm: 100,
        startRef: IsoRefPoint.axis,
        startOffsetMm: takeout,
        endRef: IsoRefPoint.faceNear,
        endOffsetMm: 0,
        gapMm: 0,
        welds: 2,
      );
      expect(cut.isFinite && cut > 0, isFalse,
          reason: 'piła nie może dostać ujemnej ani nieskończonej długości');
      expect(offline.connectionAttempts, 0);
    });
  });
}

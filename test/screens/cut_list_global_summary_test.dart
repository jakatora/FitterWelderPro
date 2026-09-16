// Kolejna część kroku „Test głównego przebiegu bez sieci”: kafelek
// „Podsumowanie” na ekranie CUT LIST pokazuje te same sumy, które
// summarizeCutList przekazuje do PDF. Transport HTTP rzuca błąd i liczy próby.
//
// Oczekiwane liczby policzone ręcznie (sztanga 6000 mm, rzaz 3 mm; ostatni
// odcinek z resztą > 0 kosztuje jedno cięcie, jak w cut_list_summary_test):
//   5000 → reszta 6000 − 5000 − 3 = 997 mm (×2)
//   1200 nie mieści się obok 5000 (5000 + 3 + 1200 > 6000) → trzecia sztanga,
//        reszta 6000 − 1200 − 3 = 4797 mm
//   sztangi: 3, netto 11 200 mm = „11.20 m”
//   odpad: 997 + 997 + 4797 = 6791 mm z 18 000 mm = 37,73 % → „37.7%”
//
// Dwie średnice: 3293, 2500, 1200 (DN100) + 700 (DN50):
//   odpad 201 + 4797 + 5297 = 10 295 mm z 18 000 mm = 57,19 % → „57.2%”
//   netto 7693 mm = „7.69 m”

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/cut_list_summary_screen.dart';
import 'package:cut_list_app/services/cut_list_summary.dart';

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

Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: Scaffold(body: child)),
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

  testWidgets('3 segmenty DN100: 3 sztangi, 11.20 m netto, 37.7% odpadu',
      (tester) async {
    final summary = summarizeCutList(
      segments: [_seg(1, 5000), _seg(2, 1200), _seg(3, 5000)],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );

    expect(summary.totalBars, 3);
    expect(summary.totalNetMm, closeTo(11200.0, 1e-9));
    expect(summary.totalWasteMm, closeTo(6791.0, 1e-9));

    await tester.pumpWidget(_wrap(CutListGlobalSummary(summary: summary)));
    await tester.pump();

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Bars'), findsOneWidget);
    expect(find.text('11.20 m'), findsOneWidget);
    expect(find.text('37.7%'), findsOneWidget);
    expect(offline.connectionAttempts, 0);
  });

  testWidgets('dwie średnice: sumy z obu grup, 7.69 m i 57.2% odpadu',
      (tester) async {
    final summary = summarizeCutList(
      segments: [
        _seg(1, 3293),
        _seg(2, 700, diameterMm: 60.3, wallMm: 3.91),
        _seg(3, 1200),
        _seg(4, 2500),
      ],
      stockLengthMm: 6000,
      sawKerfMm: 3,
    );

    await tester.pumpWidget(_wrap(CutListGlobalSummary(summary: summary)));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    expect(find.text('7.69 m'), findsOneWidget);
    expect(find.text('57.2%'), findsOneWidget);
    expect(offline.connectionAttempts, 0);
  });
}

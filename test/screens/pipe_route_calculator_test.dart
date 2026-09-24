// Kalkulator trasy rur (lib/screens/pipe_route_calculator_screen.dart).
//
// Trasa: poziomo X → pionowo |H1−H2| → poziomo Y = DWA kolana 90°.
// Odcinki (R = take-out kolana 90°, dla LR = promień CLR):
//   Odc.1 = X − R,  Odc.2 = |H1−H2| − 2R,  Odc.3 = Y − R
// Długość rozwinięta osi (proste + łuki) = Σ odcinków + 2 × (π·R/2) = Σ + π·R
//   = (X + |H1−H2| + Y) − (4 − π)·R.
//
// Przykład: X 1000, Y 800, H1 2000, H2 1000, R 152 (DN100 LR, B16.9):
//   Odc.1 = 848, Odc.2 = 1000 − 304 = 696, Odc.3 = 648, Σ = 2192
//   łuki  = π·152 = 477,52;  rozwinięta = 2669,52
//   kontrola: 2800 − (4 − π)·152 = 2800 − 130,48 = 2669,52
// Pomoc kazała dodać 3 × (π·R/2) = 716,28 — o jedno kolano (238,76 mm) za dużo.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pipe_route_calculator_screen.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('computePipeRoute: 2 kolana, odcinki i długość rozwinięta', () {
    final r = computePipeRoute(h1: 2000, h2: 1000, x: 1000, y: 800, r: 152);
    expect(r.seg1, 848);
    expect(r.seg2, 696);
    expect(r.seg3, 648);
    expect(r.total, 2192);
    expect(r.elbowCount, 2);
    expect(r.arcsMm, closeTo(math.pi * 152, 1e-9));
    expect(r.developedMm, closeTo(2669.52, 0.01));
    expect(r.developedMm, closeTo(2800 - (4 - math.pi) * 152, 1e-9));
  });

  testWidgets('tytuł i wzór mówią o 2 kolanach, łuki = 2 × (π·R/2)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(const PipeRouteCalculatorScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 kolana 90°'), findsOneWidget);
    expect(find.textContaining('3 kolanka'), findsNothing);

    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await tester.enterText(field('H1 – wys. startu'), '2000');
    await tester.enterText(field('H2 – wys. końca'), '1000');
    await tester.enterText(field('X – bieg poziomy 1'), '1000');
    await tester.enterText(field('Y – bieg poziomy 2'), '800');
    await tester.enterText(field('R – takeout kolanka 90° (C-F)'), '152');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Wzór'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 × (π·R/2)'), findsOneWidget);
    expect(find.textContaining('3 × (π·R/2)'), findsNothing);
    // Dla bieżących danych: 2192 + π·152 = 2669,5 mm
    expect(find.textContaining('2669,5'), findsOneWidget);
  });
}

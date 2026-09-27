// Trasa rur — szczelina spoiny, R z ASME B16.9 wg DN, bez startu z R = 0
// i bez akcji „Wyzeruj R” (G2 P1).
//
// Liczby niezależnie: H1 2000, H2 500, X 1000, Y 800, DN100 LR 90°
// A = 152 mm (ASME B16.9 tab. 6.1-1), g = 3 mm:
//   Odc.1 = 1000 − 152 − 3        = 845
//   Odc.2 = 1500 − 2·152 − 2·3    = 1190
//   Odc.3 = 800 − 152 − 3         = 645     Σ = 2680 (bez g: 2692, −12 mm)
// Ze spoinami na końcach trasy: 842 / 1190 / 642, Σ = 2674.
// Długość rozwinięta osi = Σ + 4·g + π·R = 2680 + 12 + 477,52 = 3169,52
//   = (X + ΔH + Y) − (4 − π)·R = 3300 − 130,48.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pipe_route_calculator_screen.dart';

Widget _app() => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: const MaterialApp(home: PipeRouteCalculatorScreen()),
    );

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
    description: label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

Future<void> _big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _fill(WidgetTester tester,
    {String h1 = '2000', String h2 = '500'}) async {
  await tester.enterText(_field('H1 – wys. startu'), h1);
  await tester.enterText(_field('H2 – wys. końca'), h2);
  await tester.enterText(_field('X – bieg poziomy 1'), '1000');
  await tester.enterText(_field('Y – bieg poziomy 2'), '800');
}

const _rLabel = 'R – takeout kolanka 90° (C-F)';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('computePipeRoute ze szczeliną', () {
    test('g 3 mm przy 4 spoinach kolan: 845 / 1190 / 645', () {
      final r = computePipeRoute(
          h1: 2000, h2: 500, x: 1000, y: 800, r: 152, gapMm: 3);
      expect(r.seg1, 845);
      expect(r.seg2, 1190);
      expect(r.seg3, 645);
      expect(r.total, 2680);
      expect(r.weldCount, 4);
      expect(r.developedMm, closeTo(3300 - (4 - math.pi) * 152, 1e-9));
    });

    test('spoiny także na końcach: 842 / 1190 / 642', () {
      final r = computePipeRoute(
          h1: 2000, h2: 500, x: 1000, y: 800, r: 152,
          gapMm: 3, endWelds: true);
      expect(r.seg1, 842);
      expect(r.seg3, 642);
      expect(r.total, 2674);
      expect(r.weldCount, 6);
      expect(r.developedMm, closeTo(3300 - (4 - math.pi) * 152, 1e-9));
    });
  });

  testWidgets('R nie startuje od 0; puste R → błąd, bez „Wyzeruj R”',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_text(tester, _rLabel), '');
    await _fill(tester);
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wybierz DN kolan'), findsOneWidget);
    expect(find.text('Wyzeruj R'), findsNothing);
  });

  testWidgets('DN100 z listy → R 152; g 3 → 845 / 1190 / 645', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DN100 (4") — R = 152 mm').last);
    await tester.pumpAndSettle();
    expect(_text(tester, _rLabel), '152');
    await tester.enterText(_field('Szczelina spoiny g'), '3');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(_text(tester, 'Odcinek 1 (poziomy, X−R−g)'), '845,0');
    expect(_text(tester, 'Odcinek 2 (pionowy, |H1−H2|−2R−2g)'), '1190,0');
    expect(_text(tester, 'Odcinek 3 (poziomy, Y−R−g)'), '645,0');
    expect(find.text('2680,0 mm'), findsOneWidget);
  });

  testWidgets('puste H1/H2 i H1 = H2 to błąd, nie trasa z pionem 0',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _fill(tester, h1: '', h2: '');
    await tester.enterText(_field(_rLabel), '152');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wpisz H1 i H2'), findsOneWidget);

    ScaffoldMessenger.of(tester.element(find.text('OBLICZ')))
        .removeCurrentSnackBar();
    await _fill(tester, h1: '1000', h2: '1000');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('brak odcinka pionowego'), findsOneWidget);
  });

  testWidgets('R = 0 wpisane jawnie: wynik z ostrzeżeniem C-C', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.enterText(_field(_rLabel), '0');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NIE długości cięcia'), findsOneWidget);
  });

  testWidgets('za duże R: komunikat bez akcji „Wyzeruj R”', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.enterText(_field(_rLabel), '900');
    await tester.tap(find.text('OBLICZ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('odcinek wyszedłby'), findsOneWidget);
    expect(find.text('Wyzeruj R'), findsNothing);
  });

  testWidgets('zapisane stare R = „0” nie wraca jako domyślne', (tester) async {
    SharedPreferences.setMockInitialValues({'pipe_route.r': '0'});
    await _big(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(_text(tester, _rLabel), '');
  });
}

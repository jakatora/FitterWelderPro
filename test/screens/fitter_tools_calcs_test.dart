// Kalkulatory montera (lib/screens/fitter_tools_screen.dart): Spadek i Wstawka.
//
// Liczby policzone niezależnie od kodu aplikacji:
//
// SPADEK — jedno cięcie skośne rury o średnicy D, spadek p %:
//   α = atan(p/100); różnica osiowa góra–dół na przekroju = D·tan α = D·p/100
//   (D·sin α to długość po skosie cięcia, nie wymiar do odmierzenia).
//   D = 200 mm, p = 50 %  →  Δh = 200·0,5 = 100,00 mm   (sin: 89,44 mm)
//
// WSTAWKA — dwa kolana o kącie θ, odsadzka (offset) h:
//   travel = h / sin θ;  wstawka = travel − 2·T
//   T (take-out) dla standardowego kolana ASME B16.9-2018:
//     θ = 90° → A, θ = 45° → B z tab. 6.1-1 (LR); inne kąty → A·tan(θ/2)
//     (B16.9 §6.2.4, segment kolana 90°).
//   a) OD 60,3 (NPS 2), h = 300, θ = 45°, LR: B = 1 3/8" → 35 mm
//      travel = 300/sin45° = 424,26;  wstawka = 424,26 − 70 = 354,26 → 354,3
//      (stary kod: R = 1,5·OD = 90,45 → T = 37,47 → 349,3)
//   b) OD 114,3 (NPS 4), h = 500, θ = 45°, LR: B = 2 1/2" → 64 mm
//      travel = 707,11;  wstawka = 707,11 − 128 = 579,11 → 579,1
//      (stary kod: R = 171,45 → 565,1)
//   c) OD 60,3, h = 300, θ = 60°, LR: A = 76 → T = 76·tan30° = 43,88
//      travel = 300/sin60° = 346,41;  wstawka = 346,41 − 87,76 = 258,65 → 258,7
//   d) Ręcznie R = 90,45, h = 300, θ = 45°: T = 90,45·tan22,5° = 37,47
//      wstawka = 424,26 − 74,93 = 349,33 → 349,3

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final f = _field(label);
  expect(f, findsOneWidget, reason: label);
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
  await tester.pumpAndSettle();
}

const _odLabel = 'Średnica zewnętrzna rury OD (mm)';
const _angleLabel = 'Kąt kolanka θ (°)';
const _offsetLabel = 'Odejście — offset (mm)';

Future<void> _pickMode(WidgetTester tester, String itemText) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Spadek — Δh = D·tan α', () {
    test('D 200 mm, 50 % → 100 mm (nie D·sin α = 89,44)', () {
      expect(slopeCutDeltaMm(200, 50), closeTo(100.0, 1e-9));
      expect(slopeCutDeltaMm(200, 50),
          closeTo(200 * math.tan(math.atan(0.5)), 1e-9));
    });

    testWidgets('zakładka Spadek pokazuje 100.00 mm', (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 0)));
      await tester.pumpAndSettle();
      await _enter(tester, 'Średnica zewnętrzna rury D (mm)', '200');
      await _enter(tester, 'Spadek (%)', '50');
      expect(find.text('100.00 mm'), findsOneWidget);
      expect(find.text('89.44 mm'), findsNothing);
    });
  });

  group('Wstawka — take-out z tabel ASME B16.9', () {
    test('insertBetweenElbows: travel − 2·T', () {
      final r = insertBetweenElbows(offsetMm: 300, angleDeg: 45, takeoutMm: 35);
      expect(r.travelMm, closeTo(300 / math.sin(math.pi / 4), 1e-9));
      expect(r.insertMm, closeTo(424.264 - 70, 0.001));
    });

    testWidgets('OD 60,3 / 300 / 45° LR → 354,3 mm (B = 35 z tab. 6.1-1)',
        (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _enter(tester, _odLabel, '60.3');
      await _enter(tester, _angleLabel, '45');
      await _enter(tester, _offsetLabel, '300');
      expect(find.text('354.3 mm'), findsOneWidget);
      expect(find.text('35.0 mm'), findsOneWidget); // take-out
      expect(find.textContaining('B16.9'), findsWidgets);
      expect(find.textContaining('B = 35 mm'), findsOneWidget);
      expect(find.text('349.3 mm'), findsNothing, reason: 'stary R = 1,5·OD');
    });

    testWidgets('OD 114,3 / 500 / 45° LR → 579,1 mm (B = 64)', (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _enter(tester, _odLabel, '114.3');
      await _enter(tester, _angleLabel, '45');
      await _enter(tester, _offsetLabel, '500');
      expect(find.text('579.1 mm'), findsOneWidget);
      expect(find.text('565.1 mm'), findsNothing);
    });

    testWidgets('OD 60,3 / 300 / 60° LR → segment A·tan30° → 258,7 mm',
        (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _enter(tester, _odLabel, '60.3');
      await _enter(tester, _angleLabel, '60');
      await _enter(tester, _offsetLabel, '300');
      expect(find.text('258.7 mm'), findsOneWidget);
      // Źródło take-outu podane przy wyniku: segment wg B16.9 §6.2.4.
      expect(find.textContaining('§6.2.4 (segment kolana 90° LR)'),
          findsOneWidget);
      expect(find.textContaining('76 × tan(30°)'), findsOneWidget);
    });

    testWidgets('OD spoza ASME / EN s.1 (108) — błąd zamiast zgadywania R',
        (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _enter(tester, _odLabel, '108');
      await _enter(tester, _angleLabel, '45');
      await _enter(tester, _offsetLabel, '300');
      expect(find.textContaining('Ręcznie'), findsWidgets);
      expect(find.textContaining('Wstawka  = travel'), findsNothing);
    });

    testWidgets('1D (SR) dla DN15 — B16.9 nie ma kolana SR poniżej NPS 1',
        (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _pickMode(tester, '1D — krótki promień SR (B16.9, od DN25)');
      await _enter(tester, _odLabel, '21.3');
      await _enter(tester, _angleLabel, '90');
      await _enter(tester, _offsetLabel, '300');
      expect(find.textContaining('od DN25'), findsWidgets);
      expect(find.textContaining('Wstawka  = travel'), findsNothing);
    });

    testWidgets('tryb ręczny R 90,45 / 300 / 45° → 349,3 mm', (tester) async {
      await tester.pumpWidget(_app(const FitterToolsScreen(initialTab: 3)));
      await tester.pumpAndSettle();
      await _pickMode(tester, 'Ręcznie — wpisz R');
      await _enter(tester, 'Promień kolanka R — oś gięcia (mm)', '90.45');
      await _enter(tester, _angleLabel, '45');
      await _enter(tester, _offsetLabel, '300');
      expect(find.text('349.3 mm'), findsOneWidget);
    });
  });
}

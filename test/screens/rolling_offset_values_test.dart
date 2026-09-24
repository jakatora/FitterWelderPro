// Rolling offset (lib/screens/rolling_offset_screen.dart) — liczby.
//
// Rise = odsadzka pionowa, Spread = odsadzka pozioma (boczna), θ = kąt kolan.
//   True offset = √(Rise² + Spread²);  Travel = True offset / sin θ
//   Obrót płaszczyzny odsadzki (obrót kolana):
//     od pionu   = atan(Spread / Rise)
//     od poziomu = atan(Rise / Spread) = 90° − od pionu
//   Długość cięcia = Travel − 2·T − 2·szczelina,
//     T = take-out kolana LR ASME B16.9-2018: 45° → B (tab. 6.1-1),
//         inny kąt → A·tan(θ/2) (segment kolana 90°, §6.2.4)
//
// a) 300 / 400 / 45°: √(90 000 + 160 000) = 500; 500/sin45° = 707,11
//    obrót od pionu atan(400/300) = 53,13°, od poziomu 36,87°
// b) 250 / 600 / 30°: √(62 500 + 360 000) = 650; 650/sin30° = 1300,0
//    obrót od pionu atan(600/250) = 67,38°, od poziomu atan(250/600) = 22,62°
// c) (a) + DN100, szczelina 3: T = B = 2,5" → 64 mm
//    cięcie = 707,11 − 128 − 6 = 573,11 → 573,1
// d) (b) + DN100, szczelina 0: T = 152·tan15° = 40,73
//    cięcie = 1300 − 81,46 = 1218,54 → 1218,5

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

Finder _field(String label, {required bool readOnly}) =>
    find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.labelText == label &&
          w.readOnly == readOnly,
      description: 'TextField "$label" readOnly=$readOnly',
    );

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final f = _field(label, readOnly: false);
  expect(f, findsOneWidget, reason: label);
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

String _result(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label, readOnly: true)).controller!.text;

const _rise = 'Rise (odchylenie pionowe)';
const _spread = 'Spread (odchylenie boczne)';
const _travel = 'Travel = True Offset × Multiplier';
const _rollV = 'Obrót kolana od pionu = atan(Spread / Rise)';
const _rollH = 'Obrót od poziomu = atan(Rise / Spread)';
const _takeout = 'Take-out kolana T';
const _cut = 'Długość cięcia = Travel − 2×T − 2×szczelina';

Future<void> _pickDn(WidgetTester tester, String item) async {
  await _tap(tester, find.byType(DropdownButtonFormField<int>));
  // The open menu is a scrollable list of all 20 DNs — bring the item in.
  await tester.ensureVisible(find.text(item).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  group('czyste funkcje', () {
    test('obrót od pionu atan(Spread/Rise): 250/600 → 67,38°', () {
      expect(rollFromVerticalDeg(250, 600),
          closeTo(math.atan(600 / 250) * 180 / math.pi, 1e-9));
      expect(rollFromVerticalDeg(250, 600), closeTo(67.38, 0.01));
      expect(90 - rollFromVerticalDeg(250, 600), closeTo(22.62, 0.01));
    });

    test('długość cięcia = travel − 2T − 2·szczelina', () {
      expect(
          rollingCutLengthMm(travelMm: 707.107, takeoutMm: 64, gapMm: 3),
          closeTo(573.107, 1e-9));
    });
  });

  testWidgets('300/400/45° → Travel 707.1, obrót 53.1° od pionu',
      (tester) async {
    await tester.pumpWidget(_app(const RollingOffsetScreen()));
    await _enter(tester, _rise, '300');
    await _enter(tester, _spread, '400');
    await _tap(tester, find.text('OBLICZ'));
    expect(_result(tester, _travel), '707.1');
    expect(_result(tester, _rollV), '53.1');
    expect(_result(tester, _rollH), '36.9');
    expect(_field(_cut, readOnly: true), findsNothing,
        reason: 'bez DN nie ma długości cięcia');
  });

  testWidgets('250/600/30° → Travel 1300.0, obrót 22.6° od poziomu',
      (tester) async {
    await tester.pumpWidget(_app(const RollingOffsetScreen()));
    await _tap(tester, find.ancestor(
        of: find.text('30°'), matching: find.byType(InkWell)));
    await _enter(tester, _rise, '250');
    await _enter(tester, _spread, '600');
    await _tap(tester, find.text('OBLICZ'));
    expect(_result(tester, _travel), '1300.0');
    expect(_result(tester, _rollV), '67.4');
    expect(_result(tester, _rollH), '22.6');
  });

  testWidgets('DN100, 45°, szczelina 3 → cięcie 573.1 (T = B = 64)',
      (tester) async {
    await tester.pumpWidget(_app(const RollingOffsetScreen()));
    await _enter(tester, _rise, '300');
    await _enter(tester, _spread, '400');
    await _pickDn(tester, 'DN100 (4")');
    await _enter(tester, 'Szczelina spoiny (mm)', '3');
    await _tap(tester, find.text('OBLICZ'));
    expect(_result(tester, _takeout), '64.0');
    expect(_result(tester, _cut), '573.1');
    expect(find.textContaining('tab. 6.1-1'), findsOneWidget);
  });

  testWidgets('DN100, 30° → T = 152·tan15° = 40.7, cięcie 1218.5',
      (tester) async {
    await tester.pumpWidget(_app(const RollingOffsetScreen()));
    await _tap(tester, find.ancestor(
        of: find.text('30°'), matching: find.byType(InkWell)));
    await _enter(tester, _rise, '250');
    await _enter(tester, _spread, '600');
    await _pickDn(tester, 'DN100 (4")');
    await _tap(tester, find.text('OBLICZ'));
    expect(_result(tester, _takeout), '40.7');
    expect(_result(tester, _cut), '1218.5');
    expect(find.textContaining('§6.2.4'), findsOneWidget);
  });
}

// P0r-11 — regression net for P0-05 + P0r-05 + P0r-06 in
// `lib/screens/rolling_offset_screen.dart`. Without these tests a
// refactor to _calculate() / _angleBtn() could silently re-introduce
// stale-result copy-paste bugs that have the welder cutting pipe to the
// wrong length.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';

Widget _wrap(Widget child) {
  // RollingOffsetScreen calls context.tr/context.language — both depend on
  // AppLanguageScope being in the tree. Mirror the app's main() setup.
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(
      home: child,
    ),
  );
}

Finder _calculateButton() {
  // FilledButton.icon may render off-screen on the default test viewport;
  // text-finder is robust to that since we ensureVisible before tapping.
  return find.text('CALCULATE');
}

Future<void> _tapCalculate(WidgetTester tester) async {
  await tester.ensureVisible(_calculateButton());
  await tester.pumpAndSettle();
  await tester.tap(_calculateButton());
}

Future<void> _typeRiseSpread(
  WidgetTester tester, {
  required String rise,
  required String spread,
}) async {
  // Two leading TextFormFields wrap text input — finder them by TextField
  // (the underlying widget). Targeting by index is brittle across locale
  // label changes but safe inside this self-contained test.
  final fields = find.byType(TextField);
  expect(fields, findsWidgets);
  await tester.enterText(fields.at(0), rise);
  await tester.enterText(fields.at(1), spread);
  await tester.pump();
}

void main() {
  testWidgets(
    'P0r-06: tapping a different angle preset wipes stale results',
    (tester) async {
      await tester.pumpWidget(_wrap(const RollingOffsetScreen()));
      await tester.pumpAndSettle();

      // Successful calc at 45° default — travel ≈ 707.1.
      await _typeRiseSpread(tester, rise: '500', spread: '500');
      await _tapCalculate(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('707'), findsWidgets);

      // Tap 60° angle preset. Without the P0r-06 wipe-on-change, the
      // stale 707.1 (which is the 45° travel) would remain visible.
      // Target the InkWell ancestor of the 60° label so the tap routes
      // through the gesture handler (not into the inert Text widget).
      final sixtyChip = find.ancestor(
        of: find.text('60°'),
        matching: find.byType(InkWell),
      );
      await tester.ensureVisible(sixtyChip);
      await tester.pumpAndSettle();
      await tester.tap(sixtyChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('707'),
        findsNothing,
        reason:
            'P0r-06 regression: tapping a different angle preset must '
            'clear stale Travel — otherwise the 45° result still '
            'displays under the 60° chip selection.',
      );
    },
  );

  testWidgets(
    'P0-05 / P0r-05: stale Travel value wiped on validation early-return',
    (tester) async {
      await tester.pumpWidget(_wrap(const RollingOffsetScreen()));
      await tester.pumpAndSettle();

      // Successful calc at 45°, rise=500, spread=500 → travel=707.1.
      await _typeRiseSpread(tester, rise: '500', spread: '500');
      await _tapCalculate(tester);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('707'),
        findsWidgets,
        reason: 'expected initial Travel result around 707.1 mm',
      );

      // Mistype rise=0 — validation early-returns. Without the P0-05
      // setState-around-clear fix, the stale 707.1 would remain visible.
      await _typeRiseSpread(tester, rise: '0', spread: '500');
      await tester.tap(_calculateButton());
      await tester.pump(); // process the early-return setState
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('707'),
        findsNothing,
        reason:
            'P0-05 regression: stale 707.1 must NOT remain after '
            'validation early-return. Welder would copy stale value '
            'to the saw and wrong-cut.',
      );
    },
  );
}

// Regression net for three defects on the screen where the cut length is born
// (`lib/screens/segment_builder_screen.dart`). All three end the same way:
// pipe cut to the wrong length.
//
//   1. `_askValue` (the "axis dimension / total length" prompt) asked for
//      TextInputType.number. The iOS numeric pad has no decimal key, so a
//      76.2 mm takeout could only be typed as 762 — a 686 mm error baked into
//      the component library.
//   2. `_addFromType` cleared the typed ISO dimension BEFORE checking whether
//      the sequence was already complete, so a gloved mistap on the palette
//      erased a good dimension instead of doing nothing.
//   3. The one message meant to STOP a bad cut ("CUT ≤ 0") was stored as
//      double-encoded UTF-8 and rendered as mojibake.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

/// SegmentBuilderScreen calls `context.tr`, which needs AppLanguageScope in
/// the tree — mirror the app's main() setup. English so labels are stable.
Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: child),
  );
}

Widget _screen({double gapMm = 0}) => SegmentBuilderScreen(
      materialGroup: 'SS',
      currentDiameter: 60.3,
      wallThickness: 2.77,
      gapMm: gapMm,
    );

/// Taps a palette button by its label.
///
/// `.first` on the ancestor result because once an element is in the sequence
/// its chip carries the same label as the palette button — but only the
/// palette button sits under an InkWell, so the ancestor finder already
/// narrows it to one.
Future<void> _tapPalette(WidgetTester tester, String label) async {
  final button =
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

/// OPEN_END → PIPE → OPEN_END is the only complete sequence that needs no
/// component library — and therefore no database. sqflite futures never
/// resolve inside the widget-test fake-async zone, so this is the only
/// sequence that can be built through the real UI here.
Future<void> _buildCompleteSequence(WidgetTester tester) async {
  await _tapPalette(tester, 'Open end');
  await _tapPalette(tester, 'Pipe');
  await _tapPalette(tester, 'Open end');
}

void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

String _screenSource() =>
    File('lib/screens/segment_builder_screen.dart').readAsStringSync();

void main() {
  testWidgets(
    'a rejected palette tap does not wipe an already typed ISO dimension',
    (tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();

      await _buildCompleteSequence(tester);
      await tester.pumpAndSettle();

      // The ISO card only renders once the sequence is complete, so this is
      // the single TextField on screen.
      final isoField = find.byType(TextField);
      expect(isoField, findsOneWidget);
      await tester.enterText(isoField, '1000');
      await tester.pump();
      expect(tester.widget<TextField>(isoField).controller?.text, '1000');

      // The gloved mistap: the sequence is already complete, so this tap is a
      // no-op by design — it must not take the dimension with it.
      await _tapPalette(tester, 'Elbow 90');
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '1000',
        reason: 'a rejected palette tap must leave the typed ISO alone — '
            'otherwise the fitter has to re-read the drawing and may mistype',
      );

      // Let the "segment is complete" SnackBar and its 4 s timer expire, so
      // the binding does not report a pending timer at teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the CUT <= 0 stop message renders readable text, not mojibake',
    (tester) async {
      _useTallPhone(tester);
      // 100 mm gap on a single weld against a 50 mm ISO forces CUT = -50.
      await tester.pumpWidget(_wrap(_screen(gapMm: 100)));
      await tester.pumpAndSettle();

      await _buildCompleteSequence(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '50');
      await tester.pump();

      expect(
        find.textContaining('CUT ≤ 0'),
        findsOneWidget,
        reason: 'the warning that stops an impossible cut must be legible',
      );
      expect(
        find.textContaining('â'),
        findsNothing,
        reason: 'double-encoded UTF-8 turned the only stop-the-cut message '
            'into garbage on the shop floor',
      );
    },
  );

  // The remaining defect — the dot-less keypad in `_askValue` — only opens
  // after a component-library lookup, and sqflite futures never resolve
  // inside the widget-test fake-async zone, so it cannot be driven through
  // the UI. Guard it (and the encoding of the whole file) at source level.
  group('segment_builder_screen.dart source guards', () {
    test('no double-encoded UTF-8 survives in user-visible strings', () {
      final source = _screenSource();
      // Each of these is what a UTF-8 byte pair looks like once it has been
      // read as Latin-1 and re-encoded: 'â‰¤' was '≤', 'Ã³' was 'ó',
      // 'Å‚' was 'ł', 'Ä…' was 'ą'. None of them is a legal character in
      // Polish or English UI copy.
      for (final mojibake in ['â', 'Ã', 'Å', 'Ä', 'Â']) {
        expect(
          source.contains(mojibake),
          isFalse,
          reason: 'found "$mojibake" — a re-encoding accident: the fitter '
              'sees garbage where a warning should be',
        );
      }
    });

    test('numeric prompts do not use the dot-less iOS keypad', () {
      expect(
        _screenSource().contains('TextInputType.number,'),
        isFalse,
        reason: 'every numeric prompt on this screen takes a millimetre value '
            'with a decimal part (its own hints say "np. 76.2"); the plain '
            'number keypad has no decimal key on iOS, so 76.2 can only be '
            'typed as 762. Use TextInputType.numberWithOptions(decimal: true).',
      );
    });
  });
}

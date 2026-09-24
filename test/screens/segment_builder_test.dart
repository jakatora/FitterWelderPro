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

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

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
  useTestDatabase();

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
      // Elbow (152 mm to the axis) → pipe → open end: ONE weld. A 100 mm gap
      // on that weld against a 50 mm ISO: 50 − 152 − 100 × 1 = −202 → stop.
      //
      // This used to be OPEN_END → pipe → OPEN_END, which only went negative
      // because the builder charged a gap to a run with no weld in it at all
      // (the start-only weld count). An open → open run has nothing to take
      // off, so it can never produce CUT ≤ 0 from the gap any more.
      await tester.runAsync(() => ComponentLibraryDao().insert(LibraryComponent(
            id: 'elb-cut-stop',
            materialGroup: 'SS',
            type: 'ELB90',
            diameterMm: 114.39,
            wallThicknessMm: 3.05,
            axisMm: 152,
            lengthMm: null,
            measurementMode: null,
            diameterOutMm: null,
            createdAt: 1,
            updatedAt: 1,
          )));
      await tester.pumpWidget(_wrap(SegmentBuilderScreen(
        materialGroup: 'SS',
        currentDiameter: 114.39,
        wallThickness: 3.05,
        gapMm: 100,
        existing: Segment(
          id: 'seg-cut-stop',
          projectId: 'proj-cut-stop',
          seqNo: 1,
          diameterMm: 114.39,
          wallThicknessMm: 3.05,
          startKind: 'axial',
          startLibraryId: 'elb-cut-stop',
          startValueMm: 152,
          endKind: 'logical',
          endLibraryId: null,
          endValueMm: 0,
          isoRef: 'AXIS|OPEN',
          isoExpr: '1000',
          isoMm: 1000,
          cutMm: 848,
          createdAt: 1,
          updatedAt: 1,
        ),
      )));
      for (var i = 0;
          i < 60 && find.byType(TextField).evaluate().isEmpty;
          i++) {
        await flushTestDatabase(tester);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }

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

  group('ISO field: decimal pad + operator key bar', () {
    Finder isoField() => find.byType(TextField);

    String isoText(WidgetTester tester) =>
        tester.widget<TextField>(isoField()).controller!.text;

    /// What the decimal pad does: the IME sends the whole new value — the
    /// current text with the digits appended at the cursor (the end).
    Future<void> typeDigits(WidgetTester tester, String digits) async {
      await tester.enterText(isoField(), isoText(tester) + digits);
      await tester.pump();
    }

    Future<void> tapKey(WidgetTester tester, String label) async {
      final key = find.byKey(ValueKey('iso-key-$label'));
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }

    Future<void> openIsoCard(WidgetTester tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(_wrap(_screen()));
      await tester.pumpAndSettle();
      await _buildCompleteSequence(tester);
      await tester.pumpAndSettle();
      expect(isoField(), findsOneWidget);
    }

    testWidgets('opens the numeric pad with a decimal key, not QWERTY',
        (tester) async {
      await openIsoCard(tester);
      final field = tester.widget<TextField>(isoField());
      expect(field.keyboardType.decimal, isTrue,
          reason: 'the numbers need the decimal pad (with the comma)');
      expect(field.keyboardType, isNot(TextInputType.text),
          reason: 'full QWERTY made a gloved fitter hunt for digits');
    });

    testWidgets('taps on the bar build 3000+525-80 and CUT follows',
        (tester) async {
      await openIsoCard(tester);

      await typeDigits(tester, '3000');
      await tapKey(tester, '+');
      expect(isoText(tester), '3000+');
      await typeDigits(tester, '525');
      await tapKey(tester, '−');
      await typeDigits(tester, '80');

      expect(isoText(tester), '3000+525-80',
          reason: 'the minus key must insert the ASCII "-" the parser reads');
      // Open end → pipe → open end, no gap: CUT is the ISO dimension.
      expect(find.text('CUT = 3445.0 mm'), findsOneWidget);

      // Backspace takes the last character off — and CUT follows again.
      await tapKey(tester, '⌫');
      expect(isoText(tester), '3000+525-8');
      expect(find.text('CUT = 3517.0 mm'), findsOneWidget);
    });

    testWidgets('brackets, × and the inch key reach the parser',
        (tester) async {
      await openIsoCard(tester);

      await tapKey(tester, '(');
      await typeDigits(tester, '1500');
      await tapKey(tester, '+');
      await typeDigits(tester, '200');
      await tapKey(tester, ')');
      await tapKey(tester, '×');
      await typeDigits(tester, '2');
      expect(isoText(tester), '(1500+200)×2');
      expect(find.text('CUT = 3400.0 mm'), findsOneWidget);

      await tester.enterText(isoField(), '76');
      await tester.pump();
      await tapKey(tester, '"');
      expect(isoText(tester), '76"');
      expect(find.text('CUT = 1930.4 mm'), findsOneWidget,
          reason: '76" is 1930.4 mm, not 76 mm');
    });

    testWidgets('a key inserts at the cursor, not only at the end',
        (tester) async {
      await openIsoCard(tester);
      await tester.enterText(isoField(), '3000525');
      await tester.pump();
      final ctrl = tester.widget<TextField>(isoField()).controller!;
      ctrl.selection = const TextSelection.collapsed(offset: 4);
      await tapKey(tester, '+');
      expect(isoText(tester), '3000+525');
      expect(ctrl.selection.baseOffset, 5);
      expect(find.text('CUT = 3525.0 mm'), findsOneWidget);
    });

    testWidgets('every key is at least 48 dp for gloved fingers',
        (tester) async {
      await openIsoCard(tester);
      for (final label in ['+', '−', '×', '(', ')', '"', '⌫']) {
        final size = tester.getSize(find.byKey(ValueKey('iso-key-$label')));
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('the comma a Polish pad types is read as a decimal point',
        (tester) async {
      await openIsoCard(tester);
      await tester.enterText(isoField(), '1020,5');
      await tester.pump();
      await tapKey(tester, '+');
      await typeDigits(tester, '20');
      expect(isoText(tester), '1020,5+20');
      expect(find.text('CUT = 1040.5 mm'), findsOneWidget);
    });
  });

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

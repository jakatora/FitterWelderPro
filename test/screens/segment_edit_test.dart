// A saved segment used to be read-only: a typo in an ISO dimension could only
// be fixed by swiping the segment away — behind a "cannot be undone" dialog —
// and rebuilding the whole sequence from the palette (START, pipe, END,
// dimension), in gloves, on a scaffold.
//
// `SegmentBuilderScreen` now takes an optional `existing` segment and reopens
// it for correction. Covered here:
//   * the pure rule that decides whether a sequence is a complete segment,
//   * the decoding of the packed `iso_ref` column a restore depends on,
//   * and the restore itself, driven through the real screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

/// SegmentBuilderScreen calls `context.tr`, which needs AppLanguageScope in
/// the tree — mirror the app's main() setup. English so labels are stable.
Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: child),
  );
}

void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A segment saved with OPEN_END → PIPE → OPEN_END.
///
/// Both anchors are logical, so restoring it touches no component library and
/// therefore no database — sqflite futures never resolve inside the
/// widget-test fake-async zone, so this is the only segment shape that can be
/// driven through the real screen here.
Segment _savedSegment({String isoExpr = '3450'}) => Segment(
      id: 'seg-1',
      projectId: 'proj-1',
      seqNo: 7,
      diameterMm: 60.3,
      wallThicknessMm: 2.77,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'OPEN|OPEN',
      isoExpr: isoExpr,
      isoMm: 3450,
      cutMm: 3450,
      createdAt: 1000,
      updatedAt: 1000,
    );

Widget _editScreen(Segment segment) => SegmentBuilderScreen(
      materialGroup: 'SS',
      currentDiameter: segment.diameterMm,
      wallThickness: segment.wallThicknessMm,
      gapMm: 0,
      existing: segment,
    );

/// Reads `canPop` off the screen's own PopScope — the flag that decides
/// whether backing out raises the "discard?" dialog. `byWidgetPredicate`
/// rather than `byType` because PopScope is generic and `find.byType` matches
/// on the exact runtimeType, type argument included.
bool _canPop(WidgetTester tester) {
  final popScope = tester
      .widgetList(find.ancestor(
        of: find.byType(Scaffold),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      ))
      .first;
  return (popScope as dynamic).canPop as bool;
}

void main() {
  group('isSegmentSequenceComplete', () {
    test('START -> PIPE -> END is the complete shape', () {
      expect(isSegmentSequenceComplete(['OPEN_END', 'PIPE', 'ELB90']), isTrue);
      expect(isSegmentSequenceComplete(['ELB90', 'PIPE', 'OPEN_END']), isTrue);
    });

    test('a half-built sequence is not complete', () {
      expect(isSegmentSequenceComplete([]), isFalse);
      expect(isSegmentSequenceComplete(['ELB90']), isFalse);
      expect(isSegmentSequenceComplete(['ELB90', 'PIPE']), isFalse,
          reason: 'there is nothing to measure the pipe up to yet');
    });

    test('the pipe has to be in the middle', () {
      // Two components welded straight together, or a pipe hung off the end,
      // is not one cut length between two anchors.
      expect(isSegmentSequenceComplete(['ELB90', 'ELB45', 'PIPE']), isFalse);
      expect(isSegmentSequenceComplete(['PIPE', 'ELB90', 'ELB45']), isFalse);
    });
  });

  group('iso_ref decoding', () {
    test('splits the packed START|END column', () {
      final refs = splitIsoRef('AXIS|FACE_FAR');
      expect(refs.start, 'AXIS');
      expect(refs.end, 'FACE_FAR');
    });

    test('legacy and malformed values yield empty halves, never a wrong one',
        () {
      // Rows written before both reference points were packed into the column
      // hold the schema default 'FACE', which is not one of the codes.
      expect(splitIsoRef('FACE').start, 'FACE');
      expect(splitIsoRef('FACE').end, '');
      expect(splitIsoRef('').start, '');
      expect(splitIsoRef('').end, '');
    });

    test('an unknown code falls back instead of guessing', () {
      // Guessing here would move the point the dimension is measured from,
      // which changes the cut length by the component takeout.
      expect(isoRefPointFromCode('AXIS', fallback: IsoRefPoint.faceNear),
          IsoRefPoint.axis);
      expect(isoRefPointFromCode('FACE', fallback: IsoRefPoint.center),
          IsoRefPoint.center);
      expect(isoRefPointFromCode('', fallback: IsoRefPoint.axis),
          IsoRefPoint.axis);
    });
  });

  group('editing a saved segment', () {
    testWidgets('opens with the sequence and the ISO dimension restored',
        (tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(_wrap(_editScreen(_savedSegment())));
      await tester.pumpAndSettle();

      // Naming the segment matters: the fitter arrives from a list of numbered
      // segments and must see he opened the right one before changing a digit.
      expect(find.text('Edit segment 7'), findsOneWidget);

      // The ISO card only renders once the sequence is complete, so the single
      // TextField on screen is proof the START/PIPE/END sequence came back —
      // and the uppercase PIPE block belongs to the measurement diagram, which
      // is rendered from the same condition (the palette button reads 'Pipe').
      expect(find.text('PIPE'), findsOneWidget);
      final isoField = find.byType(TextField);
      expect(isoField, findsOneWidget);
      expect(tester.widget<TextField>(isoField).controller?.text, '3450',
          reason: 'the dimension read off the drawing must not have to be '
              'read again just to fix one digit');

      // Restoring must also re-derive the cut, so the fitter sees what the saw
      // is currently set to before touching anything.
      expect(find.text('CUT = 3450.0 mm'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });

    testWidgets('backing straight out of an untouched segment asks nothing',
        (tester) async {
      _useTallPhone(tester);
      await tester.pumpWidget(_wrap(_editScreen(_savedSegment())));
      await tester.pumpAndSettle();

      expect(_canPop(tester), isTrue,
          reason: 'a restored segment is not unsaved work — prompting here '
              'would teach the fitter to dismiss the one dialog that '
              'protects a half-built segment');

      // ...but a real correction must still be protected on the way out.
      await tester.enterText(find.byType(TextField), '3540');
      await tester.pump();
      expect(_canPop(tester), isFalse,
          reason: 'the corrected dimension would be lost on a swipe-back');
    });
  });
}

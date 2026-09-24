// Liczba spoin, od której zależy odjęcie szczeliny (gap) w kreatorze segmentu
// (`lib/screens/segment_builder_screen.dart`).
//
// Błąd: kreator liczył `welds = START == OPEN_END ? 1 : 2` — patrzył tylko na
// początek. Rura z kolana do wolnego końca (OPEN_END) dostawała DWIE szczeliny,
// choć spoina jest jedna, a rura OPEN_END → OPEN_END (bez żadnej spoiny)
// dostawała jedną. Oba przypadki dają rurę krótszą o szczelinę — tego nie da się
// już przyspawać z powrotem.
//
// Reguła: szczelina jest na każdym końcu, który jest do czegoś przyspawany,
// czyli na każdym końcu, który NIE jest OPEN_END — 0, 1 albo 2 spoiny.
//
// Wszystkie liczby niżej liczone ręcznie z wzoru
//   CUT = ISO − offset_start − offset_end − gap × liczba_spoin
// a nie z kodu, który sprawdzamy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

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

Future<void> _tapPalette(WidgetTester tester, String label) async {
  final button =
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

/// Lets the real SQLite event loop answer the builder's library lookup, frame
/// by frame, until [done] holds. A widget test's fake-async zone never
/// completes a sqflite future on its own.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// DN100 LR 90° elbow, ASME B16.9 centre-to-end 152 mm. A distinct diameter
/// per test keeps the component library's UNIQUE key apart.
LibraryComponent _elbow(String id, double diameterMm) => LibraryComponent(
      id: id,
      materialGroup: 'SS',
      type: 'ELB90',
      diameterMm: diameterMm,
      wallThicknessMm: 3.05,
      axisMm: 152,
      lengthMm: null,
      measurementMode: null,
      diameterOutMm: null,
      createdAt: 1,
      updatedAt: 1,
    );

Segment _segment({
  required String startKind,
  required String? startLibraryId,
  required double startValueMm,
  required String endKind,
  required String? endLibraryId,
  required double endValueMm,
  required String isoRef,
  required double diameterMm,
}) =>
    Segment(
      id: 'seg-$isoRef-$diameterMm',
      projectId: 'proj-welds',
      seqNo: 3,
      diameterMm: diameterMm,
      wallThicknessMm: 3.05,
      startKind: startKind,
      startLibraryId: startLibraryId,
      startValueMm: startValueMm,
      endKind: endKind,
      endLibraryId: endLibraryId,
      endValueMm: endValueMm,
      isoRef: isoRef,
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 0,
      createdAt: 1,
      updatedAt: 1,
    );

Widget _builder(Segment? existing, {required double gapMm, double dia = 114.3}) =>
    SegmentBuilderScreen(
      materialGroup: 'SS',
      currentDiameter: existing?.diameterMm ?? dia,
      wallThickness: 3.05,
      gapMm: gapMm,
      existing: existing,
    );

void main() {
  useTestDatabase();

  group('builderWeldCount — one rule for the calc, the breakdown and the label',
      () {
    test('a weld on every end that is not OPEN_END', () {
      expect(builderWeldCount(kOpenEndTag, kOpenEndTag), 0);
      expect(builderWeldCount('ELB90', kOpenEndTag), 1);
      expect(builderWeldCount(kOpenEndTag, 'ELB90'), 1);
      expect(builderWeldCount('ELB90', 'FLANGE'), 2);
    });
  });

  testWidgets(
      'OPEN_END → pipe → OPEN_END, gap 3, ISO 1000: no weld, CUT = 1000',
      (tester) async {
    // 1000 − 0 − 0 − 3 × 0 = 1000. The old start-only rule counted one weld
    // and showed 997.
    _useTallPhone(tester);
    await tester.pumpWidget(_wrap(_builder(null, gapMm: 3)));
    await tester.pumpAndSettle();

    await _tapPalette(tester, 'Open end');
    await _tapPalette(tester, 'Pipe');
    await _tapPalette(tester, 'Open end');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();

    expect(find.text('CUT = 1000.0 mm'), findsOneWidget);
    expect(find.textContaining('− gap'), findsNothing,
        reason: 'there is no joint, so no gap row in the breakdown');
    expect(find.textContaining('+ gap'), findsNothing,
        reason: 'the diagram must not announce a gap no joint takes');
  });

  testWidgets(
      'elbow (152) → pipe → OPEN_END, gap 3, ISO 1000: one weld, CUT = 845',
      (tester) async {
    // 1000 − 152 − 0 − 3 × 1 = 845. The old rule looked only at the START
    // (an elbow, "not OPEN_END") and took two gaps: 842 — 3 mm short.
    _useTallPhone(tester);
    final dao = ComponentLibraryDao();
    await tester.runAsync(() => dao.insert(_elbow('elb-weld-a', 114.31)));

    final seg = _segment(
      startKind: 'axial',
      startLibraryId: 'elb-weld-a',
      startValueMm: 152,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'AXIS|OPEN',
      diameterMm: 114.31,
    );
    await tester.pumpWidget(_wrap(_builder(seg, gapMm: 3)));
    await _pumpUntil(
        tester, () => find.text('CUT = 845.0 mm').evaluate().isNotEmpty);

    expect(find.text('CUT = 845.0 mm'), findsOneWidget);
    expect(find.text('− gap (1 × 3.0 mm)'), findsOneWidget,
        reason: 'the breakdown must show the same single weld');
    expect(find.text('− 3.0 mm'), findsOneWidget);
    expect(find.text('+ gap: 3.0 mm × 1 welds'), findsOneWidget,
        reason: 'the diagram label must show the same single weld');
  });

  testWidgets(
      'OPEN_END → pipe → elbow (152), gap 3, ISO 1000: one weld, CUT = 845',
      (tester) async {
    // Mirror image of the case above: 1000 − 0 − 152 − 3 × 1 = 845.
    _useTallPhone(tester);
    final dao = ComponentLibraryDao();
    await tester.runAsync(() => dao.insert(_elbow('elb-weld-b', 114.32)));

    final seg = _segment(
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'axial',
      endLibraryId: 'elb-weld-b',
      endValueMm: 152,
      isoRef: 'OPEN|AXIS',
      diameterMm: 114.32,
    );
    await tester.pumpWidget(_wrap(_builder(seg, gapMm: 3)));
    await _pumpUntil(
        tester, () => find.text('CUT = 845.0 mm').evaluate().isNotEmpty);

    expect(find.text('CUT = 845.0 mm'), findsOneWidget);
    expect(find.text('− gap (1 × 3.0 mm)'), findsOneWidget);
    expect(find.text('+ gap: 3.0 mm × 1 welds'), findsOneWidget);
  });

  testWidgets('elbow → pipe → elbow, gap 3, ISO 1000: two welds, CUT = 690',
      (tester) async {
    // 1000 − 152 − 152 − 3 × 2 = 690.
    _useTallPhone(tester);
    final dao = ComponentLibraryDao();
    await tester.runAsync(() => dao.insert(_elbow('elb-weld-c', 114.33)));

    final seg = _segment(
      startKind: 'axial',
      startLibraryId: 'elb-weld-c',
      startValueMm: 152,
      endKind: 'axial',
      endLibraryId: 'elb-weld-c',
      endValueMm: 152,
      isoRef: 'AXIS|AXIS',
      diameterMm: 114.33,
    );
    await tester.pumpWidget(_wrap(_builder(seg, gapMm: 3)));
    await _pumpUntil(
        tester, () => find.text('CUT = 690.0 mm').evaluate().isNotEmpty);

    expect(find.text('CUT = 690.0 mm'), findsOneWidget);
    expect(find.text('− gap (2 × 3.0 mm)'), findsOneWidget);
    expect(find.text('+ gap: 3.0 mm × 2 welds'), findsOneWidget);
  });
}

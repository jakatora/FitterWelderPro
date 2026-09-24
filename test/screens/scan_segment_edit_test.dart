// Edycja segmentu zapisanego ze skanu izometrii.
//
// Skaner zapisuje każdą kształtkę BEZ rekordu w bibliotece komponentów
// (`start_library_id` / `end_library_id` = null): take-out z tabel ASME siedzi
// w `*_value_mm`, a rodzaj w `*_kind`. Kreator segmentu przy edycji traktował
// każdy brak id biblioteki jak OPEN_END z offsetem 0 — więc samo otwarcie
// segmentu ze skanu i „Zapisz zmiany” bez żadnej zmiany ustawiało CUT = ISO.
// Kolano DN100 (take-out 152) → rura: 152 mm rury za dużo.
//
// Regresja: segment jak ze skanu → otwarcie w kreatorze → zapis bez zmian →
// CUT i kolumny bez zmian. Liczby ręcznie:
//   CUT = ISO − zdjęte_start − zdjęte_koniec − gap × liczba_spoin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/iso_scanner_ai.dart';
import 'package:cut_list_app/services/scan_to_project.dart';

Map<String, dynamic>? _popped;

/// A host that opens the builder the way FitterScreen does and keeps what
/// "Save changes" hands back.
Widget _host(Segment seg, {required double gapMm}) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                _popped = await Navigator.push<Map<String, dynamic>>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => SegmentBuilderScreen(
                      materialGroup: 'SS',
                      currentDiameter: seg.diameterMm,
                      wallThickness: seg.wallThicknessMm,
                      gapMm: gapMm,
                      existing: seg,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void _useTallPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Opens [seg] in the builder, checks the CUT it shows, saves untouched and
/// returns what the builder handed back.
Future<Map<String, dynamic>> _openAndSaveUntouched(
  WidgetTester tester,
  Segment seg, {
  required double gapMm,
  required String expectCutText,
}) async {
  _popped = null;
  _useTallPhone(tester);
  await tester.pumpWidget(_host(seg, gapMm: gapMm));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  expect(find.text(expectCutText), findsOneWidget,
      reason: 'reopening a scanned segment must show the cut it was saved '
          'with, before anything is touched');

  final save = find.text('Save changes');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();

  expect(_popped, isNotNull, reason: '"Save changes" did not save');
  return _popped!;
}

Segment _segmentFromRow(Map<String, Object?> row) => Segment.fromRow(row);

AiScanResult _scan({
  required List<AiComponent> components,
  required List<AiSegment> segments,
}) =>
    AiScanResult(
      sizeNotation: 'DN',
      titleBlock: AiTitleBlock(
        lineNumber: 'DN100-P-2002',
        material: 'A312 TP316L',
        schedule: '10S',
        pipeClass: 'CL150',
      ),
      components: components,
      segments: segments,
    );

AiComponent _comp(String id, String type, {String? valveType}) => AiComponent(
      id: id,
      type: type,
      valveType: valveType,
      confidence: AiConfidence.high,
    );

AiSegment _seg(String id, {String? from, String? to, required double mm}) =>
    AiSegment(
      id: id,
      fromId: from,
      toId: to,
      dimensionMm: mm,
      rawDimension: mm.toStringAsFixed(0),
      confidence: AiConfidence.high,
    );

void main() {
  testWidgets(
      'row in the old scanner format: elbow 152 → open end keeps CUT 848',
      (tester) async {
    // Exactly what the scan review used to write for DN100 LR elbow → open
    // end, ISO 1000, gap 0: 1000 − 152 = 848. The builder restored the
    // library-less elbow as OPEN_END (offset 0) and re-saved CUT = 1000.
    final seg = Segment(
      id: 'scan-old',
      projectId: 'scan-proj',
      seqNo: 1,
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      startKind: 'axial',
      startLibraryId: null,
      startValueMm: 152,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'AXIS|FACE_NEAR',
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 848,
      createdAt: 1,
      updatedAt: 1,
    );

    final saved = await _openAndSaveUntouched(tester, seg,
        gapMm: 0, expectCutText: 'CUT = 848.0 mm');

    expect(saved['cutMm'], 848);
    expect(saved['startKind'], 'axial',
        reason: 'the elbow must stay an elbow, not become an open end');
    expect(saved['startValue'], 152);
    expect(saved['startLibraryId'], isNull);
    expect(saved['endKind'], 'logical');
    expect(saved['endValue'], 0);
  });

  testWidgets(
      'scan → saved row → builder → untouched save: elbow → gate valve '
      'through the body, gap 3', (tester) async {
    // DN100, Class 150: LR elbow centre-to-end 152 (ASME B16.9), gate valve
    // face-to-face 229 (B16.10). The fitter confirms centre-to-END: the
    // dimension runs through the valve body. Two welds, gap 3:
    //   2000 − 152 − 229 − 3 × 2 = 1613.
    final plan = planFromScan(
      _scan(
        components: [
          _comp('e1', 'elbow90'),
          _comp('v1', 'valve', valveType: 'gate'),
        ],
        segments: [_seg('s1', from: 'e1', to: 'v1', mm: 2000)],
      ),
      gapMm: 3,
    );
    final planned = plan.segments.single.withDimRef(DimRef.centreToEnd);
    expect(planned.cutMm, 1613);

    final row = segmentRowFor(
      planned,
      id: 'scan-new-1',
      projectId: 'scan-proj',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      nowMs: 1,
    )!;
    // The row states what was taken off on each side and where from.
    expect(row['iso_ref'], 'AXIS|FACE_FAR');
    expect(row['start_value_mm'], 152);
    expect(row['end_value_mm'], 229);
    expect(row['cut_mm'], 1613);

    final saved = await _openAndSaveUntouched(tester, _segmentFromRow(row),
        gapMm: 3, expectCutText: 'CUT = 1613.0 mm');

    expect(saved['cutMm'], 1613);
    expect(saved['isoRef'], row['iso_ref']);
    expect(saved['startKind'], row['start_kind']);
    expect(saved['startValue'], row['start_value_mm']);
    expect(saved['endKind'], row['end_kind']);
    expect(saved['endValue'], row['end_value_mm']);
    expect(saved['startLibraryId'], isNull);
    expect(saved['endLibraryId'], isNull);
  });

  testWidgets(
      'scan → saved row → builder → untouched save: open end → elbow, gap 3',
      (tester) async {
    // One weld (the open end has none): 1000 − 0 − 152 − 3 × 1 = 845.
    final plan = planFromScan(
      _scan(
        components: [_comp('e1', 'elbow90')],
        segments: [_seg('s1', to: 'e1', mm: 1000)],
      ),
      gapMm: 3,
    );
    final planned = plan.segments.single;
    expect(planned.dimRef, DimRef.centreToCentre,
        reason: 'no bodied end, no question to ask');
    expect(planned.cutMm, 845);

    final row = segmentRowFor(
      planned,
      id: 'scan-new-2',
      projectId: 'scan-proj',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      nowMs: 1,
    )!;
    expect(row['iso_ref'], 'OPEN|AXIS');
    expect(row['start_kind'], 'logical');

    final saved = await _openAndSaveUntouched(tester, _segmentFromRow(row),
        gapMm: 3, expectCutText: 'CUT = 845.0 mm');

    expect(saved['cutMm'], 845);
    expect(saved['isoRef'], 'OPEN|AXIS');
    expect(saved['startKind'], 'logical');
    expect(saved['endKind'], 'axial');
    expect(saved['endValue'], 152);
  });

  group('restoredStoredAnchor — only a logical anchor is an open end', () {
    test('logical → open end, whatever the code', () {
      expect(
          restoredStoredAnchor(kind: 'logical', valueMm: 0, refCode: 'OPEN'),
          isNull);
      expect(
          restoredStoredAnchor(
              kind: 'logical', valueMm: 0, refCode: 'FACE_NEAR'),
          isNull);
    });

    test('a fitting keeps its stored point', () {
      expect(
          restoredStoredAnchor(kind: 'axial', valueMm: 152, refCode: 'AXIS'),
          IsoRefPoint.axis);
      expect(
          restoredStoredAnchor(
              kind: 'nonAxial', valueMm: 229, refCode: 'FACE_FAR'),
          IsoRefPoint.faceFar);
      expect(
          restoredStoredAnchor(
              kind: 'nonAxial', valueMm: 0, refCode: 'FACE_NEAR'),
          IsoRefPoint.faceNear);
    });

    test('an unreadable code falls back to what subtracts the stored value',
        () {
      // Arithmetic, not a guess: the fallback's stop takes off exactly the
      // stored number, so the cut is the one the row was saved with.
      expect(restoredStoredAnchor(kind: 'axial', valueMm: 152, refCode: ''),
          IsoRefPoint.axis);
      expect(
          restoredStoredAnchor(kind: 'nonAxial', valueMm: 229, refCode: 'FACE'),
          IsoRefPoint.faceFar);
      expect(restoredStoredAnchor(kind: 'nonAxial', valueMm: 0, refCode: ''),
          IsoRefPoint.faceNear);
    });
  });
}

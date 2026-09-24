// Domyślny punkt odniesienia wymiaru ISO dla KOŁNIERZA w kreatorze segmentu.
//
// Na izometrii wymiar do kołnierza idzie do czoła uszczelnienia (przylgi, RF)
// — tak liczy też zeszyt ISO: długość kołnierza WN to ASME B16.5 kolumna Y
// („length through hub”, od przylgi do końca szyjki), bo rura jest spawana do
// końca szyjki, a wymiar kończy się na przylgi. W kreatorze przylga to
// „czoło dalekie” (odejmuje całą długość L), a „czoło bliskie” to koniec
// szyjki przy spoinie (odejmuje 0). Kreator podświetlał jako domyślne czoło
// bliskie, więc rura z kołnierzem WN DN100 (L = 76) wychodziła o 76 mm za
// długa.
//
// Zawór zostaje przy czole bliskim: wymiar do zaworu idzie do jego czoła po
// stronie rury — odjęcie całego korpusu (np. 229 mm) dałoby rurę za krótką.
//
// Liczby ręcznie: CUT = ISO − offset_start − offset_end − gap × spoiny.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

LibraryComponent _comp(String type,
        {double? axis, double? length, double dia = 114.3}) =>
    LibraryComponent(
      id: 'ref-$type-$dia',
      materialGroup: 'SS',
      type: type,
      diameterMm: dia,
      wallThicknessMm: 3.05,
      axisMm: axis,
      lengthMm: length,
      measurementMode: axis == null ? 'FACE' : null,
      diameterOutMm: type == 'REDUCER' ? 60.3 : null,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  useTestDatabase();

  group('defaultRefPointFor', () {
    test('flange: the sealing face (far face), valve: the near face', () {
      expect(defaultRefPointFor(_comp('FLANGE', length: 76)),
          IsoRefPoint.faceFar);
      expect(defaultRefPointFor(_comp('VALVE', length: 229)),
          IsoRefPoint.faceNear);
      expect(defaultRefPointFor(_comp('ELB90', axis: 152)), IsoRefPoint.axis);
      expect(defaultRefPointFor(_comp('REDUCER', length: 0)),
          IsoRefPoint.faceNear);
    });

    test('elbow 152 → pipe → WN flange DN100 (76) by default: CUT = 772', () {
      // 1000 − 152 − 76 − 0 × 2 = 772. With the old default (near face,
      // offset 0) the builder gave 848 — the pipe 76 mm long.
      final flange = _comp('FLANGE', length: 76);
      final ref = defaultRefPointFor(flange);
      final cut = builderCutMm(
        isoMm: 1000,
        startRef: IsoRefPoint.axis,
        startOffsetMm: 152,
        endRef: ref,
        endOffsetMm: refPointOffsetMm(flange, ref),
        gapMm: 0,
        welds: builderWeldCount('ELB90', 'FLANGE'),
      );
      expect(cut, 772);
    });
  });

  group('restoredRefPoint — a saved row keeps the point it was cut with', () {
    final flange = _comp('FLANGE', length: 76);

    test('a known code wins', () {
      expect(restoredRefPoint(flange, 'FACE_NEAR', storedValueMm: 76),
          IsoRefPoint.faceNear);
      expect(restoredRefPoint(flange, 'FACE_FAR', storedValueMm: 0),
          IsoRefPoint.faceFar);
    });

    test('legacy code: the point that reproduces the stored value', () {
      // A row from before the packed iso_ref ("FACE") with value 0 was cut
      // to the near face. Falling back to the NEW default would take 76 mm
      // off it on the next "Save changes".
      expect(restoredRefPoint(flange, '', storedValueMm: 0),
          IsoRefPoint.faceNear);
      expect(restoredRefPoint(flange, 'FACE', storedValueMm: 76),
          IsoRefPoint.faceFar);
      expect(restoredRefPoint(flange, 'FACE', storedValueMm: 38),
          IsoRefPoint.center);
    });

    test('nothing matches (library changed since): the default', () {
      expect(restoredRefPoint(flange, '', storedValueMm: 13),
          IsoRefPoint.faceFar);
    });
  });

  testWidgets('the reference sheet marks the far face of a flange as default',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() => ComponentLibraryDao()
        .insert(_comp('FLANGE', length: 76, dia: 114.37)));

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: const MaterialApp(
        home: SegmentBuilderScreen(
          materialGroup: 'SS',
          currentDiameter: 114.37,
          wallThickness: 3.05,
          gapMm: 0,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> tapPalette(String label) async {
      final button = find
          .ancestor(of: find.text(label), matching: find.byType(InkWell))
          .first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
    }

    await tapPalette('Open end');
    await tapPalette('Pipe');
    await tapPalette('Flange');
    for (var i = 0;
        i < 80 && find.text('Where does the ISO END?').evaluate().isEmpty;
        i++) {
      await flushTestDatabase(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('Where does the ISO END?'), findsOneWidget);

    // The "default" badge sits in the same row as the option's label.
    final farRow = find.ancestor(
        of: find.text('Far face'), matching: find.byType(Row)).first;
    final nearRow = find.ancestor(
        of: find.text('Near face'), matching: find.byType(Row)).first;
    expect(
        find.descendant(of: farRow, matching: find.text('default')),
        findsOneWidget,
        reason: 'an ISO dimension to a flange runs to its sealing face');
    expect(find.descendant(of: nearRow, matching: find.text('default')),
        findsNothing);
  });
}

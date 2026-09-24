// Średnica i ścianka „w trasie” (skąd startuje NASTĘPNY segment).
//
// Było: po redukcji na końcu segmentu zmieniało się tylko pole
// projects.current_diameter_mm, a ścianka zostawała stara (Ø60.3 z
// grubością Ø114.3), a usunięcie segmentu z redukcją NIE cofało średnicy —
// następny segment powstawał na złej średnicy i dostawał kształtki z
// biblioteki dla złego rozmiaru.
//
// Jest: pozycja w trasie wynika z zapisanych segmentów — z ostatniego
// segmentu (jego średnica i ścianka), a gdy kończy się redukcją, z wylotu
// redukcji. Grubości ścianki za redukcją nie ma nigdzie w bazie, więc jest
// null i monter podaje ją przy następnym segmencie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

Project _project({double current = 114.3}) => Project(
      id: 'route-proj',
      name: 'Trasa',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: current,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
    );

Segment _seg(int seq, double dia, double wall, {String? endLib}) => Segment(
      id: 's$seq',
      projectId: 'route-proj',
      seqNo: seq,
      diameterMm: dia,
      wallThicknessMm: wall,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: endLib == null ? 'logical' : 'nonAxial',
      endLibraryId: endLib,
      endValueMm: 0,
      isoRef: 'OPEN|FACE_NEAR',
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 1000,
      createdAt: 1,
      updatedAt: 1,
    );

/// Concentric reducer DN100 → DN50: inlet Ø114.3, outlet Ø60.3.
LibraryComponent _reducer({double inlet = 114.3, double out = 60.3}) =>
    LibraryComponent(
      id: 'red-$inlet-$out',
      materialGroup: 'SS',
      type: 'REDUCER',
      diameterMm: inlet,
      wallThicknessMm: 3.05,
      axisMm: null,
      lengthMm: 0,
      measurementMode: 'FACE',
      diameterOutMm: out,
      createdAt: 1,
      updatedAt: 1,
    );

LibraryComponent _elbow(double dia, double wall) => LibraryComponent(
      id: 'elb-$dia',
      materialGroup: 'SS',
      type: 'ELB90',
      diameterMm: dia,
      wallThicknessMm: wall,
      axisMm: 76,
      lengthMm: null,
      measurementMode: null,
      diameterOutMm: null,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  group('routeAfterSegments', () {
    test('no segments: the project size', () {
      final r = routeAfterSegments(
          project: _project(), segments: const [], lastEndComponent: null);
      expect(r.diameterMm, 114.3);
      expect(r.wallThicknessMm, 3.05);
    });

    test('behind a reducer: its outlet, and the wall is unknown', () {
      final red = _reducer();
      final r = routeAfterSegments(
        project: _project(),
        segments: [_seg(1, 114.3, 3.05, endLib: red.id)],
        lastEndComponent: red,
      );
      expect(r.diameterMm, 60.3);
      expect(r.wallThicknessMm, isNull,
          reason: 'the outlet wall is stored nowhere — the old code carried '
              'the Ø114.3 wall (3.05) onto the Ø60.3 pipe');
    });

    test('the segment after the reducer sets the wall for the rest', () {
      final elbow = _elbow(60.3, 2.77);
      final r = routeAfterSegments(
        project: _project(current: 60.3),
        segments: [
          _seg(1, 114.3, 3.05, endLib: 'red-114.3-60.3'),
          _seg(2, 60.3, 2.77, endLib: elbow.id),
        ],
        lastEndComponent: elbow,
      );
      expect(r.diameterMm, 60.3);
      expect(r.wallThicknessMm, 2.77);
    });

    test('deleting the reducer segment puts the route back on Ø114.3', () {
      // Old code: current_diameter_mm stayed 60.3 after the delete, and the
      // next segment was built on the wrong pipe.
      final r = routeAfterSegments(
        project: _project(current: 60.3),
        segments: const [],
        lastEndComponent: null,
      );
      expect(r.diameterMm, 114.3);
      expect(r.wallThicknessMm, 3.05);
    });

    test('segments come in any order: the highest seq_no is the last', () {
      final red = _reducer();
      final r = routeAfterSegments(
        project: _project(),
        segments: [
          _seg(2, 114.3, 3.05, endLib: red.id),
          _seg(1, 114.3, 3.05),
        ],
        lastEndComponent: red,
      );
      expect(r.diameterMm, 60.3);
    });

    test('a reducer whose inlet is not the pipe it ends does not move it', () {
      // 168.3 → 114.3 on the end of a Ø114.3 segment is not a reduction of
      // this pipe; the route stays where the segment was.
      final red = _reducer(inlet: 168.3, out: 114.3);
      final r = routeAfterSegments(
        project: _project(),
        segments: [_seg(1, 114.3, 3.05, endLib: red.id)],
        lastEndComponent: red,
      );
      expect(r.diameterMm, 114.3);
      expect(r.wallThicknessMm, 3.05);
    });

    test('END component gone from the library: the stored field decides', () {
      final r = routeAfterSegments(
        project: _project(current: 60.3),
        segments: [_seg(1, 114.3, 3.05, endLib: 'deleted')],
        lastEndComponent: null,
      );
      expect(r.diameterMm, 60.3);
      expect(r.wallThicknessMm, isNull);

      final same = routeAfterSegments(
        project: _project(current: 114.3),
        segments: [_seg(1, 114.3, 3.05, endLib: 'deleted')],
        lastEndComponent: null,
      );
      expect(same.diameterMm, 114.3);
      expect(same.wallThicknessMm, 3.05);
    });
  });

  group('FitterScreen', () {
    useTestDatabase();

    Widget wrap(Widget child) => AppLanguageScope(
          controller: AppLanguageController(AppLanguage.en),
          child: MaterialApp(home: child),
        );

    // Generous on purpose: the screen's load is a chain of SQLite calls made
    // from the fake-async zone, each of which only completes while real time
    // runs (runAsync). On a loaded machine that chain takes a while.
    Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 150 && !done(); i++) {
        await flushTestDatabase(tester);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets(
        'project left on Ø60.3 by a deleted reducer segment shows Ø114.3',
        (tester) async {
      // What the old code left behind: current_diameter_mm = 60.3 from a
      // reducer segment that was deleted since. No segments remain.
      final dao = ProjectDao();
      await tester.runAsync(() => dao.insert(_project(current: 60.3)));

      await tester.pumpWidget(wrap(const FitterScreen(projectId: 'route-proj')));
      await pumpUntil(tester,
          () => find.textContaining('Current route').evaluate().isNotEmpty);

      expect(find.textContaining('Current route: Ø114.3 × t 3.05'),
          findsOneWidget);
      final stored = await tester.runAsync(() => dao.getById('route-proj'));
      expect(stored!.currentDiameterMm, 114.3,
          reason: 'the stored field is brought back in step with the route');

      await tester.runAsync(() => dao.deleteById('route-proj'));
    });

    testWidgets('behind a reducer "Add segment" asks for the new wall first',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final red = _reducer(inlet: 114.3, out: 60.3);
      final projects = ProjectDao();
      await tester.runAsync(() async {
        await projects.insert(_project());
        await ComponentLibraryDao().insert(red);
        await SegmentDao().insert({
          'id': 'route-s1',
          'project_id': 'route-proj',
          'seq_no': 1,
          'diameter_mm': 114.3,
          'wall_thickness_mm': 3.05,
          'start_kind': 'logical',
          'start_library_id': null,
          'start_value_mm': 0.0,
          'end_kind': 'nonAxial',
          'end_library_id': red.id,
          'end_value_mm': 0.0,
          'iso_ref': 'OPEN|FACE_NEAR',
          'iso_expr': '1000',
          'iso_mm': 1000.0,
          'cut_mm': 1000.0,
          'created_at': 1,
          'updated_at': 1,
        });
      });

      await tester.pumpWidget(wrap(const FitterScreen(projectId: 'route-proj')));
      await pumpUntil(tester,
          () => find.textContaining('Current route').evaluate().isNotEmpty);
      expect(find.textContaining('Current route: Ø60.3'), findsOneWidget);

      await tester.tap(find.text('Add segment'));
      await tester.pumpAndSettle();

      // The wall of the pipe behind the reducer is asked for, not assumed.
      final wall = find.byType(TextField);
      expect(wall, findsOneWidget);
      await tester.enterText(wall, '2,77');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final builder =
          tester.widget<SegmentBuilderScreen>(find.byType(SegmentBuilderScreen));
      expect(builder.currentDiameter, 60.3);
      expect(builder.wallThickness, 2.77,
          reason: 'old code opened the builder with the Ø114.3 wall 3.05');

      await tester.runAsync(() => projects.deleteById('route-proj'));
    });
  });
}

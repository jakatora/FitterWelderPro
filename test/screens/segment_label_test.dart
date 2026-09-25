// Oznaczenie sztuki (spool/nr) w kreatorze segmentu — schemat v22.
//
// Monter numeruje spool: po SP02-03 kreator podpowiada SP02-04 (już wpisane,
// wystarczy zapisać), można je zmienić albo wyczyścić. Oznaczenie trafia do
// `segments.label`, a lista cięć pokazuje je obok S01.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/fitter_screen.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

void _tall(WidgetTester tester) {
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

/// OPEN_END → pipe → OPEN_END, ISO 1000: CUT 1000, nothing from the library.
Future<void> _buildOpenPipe(WidgetTester tester) async {
  // The palette says "Open end" in both languages.
  await _tapPalette(tester, 'Open end');
  await _tapPalette(tester, 'Rura');
  await _tapPalette(tester, 'Open end');
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '1000');
  await tester.pump();
}

/// Opens [builder] from a button and hands back what it popped.
class _Launcher extends StatefulWidget {
  final Widget builder;
  final void Function(Map<String, dynamic>?) onResult;
  const _Launcher(this.builder, this.onResult);

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => widget.builder),
              );
              widget.onResult(r);
            },
            child: const Text('open'),
          ),
        ),
      );
}

SegmentBuilderScreen _builder({String? suggested, Segment? existing}) =>
    SegmentBuilderScreen(
      materialGroup: 'SS',
      currentDiameter: 60.3,
      wallThickness: 2,
      gapMm: 0,
      suggestedLabel: suggested,
      existing: existing,
    );

void main() {
  useTestDatabase();

  testWidgets('podpowiedź SP02-04 jest wpisana i trafia do wyniku',
      (tester) async {
    _tall(tester);
    Map<String, dynamic>? result;
    await tester.pumpWidget(
        _wrap(_Launcher(_builder(suggested: 'SP02-04'), (r) => result = r)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('SP02-04  (kolejny numer)'), findsOneWidget);
    await _buildOpenPipe(tester);

    await tester.ensureVisible(find.text('Zapisz segment'));
    await tester.tap(find.text('Zapisz segment'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!['label'], 'SP02-04');
    expect(result!['cutMm'], 1000);
  });

  testWidgets('oznaczenie zmienione w oknie; wyczyszczone = brak',
      (tester) async {
    _tall(tester);
    Map<String, dynamic>? result;
    await tester.pumpWidget(
        _wrap(_Launcher(_builder(suggested: 'SP02-04'), (r) => result = r)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _buildOpenPipe(tester);

    Future<void> setMark(String text) async {
      final tile = find.byKey(const ValueKey('segment-label'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('segment-label-field')), text);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await setMark(' sp09-01 ');
    expect(find.text('sp09-01'), findsOneWidget);

    // The chip brings the suggestion back in one tap.
    final tile = find.byKey(const ValueKey('segment-label'));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolejny: SP02-04'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('segment-label-field')))
            .controller!
            .text,
        'SP02-04');
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.text('sp09-01'), findsOneWidget, reason: 'cancel keeps it');

    await setMark('   ');
    expect(find.textContaining('brak — dotknij'), findsOneWidget);

    await tester.ensureVisible(find.text('Zapisz segment'));
    await tester.tap(find.text('Zapisz segment'));
    await tester.pumpAndSettle();
    expect(result!.containsKey('label'), isTrue);
    expect(result!['label'], isNull);
  });

  testWidgets('poprawka segmentu: jego oznaczenie, bez podpowiedzi, bez pytań',
      (tester) async {
    _tall(tester);
    final seg = Segment(
      id: 'lbl-edit',
      projectId: 'p',
      seqNo: 4,
      diameterMm: 60.3,
      wallThicknessMm: 2,
      startKind: 'logical',
      startLibraryId: null,
      startValueMm: 0,
      endKind: 'logical',
      endLibraryId: null,
      endValueMm: 0,
      isoRef: 'OPEN|OPEN',
      isoExpr: '1000',
      isoMm: 1000,
      cutMm: 1000,
      createdAt: 1,
      updatedAt: 1,
      label: 'SP01-07',
    );
    Map<String, dynamic>? result = {'untouched': true};
    await tester.pumpWidget(_wrap(_Launcher(
        _builder(suggested: 'SP09-99', existing: seg), (r) => result = r)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('SP01-07'), findsOneWidget);
    expect(find.textContaining('SP09-99'), findsNothing);

    // Untouched → back asks nothing and returns no result.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('Porzucić'), findsNothing);
    expect(result, isNull);
  });

  group('FitterScreen', () {
    Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 150 && !done(); i++) {
        await flushTestDatabase(tester);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('po SP02-03 nowy segment dostaje SP02-04 i zapisuje go w bazie',
        (tester) async {
      _tall(tester);
      const pid = 'label-proj';
      final projects = ProjectDao();
      await tester.runAsync(() async {
        await projects.insert(Project(
          id: pid,
          name: 'Spool 2',
          materialGroup: 'SS',
          diameterMm: 60.3,
          wallThicknessMm: 2,
          currentDiameterMm: 60.3,
          stockLengthMm: 6000,
          sawKerfMm: 1,
          gapMm: 0,
          createdAt: 1,
          updatedAt: 1,
        ));
        await SegmentDao().insert({
          'id': 'label-s1',
          'project_id': pid,
          'seq_no': 1,
          'diameter_mm': 60.3,
          'wall_thickness_mm': 2.0,
          'start_kind': 'logical',
          'start_library_id': null,
          'start_value_mm': 0.0,
          'end_kind': 'logical',
          'end_library_id': null,
          'end_value_mm': 0.0,
          'iso_ref': 'OPEN|OPEN',
          'iso_expr': '800',
          'iso_mm': 800.0,
          'cut_mm': 800.0,
          'created_at': 1,
          'updated_at': 1,
          'label': 'SP02-03',
        });
      });

      await tester.pumpWidget(_wrap(const FitterScreen(projectId: pid)));
      await pumpUntil(tester,
          () => find.textContaining('SP02-03').evaluate().isNotEmpty);
      expect(find.textContaining('Segment 1 · SP02-03'), findsOneWidget);

      await tester.tap(find.text('Dodaj segment'));
      await tester.pumpAndSettle();
      final builder =
          tester.widget<SegmentBuilderScreen>(find.byType(SegmentBuilderScreen));
      expect(builder.suggestedLabel, 'SP02-04');

      await _buildOpenPipe(tester);
      expect(find.text('CUT = 1000.0 mm'), findsOneWidget);
      await tester.ensureVisible(find.text('Zapisz segment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz segment'));
      await pumpUntil(
          tester,
          () => find
              .textContaining('Segment 2 · SP02-04')
              .evaluate()
              .isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(SegmentBuilderScreen), findsNothing);

      final segs = await tester.runAsync(() => SegmentDao().listForProject(pid));
      expect(segs!.map((s) => s.label), ['SP02-03', 'SP02-04']);

      await tester.runAsync(() => projects.deleteById(pid));
    });
  });
}

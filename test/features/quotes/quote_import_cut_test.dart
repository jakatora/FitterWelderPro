// „Importuj spoiny" → źródło „Projekt CUT", z prawdziwą bazą testową:
// projekty listy cięć (projects / segments / component_library) → lista
// z liczbą spoin → podgląd z założeniami i wyborem typu kołnierzy →
// pozycje w wycenie (i w bazie po autozapisie). Także pusty stan, EN
// i wąski ekran 320 px z czcionką 130 %.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/quote_import.dart';
import 'package:cut_list_app/domain/quotes/weld_geometry.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/features/quotes/quote_edit_page.dart';
import 'package:cut_list_app/features/quotes/quote_import_sheet.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/services/cut_quote_import.dart';
import 'package:cut_list_app/services/quote_settings.dart';

import '../../support/test_database.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

WeldQuote _quote(QuoteSite site,
        {QuoteMaterial material = QuoteMaterial.carbon}) =>
    WeldQuote(
      id: 'q-cut',
      number: 'WYC/2026/011',
      title: 'Prefabrykacja linii wody',
      site: site,
      material: material,
      createdAt: DateTime(2026, 10, 17).millisecondsSinceEpoch,
      updatedAt: DateTime(2026, 10, 17).millisecondsSinceEpoch,
    );

Future<void> _clean() async {
  final db = await AppDatabase.get();
  for (final t in ['weld_quotes', 'segments', 'projects', 'component_library']) {
    await db.delete(t);
  }
}

LibraryComponent _lib(String id, String type, {double? out}) {
  final axial = type == 'ELB90' || type == 'TEE';
  return LibraryComponent(
    id: id,
    materialGroup: 'CS',
    type: type,
    diameterMm: 114.3,
    wallThicknessMm: 6.02,
    axisMm: axial ? 152.4 : null,
    lengthMm: axial ? null : 100,
    measurementMode: axial ? null : 'FACE',
    diameterOutMm: out,
    createdAt: 0,
    updatedAt: 0,
  );
}

Project _project(String id, String name, {required int updatedAt}) => Project(
      id: id,
      name: name,
      materialGroup: 'CS',
      diameterMm: 114.3,
      wallThicknessMm: 6.02,
      currentDiameterMm: 60.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 3,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

Map<String, Object?> _seg(
  String projectId,
  int seq, {
  String? start,
  String? end,
  double od = 114.3,
  double t = 6.02,
}) {
  String kind(String? lib) => lib == null
      ? 'logical'
      : (lib == 'e90' || lib == 'tee')
          ? 'axial'
          : 'nonAxial';
  return {
    'id': '$projectId-s$seq',
    'project_id': projectId,
    'seq_no': seq,
    'diameter_mm': od,
    'wall_thickness_mm': t,
    'start_kind': kind(start),
    'start_library_id': start,
    'start_value_mm': 0.0,
    'end_kind': kind(end),
    'end_library_id': end,
    'end_value_mm': 0.0,
    'iso_ref': 'AXIS|AXIS',
    'iso_expr': '1500',
    'iso_mm': 1500.0,
    'cut_mm': 1200.0,
    'created_at': 0,
    'updated_at': 0,
  };
}

/// Trasa DN100: kołnierz–kolano–trójnik–redukcja na DN50, odgałęzienie
/// trójnika do kołnierza. Spoiny: 6 × BW Ø114,3, 1 × BW Ø60,3, 2 kołnierze
/// bez typu (do sprawdzenia). Drugi projekt — pusty (bez odcinków).
Future<void> _seed() async {
  await _clean();
  final library = ComponentLibraryDao();
  for (final c in [
    _lib('fl', 'FLANGE'),
    _lib('e90', 'ELB90'),
    _lib('tee', 'TEE'),
    _lib('red', 'REDUCER', out: 60.3),
  ]) {
    await library.insert(c);
  }
  final projects = ProjectDao();
  await projects.insert(_project('p1', 'Woda chłodząca L-100',
      updatedAt: DateTime(2026, 10, 16, 14, 5).millisecondsSinceEpoch));
  await projects.insert(_project('p0', 'Pusty',
      updatedAt: DateTime(2026, 10, 1, 8).millisecondsSinceEpoch));
  final segments = SegmentDao();
  for (final row in [
    _seg('p1', 1, start: 'fl', end: 'e90'),
    _seg('p1', 2, start: 'e90', end: 'tee'),
    _seg('p1', 3, start: 'tee', end: 'red'),
    _seg('p1', 4, start: 'red', od: 60.3, t: 3.91),
    _seg('p1', 5, start: 'tee', end: 'fl'),
  ]) {
    await segments.insert(row);
  }
}

Future<void> _openEditor(WidgetTester tester, WeldQuote quote) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(AppLanguage.pl),
    child: MaterialApp(
      home: QuoteEditPage(
        quote: quote,
        settings: const QuoteSettings(),
        saveDelay: const Duration(milliseconds: 100),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Sam arkusz importu nad stroną z przyciskiem — wynik w [result].
Future<void> _openSheet(
  WidgetTester tester,
  WeldQuote quote, {
  required AppLanguage language,
  required List<List<QuoteJoint>?> result,
  Size size = const Size(1080, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-import'),
              onPressed: () async =>
                  result.add(await showQuoteImport(context, quote: quote)),
              child: const Text('import'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const ValueKey('open-import')));
  await tester.pumpAndSettle();
}

Future<List<QuoteJoint>> _savedJoints(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await _settle(tester);
  final rows = (await tester.runAsync(() => WeldQuoteDao().listAll()))!;
  return rows.single.joints;
}

const _bw60 = ValueKey('import-group-PIPE_BUTT|60.30|3.91|0.00|PA');

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('baza: projekty CUT z odcinkami w kolejności i biblioteką — spoiny '
      'liczone z zapisanych tabel', () async {
    await _seed();
    final list = await loadCutProjectsForImport();
    expect([for (final p in list) p.project.id], ['p1', 'p0']);
    final p1 = list.first;
    expect([for (final s in p1.segments) s.seqNo], [1, 2, 3, 4, 5]);
    expect(p1.library.keys, containsAll(['fl', 'e90', 'tee', 'red']));
    expect(list.last.segments, isEmpty);

    final res = importWeldsFromCutProject(p1);
    expect(res.flangeEnds, 2);
    expect(res.valveEnds, 0);
    final plan = planQuoteImport(res.welds, defaultPosition: WeldPosition.pa);
    expect([for (final g in plan.groups) (g.odMm, g.wallMm, g.count)], [
      (60.3, 3.91, 1),
      (114.3, 6.02, 6),
    ]);
    expect(plan.skippedFor(ImportSkipReason.flangeType), 2);
    expect(plan.skippedFor(ImportSkipReason.openPort), 0);

    // Odczyt niczego nie zmienia w projekcie.
    final db = await AppDatabase.get();
    final after = await db.query('projects', where: 'id = ?', whereArgs: ['p1']);
    expect(after.single['updated_at'],
        DateTime(2026, 10, 16, 14, 5).millisecondsSinceEpoch);
  });

  testWidgets(
      'projekt CUT → lista z liczbą spoin → podgląd → typ kołnierzy SO → '
      'pozycje w wycenie', (tester) async {
    await tester.runAsync(_seed);

    await _openEditor(tester, _quote(QuoteSite.shop));
    await tester.tap(find.byKey(const ValueKey('import-joints')));
    await tester.pumpAndSettle();
    expect(find.text('Projekt CUT'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-source-cut')));
    await _settle(tester);
    await tester.pumpAndSettle();

    // Lista: nazwa, data, spoiny do importu i do sprawdzenia; pusty projekt
    // nieaktywny.
    expect(find.text('Projekty CUT'), findsOneWidget);
    expect(find.text('Woda chłodząca L-100'), findsOneWidget);
    expect(
        find.text('16.10.2026 14:05  ·  spoiny: 7  ·  do sprawdzenia: 2'),
        findsOneWidget);
    expect(find.text('01.10.2026 08:00  ·  brak odcinków'), findsOneWidget);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('import-cut-p0')))
            .enabled,
        isFalse);

    await tester.tap(find.byKey(const ValueKey('import-cut-p1')));
    await tester.pumpAndSettle();

    expect(find.text('Podgląd importu'), findsOneWidget);
    expect(find.textContaining('Zaznaczone: 2 z 2 pozycji (7 z 7 spoin)'),
        findsOneWidget);
    expect(find.text('6×'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);
    expect(find.textContaining('Do sprawdzenia — kołnierze: 2'),
        findsOneWidget);
    expect(find.textContaining('S01 pocz., S05 kon.'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-cut-assumptions')),
        findsOneWidget);
    expect(find.textContaining('trójnik to 3 spoiny'), findsOneWidget);
    // Pozycja z wyceny jako założenie, numery spoin z odcinków.
    expect(find.text('PA / 1G  ·  przyjęta z wyceny (brak w danych)'),
        findsNWidgets(2));
    expect(find.textContaining('Spoiny: S01 kon., S02 pocz.'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-cut-material')), findsNothing);

    // Redukcja na DN50 nie wchodzi; potem typ kołnierzy — odznaczenie zostaje.
    await tester.tap(find.descendant(
        of: find.byKey(_bw60), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-cut-flanges')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Płaskie (SO) / mufowe (SW) — pachwinowa').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Zaznaczone: 2 z 3 pozycji (8 z 9 spoin)'),
        findsOneWidget);
    expect(find.textContaining('Do sprawdzenia — kołnierze'), findsNothing);
    expect(find.textContaining('Dodaj do wyceny (8 spoin)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Dodano pozycji: 2 (spoin: 8).'), findsOneWidget);

    final joints = await _savedJoints(tester);
    expect([for (final j in joints) (j.kind, j.odMm, j.wallMm, j.count)], [
      (JointKind.pipeButt, 114.3, 6.02, 6),
      (JointKind.pipeFillet, 114.3, 6.02, 2),
    ]);
    expect(joints.every((j) => j.label == 'Woda chłodząca L-100'), isTrue);
    expect(joints.every((j) => j.position == WeldPosition.pa), isTrue);
    expect(joints.last.throatMm, socketWeldThroatMm(6.02));
    expect(joints.every((j) => j.isValid), isTrue);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('brak projektów CUT — komunikat zamiast listy, wstecz do źródeł',
      (tester) async {
    await tester.runAsync(_clean);
    await _openEditor(tester, _quote(QuoteSite.field));
    await tester.tap(find.byKey(const ValueKey('import-joints')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('import-source-cut')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Nie ma projektów CUT'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('import-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('import-source-cut')), findsOneWidget);
  });

  testWidgets('EN: CUT project → weld neck flanges → butt welds returned',
      (tester) async {
    await tester.runAsync(_seed);
    final result = <List<QuoteJoint>?>[];
    await _openSheet(tester, _quote(QuoteSite.field),
        language: AppLanguage.en, result: result);

    expect(find.text('CUT project'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('import-source-cut')));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('CUT projects'), findsOneWidget);
    expect(find.text('16.10.2026 14:05  ·  welds: 7  ·  to check: 2'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-cut-p1')));
    await tester.pumpAndSettle();
    expect(find.text('Import preview'), findsOneWidget);
    expect(find.textContaining('To check — flanges: 2'), findsOneWidget);
    expect(find.text('How welds are counted'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Welds: S01 end, S02 start'), findsOneWidget);
    // Field quote → PF taken from the quote.
    expect(find.text('PF·PH / 5G  ·  from the quote (not in the data)'),
        findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('import-cut-flanges')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weld neck (WN) — butt weld').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Selected: 2 of 2 items (9 of 9 welds)'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import-confirm')));
    await tester.pumpAndSettle();
    final joints = result.single!;
    expect([for (final j in joints) (j.kind, j.odMm, j.count, j.position)], [
      (JointKind.pipeButt, 60.3, 1, WeldPosition.pf),
      (JointKind.pipeButt, 114.3, 8, WeldPosition.pf),
    ]);
  });

  testWidgets(
      'wąski ekran 320 px, czcionka 130 %: lista, podgląd, wybór typu i '
      'założenia bez przepełnień; cele dotyku ≥ 48 dp', (tester) async {
    await tester.runAsync(_seed);
    final result = <List<QuoteJoint>?>[];
    // Wycena ze stali nierdzewnej, projekt CS → ostrzeżenie o materiale.
    await _openSheet(tester,
        _quote(QuoteSite.shop, material: QuoteMaterial.stainless),
        language: AppLanguage.pl,
        result: result,
        size: const Size(320, 640),
        textScale: 1.3);
    expect(tester.takeException(), isNull);

    final source = find.byKey(const ValueKey('import-source-cut'));
    // Trzecie źródło jest pod krawędzią wąskiego ekranu.
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.ensureVisible(source);
    await tester.pumpAndSettle();
    expect(tester.getSize(source).height, greaterThanOrEqualTo(48));
    await tester.tap(source);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final tile = find.byKey(const ValueKey('import-cut-p1'));
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('import-cut-material')), findsOneWidget);
    final flanges = find.byKey(const ValueKey('import-cut-flanges'));
    expect(tester.getSize(flanges).height, greaterThanOrEqualTo(48));

    await tester.ensureVisible(flanges);
    await tester.pumpAndSettle();
    await tester.tap(flanges);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Luźne / gwintowane — bez spoiny').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('(7 z 7 spoin)'), findsOneWidget);

    final assumptions = find.byKey(const ValueKey('import-cut-assumptions'));
    for (var i = 0; i < 10 && assumptions.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(assumptions);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('import-confirm'))).height,
        greaterThanOrEqualTo(48));
  });
}

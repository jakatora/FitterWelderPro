// Ekran CUT LIST na prawdziwej bazie (sqflite ffi, w pamięci):
//   * sztuki na sztangach i chipy odcinków mają etykiety segmentów (S01…),
//   * cięcie dłuższe od sztangi daje wyraźne ostrzeżenie o dodatkowej spoinie,
//   * ikona udostępniania UDOSTĘPNIA (arkusz systemowy z plikiem CSV lub
//     tekstem), a kopiowanie do schowka jest obok w tym samym menu,
//   * przytrzymanie karty sztangi kopiuje ją z etykietami.
//
// Kanały platformy (path_provider, share_plus, schowek) są podstawione, żeby
// sprawdzić, CO trafia do arkusza udostępniania i do schowka.
//
// Dane: sztanga 6000 mm, rzaz 3 mm; S01 7000 (dłuższy od sztangi),
// S02 4000, S03 1200 → sztanga 1: S01 (1/2) 6000; sztanga 2: S02 4000 +
// S03 1200 (reszta 6000 − 5200 − 6 = 794); sztanga 3: S01 (2/2) 1000
// (reszta 6000 − 1000 − 3 = 4997).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/screens/cut_list_summary_screen.dart';

import '../support/test_database.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');
const _share = MethodChannel('dev.fluttercommunity.plus/share');

Map<String, Object?> _segRow(String projectId, int seqNo, double cutMm) => {
      'id': '$projectId-s$seqNo',
      'project_id': projectId,
      'seq_no': seqNo,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'FACE',
      'iso_expr': cutMm.toStringAsFixed(0),
      'iso_mm': cutMm,
      'cut_mm': cutMm,
      'created_at': 0,
      'updated_at': 0,
    };

void main() {
  useTestDatabase();

  late Directory tmp;
  final shareCalls = <MethodCall>[];
  final clipboard = <String>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fwp-cutlist-share-');
    shareCalls.clear();
    clipboard.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathProvider, (call) async {
      if (call.method == 'getTemporaryDirectory') return tmp.path;
      return null;
    });
    messenger.setMockMethodCallHandler(_share, (call) async {
      shareCalls.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathProvider, null);
    messenger.setMockMethodCallHandler(_share, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Lets real I/O (sqflite, file writes) finish and advances the widget
  /// clock, until [done] holds or the budget runs out.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 60 && !done(); i++) {
      await flushTestDatabase(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('etykiety, ostrzeżenie, udostępnianie CSV/tekstu i kopiowanie',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pid = 'cutlist-share-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() async {
      await ProjectDao().insert(Project(
        id: pid,
        name: 'Łącznik żółć',
        materialGroup: 'SS',
        diameterMm: 114.3,
        wallThicknessMm: 6.02,
        currentDiameterMm: 114.3,
        stockLengthMm: 6000,
        sawKerfMm: 3,
        gapMm: 0,
        createdAt: 0,
        updatedAt: 0,
      ));
      final segments = SegmentDao();
      await segments.insert(_segRow(pid, 1, 7000));
      await segments.insert(_segRow(pid, 2, 4000));
      await segments.insert(_segRow(pid, 3, 1200));
    });

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: CutListSummaryScreen(projectId: pid)),
    ));
    await settle(tester,
        () => find.text('Odcinek dłuższy niż sztanga').evaluate().isNotEmpty);

    // ── Ostrzeżenie o cięciu dłuższym od sztangi ──────────────────────────
    expect(find.text('Odcinek dłuższy niż sztanga'), findsOneWidget);
    expect(
      find.text('S01: odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony '
          'na 2 części; potrzebna dodatkowa spoina łącząca; uwzględnij gap.'),
      findsOneWidget,
    );

    // ── Etykiety: chipy odcinków i sztuki na sztangach ────────────────────
    for (final label in ['S01', 'S02', 'S03']) {
      expect(find.text(label), findsOneWidget, reason: 'chip $label');
    }
    expect(find.textContaining('S01 (1/2) 6000', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('S02 4000  +  S03 1200', findRichText: true),
        findsOneWidget);
    expect(find.textContaining('S01 (2/2) 1000', findRichText: true),
        findsOneWidget);
    // Karty z częścią podzielonego cięcia mówią o spoinie łączącej.
    expect(
      find.text('Część odcinka dłuższego niż sztanga — dodatkowa spoina '
          'łącząca, uwzględnij gap'),
      findsNWidgets(2),
    );

    // ── Udostępnij plik CSV ───────────────────────────────────────────────
    await tester.tap(find.byTooltip('Udostępnij / kopiuj'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Udostępnij plik CSV'));
    await tester.pumpAndSettle();
    await settle(tester, () => shareCalls.isNotEmpty);

    expect(shareCalls, hasLength(1));
    final fileCall = shareCalls.single;
    expect(fileCall.method, 'shareFiles');
    final args = (fileCall.arguments as Map).cast<String, Object?>();
    final paths = (args['paths'] as List).cast<String>();
    expect(paths, hasLength(1));
    expect(paths.single, matches(RegExp(r'CutList_Lacznik_zolc_\d{8}-\d{4}\.csv$')));
    expect(args['mimeTypes'], ['text/csv']);
    expect(args['subject'], 'CUT LIST — Łącznik żółć');

    late List<int> bytes;
    await tester.runAsync(() async {
      bytes = await File(paths.single).readAsBytes();
    });
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final csvLines = utf8.decode(bytes.skip(3).toList()).trimRight().split('\n');
    expect(csvLines[1], startsWith('projekt;materiał;'));
    expect(csvLines.skip(2), [
      '"Łącznik żółć";SS;6000;3.0;114.3;6.0;1;1;6000;0;"S01 (1/2)";7000;'
          '"odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na 2 części; '
          'potrzebna dodatkowa spoina łącząca; uwzględnij gap."',
      '"Łącznik żółć";SS;6000;3.0;114.3;6.0;2;1;4000;794;S02;4000;',
      '"Łącznik żółć";SS;6000;3.0;114.3;6.0;2;2;1200;794;S03;1200;',
      '"Łącznik żółć";SS;6000;3.0;114.3;6.0;3;1;1000;4997;"S01 (2/2)";7000;'
          '"odcinek 7000 mm dłuższy niż sztanga 6000 mm — dzielony na 2 części; '
          'potrzebna dodatkowa spoina łącząca; uwzględnij gap."',
    ]);

    // ── Udostępnij jako tekst ─────────────────────────────────────────────
    await tester.tap(find.byTooltip('Udostępnij / kopiuj'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Udostępnij jako tekst'));
    await tester.pumpAndSettle();
    await settle(tester, () => shareCalls.length == 2);

    expect(shareCalls, hasLength(2));
    expect(shareCalls.last.method, 'share');
    final text = (shareCalls.last.arguments as Map)['text'] as String;
    expect(text, contains('UWAGA: S01: odcinek 7000 mm dłuższy niż sztanga'));
    expect(text, contains('  Sztanga 2: S02: 4000 + S03: 1200  (zostaje 794 mm)'));

    // ── Kopiuj CSV (schowek, bez BOM) ─────────────────────────────────────
    await tester.tap(find.byTooltip('Udostępnij / kopiuj'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopiuj CSV'));
    await tester.pumpAndSettle();
    expect(clipboard, hasLength(1));
    expect(clipboard.single, startsWith('# generated by FitterWelderPro\n'));
    expect(clipboard.single, contains(';"S01 (2/2)";'));

    // ── Przytrzymanie karty sztangi kopiuje ją z etykietami ───────────────
    await tester.longPress(find.textContaining('S02 4000', findRichText: true));
    await tester.pumpAndSettle();
    expect(clipboard.last, 'Sztanga 2: S02: 4000 + S03: 1200 (zostaje 794 mm)');

    await tester.runAsync(() async {
      await SegmentDao().deleteAllForProject(pid);
      await ProjectDao().deleteById(pid);
    });
    // Let snackbar timers expire before the tree goes away.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
  });

  testWidgets('wąski telefon (360 dp, tekst ×1,3, EN): bez przepełnień',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final pid = 'cutlist-narrow-${DateTime.now().microsecondsSinceEpoch}';
    await tester.runAsync(() async {
      await ProjectDao().insert(Project(
        id: pid,
        name: 'Very long project name for the narrow phone layout check',
        materialGroup: 'DSS',
        diameterMm: 114.3,
        wallThicknessMm: 6.02,
        currentDiameterMm: 114.3,
        stockLengthMm: 6000,
        sawKerfMm: 3,
        gapMm: 0,
        createdAt: 0,
        updatedAt: 0,
      ));
      final segments = SegmentDao();
      await segments.insert(_segRow(pid, 1, 14000));
      for (var i = 2; i <= 12; i++) {
        await segments.insert(_segRow(pid, i, 150.0 * i));
      }
    });

    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: CutListSummaryScreen(projectId: pid),
      ),
    ));
    await settle(tester,
        () => find.text('Piece longer than the stock bar').evaluate().isNotEmpty);

    expect(find.text('Piece longer than the stock bar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await SegmentDao().deleteAllForProject(pid);
      await ProjectDao().deleteById(pid);
    });
  });
}

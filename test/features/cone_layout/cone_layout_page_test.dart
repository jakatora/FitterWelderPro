// Ekran „Rozwinięcie stożka i przejść”: liczy na żywo, komunikaty zamiast
// NaN, przełączanie kształtów, podział na części, cale, wersja EN, wąski
// ekran z dużą czcionką, cele dotyku ≥ 48 dp, PDF i tekst przez wstrzyknięte
// funkcje (bez platformy) — i prawdziwy PDF zbudowany ze specyfikacji ekranu.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/wrap_template_pdf.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

class _Spy {
  final List<(String, String)> texts = [];
  final List<(FlatTemplateSpec, String, bool)> pdfs = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(FlatTemplateSpec s, String name, bool en) async =>
      pdfs.add((s, name, en));
}

Future<_Spy> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 8000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spy = _Spy();
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ConeLayoutPage(shareText: spy.text, sharePdf: spy.pdf),
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

Finder _in(String key, String text) => find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.text(text), matchRoot: true);

Finder _readout(String key, String value) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(value));

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lej D 600 / d 200 zewn., t 4, H 400 → R 666,3; H 300 → 537,2',
      (tester) async {
    await _pump(tester);
    // Dm 596, dm 196, Δr 200, L 447,21, sin α = 0,4472 → R = 298/sin α.
    expect(_readout('cone-R', '666,3'), findsOneWidget);
    expect(_in('cone-r', '219,1 mm'), findsOneWidget);
    expect(_in('cone-theta', '161°'), findsOneWidget);
    expect(_in('cone-whole-rect', '1314,4 × 630,2 mm'), findsOneWidget);
    await _enter(tester, 'cone-H', '300');
    // L = √(300² + 200²) = 360,56, R = 298·L/200 = 537,23.
    expect(_readout('cone-R', '537,2'), findsOneWidget);
    // Kątem: α 30° → R = 298 / sin 30° = 596.
    await _tap(tester, 'cone-mode-angle');
    await _enter(tester, 'cone-alpha', '30');
    expect(_readout('cone-R', '596'), findsOneWidget);
    // Wymiary średnie: Dm = 600 → R = 600.
    await _tap(tester, 'cone-ref-mean');
    expect(_readout('cone-R', '600'), findsOneWidget);
  });

  testWidgets('błędne wejście → komunikat, bez wyniku i bez PDF',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'cone-d', '1200');
    expect(find.byKey(const ValueKey('cone-problem')), findsOneWidget);
    expect(find.textContaining('mniejsza od dużej'), findsOneWidget);
    expect(find.byKey(const ValueKey('cone-R')), findsNothing);
    expect(find.byKey(const ValueKey('cone-pdf')), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    await _enter(tester, 'cone-d', '200');
    await _enter(tester, 'cone-H', '');
    expect(find.textContaining('Podaj wysokość H'), findsOneWidget);
    await _enter(tester, 'cone-H', '400');
    await _enter(tester, 'cone-t', '100');
    expect(find.textContaining('Grubość blachy: od 0'), findsOneWidget);
    await _enter(tester, 'cone-t', '4');
    // d = 0 — stożek pełny, liczy się dalej.
    await _enter(tester, 'cone-d', '0');
    expect(find.byKey(const ValueKey('cone-problem')), findsNothing);
    expect(_in('cone-r', '0 (wierzchołek)'), findsOneWidget);
  });

  testWidgets('podział na części i dopasowanie do arkusza', (tester) async {
    await _pump(tester);
    // 1314 × 630 mieści się na 1500 × 3000.
    expect(
        _in('cone-fit', 'Każda część mieści się na arkuszu.'), findsOneWidget);
    await _enter(tester, 'cone-sheet-w', '1000');
    await _enter(tester, 'cone-sheet-l', '1200');
    expect(find.byKey(const ValueKey('cone-fit-notice')), findsOneWidget);
    expect(find.textContaining('zalecany podział: 2 cz.'), findsOneWidget);
    await _tap(tester, 'cone-parts-2');
    expect(_in('cone-part-angle', '80,5°'), findsOneWidget);
    // Połówka: 2R·sin 40,25° × (R − r·cos 40,25°) = 861,1 × 499,1.
    expect(_in('cone-part-rect', 'Prostokąt części: 861,1 × 499,1 mm'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cone-fit-notice')), findsNothing);
    expect(
        _in('cone-fit', 'Każda część mieści się na arkuszu.'), findsOneWidget);
  });

  testWidgets('przełączanie kształtów: mimośrodowy i kwadrat–koło',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'cone-shape-eccentric');
    // Jedna tworząca pionowa: e = (596 − 196)/2 = 200; tworzące 400 i 565,7.
    expect(_in('cone-ecc-e', '200 mm'), findsOneWidget);
    expect(_in('cone-ecc-gen', '400 / 565,7 mm'), findsOneWidget);
    expect(find.byKey(const ValueKey('cone-ecc-table')), findsOneWidget);
    expect(find.byKey(const ValueKey('cone-ecc-coords')), findsOneWidget);
    await _tap(tester, 'cone-ecc-custom');
    await _enter(tester, 'cone-e', '100');
    expect(_in('cone-ecc-e', '100 mm'), findsOneWidget);

    await _tap(tester, 'cone-shape-transition');
    // Szew w połowie boku B (bok −X): M3 → punkt 9 (φ 180°), na obu końcach:
    // √(150² + 400²) = 427,2 (Am 596, Dm 296).
    expect(_in('tr-lines', 'M3–9'), findsNWidgets(2));
    expect(_in('tr-lines', '427,2'), findsWidgets);
    // Krawędzie: 2·(596 + 396) = 1984, π·296 = 929,9.
    expect(_in('tr-edges', '1984 / 929,9 mm'), findsOneWidget);
    // Cztery części: druga to lustro pierwszej.
    await _tap(tester, 'cone-tparts-4');
    await _tap(tester, 'cone-view-part-2');
    expect(find.textContaining('lustrzanym'), findsOneWidget);
    // Powrót do stożka zachowuje dane.
    await _tap(tester, 'cone-shape-concentric');
    expect(_readout('cone-R', '666,3'), findsOneWidget);
  });

  testWidgets('cale: pola i wyniki przeliczone, powrót do mm', (tester) async {
    await _pump(tester);
    await _tap(tester, 'cone-unit-in');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('cone-D')))
            .controller!
            .text,
        '23,622');
    // 666,35 mm = 26,23 in.
    expect(_readout('cone-R', '26,23'), findsOneWidget);
    await _tap(tester, 'cone-unit-mm');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('cone-D')))
            .controller!
            .text,
        '600');
    expect(_readout('cone-R', '666,3'), findsOneWidget);
  });

  testWidgets('po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Cone & transition layout'), findsOneWidget);
    expect(_readout('cone-R', '666.3'), findsOneWidget);
    expect(find.text('OUTER RADIUS R'), findsOneWidget);
    await _enter(tester, 'cone-d', '1200');
    expect(
        find.textContaining('must be less than the large one'), findsOneWidget);
    await _enter(tester, 'cone-d', '200');
    await _tap(tester, 'cone-shape-transition');
    expect(find.text('Square to round'), findsOneWidget);
    expect(find.byKey(const ValueKey('tr-rect')), findsOneWidget);
  });

  testWidgets('smukły stożek: tabela rzędnych sama, PDF za duży',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'cone-D', '1000');
    await _enter(tester, 'cone-d', '900');
    await _enter(tester, 'cone-H', '2000');
    // R ≈ 19,9 m — cyrkiel odpada, tabela od cięciwy od razu.
    expect(find.byKey(const ValueKey('cone-ord-outer')), findsOneWidget);
    expect(find.byKey(const ValueKey('cone-ord-inner')), findsOneWidget);
    expect(find.byKey(const ValueKey('cone-show-ordinates')), findsNothing);
    expect(find.byKey(const ValueKey('cone-pdf')), findsNothing);
    expect(find.byKey(const ValueKey('cone-pdf-too-big')), findsOneWidget);
    expect(find.textContaining('trasuj z tabeli'), findsOneWidget);
    // Zwykły lej — tabela na żądanie.
    await _enter(tester, 'cone-D', '600');
    await _enter(tester, 'cone-d', '200');
    await _enter(tester, 'cone-H', '400');
    expect(find.byKey(const ValueKey('cone-ord-outer')), findsNothing);
    expect(find.byKey(const ValueKey('cone-pdf')), findsOneWidget);
    await _tap(tester, 'cone-show-ordinates');
    expect(find.byKey(const ValueKey('cone-ord-outer')), findsOneWidget);
    await _tap(tester, 'cone-step-500');
    // Cięciwa 1314,4 co 500: 0, 500, 1000, środek 657,2 (strzałka 556,4)
    // i koniec.
    expect(_in('cone-ord-outer', '657,2'), findsOneWidget);
    expect(_in('cone-ord-outer', '556,4'), findsOneWidget);
    expect(_in('cone-ord-outer', '1314,4'), findsOneWidget);
  });

  testWidgets('udostępnianie tekstu i PDF przez wstrzyknięte funkcje',
      (tester) async {
    final spy = await _pump(tester);
    await _tap(tester, 'cone-share-text');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Rozwinięcie blachy — wymiary');
    expect(text, contains('R 666,3 mm · r 219,1 mm · θ 161°'));
    expect(text, contains('Dm 596 / dm 196 mm'));

    await _tap(tester, 'cone-paper-a3');
    await _tap(tester, 'cone-pdf');
    expect(spy.pdfs, hasLength(1));
    final (spec, name, en) = spy.pdfs.single;
    expect(name, 'stozek_596_196.pdf');
    expect(en, isFalse);
    expect(spec.paper, TemplatePaper.a3);
    expect(spec.shapes, hasLength(1));
    expect(spec.shapes.single.widthMm, closeTo(1314.41, 0.01));
    expect(spec.sheetCount, greaterThan(1));

    // Prawdziwy PDF z tej specyfikacji.
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final bytes = await tester.runAsync(() => buildFlatTemplatePdf(spec,
        font: font('Roboto-Regular.ttf'),
        bold: font('Roboto-Bold.ttf'),
        en: false,
        generatedAt: DateTime(2026, 10, 17)));
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');

    // Przejście — tekst z liniami prawdziwymi, PDF z częściami bez duplikatów.
    await _tap(tester, 'cone-shape-transition');
    await _tap(tester, 'cone-tparts-4');
    await _tap(tester, 'cone-appbar-share');
    expect(spy.texts.last.$1, contains('Linie prawdziwe — Część 1'));
    await _tap(tester, 'cone-paper-a4');
    await _tap(tester, 'cone-pdf');
    final trSpec = spy.pdfs.last.$1;
    // Ćwiartki prostokąta: 1 i 3 identyczne, 2 i 4 lustra 1 — drukujemy jedną.
    expect(trSpec.shapes, hasLength(1));
    expect(trSpec.shapes.single.name, contains('lustro'));
    final trBytes = await tester.runAsync(() => buildFlatTemplatePdf(trSpec,
        font: font('Roboto-Regular.ttf'),
        bold: font('Roboto-Bold.ttf'),
        en: true,
        generatedAt: DateTime(2026, 10, 17)));
    expect(String.fromCharCodes(trBytes!.take(5)), '%PDF-');
  });

  testWidgets('wąski ekran 320 × 640, tekst × 1,3 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(320, 640), textScale: 1.3);
      for (final shape in ['concentric', 'eccentric', 'transition']) {
        await _tap(tester, 'cone-shape-$shape');
        if (shape == 'transition') await _tap(tester, 'cone-tparts-4');
        if (shape == 'concentric' &&
            find
                .byKey(const ValueKey('cone-show-ordinates'))
                .evaluate()
                .isNotEmpty) {
          await _tap(tester, 'cone-show-ordinates');
        }
        for (var i = 0; i < 40; i++) {
          await tester.drag(
              find.byKey(const ValueKey('cone-list')), const Offset(0, -500));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $shape');
        expect(find.byKey(const ValueKey('cone-share-text')), findsOneWidget,
            reason: '$lang $shape');
        await tester.drag(
            find.byKey(const ValueKey('cone-list')), const Offset(0, 40000));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    final keys = [
      'cone-shape-concentric',
      'cone-shape-eccentric',
      'cone-shape-transition',
      'cone-unit-mm',
      'cone-unit-in',
      'cone-mode-height',
      'cone-mode-angle',
      'cone-mode-slant',
      'cone-ref-outside',
      'cone-ref-inside',
      'cone-ref-mean',
      'cone-parts-1',
      'cone-parts-6',
      'cone-show-ordinates',
      'cone-paper-a4',
      'cone-paper-a3',
      'cone-pdf',
      'cone-share-text',
      'cone-appbar-share',
    ];
    for (final k in keys) {
      final size = tester.getSize(find.byKey(ValueKey(k)));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'cone-shape-transition');
    for (final k in [
      'cone-div-12',
      'cone-div-48',
      'cone-tparts-1',
      'cone-tparts-4',
      'tr-seam-sideA',
      'tr-seam-corner',
    ]) {
      final size = tester.getSize(find.byKey(ValueKey(k)));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    // Readout główny jest jeden (bursztyn).
    expect(
        tester
            .widgetList<Readout>(find.byType(Readout))
            .where((r) => r.hot)
            .length,
        1);
  });

  test('kafle: A3 mieszczą więcej niż A4, licznik bez wyjątku przy limicie',
      () {
    final a4 = WrapTileLayout.area(1000, 600);
    final a3 = WrapTileLayout.area(1000, 600, paper: TemplatePaper.a3);
    expect(a4.columns * a4.rows, greaterThan(a3.columns * a3.rows));
    expect(WrapTileLayout.sheetCount(1000, 600), a4.tiles.length);
    expect(WrapTileLayout.sheetCount(5000, 5000), greaterThan(100));
    expect(() => WrapTileLayout.area(5000, 5000), throwsArgumentError);
    // Zgodność wstecz: stary konstruktor (kolano) bez zmian.
    final strip = WrapTileLayout(1916.4, 163.4);
    expect(strip.tileWidthMm, WrapTileLayout.widthMm);
    expect(strip.columns, 8);
    expect(strip.rows, 2);
  });
}

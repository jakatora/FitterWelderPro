// Kolano segmentowe: ekran liczy na żywo, szablon PDF się renderuje.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:cut_list_app/domain/fitter/mitre_bend.dart';
import 'package:cut_list_app/features/mitre_bend/mitre_bend_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/wrap_template_pdf.dart';
import 'package:cut_list_app/widgets/readout.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {AppLanguage lang = AppLanguage.pl,
      double textScale = 1.0,
      double dpr = 1}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const MitreBendPage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('domyślnie DN150, 90°, 3 spoiny → cięcie 15°', (tester) async {
    await pump(tester);
    Finder hot(String v) =>
        find.descendant(of: find.byType(Readout), matching: find.text(v));
    expect(hot('15'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mitre-welds-4')));
    await tester.pump();
    expect(hot('11,25'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mitre-welds-1')));
    await tester.pump();
    // Jedno cięcie przy odcinku prostym 0 — komunikat zamiast wyniku.
    expect(
        find.textContaining('odcinek prosty musi być dłuższy'), findsOneWidget);
  });

  testWidgets('za mały promień — komunikat, bez wyniku', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('mitre-r-mm')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('mitre-radius')), '50');
    await tester.pump();
    expect(find.textContaining('Promień musi być większy'), findsOneWidget);
    expect(find.byKey(const ValueKey('mitre-pdf')), findsNothing);
  });

  testWidgets('wąski ekran, tekst ×1,3, wersja EN — bez wyjątków',
      (tester) async {
    await pump(tester, lang: AppLanguage.en, textScale: 1.3, dpr: 3);
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('mitre-pdf')), findsOneWidget);
  });

  test('szablon PDF: kafle i podziałki, DN600 mieści się w limicie', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final r = computeMitreBend(const MitreBendInput(
        odMm: 610, bendAngleDeg: 90, welds: 4, radiusMm: 915))!;
    final layout = WrapTileLayout(r.circumferenceMm, r.cutDropMm);
    expect(layout.columns, greaterThan(1));
    final bytes = await buildWrapTemplatePdf(
      WrapTemplateSpec(
        title: 'Test',
        summaryLines: const ['OD 610'],
        stripLengthMm: r.circumferenceMm,
        maxDepthMm: r.cutDropMm,
        depthAt: (x) => r.pointAt(x / r.circumferenceMm * 360).offsetMm,
        tableHeaders: const ['a', 'b'],
        tableRows: const [
          ['1', '2']
        ],
        instructions: const ['x'],
        note: 'n',
        tileHint: 'h',
      ),
      font: font('Roboto-Regular.ttf'),
      bold: font('Roboto-Bold.ttf'),
      en: false,
      generatedAt: DateTime(2026, 10, 17),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}

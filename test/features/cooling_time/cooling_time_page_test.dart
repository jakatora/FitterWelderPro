// Czas stygnięcia t8/5: ekran liczy na żywo, werdykt zmienia się z polami,
// wąski ekran z większą czcionką się mieści.
//
// Wartości z test/domain/welding/cooling_time_test.dart:
//  • domyślnie Q 1,0 · T0 100 °C · d 20 mm · wypełnienie czołowej (F3 0,9)
//    → 3D, t8/5 = 5,98 s → okno 5–15 s: w oknie;
//  • T0 20 °C → 0,9 · 5,2885 = 4,76 s → za krótko;
//  • dodatkowo d 10 mm → 2D, 0,9 · 11,3636 = 10,23 s → w oknie;
//  • okno max 8 s → za długo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/cooling_time.dart';
import 'package:cut_list_app/features/cooling_time/cooling_time_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
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
        home: const CoolingTimePage(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String resultText(WidgetTester tester) =>
      tester.widget<Readout>(find.byKey(const ValueKey('cool-result'))).value;

  Finder verdict(T85Verdict v) => find.byKey(ValueKey('cool-verdict-${v.name}'));

  testWidgets('zmiana T0, grubości i okna zmienia wynik i werdykt',
      (tester) async {
    await pump(tester);
    expect(resultText(tester), '6,0');
    expect(find.text('3D (d ≥ d_t)'), findsOneWidget);
    expect(verdict(T85Verdict.inWindow), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cool-t0')), '20');
    await tester.pump();
    expect(resultText(tester), '4,8');
    expect(verdict(T85Verdict.tooShort), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cool-d')), '10');
    await tester.pump();
    expect(resultText(tester), '10,2');
    expect(find.text('2D (d < d_t)'), findsOneWidget);
    expect(verdict(T85Verdict.inWindow), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cool-wmax')), '8');
    await tester.pump();
    expect(verdict(T85Verdict.tooLong), findsOneWidget);
  });

  testWidgets('przykład okna z karty producenta wpisuje min i max',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('cool-wmax')), '3');
    await tester.pump();
    expect(verdict(T85Verdict.invalidWindow), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('cool-preset-2')));
    await tester.tap(find.byKey(const ValueKey('cool-preset-2')));
    await tester.pump();
    // DILLIMAX 890: 5–12 s; t8/5 = 6,0 s.
    expect(find.text('12'), findsOneWidget);
    expect(verdict(T85Verdict.inWindow), findsOneWidget);
  });

  testWidgets('złącze teowe w 2D: wynik jako przedział', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('cool-t0')), '20');
    await tester.enterText(find.byKey(const ValueKey('cool-d')), '8');
    await tester.pump();
    await tester.ensureVisible(
        find.byKey(const ValueKey('cool-shape-filletTee')));
    await tester.tap(find.byKey(const ValueKey('cool-shape-filletTee')));
    await tester.pump();
    // F2 0,45–0,67: 7,99–11,90 s.
    expect(resultText(tester), '8,0–11,9');
  });

  testWidgets('Q z U, I, v i procesu — przez heat_input.dart', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('cool-mode-params')));
    await tester.pump();
    // MAG: 28 V · 250 A · 60 / 350 mm/min · 0,8 = 0,96 kJ/mm.
    expect(find.text('Q = 0,96 kJ/mm'), findsOneWidget);
    // Prędkość z podpowiedzi odwrotnej pojawia się tylko w tym trybie.
    expect(find.textContaining('mm/min'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('cool-process-saw')));
    await tester.pump();
    // SAW k = 1,0 → 1,20 kJ/mm.
    expect(find.text('Q = 1,20 kJ/mm'), findsOneWidget);
  });

  testWidgets('puste pole — komunikat zamiast wyniku', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('cool-q')), '');
    await tester.pump();
    expect(find.byKey(const ValueKey('cool-result')), findsNothing);
    expect(find.textContaining('Podaj energię liniową'), findsOneWidget);
  });

  testWidgets('wąski ekran, tekst ×1,3, wersja EN — bez wyjątków',
      (tester) async {
    await pump(tester, lang: AppLanguage.en, textScale: 1.3, dpr: 3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('cool-mode-params')));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('cool-chart')), findsOneWidget);
  });

  test('osie wykresu: ładne granice', () {
    expect(CoolingTimePainter.niceCeil(1.7), 2);
    expect(CoolingTimePainter.niceCeil(2.2), 2.5);
    expect(CoolingTimePainter.niceCeil(13), 20);
    expect(CoolingTimePainter.qTop(1.0), 2);
    expect(CoolingTimePainter.qTop(2.0), 5);
    expect(CoolingTimePainter.tTop(6, 15), 25);
  });
}

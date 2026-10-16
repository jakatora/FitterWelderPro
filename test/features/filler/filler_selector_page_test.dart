// Ekran „Dobór spoiwa”: wybór materiałów i procesu, wynik, karty stanu,
// zakładka rozcieńczenia, wersja EN i wąski telefon przy dużej czcionce.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/features/filler/filler_selector_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(1000, 4000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const FillerSelectorPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pickMaterial(
    WidgetTester tester, String side, String material) async {
  await tester.tap(find.byKey(ValueKey('filler-material-$side')));
  await tester.pumpAndSettle();
  final tile = find.byKey(ValueKey('filler-pick-$material'));
  // Lista w arkuszu buduje się leniwie — na wąskim telefonie przewiń.
  await tester.scrollUntilVisible(
    tile,
    120,
    scrollable: find
        .descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable))
        .first,
  );
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _process(WidgetTester tester, String process) async {
  await tester.tap(find.byKey(ValueKey('filler-process-$process')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('start: węglowa + węglowa, TIG → ER70S-6 / W3Si1 i disclaimer',
      (tester) async {
    await _pump(tester);

    expect(find.text('Dobór spoiwa'), findsOneWidget);
    expect(find.byKey(const ValueKey('filler-result')), findsOneWidget);
    expect(find.text('ER70S-6'), findsOneWidget);
    expect(find.text('W3Si1'), findsOneWidget);
    expect(find.text('EN ISO 636-A'), findsOneWidget);
    expect(find.text('AWS A5.18'), findsOneWidget);
    // Gaz TIG: I1 (argon); formowanie zwykle niepotrzebne.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('filler-gas')),
            matching: find.text('I1')),
        findsOneWidget);
    expect(find.text('Zwykle niepotrzebne'), findsOneWidget);
    // Wyraźny disclaimer: wiąże WPS.
    final disclaimer = find.byKey(const ValueKey('filler-disclaimer'));
    expect(disclaimer, findsOneWidget);
    expect(
        find.descendant(
            of: disclaimer,
            matching: find.textContaining('Wiążące spoiwo, gaz, podgrzewanie')),
        findsOneWidget);
  });

  testWidgets('węglowa + 304L → 309L; MMA bez gazu, formowanie wymagane',
      (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, 'b', 'ss304L');

    expect(find.text('ER309L'), findsOneWidget);
    expect(find.text('W 23 12 L'), findsOneWidget);
    expect(find.text('Wymagane'), findsOneWidget);
    expect(find.textContaining('ERNiCr-3'), findsOneWidget,
        reason: 'ostrzeżenie o pracy > ok. 315–370 °C');

    await _process(tester, 'mma');
    expect(find.text('E309L-16'), findsOneWidget);
    expect(find.text('E 23 12 L R'), findsOneWidget);
    expect(find.text('Nie dotyczy — elektroda otulona.'), findsOneWidget);

    await _process(tester, 'mig');
    expect(find.text('ER309LSi'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('filler-gas')),
            matching: find.text('M12')),
        findsOneWidget);
  });

  testWidgets('P91 + P91 → B9 / CrMo91 i PWHT w ostrzeżeniach',
      (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, 'a', 'p91');
    await _pickMaterial(tester, 'b', 'p91');

    expect(find.text('ER90S-B9 (ER90S-B91)'), findsOneWidget);
    expect(find.text('W CrMo91'), findsOneWidget);
    expect(find.textContaining('PWHT obowiązkowe'), findsOneWidget);

    // FCAW do P91 — aplikacja nie podaje, odsyła do WPS.
    await _process(tester, 'fcaw');
    expect(find.byKey(const ValueKey('filler-process-missing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('filler-result')), findsNothing);
  });

  testWidgets('aluminium + stal → nie spawa się łukowo', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, 'a', 'al5083');

    expect(find.byKey(const ValueKey('filler-not-weldable')), findsOneWidget);
    expect(find.text('Nie spawa się łukowo'), findsOneWidget);
    expect(find.byKey(const ValueKey('filler-result')), findsNothing);
    expect(find.byKey(const ValueKey('filler-disclaimer')), findsOneWidget);
  });

  testWidgets('6082 + 6082: dwa spoiwa z opisem kompromisu', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, 'a', 'al6xxx');
    await _pickMaterial(tester, 'b', 'al6xxx');

    expect(find.text('ER4043'), findsOneWidget);
    expect(find.text('ER5356'), findsOneWidget);
    expect(find.textContaining('Mniejsza skłonność do pęknięć'), findsOneWidget);
  });

  testWidgets('EN: same screen in English', (tester) async {
    await _pump(tester, lang: AppLanguage.en);

    expect(find.text('Filler metal selector'), findsOneWidget);
    expect(find.text('C-Mn carbon steel'), findsNWidgets(2));
    expect(find.text('Usually not needed'), findsOneWidget);
    expect(find.textContaining('The binding filler, gas, preheat'),
        findsOneWidget);
    expect(find.textContaining('Dobór'), findsNothing);
  });

  testWidgets('rozcieńczenie: równoważniki stopiwa 309L z węglową i 304L',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Rozcieńczenie'));
    await tester.pumpAndSettle();

    Future<void> put(String col, String el, String v) async {
      final f = find.byKey(ValueKey('dilution-$col-$el'));
      await tester.ensureVisible(f);
      await tester.enterText(f, v);
    }

    // A: stal węglowa; B: 304L; spoiwo: 309L (jak w schaeffler_test.dart).
    for (final (el, v) in [
      ('c', '0,2'),
      ('si', '0,3'),
      ('mn', '1'),
      ('cr', '0'),
      ('ni', '0'),
    ]) {
      await put('a', el, v);
    }
    for (final (el, v) in [
      ('c', '0,02'),
      ('si', '0,4'),
      ('mn', '1,5'),
      ('cr', '18,2'),
      ('ni', '8,1'),
    ]) {
      await put('b', el, v);
    }
    for (final (el, v) in [
      ('c', '0,02'),
      ('si', '0,8'),
      ('mn', '1,6'),
      ('cr', '23,5'),
      ('mo', '0,1'),
      ('ni', '13'),
    ]) {
      await put('filler', el, v);
    }
    final d = find.byKey(const ValueKey('dilution-percent'));
    await tester.ensureVisible(d);
    await tester.enterText(d, '30');
    await tester.pumpAndSettle();

    final results = find.byKey(const ValueKey('dilution-results'));
    // Spoiwo: 24,8 / 14,4; stopiwo: 20,2475 → 20,2 i 12,4725 → 12,5.
    for (final v in ['24,8', '14,4', '20,2', '12,5']) {
      expect(find.descendant(of: results, matching: find.text(v)),
          findsOneWidget,
          reason: v);
    }
    expect(find.textContaining('nie rysuje granic obszarów'), findsOneWidget);
  });

  testWidgets('rozcieńczenie: wartość > 100 % pokazuje błąd i nie liczy',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Rozcieńczenie'));
    await tester.pumpAndSettle();
    final d = find.byKey(const ValueKey('dilution-percent'));
    await tester.ensureVisible(d);
    await tester.enterText(d, '130');
    await tester.pumpAndSettle();
    expect(find.text('0–100'), findsOneWidget);
    expect(find.textContaining('Stopiwo: wpisz Cr i Ni'), findsOneWidget);
  });

  testWidgets('wąski telefon, czcionka 1,3 — bez przepełnień w obu zakładkach',
      (tester) async {
    await _pump(tester, size: const Size(360, 800), textScale: 1.3);
    await _pickMaterial(tester, 'b', 'superDuplex2507');
    expect(tester.takeException(), isNull);
    // Przewiń całą listę, żeby zbudować i rozłożyć każdą kartę.
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.byKey(const ValueKey('filler-disclaimer')), findsOneWidget);

    await tester.tap(find.text('Rozcieńczenie'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final dilutionList = find.byType(ListView).last;
    for (var i = 0; i < 8; i++) {
      await tester.drag(dilutionList, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

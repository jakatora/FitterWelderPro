// Ekran „Plan PWHT” — wpisanie grubości, werdykt, odczyty, wykres,
// udostępnianie (wstrzyknięte), język EN i duża czcionka na wąskim ekranie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/pwht/pwht_plan.dart';
import 'package:cut_list_app/domain/pwht/pwht_plan_text.dart';
import 'package:cut_list_app/features/pwht/pwht_cycle_chart.dart';
import 'package:cut_list_app/features/pwht/pwht_planner_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

class _ShareSpy {
  final List<(String, String)> texts = [];
  final List<(PwhtPlan, bool)> pdfs = [];

  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(PwhtPlan p, bool en) async => pdfs.add((p, en));
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  _ShareSpy? spy,
  Size size = const Size(900, 3200),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = spy ?? _ShareSpy();
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: PwhtPlannerPage(shareText: s.text, sharePdf: s.pdf),
    ),
  ));
  await tester.pump();
}

Future<void> _enterThickness(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('pwht-thickness')), text);
  await tester.pump();
}

Future<void> _pickMaterial(WidgetTester tester, PwhtMaterial m) async {
  final chip = find.byKey(ValueKey('pwht-material-${m.name}'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

String _verdictOf(PwhtMaterial m, double t, {bool english = false}) =>
    pwhtVerdictText(
      planPwht(
          PwhtInput(code: PwhtCode.values.first, material: m, thicknessMm: t))!,
      english: english,
    );

void main() {
  testWidgets('bez grubości: podpowiedź, bez werdyktu', (tester) async {
    await _pump(tester);
    expect(
        find.text('Wpisz grubość, żeby zobaczyć plan PWHT.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwht-verdict')), findsNothing);
    // Zastrzeżenie na górze i na dole.
    expect(find.text(pwhtDisclaimer(english: false)), findsNWidgets(2));
  });

  testWidgets('P-No 4, 25 mm: PWHT wymagane, odczyty i wykres', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, PwhtMaterial.p4);
    await _enterThickness(tester, '25');
    expect(find.text('PWHT wymagane — grubość > 16 mm'), findsOneWidget);
    expect(find.text('650–705'), findsOneWidget);
    expect(find.text('1 h 00 min'), findsOneWidget); // 1 h/25 mm
    // 335 °C/h ÷ (25/25,4 in / 2) = 340 → limit 335 °C/h.
    expect(find.text('335'), findsNWidgets(2));
    expect(find.byType(PwhtCycleChart), findsOneWidget);
    expect(find.byKey(const ValueKey('pwht-readout-cycle')), findsOneWidget);
    // Pasmo wytrzymania 3 × 25 mm.
    expect(find.text('75'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwht-readout-zones')), findsNothing);
  });

  testWidgets('P-No 1, 30 mm: zwolnienie warunkowe z listą warunków',
      (tester) async {
    await _pump(tester);
    await _enterThickness(tester, '30');
    expect(
        find.text('PWHT niewymagane tylko przy spełnieniu warunków '
            'zwolnienia'),
        findsOneWidget);
    expect(
        find.text('Podgrzewanie wstępne min. 95 °C przed spawaniem '
            '(grubość nominalna > 25 mm).'),
        findsOneWidget);
    // Parametry nadal pokazane — „jeśli PWHT jest wykonywane”.
    expect(find.text('595–650'), findsOneWidget);
    expect(find.textContaining('Parametry, jeśli PWHT jest wykonywane'),
        findsOneWidget);
  });

  testWidgets('średnica → strefy regulacji AWS D10.10', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, PwhtMaterial.p5a);
    await _enterThickness(tester, '25');
    await tester.enterText(find.byKey(const ValueKey('pwht-od')), '273');
    await tester.pump();
    final zones = find.byKey(const ValueKey('pwht-readout-zones'));
    expect(zones, findsOneWidget);
    expect(
        find.descendant(of: zones, matching: find.text('2')), findsOneWidget);
  });

  testWidgets('spoina szersza niż pasmo → ostrzeżenie', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, PwhtMaterial.p15e);
    await _enterThickness(tester, '4');
    await tester.enterText(find.byKey(const ValueKey('pwht-weld-width')), '14');
    await tester.pump();
    expect(
        find.byKey(const ValueKey('pwht-soak-weld-warning')), findsOneWidget);
  });

  testWidgets('B31.1: przełączenie normy zmienia źródło planu', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('pwht-code-asmeB311')));
    await tester.pump();
    await _pickMaterial(tester, PwhtMaterial.p3);
    await _enterThickness(tester, '20');
    expect(find.text('PWHT wymagane — grubość > 16 mm'), findsOneWidget);
    expect(
        find.text('Źródło: ASME B31.1-2022, Table 132.1.1-1'), findsOneWidget);
  });

  testWidgets('przecinek dziesiętny działa jak kropka', (tester) async {
    await _pump(tester);
    await _enterThickness(tester, '12,5');
    expect(find.text(_verdictOf(PwhtMaterial.p1, 12.5)), findsOneWidget);
  });

  testWidgets('zero → błąd pola, brak planu', (tester) async {
    await _pump(tester);
    await _enterThickness(tester, '0');
    expect(find.text('Wartość musi być > 0'), findsOneWidget);
    expect(find.byKey(const ValueKey('pwht-verdict')), findsNothing);
  });

  testWidgets('średnica ≤ 2 × grubość → błąd pola', (tester) async {
    await _pump(tester);
    await _enterThickness(tester, '20');
    await tester.enterText(find.byKey(const ValueKey('pwht-od')), '30');
    await tester.pump();
    expect(
        find.text('Średnica musi być większa niż 2 × grubość'), findsOneWidget);
    // Plan nadal liczony z grubości.
    expect(find.byKey(const ValueKey('pwht-verdict')), findsOneWidget);
  });

  testWidgets('P91 cienka ścianka: nadal wymagane', (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, PwhtMaterial.p15e);
    await _enterThickness(tester, '6');
    expect(find.text(_verdictOf(PwhtMaterial.p15e, 6)), findsOneWidget);
    expect(
        planPwht(const PwhtInput(
                code: PwhtCode.asmeB313,
                material: PwhtMaterial.p15e,
                thicknessMm: 6))!
            .verdict,
        PwhtVerdict.required);
  });

  testWidgets('austenityczna P-No 8: tabela nie wymaga, bez odczytów',
      (tester) async {
    await _pump(tester);
    await _pickMaterial(tester, PwhtMaterial.p8);
    await _enterThickness(tester, '30');
    expect(find.text(_verdictOf(PwhtMaterial.p8, 30)), findsOneWidget);
    expect(find.byKey(const ValueKey('pwht-readout-temp')), findsNothing);
    expect(find.byType(PwhtCycleChart), findsNothing);
  });

  testWidgets('Udostępnij wysyła pełny tekst planu z zastrzeżeniem',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _enterThickness(tester, '25');
    final btn = find.byKey(const ValueKey('pwht-share-text'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pump();
    expect(spy.texts, hasLength(1));
    final plan = planPwht(const PwhtInput(
        code: PwhtCode.asmeB313, material: PwhtMaterial.p1, thicknessMm: 25))!;
    expect(spy.texts.single.$1, pwhtPlanText(plan, english: false));
    expect(spy.texts.single.$1, contains('595–650 °C'));
    expect(spy.texts.single.$1, contains(pwhtDisclaimer(english: false)));
    expect(spy.texts.single.$2, 'Plan PWHT');

    final pdf = find.byKey(const ValueKey('pwht-share-pdf'));
    await tester.ensureVisible(pdf);
    await tester.tap(pdf);
    await tester.pump();
    expect(spy.pdfs, hasLength(1));
    expect(spy.pdfs.single.$2, isFalse);
    expect(spy.pdfs.single.$1.input.thicknessMm, 25);
  });

  testWidgets('EN: etykiety i werdykt po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('PWHT plan'), findsOneWidget);
    await _enterThickness(tester, '25');
    expect(find.text(_verdictOf(PwhtMaterial.p1, 25, english: true)),
        findsOneWidget);
    expect(find.text(pwhtDisclaimer(english: true)), findsNWidgets(2));
  });

  testWidgets('wąski ekran, czcionka 1,3: bez przepełnień', (tester) async {
    await _pump(tester, size: const Size(360, 5200), textScale: 1.3);
    for (final m in PwhtMaterial.values) {
      await _pickMaterial(tester, m);
      await _enterThickness(tester, '60');
      await tester.enterText(find.byKey(const ValueKey('pwht-od')), '273');
      await tester.enterText(
          find.byKey(const ValueKey('pwht-weld-width')), '30');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: m.name);
    }
  });

  testWidgets('cele dotyku chipów ≥ 48 dp', (tester) async {
    await _pump(tester);
    for (final m in PwhtMaterial.values) {
      final size =
          tester.getSize(find.byKey(ValueKey('pwht-material-${m.name}')));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: m.name);
    }
  });
}

// Ekran „Plan ściegów i elektrod”: przykład 8 × 168,3 × 7,11 (grań TIG,
// Ø2,5, Ø3,2) → 4 ściegi, 25 / 39 elektrod (z zapasem 27 / 42), weź 14 ×
// Ø2,5 i 23 × Ø3,2; przecinek = kropka; puste pole = komunikat; typoszereg
// DN / Sch; elektroda bez limitu; limit z WPS i kolejność pracy; blacha X
// i pachwina; założenia; zapis i uszkodzony zapis; EN; udostępnianie;
// 360×640 z tekstem ×1,5; cele dotyku ≥ 48 dp.
//
// Liczby jak w test/domain/pass_plan/pass_plan_test.dart. Limit z WPS
// 120 min: okno 120 − 30 = 90 min; złącze po złączu 4,251 × 1,5 = 6,4 → 6
// i 6,598 × 1,5 = 9,9 → 9; najpierw granie 6,644 × 1,5 = 9,97 → 9
// i 10,313 × 1,5 = 15,5 → 15.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/pass_plan/pass_plan.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_text.dart';
import 'package:cut_list_app/features/pass_plan/pass_plan_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

class _ShareSpy {
  final List<(String, String)> calls = [];
  Future<void> call(String text, String subject) async =>
      calls.add((text, subject));
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  _ShareSpy? spy,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  Map<String, Object>? prefs = const {},
}) async {
  // prefs == null — zostaw to, co zapisał poprzedni ekran.
  if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
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
      // UniqueKey: kolejne _pump w jednym teście = świeży stan ekranu.
      home: PassPlanPage(key: UniqueKey(), shareText: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _scrollable() => find
    .descendant(of: _key('pp-list'), matching: find.byType(Scrollable))
    .first;

/// Przewija listę, aż element powstanie i będzie widoczny (ListView buduje
/// leniwie).
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  if (f.evaluate().isEmpty) {
    await tester.drag(_scrollable(), const Offset(0, 100000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 400,
          scrollable: _scrollable(), maxScrolls: 300);
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await _reveal(tester, key);
  await tester.enterText(_key(key), text);
  await tester.pumpAndSettle();
}

/// Wybór z listy rozwijanej o kluczu [key] pozycji z tekstem [item].
Future<void> _pick(WidgetTester tester, String key, String item) async {
  await _tap(tester, key);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Finder _in(String key, String text) =>
    find.descendant(of: _key(key), matching: find.text(text));

Finder _inContaining(String key, String text) =>
    find.descendant(of: _key(key), matching: find.textContaining(text));

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

void main() {
  testWidgets(
      'przykład 8 × 168,3 × 7,11: 4 ściegi, 25 / 39 elektrod, weź 14 × Ø2,5 '
      'i 23 × Ø3,2', (tester) async {
    await _pump(tester);
    await _reveal(tester, 'pp-passes');
    expect(_in('pp-passes', '4'), findsOneWidget);
    expect(_inContaining('pp-passes', 'CZAS ZŁĄCZA 44 MIN'), findsOneWidget);
    await _reveal(tester, 'pp-layer-root');
    expect(_inContaining('pp-layer-root', 'Grań · TIG, pręt Ø2,4'),
        findsOneWidget);
    expect(_inContaining('pp-layer-root', '2 pręty'), findsOneWidget);
    await _reveal(tester, 'pp-layer-hot');
    expect(_inContaining('pp-layer-hot', 'elektroda Ø2,5 × 350 mm'),
        findsOneWidget);
    expect(_inContaining('pp-layer-hot', '1 ścieg'), findsOneWidget);
    expect(_inContaining('pp-layer-hot', '4 szt.'), findsOneWidget);
    await _reveal(tester, 'pp-layer-cap');
    expect(_in('pp-layer-cap', '2 ściegi'), findsOneWidget);
    expect(_inContaining('pp-layer-cap', '5 szt.'), findsOneWidget);
    expect(_key('pp-layer-fill'), findsNothing);

    await _reveal(tester, 'pp-supply-mma25');
    expect(_in('pp-supply-mma25', '25 szt. (z zapasem 27)'), findsOneWidget);
    await _reveal(tester, 'pp-supply-mma32');
    expect(_in('pp-supply-mma32', '39 szt. (z zapasem 42)'), findsOneWidget);
    await _reveal(tester, 'pp-supply-tig');
    expect(_inContaining('pp-supply-tig', '11 prętów (z zapasem 12)'),
        findsOneWidget);
    await _reveal(tester, 'pp-job-time');
    expect(_in('pp-job-time', '5 h 47 min'), findsOneWidget);

    await _reveal(tester, 'pp-take');
    expect(_in('pp-take', '37'), findsOneWidget);
    await _reveal(tester, 'pp-take-2.5');
    expect(_in('pp-take-2.5', '14 szt.'), findsOneWidget);
    await _reveal(tester, 'pp-take-3.2');
    expect(_in('pp-take-3.2', '23 szt.'), findsOneWidget);
    await _reveal(tester, 'pp-exposure-rule');
    expect(
        _inContaining('pp-exposure-rule',
            'Limit 4 h 00 min − 30 min zapasu = 3 h 30 min'),
        findsOneWidget);
    expect(_inContaining('pp-exposure-rule', 'bierz najwyżej 14 szt. Ø2,5'),
        findsOneWidget);
    await _reveal(tester, 'pp-portions');
    expect(_in('pp-portions', '2 porcje na całą robotę (5 h 47 min pracy)'),
        findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('przecinek i kropka dają ten sam plan', (tester) async {
    await _pump(tester);
    await _enter(tester, 'pp-od', '114,3');
    await _enter(tester, 'pp-wall', '6,02');
    await _reveal(tester, 'pp-job-time');
    final time = tester
        .widgetList<Text>(find.descendant(
            of: _key('pp-job-time'), matching: find.byType(Text)))
        .last
        .data;
    await _reveal(tester, 'pp-take');
    final take = tester
        .widgetList<Text>(
            find.descendant(of: _key('pp-take'), matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    await _enter(tester, 'pp-od', '114.3');
    await _enter(tester, 'pp-wall', '6.02');
    await _reveal(tester, 'pp-job-time');
    expect(_in('pp-job-time', time!), findsOneWidget);
    await _reveal(tester, 'pp-take');
    expect(
        tester
            .widgetList<Text>(find.descendant(
                of: _key('pp-take'), matching: find.byType(Text)))
            .map((t) => t.data)
            .toList(),
        take);
    // Inny rozmiar niż przykład — wynik naprawdę się zmienił.
    expect(time, isNot('5 h 47 min'));
  });

  testWidgets('puste pole to komunikat, nie wynik', (tester) async {
    await _pump(tester);
    await _enter(tester, 'pp-wall', '');
    await _reveal(tester, 'pp-problems');
    expect(_inContaining('pp-problems', 'Podaj grubość ścianki / blachy'),
        findsOneWidget);
    expect(_key('pp-passes'), findsNothing);
    expect(_key('pp-take'), findsNothing);
    expect(_key('pp-share'), findsNothing);
    await _enter(tester, 'pp-wall', '7,11');
    await _enter(tester, 'pp-gap', '');
    await _reveal(tester, 'pp-problems');
    expect(_inContaining('pp-problems', 'Podaj szczelinę'), findsOneWidget);
    await _enter(tester, 'pp-gap', '2,5');
    await _enter(tester, 'pp-count', '0');
    await _reveal(tester, 'pp-problems');
    expect(_inContaining('pp-problems', 'Liczba złączy'), findsOneWidget);
    await _enter(tester, 'pp-count', '8');
    await _enter(tester, 'pp-stub', '5');
    await _reveal(tester, 'pp-problems');
    expect(
        _inContaining('pp-problems', 'Ogarek od 20 do 150 mm'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    await _enter(tester, 'pp-stub', '50');
    await _reveal(tester, 'pp-passes');
    expect(_key('pp-problems'), findsNothing);
  });

  testWidgets(
      'typoszereg: DN100 → 114,3 × 6,02, Sch 80 → 8,56; ręczny OD '
      'zdejmuje wybór', (tester) async {
    await _pump(tester);
    expect(find.text('Sch 40 · 7,11'), findsOneWidget);
    await _pick(tester, 'pp-dn', 'DN100 · 4" · Ø114,3');
    expect(_fieldText(tester, 'pp-od'), '114,3');
    expect(_fieldText(tester, 'pp-wall'), '6,02');
    await _tap(tester, 'pp-sch-80');
    expect(_fieldText(tester, 'pp-wall'), '8,56');
    await _enter(tester, 'pp-od', '115');
    expect(_key('pp-sch-80'), findsNothing);
    await _reveal(tester, 'pp-passes');
    expect(find.textContaining('Ø115 × 8,56'), findsOneWidget);
  });

  testWidgets('elektroda nie zasadowa: bez limitu, weź całość z zapasem',
      (tester) async {
    await _pump(tester);
    await _pick(tester, 'pp-class', 'Nie zasadowa (rutylowa, celulozowa)');
    await _reveal(tester, 'pp-take-2.5');
    expect(_in('pp-take-2.5', '27 szt.'), findsOneWidget);
    expect(_in('pp-take-3.2', '42 szt.'), findsOneWidget);
    await _reveal(tester, 'pp-exposure-rule');
    expect(_inContaining('pp-exposure-rule', 'bez limitu czasu na powietrzu'),
        findsOneWidget);
    expect(_key('pp-portions'), findsNothing);
    expect(_key('pp-limit'), findsNothing);
  });

  testWidgets('limit z WPS 120 min, potem najpierw granie — więcej naraz',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'pp-limit', '120');
    await _reveal(tester, 'pp-exposure-rule');
    expect(
        _inContaining('pp-exposure-rule',
            'Limit 2 h 00 min − 30 min zapasu = 1 h 30 min'),
        findsOneWidget);
    await _reveal(tester, 'pp-take-2.5');
    expect(_in('pp-take-2.5', '6 szt.'), findsOneWidget);
    expect(_in('pp-take-3.2', '9 szt.'), findsOneWidget);
    await _tap(tester, 'pp-order-rootsFirst');
    await _reveal(tester, 'pp-take-2.5');
    expect(_in('pp-take-2.5', '9 szt.'), findsOneWidget);
    expect(_in('pp-take-3.2', '15 szt.'), findsOneWidget);
    // Grań elektrodą — wybór kolejności znika.
    await _tap(tester, 'pp-root-mma25');
    expect(_key('pp-order-rootsFirst'), findsNothing);
  });

  testWidgets('blacha X i pachwina: bez ściegu gorącego; rowek X tylko blacha',
      (tester) async {
    await _pump(tester);
    expect(_key('pp-groove-X'), findsNothing);
    await _tap(tester, 'pp-kind-plateButt');
    await _enter(tester, 'pp-wall', '20');
    await _tap(tester, 'pp-groove-X');
    await _reveal(tester, 'pp-hot-na');
    expect(_key('pp-hot-mma25'), findsNothing);
    await _reveal(tester, 'pp-layer-root');
    expect(_in('pp-layer-root', '2 ściegi'), findsOneWidget);
    expect(_key('pp-layer-hot'), findsNothing);
    // Powrót na rurę — rowek X zamienia się na V.
    await _tap(tester, 'pp-kind-pipeButt');
    expect(_key('pp-groove-X'), findsNothing);
    await _reveal(tester, 'pp-layer-hot');
    await _tap(tester, 'pp-kind-plateFillet');
    await _enter(tester, 'pp-throat', '3');
    await _reveal(tester, 'pp-passes');
    expect(_in('pp-passes', '1'), findsOneWidget);
    expect(_key('pp-groove-V'), findsNothing);
  });

  testWidgets('założenia: większy przekrój ściegu — mniej ściegów; Domyślne',
      (tester) async {
    await _pump(tester);
    await _reveal(tester, 'pp-bead-mma32');
    expect(find.textContaining('mm ściegu z elektrody Ø3,2 × 350 mm'),
        findsOneWidget);
    await _enter(tester, 'pp-bead-mma32', '30');
    await _reveal(tester, 'pp-passes');
    expect(_in('pp-passes', '3'), findsOneWidget);
    await _tap(tester, 'pp-reset-assumptions');
    expect(_fieldText(tester, 'pp-bead-mma32'), '18');
    await _reveal(tester, 'pp-passes');
    expect(_in('pp-passes', '4'), findsOneWidget);
    // Współczynnik jarzenia łuku MMA 15 % — dłuższy czas pracy.
    await _enter(tester, 'pp-arcon-mma', '15');
    await _reveal(tester, 'pp-job-time');
    expect(_in('pp-job-time', '5 h 47 min'), findsNothing);
  });

  testWidgets(
      'wejścia zapisują się i wracają; uszkodzony zapis → domyślne, '
      'informacja i kopia', (tester) async {
    await _pump(tester);
    await _enter(tester, 'pp-od', '114,3');
    await _enter(tester, 'pp-count', '12');
    await _tap(tester, 'pp-cap-mma25');
    await _pump(tester, prefs: null);
    expect(_fieldText(tester, 'pp-od'), '114,3');
    expect(_fieldText(tester, 'pp-count'), '12');
    await _reveal(tester, 'pp-layer-cap');
    expect(_inContaining('pp-layer-cap', 'Ø2,5 × 350 mm'), findsOneWidget);
    expect(_key('pp-load-notice'), findsNothing);

    await _pump(tester, prefs: {kPassPlanPrefsKey: 'zepsute'});
    expect(_key('pp-load-notice'), findsOneWidget);
    expect(_fieldText(tester, 'pp-od'), '168,3');
    await _reveal(tester, 'pp-passes');
    expect(_in('pp-passes', '4'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPassPlanCorruptPrefsKey), 'zepsute');
  });

  testWidgets('EN: teksty i kropka dziesiętna, te same liczby', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Pass and electrode plan'), findsOneWidget);
    expect(_fieldText(tester, 'pp-od'), '168.3');
    await _reveal(tester, 'pp-layer-cap');
    expect(_in('pp-layer-cap', '2 passes'), findsOneWidget);
    await _reveal(tester, 'pp-supply-mma32');
    expect(_in('pp-supply-mma32', '39 pcs (with reserve 42)'), findsOneWidget);
    await _reveal(tester, 'pp-take-3.2');
    expect(_in('pp-take-3.2', '23 pcs'), findsOneWidget);
    await _reveal(tester, 'pp-disclaimer');
    expect(
        find.textContaining('ESTIMATE for planning a shift'), findsOneWidget);
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _tap(tester, 'pp-share');
    expect(spy.calls, hasLength(1));
    final (text, subject) = spy.calls.single;
    expect(subject, 'Plan ściegów i elektrod');
    expect(text, contains('• Lico — elektroda Ø3,2 × 350 mm: 2 ściegi'));
    expect(text, contains('Weź z suszarki: Ø2,5 × 14 szt. · Ø3,2 × 23 szt.'));
    expect(text, contains(passPlanDisclaimer(en: false)));

    final spyEn = _ShareSpy();
    await _pump(tester, spy: spyEn, language: AppLanguage.en);
    await _tap(tester, 'pp-share');
    final (en, enSubject) = spyEn.calls.single;
    expect(enSubject, 'Pass and electrode plan');
    expect(en, contains('Take from the oven: Ø2.5 × 14 pcs · Ø3.2 × 23 pcs'));
  });

  testWidgets('wąski ekran 360×640, tekst ×1,5 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(360, 640), textScale: 1.5);
      expect(tester.takeException(), isNull);
      for (final k in [
        'pp-dn',
        'pp-sch-40',
        'pp-bevel-asme',
        'pp-class',
        'pp-src-hermeticPack',
        'pp-order-rootsFirst',
        'pp-bead-mma32',
        'pp-arcon-tig',
        'pp-passes',
        'pp-layer-root',
        'pp-layer-hot',
        'pp-layer-cap',
        'pp-supply-tig',
        'pp-job-time',
        'pp-take',
        'pp-take-3.2',
        'pp-exposure-rule',
        'pp-portions',
        'pp-share',
        'pp-sources',
        'pp-disclaimer',
      ]) {
        await _reveal(tester, k);
      }
      expect(tester.takeException(), isNull, reason: lang.name);
      // Długie wybory i stany: 450 mm, Ø4,0, rowek X, pachwina, błędy.
      await _tap(tester, 'pp-cap-mma40');
      await _tap(tester, 'pp-len-450');
      await _reveal(tester, 'pp-layer-cap');
      expect(_inContaining('pp-layer-cap', '× 450 mm'), findsOneWidget);
      await _reveal(tester, 'pp-supply-mma40');
      await _enter(tester, 'pp-limit', '12');
      await _reveal(tester, 'pp-below-one');
      await _tap(tester, 'pp-kind-plateButt');
      await _tap(tester, 'pp-groove-X');
      await _reveal(tester, 'pp-hot-na');
      await _tap(tester, 'pp-kind-pipeFillet');
      await _enter(tester, 'pp-throat', '');
      await _reveal(tester, 'pp-problems');
      expect(tester.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    final keys = [
      for (final k in kPassPlanJointKinds) 'pp-kind-${k.name}',
      'pp-dn',
      'pp-sch-40',
      'pp-od',
      'pp-wall',
      'pp-count',
      'pp-groove-V',
      'pp-groove-I',
      'pp-bevel-en',
      'pp-bevel-asme',
      'pp-angle',
      'pp-root-face',
      'pp-gap',
      for (final c in kRootChoices) 'pp-root-${c.name}',
      'pp-hot-none',
      for (final c in kHotChoices) 'pp-hot-${c.name}',
      for (final c in kFillChoices) 'pp-fill-${c.name}',
      for (final c in kCapChoices) 'pp-cap-${c.name}',
      'pp-len-350',
      'pp-len-450',
      'pp-rod-2.4',
      'pp-stub',
      'pp-reserve',
      'pp-class',
      'pp-src-oven',
      'pp-src-hermeticPack',
      'pp-limit',
      'pp-order-jointByJoint',
      'pp-order-rootsFirst',
      'pp-shift',
      'pp-reset-assumptions',
      'pp-bead-mma25',
      'pp-bead-mma32',
      'pp-arcon-tig',
      'pp-arcon-mma',
      'pp-share',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });
}

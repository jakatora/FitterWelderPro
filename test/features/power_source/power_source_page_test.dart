// Ekran „Spawarka: cykl pracy i przewody”: tabliczka → cykl pracy, poza
// zakresem źródła, przewód → spadek napięcia i werdykt, obciążalność, dobór
// przekroju, puste pole = komunikat, zapis tabliczki, wersja EN,
// udostępnianie (wstrzyknięte), 320×640 z tekstem ×1,3, cele dotyku ≥ 48 dp.
//
// Liczby (jak w test/domain/welding/power_source_test.dart):
//  • domyślna tabliczka 200/35, 160/60, 130/100 i 150 A → 62 %
//    (35·(200/150)² = 62,22), 6,2 min spawania, 3,8 min przerwy; praca
//    ciągła 130 A (z tabliczki); sam punkt 200/35 → 118 A; 250 A → poza
//    zakresem;
//  • 200 A, 25 + 25 m, 35 mm²: ΔU 7,09 → „7,1” V > 4 V, najdłuższa pętla
//    28 m, obciążalność 243 × 0,96 = 233 A; 70 mm² → 3,48 → „3,5” V;
//  • dobór 200 A / 50 m / 60 % / 30 °C → 70 mm² (spadek); 300 A, 2 + 2 m,
//    100 %, 40 °C → 70 mm² (nagrzewanie, 355 × 0,87 = 308 A).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/power_source.dart';
import 'package:cut_list_app/features/power_source/power_source_page.dart';
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
      home: PowerSourcePage(key: UniqueKey(), shareText: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _scrollable() => find
    .descendant(of: _key('ps-list'), matching: find.byType(Scrollable))
    .first;

/// Przewija listę, aż element powstanie i będzie widoczny (ListView buduje
/// leniwie).
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  if (f.evaluate().isEmpty) {
    // Element może być nad bieżącym widokiem — od góry w dół.
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

Finder _in(String key, String text) =>
    find.descendant(of: _key(key), matching: find.text(text));

Finder _inContaining(String key, String text) =>
    find.descendant(of: _key(key), matching: find.textContaining(text));

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

void main() {
  testWidgets(
      'tabliczka → cykl pracy: 150 A → 62 %, 6,2 min spawania, 3,8 min '
      'przerwy', (tester) async {
    await _pump(tester);
    expect(_in('ps-duty', '62'), findsOneWidget);
    expect(_in('ps-duty', 'DOPUSZCZALNY CYKL PRACY'), findsOneWidget);
    expect(_in('ps-weld-min', '6,2 min'), findsOneWidget);
    expect(_in('ps-rest-min', '3,8 min'), findsOneWidget);
    expect(_in('ps-duty-basis', 'szacunek z 200 A / 35 %'), findsOneWidget);
    expect(_in('ps-i100', '130 A'), findsOneWidget);
    // Prąd jak w tabliczce — wartość z tabliczki, nie szacunek.
    await _enter(tester, 'ps-current', '160');
    expect(_in('ps-duty', '60'), findsOneWidget);
    expect(_in('ps-duty-basis', 'tabliczka 160 A / 60 %'), findsOneWidget);
    // Przecinek i kropka.
    await _enter(tester, 'ps-current', '150,0');
    expect(_in('ps-duty', '62'), findsOneWidget);
    await _enter(tester, 'ps-current', '150.0');
    expect(_in('ps-duty', '62'), findsOneWidget);
  });

  testWidgets(
      '100 A: podstawa „tabliczka 130 A / 100 %” na ekranie i w tekście, '
      'nie szacunek', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _enter(tester, 'ps-current', '100');
    expect(_in('ps-duty', '100'), findsOneWidget);
    expect(_in('ps-weld-min', '10,0 min'), findsOneWidget);
    expect(_in('ps-rest-min', '0,0 min'), findsOneWidget);
    expect(_in('ps-duty-basis', 'tabliczka 130 A / 100 %'), findsOneWidget);
    expect(find.textContaining('szacunek z'), findsNothing);
    await _tap(tester, 'ps-share');
    final (text, _) = spy.calls.single;
    expect(text, contains('(z tabliczki: 130 A / 100 %)'));
    expect(text, isNot(contains('szacunek z')));
  });

  testWidgets(
      'sam punkt 200 A / 35 %: praca ciągła 118 A; 250 A — poza '
      'zakresem źródła', (tester) async {
    await _pump(tester);
    for (final k in [
      'ps-plate-i-2',
      'ps-plate-x-2',
      'ps-plate-i-3',
      'ps-plate-x-3'
    ]) {
      await _enter(tester, k, '');
    }
    await _reveal(tester, 'ps-i100');
    expect(_in('ps-i100', '118 A'), findsOneWidget);
    expect(_in('ps-duty', '62'), findsOneWidget);
    await _enter(tester, 'ps-current', '250');
    await _reveal(tester, 'ps-out-of-range');
    expect(_inContaining('ps-out-of-range', 'Poza zakresem źródła: 250 A'),
        findsOneWidget);
    expect(_inContaining('ps-out-of-range', '(200 A)'), findsOneWidget);
    expect(_key('ps-duty'), findsNothing);
    expect(_key('ps-weld-min'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('przewód 200 A, 50 m, 35 mm²: ΔU 7,1 V za dużo; 70 mm² — OK',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'ps-current', '200');
    await _reveal(tester, 'ps-loop');
    expect(_in('ps-loop', '50 m'), findsOneWidget);
    expect(_in('ps-cable-current', '200 A'), findsOneWidget);
    await _reveal(tester, 'ps-drop');
    expect(_in('ps-drop', '7,1'), findsOneWidget);
    expect(_inContaining('ps-drop-verdict', 'Za duży spadek: 7,1 V > 4 V'),
        findsOneWidget);
    await _reveal(tester, 'ps-max-loop');
    expect(_in('ps-max-loop', '28 m'), findsOneWidget);
    await _reveal(tester, 'ps-ampacity');
    expect(_in('ps-ampacity', '233 A'), findsOneWidget);
    expect(_inContaining('ps-heat-verdict', 'przekrój OK — 233 A ≥ 200 A'),
        findsOneWidget);
    // Grubszy przewód.
    await _tap(tester, 'ps-section-70');
    await _reveal(tester, 'ps-drop');
    expect(_in('ps-drop', '3,5'), findsOneWidget);
    expect(_inContaining('ps-drop-verdict', 'mieści się w progu 4 V'),
        findsOneWidget);
    // Wyższy próg — 35 mm² mieści się przy 7,5 V.
    await _tap(tester, 'ps-section-35');
    await _enter(tester, 'ps-drop-limit', '7,5');
    await _reveal(tester, 'ps-drop-verdict');
    expect(_inContaining('ps-drop-verdict', 'mieści się w progu 7,5 V'),
        findsOneWidget);
    // Za cienki na prąd: 16 mm² przy 60 % i 30 °C = 139 × 0,96 = 133 A.
    await _tap(tester, 'ps-section-16');
    await _reveal(tester, 'ps-heat-verdict');
    expect(_inContaining('ps-heat-verdict', 'przekrój za mały — 133 A < 200 A'),
        findsOneWidget);
  });

  testWidgets(
      'dobór przekroju: 70 mm² (spadek); krótko i 100 % — '
      'nagrzewanie', (tester) async {
    await _pump(tester);
    await _enter(tester, 'ps-current', '200');
    await _reveal(tester, 'ps-min-section');
    expect(_in('ps-min-section', '70'), findsOneWidget);
    expect(_in('ps-min-governs', 'spadek napięcia'), findsOneWidget);
    expect(_in('ps-min-drop', '3,5 V'), findsOneWidget);
    // 300 A, pętla 2 + 2 m, 100 %, do 40 °C.
    await _enter(tester, 'ps-current', '300');
    await _enter(tester, 'ps-lead-weld', '2');
    await _enter(tester, 'ps-lead-return', '2');
    await _enter(tester, 'ps-cable-duty', '100');
    await _tap(tester, 'ps-amb-40');
    await _reveal(tester, 'ps-min-section');
    expect(_in('ps-min-section', '70'), findsOneWidget);
    expect(_in('ps-min-governs', 'nagrzewanie'), findsOneWidget);
    expect(_in('ps-min-ampacity', '308 A'), findsOneWidget);
    // Za daleko: 200 A, 100 + 100 m — żaden do 95 mm².
    await _enter(tester, 'ps-current', '200');
    await _enter(tester, 'ps-lead-weld', '100');
    await _enter(tester, 'ps-lead-return', '100');
    await _reveal(tester, 'ps-min-none');
    expect(_inContaining('ps-min-none', 'Żaden przekrój do 95 mm²'),
        findsOneWidget);
    expect(_key('ps-min-section'), findsNothing);
  });

  testWidgets('puste pole to komunikat, nie wynik', (tester) async {
    await _pump(tester);
    await _enter(tester, 'ps-current', '');
    expect(_key('ps-duty'), findsNothing);
    expect(_inContaining('ps-duty-problems', 'Podaj prąd spawania'),
        findsOneWidget);
    await _reveal(tester, 'ps-cable-problems');
    expect(_inContaining('ps-cable-problems', 'Podaj prąd spawania na górze'),
        findsOneWidget);
    expect(_key('ps-drop'), findsNothing);
    expect(_key('ps-min-section'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    // Wiersz tabliczki z jednym polem — błąd wiersza.
    await _enter(tester, 'ps-current', '150');
    await _enter(tester, 'ps-plate-i-1', '');
    await _reveal(tester, 'ps-duty-problems');
    expect(_inContaining('ps-duty-problems', 'Wiersz 1: podaj prąd'),
        findsOneWidget);
    expect(_key('ps-duty'), findsNothing);
    // Zamienione pola — sprzeczna tabliczka.
    await _enter(tester, 'ps-plate-i-1', '35');
    await _enter(tester, 'ps-plate-x-1', '200');
    await _reveal(tester, 'ps-duty-problems');
    expect(_inContaining('ps-duty-problems', 'cykl pracy od 1 do 100 %'),
        findsOneWidget);
    await _enter(tester, 'ps-plate-i-1', '200');
    await _enter(tester, 'ps-plate-x-1', '80');
    await _reveal(tester, 'ps-duty-problems');
    expect(_inContaining('ps-duty-problems', 'Sprzeczna tabliczka'),
        findsOneWidget);
    // Puste długości przewodów.
    await _enter(tester, 'ps-lead-weld', '');
    await _reveal(tester, 'ps-cable-problems');
    expect(_inContaining('ps-cable-problems', 'przewodu spawalniczego'),
        findsOneWidget);
    expect(_key('ps-drop'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets(
      'tabliczka zapisuje się i wraca; uszkodzony zapis → domyślna '
      'i kopia', (tester) async {
    await _pump(tester);
    await _enter(tester, 'ps-plate-i-1', '250');
    await _enter(tester, 'ps-plate-x-1', '30');
    // Ponowne otwarcie ekranu — te same SharedPreferences.
    await _pump(tester, prefs: null);
    expect(_fieldText(tester, 'ps-plate-i-1'), '250');
    expect(_fieldText(tester, 'ps-plate-x-1'), '30');
    expect(_fieldText(tester, 'ps-plate-i-2'), '160');
    // 150 A: szacunki 83,3 / 68,3 / 75,1, tabliczka 160 A / 60 % → 68 %.
    expect(_in('ps-duty', '68'), findsOneWidget);

    await _pump(tester, prefs: {kPowerSourcePlatePrefsKey: 'zepsute'});
    expect(_fieldText(tester, 'ps-plate-i-1'), '200');
    expect(_in('ps-duty', '62'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlateCorruptPrefsKey), 'zepsute');
  });

  testWidgets('EN: teksty i kropka dziesiętna, te same liczby', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Welder: duty cycle and cables'), findsOneWidget);
    expect(_in('ps-duty', '62'), findsOneWidget);
    expect(_in('ps-weld-min', '6.2 min'), findsOneWidget);
    expect(_in('ps-rest-min', '3.8 min'), findsOneWidget);
    expect(_in('ps-duty-basis', 'estimate from 200 A / 35 %'), findsOneWidget);
    await _enter(tester, 'ps-current', '200');
    await _reveal(tester, 'ps-drop');
    expect(_in('ps-drop', '7.1'), findsOneWidget);
    expect(_inContaining('ps-drop-verdict', 'Drop too large: 7.1 V > 4 V'),
        findsOneWidget);
    await _reveal(tester, 'ps-min-governs');
    expect(_in('ps-min-governs', 'voltage drop'), findsOneWidget);
    await _reveal(tester, 'ps-disclaimer');
    expect(find.textContaining('ESTIMATE: the rating plate'), findsOneWidget);
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _enter(tester, 'ps-current', '200');
    await _tap(tester, 'ps-share');
    expect(spy.calls, hasLength(1));
    final (text, subject) = spy.calls.single;
    expect(subject, 'Spawarka: cykl pracy i przewody');
    expect(text, contains('Prąd spawania 200 A → cykl pracy 35 %'));
    expect(text, contains('(z tabliczki: 200 A / 35 %)'));
    expect(text, contains('ΔU = 7,1 V — POWYŻEJ progu 4 V'));
    expect(text, contains('Najmniejszy przekrój: 70 mm²'));
    expect(text, contains(powerSourceDisclaimer(en: false)));

    final spyEn = _ShareSpy();
    await _pump(tester, spy: spyEn, language: AppLanguage.en);
    await _tap(tester, 'ps-share');
    final (en, enSubject) = spyEn.calls.single;
    expect(enSubject, 'Welder: duty cycle and cables');
    expect(en, contains('duty cycle 62 %: 6.2 min welding, 3.8 min rest'));
    expect(en, contains('Continuous welding (100 %): up to 130 A'));
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(320, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await _reveal(tester, 'ps-duty-basis');
      await _reveal(tester, 'ps-i100');
      await _enter(tester, 'ps-current', '200');
      await _reveal(tester, 'ps-drop-verdict');
      await _reveal(tester, 'ps-heat-verdict');
      await _reveal(tester, 'ps-min-ampacity');
      await _reveal(tester, 'ps-tip-no-load');
      await _reveal(tester, 'ps-disclaimer');
      expect(tester.takeException(), isNull, reason: lang.name);
      await _tap(tester, 'ps-section-95');
      await _tap(tester, 'ps-amb-50');
      await _enter(tester, 'ps-current', '250');
      await _reveal(tester, 'ps-out-of-range');
      await _enter(tester, 'ps-lead-weld', '200');
      await _reveal(tester, 'ps-min-none');
      await _enter(tester, 'ps-current', '');
      await _reveal(tester, 'ps-duty-problems');
      await _reveal(tester, 'ps-cable-problems');
      expect(tester.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    final keys = [
      'ps-current',
      for (var k = 1; k <= kPlateRows; k++) ...[
        'ps-plate-i-$k',
        'ps-plate-x-$k',
      ],
      'ps-lead-weld',
      'ps-lead-return',
      for (final s in kCableSectionsMm2) 'ps-section-$s',
      'ps-cable-duty',
      for (final (t, _) in kCableAmbientFactors) 'ps-amb-$t',
      'ps-drop-limit',
      'ps-share',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });
}

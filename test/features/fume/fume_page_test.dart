// Ekran „Dymy spawalnicze i odciąg”: puste pola → komunikaty i UZUPEŁNIJ,
// składniki z NDS, kalkulator DallaValle (zasięg, kołnierz, poza zakresem,
// wymagana wydajność), jednostki bez wpływu na werdykt, próg prędkości
// tylko w górę, brak odciągu → nigdy zielono, komplet → OK, zapis wejść
// (bez listy), uszkodzony zapis, 360×640 z tekstem ×1,5, cele dotyku.
//
// Liczby jak w test/domain/fume/fume_capture_test.dart:
//  • Q 1200 m³/h, D 300 mm → 24 cm; z kołnierzem 28 cm;
//  • Q 1000 m³/h, D 150 mm → równanie 23 cm > 1,5·D = 22 cm → 22 cm,
//    „poza zakresem równania — przyjmij bliżej”;
//  • X 200 mm, D 300 mm → ≥ 848 m³/h (≥ 236 l/s); 848 wystarcza, 847 nie.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/fume/fume_checklist.dart';
import 'package:cut_list_app/domain/fume/fume_inputs.dart';
import 'package:cut_list_app/features/fume/fume_page.dart';
import 'package:cut_list_app/features/quotes/quote_widgets.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  Map<String, Object>? prefs,
}) async {
  if (prefs != null) SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const FumePage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

Finder get _scrollable => find
    .descendant(of: _key('fume-list'), matching: find.byType(Scrollable))
    .first;

/// Przewija listę, aż element powstanie i będzie widoczny — ListView buduje
/// leniwie, na wąskim ekranie dalsze sekcje nie istnieją.
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  if (f.evaluate().isEmpty) {
    await tester.drag(_scrollable, const Offset(0, 30000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 300,
          scrollable: _scrollable, maxScrolls: 400);
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

String _readout(WidgetTester tester, String key) =>
    tester.widget<Readout>(_key(key)).value;

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(_key(key)).data!;

String _notice(WidgetTester tester, String key) => tester
    .widget<QuoteNotice>(
        find.descendant(of: _key(key), matching: find.byType(QuoteNotice)))
    .text;

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

Future<String> _verdict(WidgetTester tester) async {
  await _reveal(tester, 'fume-verdict-level');
  return _text(tester, 'fume-verdict-level');
}

Future<void> _tickAll(WidgetTester tester) async {
  for (final c in kFumeChecks) {
    await _tap(tester, 'fume-check-${c.id}');
  }
}

/// Stal węglowa + MAG + odciąg Q 1200 m³/h, D 300 mm (24 cm).
Future<void> _goodSetup(WidgetTester tester) async {
  await _tap(tester, 'fume-mat-carbonSteel');
  await _tap(tester, 'fume-proc-migMag');
  await _tap(tester, 'fume-lev-present');
  await _enter(tester, 'fume-flow', '1200');
  await _enter(tester, 'fume-diameter', '300');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('puste pola — komunikaty zamiast wyniku, ocena UZUPEŁNIJ',
      (tester) async {
    await _pump(tester);
    expect(_key('fume-intro'), findsOneWidget);
    expect(_notice(tester, 'fume-intro'), contains('IARC'));
    expect(_key('fume-hazards-prompt'), findsOneWidget);
    expect(_key('fume-reach'), findsNothing);
    expect(await _verdict(tester), 'UZUPEŁNIJ');
    expect(_key('fume-reason-materialMissing'), findsOneWidget);
    expect(_key('fume-reason-levUnknown'), findsOneWidget);
    expect(_key('fume-reason-rpeMissing'), findsOneWidget);
    expect(_key('fume-reason-checklistOpen'), findsOneWidget);
  });

  testWidgets(
      'nierdzewka + MMA → Cr(VI) z NDS 0,005 i uwagą o 2025; '
      'aluminium → „sprawdź aktualny wykaz NDS”', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-mat-stainless');
    await _tap(tester, 'fume-proc-mma');
    await _reveal(tester, 'fume-agent-crVI');
    expect(_text(tester, 'fume-nds-crVI'), contains('0,005 mg/m³'));
    expect(_text(tester, 'fume-nds-ni'), contains('0,01 mg/m³'));
    await _reveal(tester, 'fume-crvi-note');
    expect(_notice(tester, 'fume-crvi-note'), contains('17.01.2025'));
    await _tap(tester, 'fume-mat-aluminium');
    await _tap(tester, 'fume-proc-tig');
    await _reveal(tester, 'fume-nds-al');
    expect(
        _text(tester, 'fume-nds-al'), contains('sprawdź aktualny wykaz NDS'));
    expect(_text(tester, 'fume-nds-o3'), contains('0,15 mg/m³'));
    await _reveal(tester, 'fume-gas-note');
    expect(_notice(tester, 'fume-gas-note'), contains('nie zatrzymują'));
  });

  testWidgets('kalkulator: 1200 m³/h, Ø 300 mm → 24 cm, z kołnierzem 28 cm',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-lev-present');
    expect(_key('fume-capture-prompt'), findsOneWidget);
    await _enter(tester, 'fume-flow', '1200');
    await _enter(tester, 'fume-diameter', '300');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '24');
    expect(_notice(tester, 'fume-capture-howto'), contains('24 cm'));
    await _tap(tester, 'fume-flange-yes');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '28');
  });

  testWidgets('poza zakresem równania — przyjmij bliżej, nie zielono',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-lev-present');
    await _enter(tester, 'fume-flow', '1000');
    await _enter(tester, 'fume-diameter', '150');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '22');
    expect(_key('fume-capture-howto'), findsNothing);
    final t = _notice(tester, 'fume-out-of-range');
    expect(t, contains('przyjmij bliżej'));
    expect(t, contains('23 cm'));
    expect(t, contains('22 cm'));
    await _reveal(tester, 'fume-reason-captureOutOfRange');
  });

  testWidgets(
      'odległość → potrzebna wydajność; zmiana jednostek nie zmienia '
      'werdyktu', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-lev-present');
    await _enter(tester, 'fume-flow', '848');
    await _enter(tester, 'fume-diameter', '300');
    await _enter(tester, 'fume-distance', '200');
    await _reveal(tester, 'fume-required-flow');
    expect(_text(tester, 'fume-required-flow'), '≥ 848 m³/h');
    expect(_notice(tester, 'fume-capture-verdict'), contains('wystarcza'));

    // m³/h → l/s: pole przeliczone w dół, werdykt bez zmian.
    await _tap(tester, 'fume-flow-unit-ls');
    expect(_field(tester, 'fume-flow'), '235,55');
    await _reveal(tester, 'fume-required-flow');
    expect(_text(tester, 'fume-required-flow'), '≥ 236 l/s');
    expect(_notice(tester, 'fume-capture-verdict'), contains('wystarcza'));

    // mm → cm: pola przeliczone dokładnie.
    await _tap(tester, 'fume-len-cm');
    expect(_field(tester, 'fume-diameter'), '30');
    expect(_field(tester, 'fume-distance'), '20');
    await _reveal(tester, 'fume-capture-verdict');
    expect(_notice(tester, 'fume-capture-verdict'), contains('wystarcza'));

    // Mniej powietrza → za mało.
    await _tap(tester, 'fume-flow-unit-m3h');
    await _enter(tester, 'fume-flow', '847');
    await _reveal(tester, 'fume-capture-verdict');
    expect(_notice(tester, 'fume-capture-verdict'), contains('Za mało'));
    expect(_notice(tester, 'fume-capture-verdict'), contains('848'));
  });

  testWidgets(
      'prędkość uchwycenia: poniżej 0,5 — błąd; szlifowanie podnosi '
      'do 2,5', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-lev-present');
    expect(_field(tester, 'fume-velocity'), '0,5');
    await _enter(tester, 'fume-flow', '1200');
    await _enter(tester, 'fume-diameter', '300');
    await _enter(tester, 'fume-velocity', '0,4');
    expect(find.textContaining('Nie mniej niż 0,5 m/s'), findsOneWidget);
    expect(_key('fume-reach'), findsNothing);
    await _enter(tester, 'fume-velocity', '1');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '16');
    await _tap(tester, 'fume-proc-grinding');
    expect(_field(tester, 'fume-velocity'), '2,5');
    await _reveal(tester, 'fume-vel-raised');
    // Powrót do spawania nie obniża progu sam z siebie.
    await _tap(tester, 'fume-proc-tig');
    expect(_field(tester, 'fume-velocity'), '2,5');
  });

  testWidgets('MIG/MAG: uwaga o osłonie gazowej; ponad 2,2 m/s — ostrzeżenie',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-proc-migMag');
    await _tap(tester, 'fume-lev-present');
    await _enter(tester, 'fume-flow', '1200');
    await _enter(tester, 'fume-diameter', '300');
    await _reveal(tester, 'fume-shield-note');
    expect(_notice(tester, 'fume-shield-note'), contains('osłonę gazową'));
    await _enter(tester, 'fume-flow', '1500');
    await _enter(tester, 'fume-diameter', '100');
    await _enter(tester, 'fume-distance', '50');
    await _reveal(tester, 'fume-shield-note');
    expect(_notice(tester, 'fume-shield-note'), contains('ACGIH'));
  });

  testWidgets('brak odciągu → nigdy zielono, nawet z TH3 i pełną listą',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-mat-carbonSteel');
    await _tap(tester, 'fume-proc-migMag');
    await _tap(tester, 'fume-lev-absent');
    expect(_notice(tester, 'fume-lev-absent-notice'), contains('HSE'));
    await _tap(tester, 'fume-rpe-th3');
    await _tickAll(tester);
    expect(await _verdict(tester), 'OSTROŻNIE');
    expect(_key('fume-reason-levAbsent'), findsOneWidget);
  });

  testWidgets('komplet → OK; otwarty punkt → UZUPEŁNIJ; FFP2 → STOP',
      (tester) async {
    await _pump(tester);
    await _goodSetup(tester);
    await _tap(tester, 'fume-rpe-th2');
    await _reveal(tester, 'fume-rpe-min');
    expect(_notice(tester, 'fume-rpe-min'), contains('spełnia minimum'));
    await _tickAll(tester);
    expect(await _verdict(tester), 'OK');
    await _tap(tester, 'fume-check-lev-close');
    expect(await _verdict(tester), 'UZUPEŁNIJ');
    await _tap(tester, 'fume-check-lev-close');
    await _tap(tester, 'fume-rpe-p2');
    expect(await _verdict(tester), 'STOP');
    expect(_key('fume-reason-rpeTooWeak'), findsOneWidget);
    // Nierdzewka: TH2 za mało (P3/TH3).
    await _tap(tester, 'fume-mat-stainless');
    await _tap(tester, 'fume-rpe-th2');
    expect(await _verdict(tester), 'STOP');
    await _tap(tester, 'fume-rpe-th3');
    expect(await _verdict(tester), 'OK');
  });

  testWidgets('„n/d” tylko przy punktach, które na to pozwalają',
      (tester) async {
    await _pump(tester);
    for (final c in kFumeChecks) {
      await _reveal(tester, 'fume-check-${c.id}');
      expect(
          _key('fume-na-${c.id}'), c.naAllowed ? findsOneWidget : findsNothing,
          reason: c.id);
    }
    await _tap(tester, 'fume-na-$kFumeCheckConfinedId');
    expect(find.textContaining('to nie jest przestrzeń zamknięta'),
        findsOneWidget);
    await _reveal(tester, 'fume-note-confined');
    expect(find.textContaining('Przestrzeń zamknięta: wejście i spawanie'),
        findsWidgets);
  });

  testWidgets('ostatnie wejścia wracają po ponownym otwarciu, lista nie',
      (tester) async {
    await _pump(tester);
    await _goodSetup(tester);
    await _tap(tester, 'fume-rpe-th3');
    await _tap(tester, 'fume-check-lev-close');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kFumeInputsPrefsKey), isNotNull);

    await _pump(tester);
    expect(_field(tester, 'fume-flow'), '1200');
    expect(_field(tester, 'fume-diameter'), '300');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '24');
    await _reveal(tester, 'fume-check-count');
    expect(_text(tester, 'fume-check-count'),
        startsWith('Otwarte: ${kFumeChecks.length} z ${kFumeChecks.length}'));
    expect(_key('fume-store-corrupt'), findsNothing);
  });

  testWidgets('uszkodzony zapis → wartości domyślne i informacja',
      (tester) async {
    await _pump(tester, prefs: {kFumeInputsPrefsKey: '{to nie jest json'});
    expect(_key('fume-store-corrupt'), findsOneWidget);
    expect(_key('fume-hazards-prompt'), findsOneWidget);
    await _tap(tester, 'fume-lev-present');
    expect(_field(tester, 'fume-velocity'), '0,5');
  });

  testWidgets('360×640, tekst ×1,5 — bez przepełnień (PL i EN)',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(360, 640), textScale: 1.5);
      expect(tester.takeException(), isNull, reason: lang.name);
      await _tap(tester, 'fume-mat-coated');
      await _tap(tester, 'fume-proc-cutting');
      await _reveal(tester, 'fume-agent-coatingOrganics');
      await _reveal(tester, 'fume-pb-note');
      expect(tester.takeException(), isNull, reason: lang.name);
      await _tap(tester, 'fume-lev-present');
      await _tap(tester, 'fume-shape-rectangular');
      await _enter(tester, 'fume-flow', '1000');
      await _enter(tester, 'fume-width', '200');
      await _enter(tester, 'fume-height', '100');
      await _enter(tester, 'fume-distance', '300');
      await _reveal(tester, 'fume-reach');
      await _reveal(tester, 'fume-capture-verdict');
      expect(tester.takeException(), isNull, reason: lang.name);
      await _tap(tester, 'fume-proc-tig');
      await _reveal(tester, 'fume-shield-note');
      await _tap(tester, 'fume-rpe-p2');
      await _reveal(tester, 'fume-apf');
      await _reveal(tester, 'fume-low-rpe-note');
      await _tap(tester, 'fume-na-lev-filter');
      await _reveal(tester, 'fume-verdict');
      await _reveal(tester, 'fume-note-measure');
      await _reveal(tester, 'fume-source-7');
      expect(tester.takeException(), isNull, reason: lang.name);
      await _tap(tester, 'fume-lev-absent');
      await _reveal(tester, 'fume-lev-absent-notice');
      expect(tester.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fume-lev-present');
    final keys = [
      'fume-mat-stainless',
      'fume-proc-mma',
      'fume-lev-present',
      'fume-lev-absent',
      'fume-flow',
      'fume-flow-unit-ls',
      'fume-shape-round',
      'fume-len-cm',
      'fume-diameter',
      'fume-flange-yes',
      'fume-velocity',
      'fume-vel-1.0',
      'fume-distance',
      'fume-rpe-th3',
      for (final c in kFumeChecks) 'fume-check-${c.id}',
      for (final c in kFumeChecks.where((c) => c.naAllowed)) 'fume-na-${c.id}',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  testWidgets('wersja EN: tytuł, ocena i jednostki po angielsku',
      (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Welding fume and extraction'), findsOneWidget);
    expect(await _verdict(tester), 'INCOMPLETE');
    await _tap(tester, 'fume-lev-present');
    expect(_field(tester, 'fume-velocity'), '0.5');
    await _enter(tester, 'fume-flow', '1200');
    await _enter(tester, 'fume-diameter', '300');
    await _reveal(tester, 'fume-reach');
    expect(_readout(tester, 'fume-reach'), '24');
    expect(_notice(tester, 'fume-capture-howto'), contains('within 24 cm'));
  });
}

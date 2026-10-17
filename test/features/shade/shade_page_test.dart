// Ekran „Filtr przyłbicy: stopień zaciemnienia”: proces + prąd → stopień
// EN 169 i ANSI/OSHA, zmiana procesu, granica przedziału, poza tabelą, puste
// pole, procesy gazowe, wersja EN, wąski ekran 320×640 z tekstem ×1,3, cele
// dotyku ≥ 48 dp, udostępnianie przez wstrzykniętą funkcję.
//
// Liczby (jak w test/domain/welding/shade_number_test.dart):
//  • MMA 120 A: EN 10 (100–150 A), ANSI 60–160 A min 8 / zalecany 10 →
//    zacznij od 10, nie jaśniej niż 9; MMA 100 A → 10 (granica: wyższy);
//  • TIG 100 A: EN 10 (70–125 A), ANSI 8 / 12 → zacznij od 12, nie jaśniej
//    niż 9; TIG 400 A: EN ≥ 13 (poza tabelą), ANSI 150–500 A → 14;
//  • MIG aluminium 100 A: poniżej tabeli EN (od 125 A) → 10;
//  • gaz: grubość 8 mm → ANSI 5–6; przepływ 150 l/h → EN 5.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/features/quotes/quote_widgets.dart';
import 'package:cut_list_app/features/shade/shade_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

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
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = spy ?? _ShareSpy();
  // Świeży stan ekranu przy ponownym pompowaniu w tym samym teście.
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
      home: ShadePage(shareText: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija listę, aż element powstanie i będzie widoczny — ListView buduje
/// leniwie, na wąskim ekranie dalsze sekcje nie istnieją.
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  final scrollable = find
      .descendant(of: _key('shade-list'), matching: find.byType(Scrollable))
      .first;
  if (f.evaluate().isEmpty) {
    await tester.drag(scrollable, const Offset(0, 20000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 200, scrollable: scrollable);
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

void main() {
  testWidgets('proces + prąd → stopień EN 169 i ANSI/OSHA', (tester) async {
    await _pump(tester);
    // Puste pole — komunikat, bez wyniku.
    expect(_key('shade-prompt'), findsOneWidget);
    expect(_key('shade-en'), findsNothing);
    expect(_key('shade-share'), findsNothing);

    await _enter(tester, 'shade-current', '120');
    expect(_key('shade-prompt'), findsNothing);
    expect(_readout(tester, 'shade-en'), '10');
    expect(
        tester.widget<Readout>(_key('shade-en')).unit, 'stopień · 100–150 A');
    expect(_text(tester, 'shade-ansi-suggested'), '10');
    expect(_text(tester, 'shade-osha-min'), '8');
    expect(_text(tester, 'shade-ansi-band'), '60–160 A');
    expect(_notice(tester, 'shade-safe'), contains('zacznij od 10'));
    expect(_notice(tester, 'shade-safe'), contains('nie jaśniej niż 9'));
    expect(_key('shade-en-below'), findsNothing);
    expect(_key('shade-en-above'), findsNothing);
  });

  testWidgets('zmiana procesu zmienia stopień; granica → wyższy',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'shade-current', '100');
    // MMA 100 A leży na granicy 9 | 10 → 10.
    expect(_readout(tester, 'shade-en'), '10');

    await _tap(tester, 'shade-proc-tig');
    expect(_readout(tester, 'shade-en'), '10');
    expect(tester.widget<Readout>(_key('shade-en')).unit, 'stopień · 70–125 A');
    expect(_text(tester, 'shade-ansi-suggested'), '12');
    expect(_notice(tester, 'shade-safe'), contains('zacznij od 12'));
    expect(_notice(tester, 'shade-safe'), contains('nie jaśniej niż 9'));

    await _tap(tester, 'shade-proc-migLight');
    expect(_readout(tester, 'shade-en'), '10');
    expect(_key('shade-en-below'), findsOneWidget);
    expect(_notice(tester, 'shade-en-below'), contains('125–500 A'));

    await _tap(tester, 'shade-proc-migHeavy');
    expect(_readout(tester, 'shade-en'), '9');
    expect(_key('shade-en-below'), findsNothing);
  });

  testWidgets('prąd poza tabelą → „co najmniej” i ostrzeżenie, nie w dół',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'shade-proc-tig');
    await _enter(tester, 'shade-current', '400');
    expect(_readout(tester, 'shade-en'), '≥ 13');
    expect(_key('shade-en-above'), findsOneWidget);
    expect(_notice(tester, 'shade-en-above'), contains('Co najmniej 13'));
    // ANSI GTAW 150–500 A zaleca 14 → start 14 > 13: uwaga o zakresie
    // przyłbic samościemniających.
    expect(_notice(tester, 'shade-safe'), contains('14'));
    expect(_key('shade-over13'), findsOneWidget);

    await _enter(tester, 'shade-current', '5');
    expect(_readout(tester, 'shade-en'), '8');
    expect(_key('shade-en-below'), findsOneWidget);
    expect(_notice(tester, 'shade-en-below'), contains('nie dobieraj go'));
  });

  testWidgets(
      'puste i nieczytelne pole — komunikat zamiast wyniku; '
      'przecinek i kropka', (tester) async {
    await _pump(tester);
    await _enter(tester, 'shade-current', '0');
    expect(_key('shade-en'), findsNothing);
    expect(find.text('Wpisz liczbę większą od 0.'), findsOneWidget);

    await _enter(tester, 'shade-current', ',');
    expect(_key('shade-en'), findsNothing);
    expect(find.text('Wpisz liczbę większą od 0.'), findsOneWidget);

    await _enter(tester, 'shade-current', '');
    expect(_key('shade-en'), findsNothing);
    expect(_key('shade-prompt'), findsOneWidget);

    await _enter(tester, 'shade-current', '99,5');
    expect(_readout(tester, 'shade-en'), '9');
    await _enter(tester, 'shade-current', '150.5');
    expect(_readout(tester, 'shade-en'), '11');
  });

  testWidgets('gaz: grubość → ANSI, przepływ → EN 169', (tester) async {
    await _pump(tester);
    await _tap(tester, 'shade-proc-gasWelding');
    expect(_key('shade-current'), findsNothing);
    expect(_key('shade-prompt'), findsOneWidget);

    await _enter(tester, 'shade-thickness', '8');
    expect(_readout(tester, 'shade-ansi-main'), '5–6');
    expect(_text(tester, 'shade-osha-min'), '5');
    expect(_notice(tester, 'shade-safe'), contains('zacznij od 6'));

    await _enter(tester, 'shade-flow', '150');
    expect(_readout(tester, 'shade-en'), '5');
    expect(_key('shade-ansi-main'), findsNothing);

    await _tap(tester, 'shade-proc-oxyCutting');
    // Te same pola: 150 l/h tlenu — poniżej tabeli EN (900–8000 l/h) → 5.
    expect(_readout(tester, 'shade-en'), '5');
    expect(_key('shade-en-below'), findsOneWidget);
  });

  testWidgets('wersja EN — te same liczby', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Welding filter: shade number'), findsOneWidget);
    await _enter(tester, 'shade-current', '120');
    expect(_readout(tester, 'shade-en'), '10');
    expect(tester.widget<Readout>(_key('shade-en')).unit, 'shade · 100–150 A');
    expect(_notice(tester, 'shade-safe'), contains('start at 10'));
    expect(_notice(tester, 'shade-safe'), contains('not lighter than 9'));
    await _tap(tester, 'shade-proc-plasmaWelding');
    await _enter(tester, 'shade-current', '1.5');
    expect(_readout(tester, 'shade-en'), '4');
    expect(tester.widget<Readout>(_key('shade-en')).unit, 'shade · 1.5–6 A');
  });

  testWidgets('tabela EN 169 procesu podświetla bieżący przedział',
      (tester) async {
    await _pump(tester);
    await _reveal(tester, 'shade-row');
    expect(
        find.descendant(of: _key('shade-row'), matching: find.text('< 60 A')),
        findsOneWidget);
    await _tap(tester, 'shade-proc-tig');
    await _reveal(tester, 'shade-row');
    expect(
        find.descendant(
            of: _key('shade-row'), matching: find.text('300–350 A')),
        findsOneWidget);
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _enter(tester, 'shade-current', '700');
    await _reveal(tester, 'shade-over13');
    await _reveal(tester, 'shade-sources');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'shade-proc-plasmaCutting');
    await _enter(tester, 'shade-current', '40');
    await _reveal(tester, 'shade-en-below');
    await _reveal(tester, 'shade-note-skin');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'shade-proc-oxyCutting');
    await _enter(tester, 'shade-thickness', '30');
    await _reveal(tester, 'shade-row');
    expect(tester.takeException(), isNull);
    // Ta sama ścieżka po angielsku.
    await _pump(tester,
        language: AppLanguage.en, size: const Size(320, 640), textScale: 1.3);
    await _enter(tester, 'shade-current', '700');
    await _reveal(tester, 'shade-en-above');
    await _reveal(tester, 'shade-sources');
    await _tap(tester, 'shade-proc-gasWelding');
    await _enter(tester, 'shade-flow', '900');
    await _reveal(tester, 'shade-note-adf');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    await _enter(tester, 'shade-current', '120');
    final keys = [
      for (final p in [
        'mma',
        'mag',
        'migHeavy',
        'migLight',
        'tig',
        'arcGouging',
        'plasmaCutting',
        'plasmaWelding',
        'gasWelding',
        'oxyCutting',
      ])
        'shade-proc-$p',
      'shade-current',
      'shade-share',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'shade-proc-gasWelding');
    for (final k in ['shade-flow', 'shade-thickness']) {
      await _reveal(tester, k);
      expect(
          tester.getSize(_key(k)).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });

  testWidgets('udostępnianie — wstrzyknięta funkcja dostaje te same liczby',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _tap(tester, 'shade-proc-tig');
    await _enter(tester, 'shade-current', '100');
    await _tap(tester, 'shade-share');
    expect(spy.calls, hasLength(1));
    final (text, subject) = spy.calls.single;
    expect(subject, 'Stopień zaciemnienia filtra');
    expect(text, contains('Proces: 141 TIG'));
    expect(text, contains('Prąd: 100 A'));
    expect(text, contains('EN 169: 10 (70–125 A'));
    expect(text, contains('zalecany 12 · minimum OSHA 8'));
    expect(text, contains('nie jaśniej niż 9'));

    // Po angielsku — temat i tekst EN.
    final spyEn = _ShareSpy();
    await _pump(tester, language: AppLanguage.en, spy: spyEn);
    await _enter(tester, 'shade-current', '120');
    await _tap(tester, 'shade-share');
    expect(spyEn.calls.single.$2, 'Welding filter shade');
    expect(spyEn.calls.single.$1, contains('Current: 120 A'));
    expect(spyEn.calls.single.$1, contains('EN 169: 10 (100–150 A'));
  });
}

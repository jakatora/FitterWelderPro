// Ekran „Symbole spawalnicze”: czytnik składa zdanie z tego, co spawacz
// wskaże, zakładki ściągi renderują się na telefonie i przy dużym tekście.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/features/weld_symbols/weld_symbols_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Widget _app({AppLanguage lang = AppLanguage.pl, double textScale = 1.0}) =>
    AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const WeldSymbolsPage(),
      ),
    );

/// Telefon 1080 × 2400 przy gęstości 3 → 360 × 800 dp.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

String _sentence(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('ws-sentence'))).data!;

Finder _scrollableOf(String listKey) => find
    .descendant(
        of: find.byKey(ValueKey(listKey)), matching: find.byType(Scrollable))
    .first;

/// Przewija listę [listKey] od góry, aż [target] będzie widoczny (lista
/// buduje elementy leniwie — poza ekranem ich nie ma).
Future<void> _reveal(WidgetTester tester, Finder target,
    {String listKey = 'ws-builder-list'}) async {
  final scrollable = _scrollableOf(listKey);
  await tester.drag(scrollable, const Offset(0, 8000));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(target, 120, scrollable: scrollable);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await _reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await _reveal(tester, f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab =
      find.descendant(of: find.byType(TabBar), matching: find.text(label));
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('czytnik: domyślnie pachwina a5 po stronie strzałki',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Symbole spawalnicze'), findsOneWidget);
    expect(find.byKey(const ValueKey('ws-drawing')), findsOneWidget);
    expect(_sentence(tester), 'Spoina pachwinowa a5 po stronie strzałki.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('czytnik: wybór elementów zmienia zdanie (przykład z rysunku)',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    // Symbol na linii przerywanej (system A) = strona przeciwna.
    await _tap(tester, 'ws-side-other');
    expect(_sentence(tester), 'Spoina pachwinowa a5 po stronie przeciwnej.');
    await _tap(tester, 'ws-side-arrow');

    // Przerywana 3 × 50 (100), dookoła, montażowa.
    await _tap(tester, 'ws-intermittent');
    expect(_sentence(tester),
        'Spoina pachwinowa a5 po stronie strzałki, przerywana.');
    await _type(tester, 'ws-count', '3');
    await _type(tester, 'ws-element', '50');
    await _type(tester, 'ws-gap', '100');
    expect(_sentence(tester),
        'Spoina pachwinowa a5 po stronie strzałki, przerywana 3 × 50 (100).');
    await _tap(tester, 'ws-all-around');
    await _tap(tester, 'ws-field');
    expect(
        _sentence(tester),
        'Spoina pachwinowa a5 po stronie strzałki, przerywana 3 × 50 (100), '
        'dookoła, montażowa.');
    // Kółko „dookoła” przy spoinie nieciągłej — ostrzeżenie na górze listy.
    await _reveal(tester, find.textContaining('nieciągłej'));
    expect(find.textContaining('nieciągłej'), findsOneWidget);

    // Rozwidlenie: proces 111.
    await _type(tester, 'ws-process', '111');
    expect(_sentence(tester), endsWith('montażowa, proces 111 (MMA).'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('czytnik: spoina czołowa — liczba to głębokość wtopienia',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _tap(tester, 'ws-kind-singleV');
    expect(_sentence(tester),
        'Spoina na V po stronie strzałki, głębokość wtopienia 5 mm.');
    await _type(tester, 'ws-size', '');
    expect(
        _sentence(tester), 'Spoina na V po stronie strzałki, pełny przetop.');

    // Podkładka dostępna tylko przy czołowej z jednej strony.
    await _tap(tester, 'ws-backing-permanent');
    expect(
        _sentence(tester),
        'Spoina na V po stronie strzałki, pełny przetop, '
        'na podkładce stałej (M).');
    await _tap(tester, 'ws-side-both');
    expect(find.byKey(const ValueKey('ws-backing-permanent')), findsNothing);
    expect(_sentence(tester), 'Spoina na V po obu stronach, pełny przetop.');
    expect(tester.takeException(), isNull);
  });

  testWidgets('czytnik: system B — etykiety „pod / nad linią”, to samo zdanie',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _reveal(tester, find.text('Na linii przerywanej'));
    expect(find.text('Na linii przerywanej'), findsOneWidget);
    await _reveal(tester, find.text('B: jedna linia'));
    await tester.tap(find.text('B: jedna linia'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.text('Nad linią'));
    expect(find.text('Na linii przerywanej'), findsNothing);
    expect(find.text('Nad linią'), findsOneWidget);
    await _tap(tester, 'ws-side-other');
    expect(_sentence(tester), 'Spoina pachwinowa a5 po stronie przeciwnej.');
  });

  testWidgets('czytnik po angielsku', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(lang: AppLanguage.en));
    await tester.pumpAndSettle();
    expect(find.text('Welding symbols'), findsOneWidget);
    expect(_sentence(tester), 'Fillet weld a5 on the arrow side.');
    await _tap(tester, 'ws-field');
    expect(_sentence(tester), 'Fillet weld a5 on the arrow side, field weld.');
  });

  testWidgets('wymiary: przelicznik a5 → z 7,07, z7 → a 4,95', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await _openTab(tester, 'Wymiary');
    const list = 'ws-dimensions-list';
    final result = find.byKey(const ValueKey('ws-conv-result'));
    await _reveal(tester, result, listKey: list);
    expect(find.descendant(of: result, matching: find.text('z 7,07')),
        findsOneWidget);
    await _reveal(tester, find.text('Mam z'), listKey: list);
    await tester.tap(find.text('Mam z'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ws-conv-input'));
    await _reveal(tester, input, listKey: list);
    await tester.enterText(input, '7');
    await tester.pumpAndSettle();
    await _reveal(tester, result, listKey: list);
    expect(find.descendant(of: result, matching: find.text('a 4,95')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ściąga: symbole podstawowe z nazwami PL', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _openTab(tester, 'Symbole');
    expect(find.text('Spoina pachwinowa'), findsOneWidget);
    await _reveal(tester, find.text('Spoina na ½U (J)'),
        listKey: 'ws-basic-list');
    expect(find.text('Spoina na ½U (J)'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('wszystkie zakładki renderują się na telefonie, tekst ×$scale',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(textScale: scale));
      await tester.pumpAndSettle();

      const tabs = {
        'Symbole': 'ws-basic-list',
        'Uzupełniające': 'ws-supplementary-list',
        'Linia i strony': 'ws-reference-list',
        'Wymiary': 'ws-dimensions-list',
        'Czytnik': 'ws-builder-list',
      };
      for (final MapEntry(key: tab, value: listKey) in tabs.entries) {
        await _openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
        // Przewiń do końca — karty i rysunki niżej też muszą się ułożyć.
        for (var i = 0; i < 12; i++) {
          await tester.drag(_scrollableOf(listKey), const Offset(0, -600));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tab, krok $i');
        }
      }
      expect(find.byType(Scaffold), findsOneWidget);
    });
  }
}

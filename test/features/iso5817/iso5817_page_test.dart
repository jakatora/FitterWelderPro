// Ekran „Odbiór spoin ISO 5817”: wpisanie t i pomiaru zmienia werdykt,
// wybór poziomu, długość niezgodności, wybór pozycji z listy i z menu,
// udostępnienie protokołu, EN i skala tekstu 1,3.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/features/iso5817/iso5817_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Widget _app(
  Widget child, {
  AppLanguage language = AppLanguage.pl,
  double textScale = 1.0,
}) =>
    AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, appChild) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: appChild!,
        ),
        home: child,
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Text _headlineWidget(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('iso5817-headline')));

Future<String> _verdict(WidgetTester tester) async {
  await _reveal(tester, find.byKey(const ValueKey('iso5817-headline')));
  return _headlineWidget(tester).data!;
}

/// ListView buduje elementy leniwie — element poza ekranem może nie istnieć.
/// Przewijamy na górę i w dół, aż się pojawi.
Future<void> _reveal(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, 20000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      f,
      300,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await _reveal(tester, f);
  await tester.enterText(f, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await _reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wpisanie t i pomiaru zmienia werdykt (podtopienie 1.7)',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const Iso5817Page()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('iso5817-disclaimer')), findsOneWidget);
    expect(await _verdict(tester), 'Podaj grubość t');

    await _enter(tester, 'iso5817-t', '10');
    expect(await _verdict(tester), 'Wpisz zmierzoną wartość');

    await _enter(tester, 'iso5817-measured', '0,4');
    expect(await _verdict(tester), 'Mieści się w C (limit 0,5 mm)');
    expect(_headlineWidget(tester).style!.color, kPass);
    expect(find.text('Spełnia również B (limit 0,5 mm)'), findsOneWidget);

    await _enter(tester, 'iso5817-measured', '0,8');
    expect(await _verdict(tester),
        'Przekracza C (limit 0,5 mm), mieści się w D (limit 1 mm)');
    expect(_headlineWidget(tester).style!.color, kWarn);

    await _enter(tester, 'iso5817-measured', '1,2');
    expect(await _verdict(tester), 'Niedopuszczalne — przekracza też D (limit 1 mm)');
    expect(_headlineWidget(tester).style!.color, kFail);

    // t ≤ 3 mm: inna kolumna tablicy 1 (C krótkie 0,1·t, D krótkie 0,2·t).
    await _enter(tester, 'iso5817-t', '2');
    expect(find.text('Zakres tablicy 1: 0,5–3 mm'), findsOneWidget);
    expect(await _verdict(tester),
        'Niedopuszczalne — przekracza też D (limit 0,4 mm)');
    await _enter(tester, 'iso5817-measured', '0,15');
    expect(await _verdict(tester), 'Mieści się w C (limit 0,2 mm)');

    // Poziom B: w cienkim zakresie podtopienie niedopuszczalne.
    await _tap(tester, find.byKey(const ValueKey('iso5817-level-B')));
    expect(await _verdict(tester),
        'Niedopuszczalne w B, mieści się w C (limit 0,2 mm)');

    // Niezgodność długa — C i D dopuszczają tylko krótkie.
    await _tap(tester, find.byKey(const ValueKey('iso5817-short')));
    expect(await _verdict(tester),
        'Niedopuszczalne — niezgodność długa, a limity dotyczą tylko '
        'krótkich');

    // t < 0,5 mm — poza zakresem normy.
    await _enter(tester, 'iso5817-t', '0,4');
    expect(await _verdict(tester), 't < 0,5 mm — poza zakresem EN ISO 5817');
  });

  testWidgets(
      'spoina pachwinowa: pozycja z listy, werdykt i protokół do udostępnienia',
      (tester) async {
    _phone(tester);
    String? sharedText;
    String? sharedSubject;
    await tester.pumpWidget(_app(Iso5817Page(
      clock: () => DateTime(2026, 10, 17),
      onShare: (text, subject) async {
        sharedText = text;
        sharedSubject = subject;
      },
    )));
    await tester.pumpAndSettle();

    // Bez werdyktu nie ma czego udostępniać.
    final share = find.byKey(const ValueKey('iso5817-share'));
    expect(tester.widget<OutlinedButton>(share).onPressed, isNull);

    await _tap(tester, find.text('Pachwinowa'));
    expect(find.byKey(const ValueKey('iso5817-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('iso5817-broot')), findsNothing);
    await _enter(tester, 'iso5817-t', '8');
    await _enter(tester, 'iso5817-a', '5');

    // Pozycja 1.21 wybrana dotknięciem karty na liście.
    await _tap(tester, find.byKey(const ValueKey('iso5817-card-1.21')));
    await _enter(tester, 'iso5817-measured', '3');
    expect(await _verdict(tester),
        'Przekracza C (limit 2 mm), mieści się w D (bez limitu)');

    await _tap(tester, share);
    expect(sharedSubject, 'Odbiór spoiny ISO 5817 — 1.21');
    final lines = sharedText!.split('\n');
    expect(lines, contains('Data: 2026-10-17'));
    expect(lines, contains('Spoina pachwinowa · t = 8 mm · a = 5 mm'));
    expect(lines,
        contains('Niezgodność: 1.21 Za duża grubość spoiny pachwinowej '
            '(ISO 6520-1: 5214)'));
    expect(lines, contains('Pomiar: h = 3 mm'));
    expect(lines,
        contains('Wynik: Przekracza C (limit 2 mm), mieści się w D '
            '(bez limitu)'));
    expect(sharedText, contains('EN ISO 5817:2014'));
    expect(sharedText, contains('nie ocenia metalurgii'));
  });

  testWidgets('wybór z menu: kąt przejścia lica 1.12 mierzony w stopniach',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const Iso5817Page()));
    await tester.pumpAndSettle();
    await _enter(tester, 'iso5817-t', '10');

    await _tap(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('1.12 · Nieprawidłowy kąt przejścia lica').last);
    await tester.pumpAndSettle();

    expect(find.text('Zmierzony kąt α (°)'), findsOneWidget);
    await _enter(tester, 'iso5817-measured', '120');
    expect(await _verdict(tester), 'Mieści się w C (min. 110°)');
    await _enter(tester, 'iso5817-measured', '100');
    expect(await _verdict(tester),
        'Nie spełnia C (min. 110°), mieści się w D (min. 90°)');

    // Zmiana pozycji czyści pomiar — 100 (°) nie może zostać ocenione jako
    // 100 mm podtopienia.
    await _tap(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('1.7 · Podtopienie ciągłe / przerywane').last);
    await tester.pumpAndSettle();
    expect(await _verdict(tester), 'Wpisz zmierzoną wartość');
    final measured = find.byKey(const ValueKey('iso5817-measured'));
    await _reveal(tester, measured);
    expect(tester.widget<TextField>(measured).controller!.text, isEmpty);
  });

  testWidgets(
      'initialItemId: start na wybranej pozycji i rodzaju spoiny; null i '
      'nieznany — jak dotąd', (tester) async {
    _phone(tester);
    Finder item(String kind, String id) =>
        find.byKey(ValueKey('iso5817-item-$kind-$id'));

    // Bez parametru: 1.7, spoina czołowa (zachowanie bez zmian).
    await tester.pumpWidget(_app(const Iso5817Page()));
    await tester.pumpAndSettle();
    await _reveal(tester, item('butt', '1.7'));
    expect(item('butt', '1.7'), findsOneWidget);

    // Pozycja tylko dla spoin czołowych.
    await tester.pumpWidget(_app(const Iso5817Page(
        key: ValueKey('p-1.14'), initialItemId: '1.14')));
    await tester.pumpAndSettle();
    await _reveal(tester, item('butt', '1.14'));
    expect(item('butt', '1.14'), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('iso5817-broot')));
    expect(find.byKey(const ValueKey('iso5817-broot')), findsOneWidget);
    await _enter(tester, 'iso5817-t', '10');
    await _enter(tester, 'iso5817-measured', '0,5');
    // 1.14 poziom C dla t > 3: h ≤ 0,1·t, maks. 1 mm → 1 mm.
    expect(await _verdict(tester), 'Mieści się w C (limit 1 mm)');

    // Pozycja tylko dla spoin pachwinowych — rodzaj przełącza się sam.
    await tester.pumpWidget(_app(const Iso5817Page(
        key: ValueKey('p-1.12-fillet'), initialItemId: '1.12-fillet')));
    await tester.pumpAndSettle();
    await _reveal(tester, item('fillet', '1.12-fillet'));
    expect(item('fillet', '1.12-fillet'), findsOneWidget);
    await _reveal(tester, find.byKey(const ValueKey('iso5817-a')));
    expect(find.byKey(const ValueKey('iso5817-a')), findsOneWidget);
    await _reveal(tester, find.text('Zmierzony kąt α (°)'));
    expect(find.text('Zmierzony kąt α (°)'), findsOneWidget);

    // Nieznany identyfikator — start jak bez parametru.
    await tester.pumpWidget(_app(const Iso5817Page(
        key: ValueKey('p-x'), initialItemId: 'x.99')));
    await tester.pumpAndSettle();
    await _reveal(tester, item('butt', '1.7'));
    expect(item('butt', '1.7'), findsOneWidget);
  });

  testWidgets('EN i skala tekstu 1,3 renderują się bez błędów',
      (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(const Iso5817Page(),
        language: AppLanguage.en, textScale: 1.3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Weld acceptance ISO 5817'), findsOneWidget);
    expect(await _verdict(tester), 'Enter thickness t');

    await _enter(tester, 'iso5817-t', '10');
    await _enter(tester, 'iso5817-measured', '0.4');
    expect(await _verdict(tester), 'Within C (limit 0.5 mm)');

    // Przewinięcie całej listy pozycji przy dużej czcionce.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

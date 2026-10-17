// Ekran „Gięcie rurek”: liczy na żywo, trzy tryby, dodawanie i usuwanie
// gięć, ostrzeżenia, cale, wersja EN, wąski ekran z dużą czcionką, cele
// dotyku ≥ 48 dp, udostępnianie przez wstrzykniętą funkcję i zapis ostatniej
// rurki.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/features/tube_bending/tube_bending_page.dart';
import 'package:cut_list_app/features/tube_bending/tube_bending_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';
import 'package:cut_list_app/widgets/readout.dart';

class _Spy {
  final List<(String, String)> texts = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
}

Future<_Spy> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 8000),
  double textScale = 1.0,
  Map<String, Object>? prefs,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? {});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spy = _Spy();
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: TubeBendingPage(shareText: spy.text),
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

Finder _in(String key, String text) => find.descendant(
    of: find.byKey(ValueKey(key)), matching: find.text(text), matchRoot: true);

Finder _cut(String value) => find.descendant(
    of: find.byKey(const ValueKey('tb-cut')), matching: find.text(value));

/// Na wąskim ekranie lista buduje tylko to, co blisko widoku — najpierw
/// przewiń, aż pole powstanie (w dół, a gdy to nie pomoże — w górę).
Future<void> _reveal(WidgetTester tester, Finder f) async {
  final list = find.descendant(
      of: find.byKey(const ValueKey('tb-list')),
      matching: find.byType(Scrollable));
  for (final delta in const [300.0, -300.0]) {
    if (f.evaluate().isNotEmpty) break;
    try {
      await tester.scrollUntilVisible(f, delta,
          scrollable: list.first, maxScrolls: 80);
    } on StateError {
      // Nie znalazł w tym kierunku — spróbuj w drugim.
    } on TestFailure {
      // j.w.
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await _reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await _reveal(tester, f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

void main() {
  testWidgets('domyślnie 3 gięcia: cięcie 686 mm, znaczniki 112 / 318 / 544',
      (tester) async {
    await _pump(tester);
    // 720 − (16,31 + 1,64 + 16,31) = 685,75 → w górę do 0,5 → 686.
    expect(_cut('686'), findsOneWidget);
    expect(_in('tb-exact', '685,75 mm'), findsOneWidget);
    expect(_in('tb-mark-1-value', '112 mm'), findsOneWidget);
    expect(_in('tb-mark-2-value', '318 mm'), findsOneWidget);
    expect(_in('tb-mark-3-value', '544 mm'), findsOneWidget);
    expect(find.byKey(const ValueKey('tb-sketch')), findsOneWidget);
    expect(find.byKey(const ValueKey('tb-warning')), findsNothing);
    expect(find.byKey(const ValueKey('tb-reference')), findsOneWidget);
  });

  testWidgets('jedno gięcie: wpisanie → wynik; kąt 0 / 180 / pusty → komunikat',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'tb-mode-single');
    // 200 + 150 − 16,31 = 333,69 → 334.
    expect(_cut('334'), findsOneWidget);
    expect(_in('tb-arc', '59,69 mm'), findsOneWidget);
    expect(_in('tb-setback', '38 mm'), findsOneWidget);
    expect(_in('tb-gain', '16,31 mm'), findsOneWidget);
    expect(_in('tb-mark-1-value', '162 mm'), findsOneWidget);
    await _enter(tester, 'tb-s-angle', '45');
    // 350 − 1,64 = 348,36 → 348,5.
    expect(_cut('348,5'), findsOneWidget);
    expect(_in('tb-setback', '15,74 mm'), findsOneWidget);
    for (final bad in ['0', '180', '']) {
      await _enter(tester, 'tb-s-angle', bad);
      expect(find.byKey(const ValueKey('tb-problem')), findsOneWidget,
          reason: bad);
      expect(find.textContaining('Kąt gięcia od 0° do 180°'), findsOneWidget,
          reason: bad);
      expect(find.byKey(const ValueKey('tb-cut')), findsNothing, reason: bad);
      expect(find.textContaining('NaN'), findsNothing);
    }
    await _tap(tester, 'tb-s-angle-90');
    expect(_cut('334'), findsOneWidget);
    await _enter(tester, 'tb-clr', '');
    expect(find.textContaining('Podaj promień gięcia po osi'), findsOneWidget);
  });

  testWidgets('odsadzka H 100 przy 45° → 141,42; przestrzenna 300 + 400',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'tb-mode-offset');
    expect(_in('tb-o-travel', '141,42 mm'), findsOneWidget);
    expect(_in('tb-o-shrink', '41,42 mm'), findsOneWidget);
    // 200 + 141,42 + 200 − 2 × 1,64 = 538,15 → 538,5.
    expect(_cut('538,5'), findsOneWidget);
    expect(find.byKey(const ValueKey('tb-o-true')), findsNothing);
    await _enter(tester, 'tb-o-h', '300');
    await _enter(tester, 'tb-o-spread', '400');
    expect(_in('tb-o-true', '500 mm'), findsOneWidget);
    expect(_in('tb-o-roll', '53,1°'), findsOneWidget);
    expect(_in('tb-o-travel', '707,11 mm'), findsOneWidget);
    await _tap(tester, 'tb-o-angle-30');
    // 500 / sin 30° = 1000.
    expect(_in('tb-o-travel', '1000 mm'), findsOneWidget);
    await _enter(tester, 'tb-o-angle', '120');
    expect(find.textContaining('Kąt odsadzki: więcej niż 0°'), findsOneWidget);
  });

  testWidgets('dodanie i usunięcie gięcia', (tester) async {
    await _pump(tester);
    await _tap(tester, 'tb-add');
    expect(find.byKey(const ValueKey('tb-angle-4')), findsOneWidget);
    expect(_field(tester, 'tb-seg-5'), '100');
    // 820 − (34,25 + 16,31) = 769,44 → 769,5.
    expect(_cut('769,5'), findsOneWidget);
    expect(find.byKey(const ValueKey('tb-mark-4')), findsOneWidget);
    // Usuń gięcie 2 (45°) razem z odcinkiem za nim (250).
    await _tap(tester, 'tb-remove-2');
    expect(find.byKey(const ValueKey('tb-angle-4')), findsNothing);
    expect(_field(tester, 'tb-angle-2'), '90');
    expect(_field(tester, 'tb-seg-3'), '120');
    // 150 + 200 + 120 + 100 − 3 × 16,31 = 521,07 → 521,5.
    expect(_cut('521,5'), findsOneWidget);
    await _tap(tester, 'tb-remove-1');
    await _tap(tester, 'tb-remove-1');
    // Zostaje jedno gięcie — bez przycisku usuwania.
    expect(find.byKey(const ValueKey('tb-remove-1')), findsNothing);
    expect(find.byKey(const ValueKey('tb-angle-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nakładające się łuki i za krótka prosta → ostrzeżenia',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'tb-seg-2', '50');
    // 50 < 38 + 15,74 — łuki gięć 1 i 2 zachodzą.
    expect(find.byKey(const ValueKey('tb-warning')), findsOneWidget);
    expect(find.textContaining('Łuki gięć 1 i 2 zachodzą na siebie'),
        findsOneWidget);
    expect(find.textContaining('co najmniej 53,74 mm'), findsOneWidget);
    expect(find.byKey(const ValueKey('tb-cut')), findsNothing);
    expect(find.byKey(const ValueKey('tb-share')), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('tb-appbar-share')))
            .onPressed,
        isNull);

    await _enter(tester, 'tb-seg-2', '200');
    await _enter(tester, 'tb-min-straight', '150');
    // Proste 112 / 146,26 / 196,26 / 82: trzy za krótkie, wynik zostaje.
    expect(find.byKey(const ValueKey('tb-warning')), findsOneWidget);
    expect(find.textContaining('Prosta między gięciami 1 i 2: 146,26 mm'),
        findsOneWidget);
    expect(find.textContaining('Prosta na początku rurki: 112 mm'),
        findsOneWidget);
    expect(find.textContaining('Prosta na końcu rurki: 82 mm'), findsOneWidget);
    expect(_cut('686'), findsOneWidget);
  });

  testWidgets('dogięcie i przesunięcie znacznika', (tester) async {
    await _pump(tester);
    await _enter(tester, 'tb-springback', '2');
    // Długość bez zmian, kąt „gnij do” 92° / 47°.
    expect(_cut('686'), findsOneWidget);
    expect(find.text('92°'), findsWidgets);
    expect(find.text('47°'), findsOneWidget);
    await _enter(tester, 'tb-marker-offset', '-10');
    expect(_in('tb-mark-1-value', '102 mm'), findsOneWidget);
    expect(_cut('686'), findsOneWidget);
  });

  testWidgets('cale: pola i wyniki przeliczone, powrót do mm', (tester) async {
    await _pump(tester);
    await _tap(tester, 'tb-unit-in');
    expect(_field(tester, 'tb-clr'), '1,4961');
    expect(_field(tester, 'tb-seg-1'), '5,9055');
    // 685,75 mm = 26,998" → w górę do 1/32" = 27".
    expect(_cut('27"'), findsOneWidget);
    // 112 mm = 4,409" → 4 13/32".
    expect(_in('tb-mark-1-value', '4 13/32"'), findsOneWidget);
    await _tap(tester, 'tb-unit-mm');
    expect(_field(tester, 'tb-clr'), '38');
    expect(_field(tester, 'tb-seg-1'), '150');
    expect(_cut('686'), findsOneWidget);
  });

  testWidgets('po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Tube bending'), findsOneWidget);
    expect(find.text('CUT LENGTH'), findsOneWidget);
    expect(_cut('686'), findsOneWidget);
    expect(_in('tb-exact', '685.75 mm'), findsOneWidget);
    await _enter(tester, 'tb-angle-2', '0');
    expect(find.textContaining('Bend 2: bend angle between 0° and 180°'),
        findsOneWidget);
    await _enter(tester, 'tb-angle-2', '45');
    await _enter(tester, 'tb-seg-2', '50');
    expect(find.textContaining('overlap'), findsOneWidget);
  });

  testWidgets('wąski ekran 320 × 640, tekst × 1,3 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      // Świeży ekran (bez stanu z poprzedniego języka).
      await tester.pumpWidget(const SizedBox());
      await _pump(tester,
          language: lang, size: const Size(320, 640), textScale: 1.3);
      for (final mode in ['multi', 'single', 'offset']) {
        await _tap(tester, 'tb-mode-$mode');
        if (mode == 'offset') await _enter(tester, 'tb-o-spread', '50');
        await _enter(tester, 'tb-springback', '2');
        for (var i = 0; i < 40; i++) {
          await tester.drag(
              find.byKey(const ValueKey('tb-list')), const Offset(0, -500));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$lang $mode');
        expect(find.byKey(const ValueKey('tb-share')), findsOneWidget,
            reason: '$lang $mode');
        await tester.drag(
            find.byKey(const ValueKey('tb-list')), const Offset(0, 40000));
        await tester.pumpAndSettle();
      }
      // Ostrzeżenie też musi się zmieścić.
      await _tap(tester, 'tb-mode-multi');
      await _enter(tester, 'tb-seg-2', '50');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$lang warning');
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    void check(List<String> keys) {
      for (final k in keys) {
        final size = tester.getSize(find.byKey(ValueKey(k)));
        expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
        expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      }
    }

    check([
      'tb-mode-single',
      'tb-mode-offset',
      'tb-mode-multi',
      'tb-unit-mm',
      'tb-unit-in',
      'tb-remove-1',
      'tb-remove-3',
      'tb-add',
      'tb-share',
      'tb-appbar-share',
    ]);
    await _tap(tester, 'tb-mode-single');
    check(['tb-s-angle-90', 'tb-s-angle-45', 'tb-s-angle-30', 'tb-s-angle-60']);
    await _tap(tester, 'tb-mode-offset');
    check(['tb-o-angle-30', 'tb-o-angle-45', 'tb-o-angle-60']);
    // Jeden wynik główny (bursztyn).
    expect(
        tester
            .widgetList<Readout>(find.byType(Readout))
            .where((r) => r.hot)
            .length,
        1);
  });

  testWidgets('udostępnianie tabeli znaczników przez wstrzykniętą funkcję',
      (tester) async {
    final spy = await _pump(tester);
    await _tap(tester, 'tb-share');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Gięcie rurki — znaczniki');
    expect(text, contains('CLR 38 mm'));
    expect(text, contains('Długość cięcia: 686 mm'));
    expect(text, contains('150 · 200 · 250 · 120 mm'));
    expect(text, contains('1. 90° — znacznik 112 mm · wierzchołek 150 mm'));
    expect(text, contains('2. 45°, bez obrotu'));
    expect(text, contains('znacznik 318 mm'));
    // RIDGID 45°: środek łuku 2 = 317,95 + 14,92 = 332,87 → 333.
    expect(text, contains('środek łuku 333 mm'));
    expect(text, contains('w górę'));
    await _tap(tester, 'tb-appbar-share');
    expect(spy.texts, hasLength(2));
    // Obrót 180° w treści.
    await _enter(tester, 'tb-rot-2', '180');
    await _tap(tester, 'tb-share');
    expect(spy.texts.last.$1, contains('obróć rurkę o 180°'));
  });

  testWidgets('zapis ostatniej rurki: po ponownym otwarciu te same dane',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'tb-add');
    await _enter(tester, 'tb-angle-4', '30');
    await _tap(tester, 'tb-unit-in');
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(TubeBendingStore.key);
    expect(saved, isNotNull);
    // Ponowne otwarcie z tym zapisem.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, prefs: {TubeBendingStore.key: saved!});
    expect(_field(tester, 'tb-angle-4'), '30');
    expect(_field(tester, 'tb-clr'), '1,4961');
    expect(find.byKey(const ValueKey('tb-damaged')), findsNothing);
  });

  testWidgets('uszkodzony zapis: komunikat, kopia, wartości domyślne',
      (tester) async {
    await _pump(tester, prefs: {TubeBendingStore.key: 'zepsute'});
    expect(find.byKey(const ValueKey('tb-damaged')), findsOneWidget);
    expect(_cut('686'), findsOneWidget);
    await _enter(tester, 'tb-seg-1', '160');
    expect(find.byKey(const ValueKey('tb-damaged')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TubeBendingStore.corruptKey), 'zepsute');
    expect(decodeTubeBending(prefs.getString(TubeBendingStore.key)).intact,
        isTrue);
  });
}

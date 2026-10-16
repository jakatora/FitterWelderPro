// Ekran „Ciężar stali": wybór profilu i długości zmienia masę, dodanie do
// listy (zapis w SharedPreferences), suma z zapasem i koszt, udostępnianie
// (wstrzyknięte), wąski ekran z dużą czcionką.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/quotes/quote_calculator.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

class _ShareSpy {
  final List<(String, String)> texts = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
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
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SteelWeightPage(shareText: s.text),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Wartość głównego odczytu (Readout z kluczem [key]).
Finder _readout(String key, String value) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(value));

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('wybór profilu i długości zmienia masę', (tester) async {
    await _pump(tester);
    // Domyślnie: HEB 200 × 6000 mm, 1 szt. → 61,3 · 6 = 367,8 kg.
    expect(_readout('sw-mass', '367,8'), findsOneWidget);
    expect(find.text('h 200 · b 200 · tw 9 · tf 15 · r 18 mm'), findsOneWidget);

    await _tapKey(tester, 'sw-shape-ipe');
    // IPE 200: 22,4 · 6 = 134,4 kg.
    expect(_readout('sw-mass', '134,4'), findsOneWidget);
    expect(find.text('22,40 kg/m'), findsOneWidget);
    expect(find.text('0,768 m²/m'), findsOneWidget);

    await _tapKey(tester, 'sw-len-12000');
    expect(_readout('sw-mass', '268,8'), findsOneWidget);

    await _tapKey(tester, 'sw-section-ipe');
    await tester.tap(find.text('IPE 240').last);
    await tester.pumpAndSettle();
    // IPE 240: 30,7 · 12 = 368,4 kg.
    expect(_readout('sw-mass', '368,4'), findsOneWidget);

    // Długość wpisana ręcznie: 2500 mm × 2 szt. = 5 m → 153,5 kg.
    await tester.enterText(find.byKey(const ValueKey('sw-len-1')), '2500');
    await tester.enterText(find.byKey(const ValueKey('sw-count')), '2');
    await tester.pump();
    expect(_readout('sw-mass', '153,5'), findsOneWidget);
  });

  testWidgets('kątownik: rozmiar z listy, grubość z chipów', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sw-shape-angleEqual');
    // L 50×50×5: 3,77 · 6 = 22,62 kg.
    expect(_readout('sw-mass', '22,6'), findsOneWidget);
    await _tapKey(tester, 'sw-angle-t-6');
    // L 50×50×6: 4,47 · 6 = 26,82 kg.
    expect(_readout('sw-mass', '26,8'), findsOneWidget);
    expect(find.text('a 50 · b 50 · t 6 · r1 7 · r2 3,5 mm'), findsOneWidget);
  });

  testWidgets('blacha i płaskownik — z wymiarów', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sw-shape-plate');
    await tester.enterText(find.byKey(const ValueKey('sw-plate-t')), '8');
    await tester.pump();
    // 8 × 1500 × 3000 mm · 7850 = 282,6 kg; 62,8 kg/m².
    expect(_readout('sw-mass', '282,6'), findsOneWidget);
    expect(find.text('62,80 kg/m²'), findsOneWidget);

    await _tapKey(tester, 'sw-shape-flat');
    // Płaskownik 80×10 × 6 m = 37,68 kg.
    expect(_readout('sw-mass', '37,7'), findsOneWidget);
    await _tapKey(tester, 'sw-mat-stainless304');
    // Nierdzewka 7900: 0,0008 · 7900 · 6 = 37,92 kg.
    expect(_readout('sw-mass', '37,9'), findsOneWidget);
  });

  testWidgets('profil zamknięty: tabela EN 10219-2 i własny wymiar',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'sw-shape-hollow');
    // SHS 100×100×4: ≈ 11,73 kg/m · 6 = 70,4 kg.
    expect(_readout('sw-mass', '70,4'), findsOneWidget);
    await _tapKey(tester, 'sw-hollow-custom');
    await tester.enterText(find.byKey(const ValueKey('sw-hollow-h')), '30');
    await tester.enterText(find.byKey(const ValueKey('sw-hollow-b')), '20');
    await tester.enterText(find.byKey(const ValueKey('sw-hollow-t')), '2');
    await tester.pump();
    final expected = const SteelItem(
            shape: SteelShape.hollow, a: 30, b: 20, t: 2, lengthMm: 6000)
        .totalKg;
    expect(_readout('sw-mass', fmtKg(expected)), findsOneWidget);
    // Za gruba ścianka → komunikat zamiast wyniku.
    await tester.enterText(find.byKey(const ValueKey('sw-hollow-t')), '9');
    await tester.pump();
    expect(find.byKey(const ValueKey('sw-problem')), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-add')), findsNothing);
  });

  testWidgets('dodanie do listy: zapis, suma z zapasem 5 % i koszt',
      (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('sw-count')), '2');
    await tester.pump();
    expect(_readout('sw-mass', '735,6'), findsOneWidget);
    await _tapKey(tester, 'sw-add');
    expect(find.text('Lista (1)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    final saved = await const SteelOrderStore().load();
    expect(saved.items.length, 1);
    expect(saved.items.single.label(), 'HEB 200');
    expect(saved.items.single.count, 2);

    await _tapKey(tester, 'sw-tab-list');
    expect(find.byKey(const ValueKey('sw-item-0')), findsOneWidget);
    // 735,6 kg + 5 % = 772,38 kg.
    expect(_readout('sw-order-mass', '772,4'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sw-price-1')), '5,2');
    await tester.pump();
    // 735,6 · 5,20 = 3825,12 zł; + 5 % (191,26 zł) = 4016,38 zł.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('sw-order-cost')),
            matching: find.text(formatPln(401638))),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect((await const SteelOrderStore().load()).pricePerKg, 5.2);

    // Zapas 10 % z chipa.
    await _tapKey(tester, 'sw-waste-preset-10');
    expect(_readout('sw-order-mass', '809,2'), findsOneWidget);

    // Usunięcie pozycji.
    await _tapKey(tester, 'sw-del-0');
    expect(find.text('Lista (0)'), findsOneWidget);
    expect(find.byKey(const ValueKey('sw-empty')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('lista wczytuje się z pamięci; edycja pozycji zmienia sumę',
      (tester) async {
    const order = SteelOrder(items: [
      SteelItem(
          shape: SteelShape.upn, section: 'UPN 200', lengthMm: 6000, count: 4),
      SteelItem(
          shape: SteelShape.flat, a: 80, t: 10, lengthMm: 1200, count: 10),
      SteelItem(
          shape: SteelShape.upn, section: 'UPN 200', lengthMm: 3000, count: 1),
    ], wastePct: 0);
    SharedPreferences.setMockInitialValues(
        {SteelOrderStore.key: jsonEncode(order.toJson())});
    await _pump(tester);
    expect(find.text('Lista (3)'), findsOneWidget);
    await _tapKey(tester, 'sw-tab-list');
    // UPN 200 zgrupowany: 27 m, 5 szt.
    expect(find.text('27,00 m · 5 szt.'), findsOneWidget);
    final net = 25.3 * 27 + 6.28 * 12;
    expect(_readout('sw-order-mass', fmtKg(net)), findsOneWidget);

    await _tapKey(tester, 'sw-item-1');
    await tester.enterText(find.byKey(const ValueKey('sw-edit-count')), '20');
    await tester.pump();
    await _tapKey(tester, 'sw-edit-save');
    expect(_readout('sw-order-mass', fmtKg(25.3 * 27 + 6.28 * 24)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('udostępnianie wysyła tekst listy', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    // Pusta lista — udostępnianie wyłączone.
    final share = tester
        .widget<IconButton>(find.byKey(const ValueKey('sw-appbar-share')));
    expect(share.onPressed, isNull);

    await _tapKey(tester, 'sw-add');
    await _tapKey(tester, 'sw-appbar-share');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Lista materiałowa — stal');
    expect(text, contains('1. HEB 200 — 1 × 6000 mm = 6 m'));
    expect(text, contains('EN 10365'));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Steel weight'), findsOneWidget);
    expect(_readout('sw-mass', '367.8'), findsOneWidget);
    expect(find.text('TOTAL MASS'), findsOneWidget);
  });

  testWidgets('wąski ekran, czcionka 1,3: bez przepełnień', (tester) async {
    await _pump(tester, size: const Size(360, 4000), textScale: 1.3);
    for (final s in SteelShape.values) {
      await _tapKey(tester, 'sw-shape-${s.name}');
      expect(tester.takeException(), isNull, reason: s.name);
      if (find.byKey(const ValueKey('sw-add')).evaluate().isNotEmpty) {
        await _tapKey(tester, 'sw-add');
      }
    }
    await _tapKey(tester, 'sw-tab-list');
    final price = find.byKey(const ValueKey('sw-price-1'));
    await tester.scrollUntilVisible(price, 400,
        scrollable: find.descendant(
            of: find.byKey(const ValueKey('sw-list-list')),
            matching: find.byType(Scrollable)));
    await tester.enterText(price, '5,49');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Lista (${SteelShape.values.length})'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('cele dotyku chipów ≥ 48 dp', (tester) async {
    await _pump(tester);
    for (final s in SteelShape.values) {
      final size = tester.getSize(find.byKey(ValueKey('sw-shape-${s.name}')));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: s.name);
    }
  });
}

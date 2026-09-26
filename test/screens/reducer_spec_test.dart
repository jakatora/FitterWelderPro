// Redukcja zakładana z palety kreatora segmentu.
//
// Było (P1, sonda z przeglądu G1): kreator pytał tylko o średnicę wyjścia i
// zapisywał redukcję z długością 0. Arkusz proponował dla redukcji „czoło
// dalekie”, które odejmuje długość — czyli 0. ELB DN100 (152,4) → rura →
// redukcja 4"×2" do końca, ISO 1000, gap 0 dawało CUT 847,6 zamiast
// 1000 − 152,4 − 102 = 745,6: rura za długa o całą redukcję. Redukcja
// zakładana jako START zapisywała się odwrotnie (wlot = mały koniec).
//
// Jest: dialog pyta o kierunek (zwężka / ekspander), drugą średnicę i H —
// z podpowiedzią ASME B16.9 wg większego DN (tylko po dotknięciu). Wpis w
// bibliotece ma zawsze duży → mały koniec. Stara redukcja z H = 0 wybrana z
// biblioteki najpierw pyta o H i poprawia wpis.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/widgets/reducer_spec_dialog.dart';

import '../support/test_database.dart';

Widget _wrap(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.en),
      child: MaterialApp(home: child),
    );

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 120 && finder.evaluate().isEmpty; i++) {
    await flushTestDatabase(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets, reason: 'waited for $finder');
  // Let the sheet / dialog finish sliding in before anything is tapped.
  await tester.pumpAndSettle();
}

Future<void> _tapPalette(WidgetTester tester, String label) async {
  final button =
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  group('suggestedReducerLength (ASME B16.9 H wg większego końca)', () {
    test('DN100 × DN50 → H 102 mm, w obie strony', () {
      expect(suggestedReducerLength(114.3, 60.3), (dn: 100, h: 102.0));
      expect(suggestedReducerLength(60.3, 114.3), (dn: 100, h: 102.0));
    });
    test('średnica spoza B16.9 → brak podpowiedzi (bez zgadywania)', () {
      expect(suggestedReducerLength(104, 60.3), isNull);
    });
  });

  group('validateReducerSpec', () {
    String? v({
      bool atStart = false,
      bool? expander = false,
      double? other = 60.3,
      double? h = 102,
    }) =>
        validateReducerSpec(
          currentDiameterMm: 114.3,
          atStart: atStart,
          expander: expander,
          otherDiameterMm: other,
          lengthMm: h,
          english: false,
        );

    test('poprawne: zwężka na końcu do mniejszej rury', () {
      expect(v(), isNull);
    });
    test('H = 0 jest odrzucane (to był błąd P1)', () {
      expect(v(h: 0), contains('H'));
      expect(v(h: null), isNotNull);
    });
    test('kierunek musi się zgadzać ze średnicą', () {
      expect(v(other: 168.3), isNotNull,
          reason: 'zwężka na końcu nie prowadzi do większej rury');
      expect(v(expander: true, other: 168.3), isNull);
      expect(v(atStart: true, other: 168.3), isNull,
          reason: 'zwężka na początku: rura przed nią była większa');
      expect(v(expander: null), isNotNull, reason: 'kierunek trzeba wybrać');
      expect(v(other: 114.3), isNotNull, reason: 'te same średnice');
    });
    test('wpis w bibliotece: zawsze duży → mały koniec', () {
      const spec =
          ReducerSpec(otherDiameterMm: 168.3, lengthMm: 140, expander: true);
      expect(spec.libraryEnds(114.3), (168.3, 114.3));
    });
  });

  group('kreator segmentu', () {
    useTestDatabase();

    setUp(() async {
      final db = await AppDatabase.get();
      await db.delete('component_library');
    });

    void tallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('ELB → rura → NOWA redukcja do końca: CUT 745,6 (nie 847,6)',
        (tester) async {
      tallPhone(tester);
      await tester.runAsync(() => ComponentLibraryDao().insert(LibraryComponent(
            id: 'elb-100',
            materialGroup: 'SS',
            type: 'ELB90',
            diameterMm: 114.3,
            wallThicknessMm: 3.05,
            axisMm: 152.4,
            lengthMm: null,
            measurementMode: null,
            diameterOutMm: null,
            createdAt: 1,
            updatedAt: 1,
          )));
      await tester.pumpWidget(_wrap(const SegmentBuilderScreen(
        materialGroup: 'SS',
        currentDiameter: 114.3,
        wallThickness: 3.05,
        gapMm: 0,
      )));
      await tester.pumpAndSettle();

      await _tapPalette(tester, 'Elbow 90');
      await _pumpUntil(tester, find.text('Axis'));
      await tester.tap(find.text('Axis'));
      await tester.pumpAndSettle();
      await _tapPalette(tester, 'Pipe');
      await _tapPalette(tester, 'Reducer');
      await _pumpUntil(tester, find.byType(ReducerSpecDialog));

      // OK bez niczego: dialog zostaje i mówi, czego brakuje.
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.byKey(const ValueKey('reducer-error')), findsOneWidget);

      await tester.tap(find.text('Reducer').last);
      await tester.enterText(
          find.byKey(const ValueKey('reducer-other-diameter')), '60,3');
      await tester.pump();
      // H nie wpisuje się samo — dopiero po dotknięciu podpowiedzi.
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('reducer-length')))
              .controller!
              .text,
          '');
      await tester.tap(find.byKey(const ValueKey('reducer-length-suggestion')));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await _pumpUntil(tester, find.text('Far face'));
      await tester.tap(find.text('Far face'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1000');
      await tester.pump();
      expect(find.text('CUT = 745.6 mm'), findsOneWidget);

      final saved = await tester.runAsync(() => ComponentLibraryDao().listAll());
      final red = saved!.singleWhere((c) => c.type == 'REDUCER');
      expect(red.diameterMm, 114.3);
      expect(red.diameterOutMm, 60.3);
      expect(red.lengthMm, 102);
    });

    testWidgets('stara redukcja z H = 0 z biblioteki: najpierw pytanie o H',
        (tester) async {
      tallPhone(tester);
      await tester.runAsync(() => ComponentLibraryDao().insert(LibraryComponent(
            id: 'red-old',
            materialGroup: 'SS',
            type: 'REDUCER',
            diameterMm: 114.3,
            wallThicknessMm: 3.05,
            axisMm: null,
            lengthMm: 0,
            measurementMode: 'FACE',
            diameterOutMm: 60.3,
            createdAt: 1,
            updatedAt: 1,
          )));
      await tester.pumpWidget(_wrap(const SegmentBuilderScreen(
        materialGroup: 'SS',
        currentDiameter: 114.3,
        wallThickness: 3.05,
        gapMm: 0,
      )));
      await tester.pumpAndSettle();

      await _tapPalette(tester, 'Open end');
      await _tapPalette(tester, 'Pipe');
      await _tapPalette(tester, 'Reducer');
      await _pumpUntil(tester, find.text('Reducer without length H'));
      await tester.enterText(
          find.byKey(const ValueKey('reducer-length')), '102');
      await tester.tap(find.text('OK'));
      await _pumpUntil(tester, find.text('Far face'));
      await tester.tap(find.text('Far face'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '1000');
      await tester.pump();
      expect(find.text('CUT = 898.0 mm'), findsOneWidget);

      final fixed =
          await tester.runAsync(() => ComponentLibraryDao().getById('red-old'));
      expect(fixed!.lengthMm, 102, reason: 'wpis w bibliotece poprawiony');
    });
  });
}

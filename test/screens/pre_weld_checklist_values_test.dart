// Część kroku „Zamknąć kolejkę P0 audytu” — moduł pre-weld-checklist.
//
// Lista uniwersalna ma 11 pozycji (bez wybranego materiału). Sprawdzamy:
//  • licznik 0/11 → 11/11 i komunikat „All set” dopiero po komplecie,
//  • przypadek błędny: zapisany znacznik spoza listy (p10-ferrite-check bez
//    materiału Duplex) NIE może zastąpić niezaznaczonej pozycji,
//  • zerowanie wymaga potwierdzenia i da się je cofnąć.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pre_weld_checklist_screen.dart';

const _universalIds = <String>[
  'univ-fitup-gap',
  'univ-tube-ends-clean',
  'univ-backing-gas',
  'univ-gas-flow',
  'univ-o2-limit',
  'univ-pre-purge',
  'univ-tungsten',
  'univ-wps-params',
  'univ-test-coupon',
  'univ-weld-no',
  'univ-tools-ss-only',
];

const _universalEn = <String>[
  'Fit-up gap ≈ 0, tubes aligned (no land mismatch)',
  'Tube ends clean — degreased, no marker ink',
  'Backing gas connected, purge dams/plugs fitted',
  'Shielding and backing gas flow set',
  'Backing-gas O₂ below the limit (meter checked)',
  'Pre-purge time elapsed — air flushed out',
  'Tungsten electrode sharp, clean, correct diameter',
  'Machine parameters match the WPS / program',
  "Today's test coupon welded and accepted",
  'Weld number marked, weld map updated',
  'Stainless-only tools used (no iron cross-contamination)',
];

const _allSet = 'All set — you can strike the arc.';
const _tickEvery = 'Tick every item before welding.';

String _today() {
  final n = DateTime.now();
  return '${n.year}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

Widget _wrap(Widget child) {
  return AppLanguageScope(
    controller: AppLanguageController(AppLanguage.en),
    child: MaterialApp(home: child),
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_wrap(const PreWeldChecklistScreen()));
  await tester.pumpAndSettle();
}

void main() {
  test('lista uniwersalna w teście ma 11 pozycji', () {
    expect(_universalIds.length, 11);
    expect(_universalEn.length, 11);
  });

  testWidgets('świeży ekran pokazuje 0/11 i prośbę o sprawdzenie',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester);

    expect(find.text('0/11'), findsOneWidget);
    expect(find.text(_tickEvery), findsOneWidget);
    expect(find.text(_allSet), findsNothing);
  });

  testWidgets('komplet 11 pozycji daje 11/11 i „All set”', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester);

    for (var i = 0; i < _universalEn.length; i++) {
      expect(find.text(_allSet), findsNothing,
          reason: 'przed odhaczeniem pozycji ${i + 1} nie może być kompletu');
      await tester.tap(find.text(_universalEn[i]));
      await tester.pump();
      expect(find.text('${i + 1}/11'), findsOneWidget);
    }

    expect(find.text(_allSet), findsOneWidget);
    expect(find.text(_tickEvery), findsNothing);
  });

  testWidgets(
      'znacznik spoza listy nie zastępuje niezaznaczonej pozycji (10/11)',
      (tester) async {
    final today = _today();
    SharedPreferences.setMockInitialValues({
      'preweld_done_$today': [
        ..._universalIds.take(10),
        'p10-ferrite-check',
      ],
    });
    await _pumpScreen(tester);

    expect(find.text('10/11'), findsOneWidget);
    expect(find.text('11/11'), findsNothing);
    expect(find.text(_allSet), findsNothing);
    expect(find.text(_tickEvery), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('preweld_done_$today') ?? const [];
    expect(saved, isNot(contains('p10-ferrite-check')));
    expect(saved.toSet(), _universalIds.take(10).toSet());
  });

  testWidgets('zerowanie wymaga potwierdzenia i da się je cofnąć',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpScreen(tester);

    await tester.tap(find.text(_universalEn.first));
    await tester.pump();
    expect(find.text('1/11'), findsOneWidget);

    // Anuluj — nic się nie zmienia.
    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('1/11'), findsOneWidget);

    // Potwierdzenie — licznik wraca do zera.
    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.text('0/11'), findsOneWidget);

    // Cofnij — stan wraca.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('1/11'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
  });
}

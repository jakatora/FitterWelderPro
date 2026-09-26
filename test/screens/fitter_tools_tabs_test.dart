// Zakładki „Kalkulatory montera” bez wcześniejszych testów + poprawki G2.
// Liczby wyliczone niezależnie (patrz test/domain/fitter/fitter_calcs_test.dart):
//  • Cięcie pod spadek 2 %: α = atan(0,02) = 1,146° (skala 0° = prosto),
//    90 − α = 88,854°.
//  • Cięcie kolanka DN50 LR 166,74 / 72,02 → 60°: 111,2 / 48,0 mm.
//  • Obrót: OD 60,3, obwód „0”, 90° → π·60,3/4 = 47,4 mm (było 0,0).
//  • Wstawka OD 60,3, 45° LR (B = 35, ASME B16.9 tab. 6.1-1), offset 300,
//    g 3: 424,26 − 70 − 6 = 348,26 → 348,3; run = 300/tan45° = 300,0.
//  • Redukcja 114,3/60,3, L 102, cel 88,9 → 47,98 → 48,0 mm.
//  • Ciężar 316L (ρ 8,0 kg/dm³, EN 10088-1) 60,3 × 3,91 → 5,541 kg/m
//    (było 5,493 dla ρ 7,93).
//  • Fazowanie X: t 20, b 2, β 30° → h 9, w 5,20 mm na stronę (było 10,39);
//    ISO 9692-1 kąt rowka 60°, t 10, b 1 → w 5,20 (było 15,59).
//  • Dylatacja 304L α 16,0 (EN 10088, Industeel UR 304L) 50 m, ΔT 100 → 80,0
//    (było 86,0).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/widgets/help_button.dart';

Widget _app(int tab) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: FitterToolsScreen(initialTab: tab)),
    );

Finder _field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
      description: 'TextField "$label"',
    );

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final f = _field(label);
  expect(f, findsOneWidget, reason: label);
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, int index, String item) async {
  final dd = find
      .byWidgetPredicate((w) => w is DropdownButtonFormField)
      .at(index);
  await tester.ensureVisible(dd);
  await tester.tap(dd);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> _big(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('pomoc: Wstawka między kolanami, Obrót = długość łuku, 8 zakładek', () {
    final pl = [
      kHelpFitterTools.bodyPl,
      for (final s in kHelpFitterTools.stepsPl) s.text,
    ].join('\n');
    expect(pl, contains('MIĘDZY DWOMA KOLANAMI'));
    expect(pl, isNot(contains('kołnierzami')));
    expect(pl, contains('długość łuku'));
    for (final tab in [
      'Cięcie pod spadek',
      'Ciężar rury',
      'Fazowanie',
      'Dylatacja',
    ]) {
      expect(pl, contains(tab), reason: tab);
    }
    expect(kHelpFitterTools.stepsPl.length, 8);
    expect(kHelpFitterTools.stepsEn.length, 8);
  });

  testWidgets('Cięcie pod spadek: kąt piły od prostopadłej (skala 0°)',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(0));
    await tester.pumpAndSettle();
    expect(find.text('Cięcie pod spadek'), findsWidgets);
    await _enter(tester, 'Średnica zewnętrzna rury D (mm)', '114,3');
    await _enter(tester, 'Spadek (%)', '2');
    expect(find.textContaining('skala 0° = prosto'), findsWidgets);
    expect(find.text('1.146°'), findsNWidgets(2)); // α spadku = α piły
    expect(find.textContaining('88.854° (90° − α)'), findsOneWidget);
    expect(find.text('2.29 mm'), findsOneWidget);
  });

  testWidgets('Cięcie kolanka DN50 LR 90° → 60°', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(1));
    await tester.pumpAndSettle();
    await _enter(tester, 'Długi bok kolanka — extrados (mm)', '166,74');
    await _enter(tester, 'Krótki bok kolanka — intrados (mm)', '72,02');
    await _enter(tester, 'Żądany kąt kolanka (°)', '60');
    expect(find.text('111.2 mm'), findsOneWidget);
    expect(find.text('48.0 mm'), findsOneWidget);
    expect(find.textContaining('60.3 mm'), findsOneWidget); // OD z pomiaru
  });

  testWidgets('Obrót kolanka: obwód „0” liczy z OD (47,4 mm, nie 0,0)',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(2));
    await tester.pumpAndSettle();
    await _enter(tester, 'OD (mm)', '60,3');
    await _enter(tester, 'Obwód (mm)', '0');
    await _enter(tester, 'Obrót (°)', '90');
    expect(find.text('47.4 mm'), findsOneWidget);
    expect(find.text('0.0 mm'), findsNothing);
  });

  testWidgets('Obrót kolanka: > 360° z ostrzeżeniem', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(2));
    await tester.pumpAndSettle();
    await _enter(tester, 'OD (mm)', '60,3');
    await _enter(tester, 'Obrót (°)', '400');
    expect(find.textContaining('więcej niż pełny obrót'), findsOneWidget);
  });

  testWidgets('Wstawka: szczelina 3 mm odjęta 2× → 348,3; run 300,0',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(3));
    await tester.pumpAndSettle();
    await _enter(tester, 'Średnica zewnętrzna rury OD (mm)', '60,3');
    await _enter(tester, 'Kąt kolanka θ (°)', '45');
    await _enter(tester, 'Odejście — offset (mm)', '300');
    await _enter(tester, 'Szczelina spoiny g (mm)', '3');
    expect(find.text('348.3 mm'), findsOneWidget); // do cięcia
    expect(find.text('354.3 mm'), findsOneWidget); // między końcami kolan
    expect(find.text('300.0 mm'), findsOneWidget); // run
    expect(find.textContaining('− 2×g'), findsWidgets);
  });

  testWidgets('Redukcja 114,3 × 60,3, L 102 → 48,0 mm od dużego końca',
      (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(4));
    await tester.pumpAndSettle();
    await _enter(tester, 'OD wejścia [mm]', '114,3');
    await _enter(tester, 'OD wyjścia [mm]', '60,3');
    await _enter(tester, 'Długość części stożkowej L [mm]', '102');
    await _enter(tester, 'Wymagane OD [mm]', '88,9');
    expect(find.text('48.0 mm'), findsOneWidget);
    expect(find.textContaining('odcinki walcowe'), findsOneWidget);
  });

  group('Ciężar rury', () {
    testWidgets('316L 60,3 × 3,91 → 5,541 kg/m (ρ 8,0)', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(5));
      await tester.pumpAndSettle();
      await _enter(tester, 'OD (mm)', '60,3');
      await _enter(tester, 'Gr. ścianki t (mm)', '3,91');
      expect(find.text('5.541 kg/m'), findsOneWidget);
      expect(find.text('5.493 kg/m'), findsNothing);
      expect(find.text('Odcinek 1000 mm'), findsOneWidget);
    });

    testWidgets('puste długość i ilość: bez cichych 1000 mm / 1 szt.',
        (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(5));
      await tester.pumpAndSettle();
      await _enter(tester, 'OD (mm)', '60,3');
      await _enter(tester, 'Gr. ścianki t (mm)', '3,91');
      await _enter(tester, 'Długość (mm)', '');
      await _enter(tester, 'Ilość szt.', '');
      expect(find.text('5.541 kg/m'), findsOneWidget);
      expect(find.textContaining('Odcinek'), findsNothing);
      expect(find.textContaining('Razem'), findsNothing);
    });

    testWidgets('ułamkowa ilość sztuk to błąd', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(5));
      await tester.pumpAndSettle();
      await _enter(tester, 'OD (mm)', '60,3');
      await _enter(tester, 'Gr. ścianki t (mm)', '3,91');
      await _enter(tester, 'Ilość szt.', '1,5');
      expect(find.textContaining('całkowitą liczbę'), findsOneWidget);
    });
  });

  group('Fazowanie', () {
    testWidgets('X: w = (t − b)/2 · tan β = 5,20 mm na stronę', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(6));
      await tester.pumpAndSettle();
      await _pick(tester, 0, 'X — dwustronne (grube ścianki)');
      await _enter(tester, 'Grubość ścianki t (mm)', '20');
      await _enter(tester, 'Kąt fazy β (°)', '30');
      await _enter(tester, 'Próg b (mm)', '2');
      await _enter(tester, 'Szczelina g (mm)', '2');
      expect(find.text('5.20 mm'), findsOneWidget);
      expect(find.text('10.39 mm'), findsNothing);
      expect(find.text('9.00 mm'), findsOneWidget); // h z każdej strony
      expect(find.text('12.39 mm'), findsOneWidget); // g + 2w = 2 + 10,39
    });

    testWidgets('ISO 9692-1: kąt rowka 60° → β 30°, w 5,20 (nie 15,59)',
        (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(6));
      await tester.pumpAndSettle();
      await _pick(
          tester, 1, 'Kąt rowka α całkowity (EN ISO 9692-1, np. 60°)');
      // 37,5 na stronę przeliczone na 75 całkowitego.
      expect(find.text('75'), findsOneWidget);
      await _enter(tester, 'Grubość ścianki t (mm)', '10');
      await _enter(tester, 'Kąt rowka α (°)', '60');
      await _enter(tester, 'Próg b (mm)', '1');
      expect(find.text('5.20 mm'), findsOneWidget);
      expect(find.text('15.59 mm'), findsNothing);
      expect(find.text('β 30° · α 60°'), findsOneWidget);
    });

    testWidgets('pusta szczelina to błąd, nie cicha wartość 2 mm',
        (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(6));
      await tester.pumpAndSettle();
      await _enter(tester, 'Grubość ścianki t (mm)', '10');
      await _enter(tester, 'Szczelina g (mm)', '');
      expect(find.textContaining('Szczelina g: wpisz'), findsOneWidget);
      await _enter(tester, 'Kąt fazy β (°)', '');
      expect(find.textContaining('Kąt fazy β na stronę'), findsOneWidget);
    });

    testWidgets('α ≥ 90° na stronę odrzucone', (tester) async {
      await _big(tester);
      await tester.pumpWidget(_app(6));
      await tester.pumpAndSettle();
      await _enter(tester, 'Grubość ścianki t (mm)', '10');
      await _enter(tester, 'Kąt fazy β (°)', '90');
      expect(find.textContaining('0–60°'), findsOneWidget);
    });
  });

  testWidgets('Dylatacja 304L: 50 m, ΔT 100 → 80,0 mm', (tester) async {
    await _big(tester);
    await tester.pumpWidget(_app(7));
    await tester.pumpAndSettle();
    await _pick(tester, 0, 'SS 304L   α = 16.0 ×10⁻⁶ /°C');
    await _enter(tester, 'Długość rurociągu L (m)', '50');
    await _enter(tester, 'ΔT (°C)', '100');
    expect(find.text('80.0 mm'), findsOneWidget);
    expect(find.text('86.0 mm'), findsNothing);
  });
}

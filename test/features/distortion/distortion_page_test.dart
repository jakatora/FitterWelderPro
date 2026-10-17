// Ekran „Odkształcenia spawalnicze”: skurcz na żywo, łańcuch wymiarowy
// z zaokrągleniem w górę, pomiar zamiast szacunku, wybór sytuacji → lista
// środków, przyciski do energii liniowej i odbioru kołnierzy, wersja EN,
// udostępnianie (wstrzyknięte), 320×640 z tekstem ×1,3, cele dotyku ≥ 48 dp.
//
// Liczby (jak w test/domain/welding/distortion_test.dart):
//  • domyślnie V 60°, t 10, d 2, c 1,5: A_w 61,71 → „61,7 mm²”,
//    S 1,334 → „1,3”; łańcuch 1000 + 2 × 1,3 = 1002,6 → „1003,0”;
//  • t 20: A_w 237,60, S 2,476 → „2,5”; rowek X: 138,80, S 1,488 → „1,5”;
//  • pomiar 1,8: 1000 + 3,6 = 1003,6 → „1004,0”;
//  • pomiar 1,8 + pachwiny 2 × 0,8: 3,6 + 1,6 = 5,2 → 1005,2 → „1005,5”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/welding/distortion.dart';
import 'package:cut_list_app/features/distortion/distortion_page.dart';
import 'package:cut_list_app/features/flange_check/flange_check_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/heat_input_screen.dart';
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
}) async {
  SharedPreferences.setMockInitialValues({});
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
      home: DistortionPage(key: UniqueKey(), shareText: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija listę, aż element powstanie i będzie widoczny (ListView buduje
/// leniwie).
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  final scrollable = find
      .descendant(of: _key('dist-list'), matching: find.byType(Scrollable))
      .first;
  if (f.evaluate().isEmpty) {
    // Element może być nad bieżącym widokiem — od góry w dół.
    await tester.drag(scrollable, const Offset(0, 100000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 400,
          scrollable: scrollable, maxScrolls: 200);
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

Future<void> _scrollTop(WidgetTester tester) async {
  final scrollable = find
      .descendant(of: _key('dist-list'), matching: find.byType(Scrollable))
      .first;
  await tester.drag(scrollable, const Offset(0, 30000));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('domyślnie: skurcz 1,3 mm i wymiar przed spawaniem 1003,0',
      (tester) async {
    await _pump(tester);
    expect(_in('dist-shrinkage', '1,3'), findsOneWidget);
    expect(_in('dist-shrinkage', 'SKURCZ POPRZECZNY — SZACUNEK'),
        findsOneWidget);
    expect(_in('dist-area', '61,7 mm²'), findsOneWidget);
    await _reveal(tester, 'dist-preweld');
    expect(_in('dist-preweld', '1003,0'), findsOneWidget);
    expect(_in('dist-total', '2,6 mm'), findsOneWidget);
    expect(find.text('+0,4 mm'), findsOneWidget);
    await _reveal(tester, 'dist-disclaimer');
    expect(
        find.descendant(
            of: _key('dist-disclaimer'),
            matching: find.textContaining('SZACUNEK: rzeczywisty skurcz')),
        findsOneWidget);
  });

  testWidgets('wpisanie grubości i zmiana rowka liczą na żywo; kropka '
      'i przecinek', (tester) async {
    await _pump(tester);
    await _enter(tester, 'dist-t', '20');
    expect(_in('dist-shrinkage', '2,5'), findsOneWidget);
    await _tap(tester, 'dist-groove-x');
    expect(_in('dist-shrinkage', '1,5'), findsOneWidget);
    await _tap(tester, 'dist-groove-v');
    await _enter(tester, 'dist-rootface', '1.5');
    expect(_in('dist-shrinkage', '2,5'), findsOneWidget);
    // ½V: osobne pole kąta fazy (domyślnie 45°).
    await _tap(tester, 'dist-groove-halfV');
    expect(_key('dist-bevel'), findsOneWidget);
    expect(_key('dist-angle'), findsNothing);
  });

  testWidgets('puste pole to komunikat, nie wynik', (tester) async {
    await _pump(tester);
    await _enter(tester, 'dist-t', '');
    expect(_key('dist-shrinkage'), findsNothing);
    expect(_key('dist-shrink-problems'), findsOneWidget);
    expect(find.textContaining('Podaj grubość blachy'), findsOneWidget);
    // Łańcuch nie liczy z pustego szacunku.
    await _reveal(tester, 'dist-preweld-problems');
    expect(find.textContaining('Brak szacunku skurczu'), findsOneWidget);
    expect(_key('dist-preweld'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
  });

  testWidgets('mój pomiar zamiast szacunku; pachwiny wg TWI', (tester) async {
    await _pump(tester);
    await _tap(tester, 'dist-src-measured');
    await _reveal(tester, 'dist-preweld-problems');
    expect(find.textContaining('Wpisz zmierzony skurcz'), findsOneWidget);
    await _enter(tester, 'dist-measured', '1,8');
    await _reveal(tester, 'dist-preweld');
    expect(_in('dist-preweld', '1004,0'), findsOneWidget);
    await _enter(tester, 'dist-measured', '1.8');
    expect(_in('dist-preweld', '1004,0'), findsOneWidget);
    await _enter(tester, 'dist-fillet-count', '2');
    await _reveal(tester, 'dist-preweld');
    expect(_in('dist-total', '5,2 mm'), findsOneWidget);
    expect(_in('dist-preweld', '1005,5'), findsOneWidget);
    // Puste pole liczby spoin to błąd, nie zero.
    await _enter(tester, 'dist-butt-count', '');
    await _reveal(tester, 'dist-preweld-problems');
    expect(find.textContaining('Liczba spoin czołowych'), findsOneWidget);
  });

  testWidgets('wybór sytuacji zmienia listę środków', (tester) async {
    await _pump(tester);
    await _reveal(tester, 'dist-measure-preset');
    expect(_key('dist-measure-preset'), findsOneWidget);
    await _tap(tester, 'dist-el-flangeOnPipe');
    // Kołnierz → domyślnie „poszedł w skos”.
    final chip = tester.widget<ChoiceChip>(_key('dist-kind-flangeTilt'));
    expect(chip.selected, isTrue);
    expect(_key('dist-kind-buckling'), findsNothing);
    await _reveal(tester, 'dist-measure-pipe-tacks');
    expect(find.textContaining('12, 3, 6 i 9'), findsOneWidget);
    await _reveal(tester, 'dist-measure-flange-check');
    expect(_key('dist-measure-preset'), findsNothing);
    expect(_key('dist-measure-flame'), findsNothing);
    // Długi profil, wygięcie: wstępne wygięcie i prostowanie (korekta).
    await _tap(tester, 'dist-el-longMember');
    await _reveal(tester, 'dist-measure-prebend');
    await _reveal(tester, 'dist-measure-flame');
    expect(find.text('KOREKTA PO SPAWANIU'), findsOneWidget);
  });

  testWidgets('przycisk otwiera kalkulator energii liniowej', (tester) async {
    await _pump(tester);
    await _tap(tester, 'dist-open-heat-input');
    expect(find.byType(HeatInputScreen), findsOneWidget);
  });

  testWidgets('przycisk otwiera odbiór połączenia kołnierzowego',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'dist-el-flangeOnPipe');
    await _tap(tester, 'dist-open-flange-check');
    expect(find.byType(FlangeCheckPage), findsOneWidget);
  });

  testWidgets('EN: teksty i kropka dziesiętna, te same liczby',
      (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Welding distortion'), findsOneWidget);
    expect(_in('dist-shrinkage', '1.3'), findsOneWidget);
    expect(_in('dist-area', '61.7 mm²'), findsOneWidget);
    await _reveal(tester, 'dist-preweld');
    expect(_in('dist-preweld', '1003.0'), findsOneWidget);
    await _tap(tester, 'dist-el-flangeOnPipe');
    expect(find.text('Flange out of square'), findsOneWidget);
    await _reveal(tester, 'dist-measure-pipe-tacks');
    expect(find.textContaining('12, 3, 6 and 9'), findsOneWidget);
    await _reveal(tester, 'dist-disclaimer');
    expect(find.textContaining('ESTIMATE: actual shrinkage'), findsOneWidget);
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _tap(tester, 'dist-share');
    expect(spy.calls, hasLength(1));
    final (text, subject) = spy.calls.single;
    expect(subject, 'Odkształcenia spawalnicze');
    expect(text, contains('S ≈ 1,3 mm na spoinę'));
    expect(text, contains('1003,0 mm'));
    expect(text, contains('Sytuacja: Blachy doczołowo'));
    expect(text, contains('Ustawienie wstępne'));
    expect(text, contains(distortionDisclaimer(en: false)));

    // EN, inna sytuacja.
    final spyEn = _ShareSpy();
    await _pump(tester, spy: spyEn, language: AppLanguage.en);
    await _tap(tester, 'dist-el-flangeOnPipe');
    await _tap(tester, 'dist-share');
    final (en, enSubject) = spyEn.calls.single;
    expect(enSubject, 'Welding distortion');
    expect(en, contains('Situation: Flange on pipe — Flange out of square'));
    expect(en, contains('Check the flange after tacking'));
    expect(en, contains('1003.0 mm'));
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    for (final lang in AppLanguage.values) {
      await _pump(tester,
          language: lang, size: const Size(320, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'dist-groove-halfV');
      await _tap(tester, 'dist-src-measured');
      await _enter(tester, 'dist-measured', '2');
      await _enter(tester, 'dist-fillet-count', '3');
      await _reveal(tester, 'dist-preweld');
      await _reveal(tester, 'dist-open-heat-input');
      await _reveal(tester, 'dist-measure-flame');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'dist-el-flangeOnPipe');
      await _reveal(tester, 'dist-open-flange-check');
      await _reveal(tester, 'dist-disclaimer');
      expect(tester.takeException(), isNull);
      await _scrollTop(tester);
      await _enter(tester, 'dist-t', '');
      await _reveal(tester, 'dist-shrink-problems');
      // Pomiar wpisany — łańcuch liczy dalej bez szacunku.
      await _reveal(tester, 'dist-preweld');
      expect(_key('dist-preweld-problems'), findsNothing);
      await _tap(tester, 'dist-src-estimate');
      await _reveal(tester, 'dist-preweld-problems');
      expect(tester.takeException(), isNull, reason: lang.name);
    }
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    final keys = [
      for (final g in ButtGroove.values) 'dist-groove-${g.name}',
      'dist-t',
      'dist-gap',
      'dist-rootface',
      'dist-angle',
      'dist-final',
      'dist-butt-count',
      'dist-src-estimate',
      'dist-src-measured',
      'dist-fillet-count',
      for (final e in DistortionElement.values) 'dist-el-${e.name}',
      'dist-kind-angular',
      'dist-kind-gapClosing',
      'dist-open-heat-input',
      'dist-share',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'dist-src-measured');
    expect(tester.getSize(_key('dist-measured')).height,
        greaterThanOrEqualTo(kMinTapTarget));
    await _tap(tester, 'dist-el-flangeOnPipe');
    await _reveal(tester, 'dist-open-flange-check');
    expect(tester.getSize(_key('dist-open-flange-check')).height,
        greaterThanOrEqualTo(kMinTapTarget));
  });
}

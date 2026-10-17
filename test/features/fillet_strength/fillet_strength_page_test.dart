// Ekran „Nośność spoiny pachwinowej”: wynik na żywo, werdykt i kolor,
// wymagane a, przełącznik a ↔ z, spoina obwodowa, metoda kierunkowa,
// zastrzeżenie, udostępnianie (wstrzyknięte), wersja EN, wąski ekran
// 320×640 z tekstem ×1,3, cele dotyku ≥ 48 dp.
//
// Liczby (jak w test/domain/welding/fillet_weld_strength_test.dart):
//  • domyślnie S235, a 4, 2 × l 100, uproszczona: fvw,d 207,8461 MPa,
//    A = 4 · 2 · 92 = 736 mm² → 152,9747 kN → „152,9” (w dół);
//  • F_Ed 100 kN → 65,37 % → „65,4 %”, zielony;
//    F_Ed 160 kN → 104,59 % → „104,6 %”, czerwony; wymagane a:
//    2·207,8461·a(100 − 2a) = 160 000 → a = 4,2022 → „≥ 4,3”, a5;
//  • a ↔ z: pole pokazuje z = 4·√2 = 5,657 → „5,65” (w dół), ale liczy się
//    dalej z wpisanego a = 4 → „152,9”; a 3: 207,8461·3·188 = 117,225 kN →
//    „117,2”; z wpisane 5,66 → a = 4,0022 → 207,8461·4,0022·183,9912 =
//    153,051 kN → „153,0”;
//  • obwodowa D 60,3, a 4: π·60,3 = 189,438 mm → 157,496 kN → „157,4”;
//  • kierunkowa w poprzek: 360/√2 · 736 = 187,355 kN → „187,3”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/domain/welding/fillet_weld_strength.dart';
import 'package:cut_list_app/features/fillet_strength/fillet_strength_page.dart';
import 'package:cut_list_app/features/quotes/quote_widgets.dart';
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
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: FilletStrengthPage(shareText: s.call),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Przewija listę, aż element powstanie i będzie widoczny — ListView buduje
/// leniwie, na wąskim ekranie dalsze (albo wcześniejsze) sekcje nie istnieją.
Future<void> _reveal(WidgetTester tester, String key) async {
  final f = _key(key);
  if (f.evaluate().isEmpty) {
    final scrollable = find
        .descendant(of: _key('fillet-list'), matching: find.byType(Scrollable))
        .first;
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

Color _noticeColor(WidgetTester tester, String key) => tester
    .widget<QuoteNotice>(
        find.descendant(of: _key(key), matching: find.byType(QuoteNotice)))
    .color;

void main() {
  testWidgets('dane → wynik; siła poniżej nośności → zielony', (tester) async {
    await _pump(tester);
    expect(_readout(tester, 'fillet-result'), '152,9');
    expect(find.text('fvw,d'), findsOneWidget);
    expect(find.text('207,8 MPa'), findsOneWidget);
    // Bez siły — bez werdyktu i bez „wymaganego a”.
    expect(_key('fillet-verdict-ok'), findsNothing);
    expect(_key('fillet-required'), findsNothing);

    await _enter(tester, 'fillet-force', '100');
    expect(_key('fillet-verdict-ok'), findsOneWidget);
    expect(_noticeColor(tester, 'fillet-verdict-ok'), kPass);
    expect(find.textContaining('wykorzystanie 65,4 %'), findsOneWidget);
    expect(find.textContaining('F_Ed 100,0 kN ≤ F_Rd 152,9 kN'), findsOneWidget);
  });

  testWidgets('wykorzystanie > 100 % → czerwony; wymagane a w górę',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'fillet-force', '160');
    expect(_key('fillet-verdict-fail'), findsOneWidget);
    expect(_key('fillet-verdict-ok'), findsNothing);
    expect(_noticeColor(tester, 'fillet-verdict-fail'), kFail);
    expect(find.textContaining('wykorzystanie 104,6 %'), findsOneWidget);
    expect(find.textContaining('F_Ed 160,0 kN > F_Rd 152,9 kN'), findsOneWidget);
    await _reveal(tester, 'fillet-required');
    expect(_readout(tester, 'fillet-required'), '≥ 4,3');
    expect(find.text('a5 · z ≥ 7,1 mm'), findsOneWidget);
  });

  testWidgets('siła tuż ponad nośnością nie wygląda na „100 %”',
      (tester) async {
    await _pump(tester);
    // F_Rd = 152,9747 kN; 153 kN to 100,017 % → „100,1 %”, czerwony.
    await _enter(tester, 'fillet-force', '153');
    expect(_key('fillet-verdict-fail'), findsOneWidget);
    expect(find.textContaining('wykorzystanie 100,1 %'), findsOneWidget);
    // Liczby obok werdyktu nie przeczą kolorowi.
    expect(find.textContaining('F_Ed 153,0 kN > F_Rd 152,9 kN'), findsOneWidget);
    // 152,97 kN — 99,998 %, zielony: wykorzystanie i para sił z 2 miejscami.
    await _enter(tester, 'fillet-force', '152,97');
    expect(_key('fillet-verdict-ok'), findsOneWidget);
    expect(find.textContaining('wykorzystanie 100,0 %'), findsOneWidget);
    expect(find.textContaining('F_Ed 152,97 kN ≤ F_Rd 152,97 kN'), findsOneWidget);
  });

  testWidgets('siła charakterystyczna × 1,5', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fillet-force-variable');
    await _enter(tester, 'fillet-force', '80');
    // 1,5 · 80 = 120 kN → 78,45 % → „78,5 %”. F_Ed tymi samymi cyframi co
    // przy werdykcie i w tekście do udostępnienia.
    expect(find.text('F_Ed = 1,5 × 80 kN = 120,0 kN'), findsOneWidget);
    expect(find.textContaining('F_Ed 120,0 kN ≤ F_Rd'), findsOneWidget);
    expect(find.textContaining('wykorzystanie 78,5 %'), findsOneWidget);
  });

  // Regresja z przeglądu: przełączanie a ↔ z nadpisywało pole liczbą
  // zaokrągloną w dół i liczyło z niej (a 4 → z 5,65 → a 3,99 → …; a 3 po
  // jednym obiegu dawało 2,99 i błąd „a < 3 mm”).
  testWidgets('a ↔ z: przełączanie nie zmienia wpisanej wartości (a 4, a 3)',
      (tester) async {
    await _pump(tester);
    for (var k = 0; k < 5; k++) {
      await _tap(tester, 'fillet-size-z');
      expect(find.widgetWithText(TextField, '5,65'), findsOneWidget);
      expect(find.textContaining('a = z/√2 = 4,00 mm'), findsOneWidget);
      expect(_readout(tester, 'fillet-result'), '152,9');
      await _tap(tester, 'fillet-size-a');
      expect(find.widgetWithText(TextField, '4'), findsOneWidget);
      expect(find.textContaining('z = a·√2 = 5,65 mm'), findsOneWidget);
      expect(_readout(tester, 'fillet-result'), '152,9');
    }
    await _enter(tester, 'fillet-size', '3');
    for (var k = 0; k < 5; k++) {
      await _tap(tester, 'fillet-size-z');
      expect(find.widgetWithText(TextField, '4,24'), findsOneWidget);
      expect(_key('fillet-problems'), findsNothing);
      expect(_readout(tester, 'fillet-result'), '117,2');
      await _tap(tester, 'fillet-size-a');
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(_key('fillet-problems'), findsNothing);
      expect(_readout(tester, 'fillet-result'), '117,2');
    }
  });

  testWidgets('z wpisane ręcznie: a = z/√2; przełączenie nie nadpisuje wartości',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fillet-size-z');
    await _enter(tester, 'fillet-size', '5,66');
    expect(find.textContaining('a = z/√2 = 4,00 mm'), findsOneWidget);
    expect(_readout(tester, 'fillet-result'), '153,0');
    // Pole a pokazuje „4” (w dół), ale liczy się dalej a = 4,0022 z z 5,66.
    await _tap(tester, 'fillet-size-a');
    expect(find.widgetWithText(TextField, '4'), findsOneWidget);
    expect(_readout(tester, 'fillet-result'), '153,0');
    // Dopiero edycja pola zmienia wartość źródłową.
    await _enter(tester, 'fillet-size', '4,0');
    expect(_readout(tester, 'fillet-result'), '152,9');
    // z = 4,2 → a = 2,97 < 3 mm: komunikat zamiast wyniku.
    await _tap(tester, 'fillet-size-z');
    await _enter(tester, 'fillet-size', '4,2');
    expect(_key('fillet-result'), findsNothing);
    expect(find.textContaining('a = 2,96 mm — mniej niż 3 mm'), findsOneWidget);
  });

  // Regresja z przeglądu: ekran zaokrąglał w dół, tekst do udostępnienia do
  // najbliższej (S275 fvw,d 233,657: „233,6” vs „233,7”; tak samo l_eff,
  // π·D, βLw).
  testWidgets('te same dane — te same liczby na ekranie i w tekście',
      (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    String kv(String k) => tester.widget<Text>(_key(k)).data!;
    String verdictText() {
      final f = find.descendant(
          of: find.byWidgetPredicate((w) =>
              w.key == const ValueKey('fillet-verdict-ok') ||
              w.key == const ValueKey('fillet-verdict-fail')),
          matching: find.byType(QuoteNotice));
      return tester.widget<QuoteNotice>(f).text;
    }

    void sameNumbers(String text, List<String> kvKeys) {
      for (final k in kvKeys) {
        expect(text, contains(kv(k)), reason: k);
      }
      expect(text, contains('F_w,Rd = ${_readout(tester, 'fillet-result')} kN'));
      final v = verdictText();
      final pct = RegExp(r'wykorzystanie ([\d,]+) %').firstMatch(v)!.group(1);
      final ed = RegExp(r'F_Ed ([\d,]+) kN').firstMatch(v)!.group(1);
      final rd = RegExp(r'F_Rd ([\d,]+) kN').firstMatch(v)!.group(1);
      expect(text, contains('Wykorzystanie $pct %'));
      expect(text, contains('F_Ed = $ed kN'));
      expect(rd, _readout(tester, 'fillet-result'));
      expect(
          text, contains('Wymagane a ${_readout(tester, 'fillet-required')} mm'));
    }

    // S275, a 3,37, 2 × l 640, uproszczona, F_Ed 900 kN.
    await _tap(tester, 'fillet-steel-s275');
    await _enter(tester, 'fillet-size', '3,37');
    await _enter(tester, 'fillet-length', '640');
    await _enter(tester, 'fillet-force', '900');
    expect(find.textContaining('l_eff = l − 2a = 633,2 mm'), findsOneWidget);
    await _reveal(tester, 'fillet-kv-beta');
    expect(kv('fillet-kv-strength'), '233,6 MPa');
    expect(kv('fillet-kv-leff'), '1266,5 mm');
    expect(kv('fillet-kv-beta'), '0,946');
    await _reveal(tester, 'fillet-required');
    await _tap(tester, 'fillet-share');
    var text = spy.calls.last.$1;
    expect(text, contains('l_eff = l − 2a = 633,2 mm'));
    await _reveal(tester, 'fillet-kv-beta');
    sameNumbers(text, [
      'fillet-kv-strength',
      'fillet-kv-leff',
      'fillet-kv-area',
      'fillet-kv-beta',
    ]);
    expect(text, isNot(contains('233,7')));

    // Rura D 60,35 (π·D = 189,595 → „189,5”), kierunkowa: 286,170 → „286,1”.
    await _tap(tester, 'fillet-layout-circumferential');
    await _enter(tester, 'fillet-tube', '60,35');
    await _tap(tester, 'fillet-method-directional');
    await _reveal(tester, 'fillet-kv-simplified');
    expect(kv('fillet-kv-strength'), '286,1 MPa');
    expect(kv('fillet-kv-leff'), '189,5 mm');
    await _reveal(tester, 'fillet-required');
    await _tap(tester, 'fillet-share');
    text = spy.calls.last.$1;
    expect(text, contains('l = π·D = 189,5 mm'));
    await _reveal(tester, 'fillet-kv-simplified');
    sameNumbers(text, [
      'fillet-kv-strength',
      'fillet-kv-simplified',
      'fillet-kv-leff',
      'fillet-kv-area',
    ]);
    expect(text, isNot(contains('189,6')));
    expect(text, isNot(contains('286,2')));
  });

  testWidgets('spoina obwodowa rury: l = π·D, metoda kierunkowa osiowo',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fillet-layout-circumferential');
    expect(find.textContaining('l = π·D = 189,4 mm'), findsOneWidget);
    expect(_readout(tester, 'fillet-result'), '157,4');
    expect(_key('fillet-length'), findsNothing);
    expect(_key('fillet-welds-2'), findsNothing);
    await _tap(tester, 'fillet-method-directional');
    expect(_key('fillet-dir-across'), findsNothing);
    // 360/√2 · 757,752 = 192,894 kN.
    expect(_readout(tester, 'fillet-result'), '192,8');
  });

  testWidgets('metoda kierunkowa w poprzek ≈ 1,22 × uproszczona',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'fillet-method-directional');
    expect(_readout(tester, 'fillet-result'), '187,3');
    await _tap(tester, 'fillet-dir-along');
    expect(_readout(tester, 'fillet-result'), '152,9');
    await _tap(tester, 'fillet-dir-angle');
    await _enter(tester, 'fillet-angle', '95');
    expect(_key('fillet-result'), findsNothing);
    expect(find.textContaining('od 0° (wzdłuż) do 90°'), findsOneWidget);
  });

  testWidgets('puste i nieczytelne pola → komunikat, nie wynik',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'fillet-size', '');
    expect(_key('fillet-result'), findsNothing);
    expect(find.textContaining('Podaj grubość obliczeniową spoiny a'),
        findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);

    await _enter(tester, 'fillet-size', '4');
    await _enter(tester, 'fillet-force', '1,2,3');
    expect(find.text('Wpisz liczbę większą od 0.'), findsOneWidget);
    expect(_key('fillet-verdict-ok'), findsNothing);
    expect(_key('fillet-verdict-fail'), findsNothing);

    await _enter(tester, 'fillet-t', '45');
    expect(_key('fillet-result'), findsNothing);
    expect(find.textContaining('części do 40 mm'), findsOneWidget);

    await _enter(tester, 'fillet-t', '10');
    await _enter(tester, 'fillet-length', '35');
    expect(_key('fillet-result'), findsNothing);
    expect(find.textContaining('Za krótka spoina: l_eff = l − 2a = 27,0 mm'),
        findsOneWidget);
  });

  testWidgets('jakie a wystarczy — także bez wpisanego a', (tester) async {
    await _pump(tester);
    await _enter(tester, 'fillet-size', '');
    await _enter(tester, 'fillet-force', '160');
    expect(_key('fillet-result'), findsNothing);
    await _reveal(tester, 'fillet-required');
    expect(_readout(tester, 'fillet-required'), '≥ 4,3');
    // Za duża siła dla tej długości.
    await _enter(tester, 'fillet-force', '500');
    await _reveal(tester, 'fillet-required-none');
    expect(find.textContaining('Nawet największe a dla tej długości'),
        findsOneWidget);
  });

  testWidgets('zastrzeżenie widoczne; pojedyncza spoina — ostrzeżenie 4.12',
      (tester) async {
    await _pump(tester);
    await _reveal(tester, 'fillet-disclaimer');
    expect(find.text(filletDisclaimer(en: false)), findsOneWidget);
    expect(_key('fillet-warn-single'), findsNothing);
    await _tap(tester, 'fillet-welds-1');
    await _reveal(tester, 'fillet-warn-single');
    expect(find.textContaining('p. 4.12'), findsOneWidget);
  });

  testWidgets('udostępnianie przez wstrzykniętą funkcję', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, spy: spy);
    await _enter(tester, 'fillet-force', '160');
    await _tap(tester, 'fillet-share');
    expect(spy.calls, hasLength(1));
    final (text, subject) = spy.calls.single;
    expect(subject, 'Nośność spoiny pachwinowej');
    expect(text, contains('F_w,Rd = 152,9 kN'));
    expect(text, contains('Wykorzystanie 104,6 % — SPOINA NIE WYSTARCZY.'));
    expect(text, contains('Wymagane a ≥ 4,3 mm'));
    expect(text, contains(filletDisclaimer(en: false)));
  });

  testWidgets('wersja EN', (tester) async {
    final spy = _ShareSpy();
    await _pump(tester, language: AppLanguage.en, spy: spy);
    expect(find.text('Fillet weld resistance'), findsOneWidget);
    expect(_readout(tester, 'fillet-result'), '152.9');
    await _enter(tester, 'fillet-force', '100');
    expect(find.textContaining('Sufficient — utilisation 65.4 %'),
        findsOneWidget);
    await _reveal(tester, 'fillet-disclaimer');
    expect(find.text(filletDisclaimer(en: true)), findsOneWidget);
    await _tap(tester, 'fillet-share');
    expect(spy.calls.single.$1, contains(filletDisclaimer(en: true)));
    expect(spy.calls.single.$2, 'Fillet weld resistance');
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez przepełnień',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _enter(tester, 'fillet-force', '160');
    await _tap(tester, 'fillet-welds-1');
    await _tap(tester, 'fillet-method-directional');
    await _tap(tester, 'fillet-dir-angle');
    await _enter(tester, 'fillet-length', '700');
    await _reveal(tester, 'fillet-warn-long');
    await _reveal(tester, 'fillet-disclaimer');
    expect(tester.takeException(), isNull);
    await _tap(tester, 'fillet-layout-circumferential');
    await _tap(tester, 'fillet-force-permanent');
    await _reveal(tester, 'fillet-disclaimer');
    expect(tester.takeException(), isNull);
    // Ta sama ścieżka po angielsku.
    await _pump(tester,
        language: AppLanguage.en, size: const Size(320, 640), textScale: 1.3);
    await _enter(tester, 'fillet-force', '500');
    await _reveal(tester, 'fillet-disclaimer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester);
    await _tap(tester, 'fillet-method-directional');
    await _tap(tester, 'fillet-dir-angle');
    final keys = [
      for (final s in WeldSteelGrade.values) 'fillet-steel-${s.name}',
      'fillet-t',
      'fillet-size-a',
      'fillet-size-z',
      'fillet-size',
      'fillet-layout-linear',
      'fillet-layout-circumferential',
      'fillet-length',
      'fillet-welds-1',
      'fillet-welds-2',
      'fillet-welds-4',
      'fillet-method-simplified',
      'fillet-method-directional',
      'fillet-dir-along',
      'fillet-dir-across',
      'fillet-dir-angle',
      'fillet-angle',
      'fillet-force-design',
      'fillet-force-permanent',
      'fillet-force-variable',
      'fillet-force',
      'fillet-share',
    ];
    for (final k in keys) {
      await _reveal(tester, k);
      final size = tester.getSize(_key(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await _tap(tester, 'fillet-layout-circumferential');
    final tube = tester.getSize(_key('fillet-tube'));
    expect(tube.height, greaterThanOrEqualTo(kMinTapTarget));
  });
}

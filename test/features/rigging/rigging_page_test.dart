// Ekran „Zawiesia i podwieszanie”: werdykt OK / STOP z kalkulatora, kąt
// od pionu i wierzchołkowy, zadusznik z potrzebnym WLL, przełącznik kg / t,
// brak etykiety, niesymetria, masa z rury, lista kontrolna i gotowość,
// zapamiętywanie danych, uszkodzony zapis, EN, wąski ekran z dużą czcionką,
// cele dotyku.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/rigging/rigging_calc.dart';
import 'package:cut_list_app/domain/rigging/rigging_checklist.dart';
import 'package:cut_list_app/features/rigging/rigging_page.dart';
import 'package:cut_list_app/features/rigging/rigging_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  // Wysoki widok: cała lista zbudowana, werdykt i gotowość zawsze w drzewie.
  Size size = const Size(900, 12000),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const RiggingPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _k(String key) => find.byKey(ValueKey(key));

Future<void> _show(WidgetTester tester, String key) async {
  if (_k(key).evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(_k(key), 300,
          scrollable: list, maxScrolls: 60);
    } catch (_) {
      await tester.scrollUntilVisible(_k(key), -300,
          scrollable: list, maxScrolls: 120);
    }
  }
  await tester.ensureVisible(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _show(tester, key);
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await _show(tester, key);
  await tester.enterText(_k(key), text);
  await tester.pumpAndSettle();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_k(key)).controller!.text;

Finder _verdict(RiggingVerdict v) => _k('rig-verdict-${v.name}');

String _kvValue(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(
          find.descendant(of: _k(key), matching: find.byType(Text)))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .toList();
  return texts.last;
}

/// Zielony pas 2 t, etykieta czytelna, masa w kg. [perLeg] — przy 2 / 3–4
/// cięgnach: zawieszka podaje WLL jednego cięgna (dwa osobne pasy).
Future<void> _greenSling(WidgetTester tester, String massKg,
    {bool perLeg = false}) async {
  await _enter(tester, 'rig-mass', massKg);
  await _tap(tester, 'rig-colour-green');
  await _tap(tester, 'rig-colour-fill');
  await _tap(tester, 'rig-label-readable');
  if (perLeg) await _tap(tester, 'rig-wll-basis-perLeg');
}

bool _selected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(_k(key)).selected;

String _verdictText(WidgetTester tester, RiggingVerdict v) => tester
    .widgetList<Text>(
        find.descendant(of: _verdict(v), matching: find.byType(Text)))
    .map((t) => t.data ?? '')
    .join('\n');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('puste dane → brak werdyktu, nie zielony', (tester) async {
    await _pump(tester);
    expect(find.text('Zawiesia i podwieszanie'), findsOneWidget);
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
    expect(_verdict(RiggingVerdict.ok), findsNothing);
    expect(_k('rig-ready-${LiftReadiness.notReady.name}'), findsOneWidget);
  });

  testWidgets('zielony 2 t, spool 1,6 t, 2 cięgna 60° od pionu → OK',
      (tester) async {
    await _pump(tester);
    await _greenSling(tester, '1600', perLeg: true);
    expect(_field(tester, 'rig-wll'), '2000');
    // Bez kąta — brak werdyktu.
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
    await _enter(tester, 'rig-angle', '60');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(
        find.descendant(of: _k('rig-capacity'), matching: find.text('2 000')),
        findsOneWidget);
    expect(_kvValue(tester, 'rig-factor'), contains('×1'));
    expect(_k('rig-tension'), findsOneWidget);
  });

  testWidgets(
      'kąt wierzchołkowy: przeliczenie wpisu, ten sam werdykt; '
      'α 121° → STOP', (tester) async {
    await _pump(tester);
    await _greenSling(tester, '2700', perLeg: true);
    await _enter(tester, 'rig-angle', '30');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget); // 2000 × 1,4 = 2800
    await _tap(tester, 'rig-angle-kind-included');
    expect(_field(tester, 'rig-angle'), '60');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(find.textContaining('= β 30° od pionu'), findsOneWidget);
    // Ten sam wpis 60 jako β od pionu → ×1,0 → przeciążenie.
    await _tap(tester, 'rig-angle-kind-fromVertical');
    await _enter(tester, 'rig-angle', '60');
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
    await _tap(tester, 'rig-angle-kind-included');
    await _enter(tester, 'rig-angle', '121');
    expect(_verdict(RiggingVerdict.angleNotAllowed), findsOneWidget);
  });

  testWidgets('zadusznik: 2 t i 1601 kg → STOP z potrzebnym WLL i pasem 3 t',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-choke');
    await _greenSling(tester, '1600');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget); // równo 1600 kg
    await _enter(tester, 'rig-mass', '1601');
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
    expect(_kvValue(tester, 'rig-series'), '3 t');
    expect(_kvValue(tester, 'rig-required'), startsWith('2 002 kg'));
    expect(find.textContaining('Potrzebne WLL co najmniej 2 002 kg'),
        findsOneWidget);
  });

  testWidgets('kg ↔ t: przełącznik przelicza pola, werdykt bez zmian',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-choke');
    await _greenSling(tester, '1600');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    await _tap(tester, 'rig-unit-t');
    expect(_field(tester, 'rig-mass'), '1,6');
    expect(_field(tester, 'rig-wll'), '2');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(find.descendant(of: _k('rig-capacity'), matching: find.text('1,6')),
        findsOneWidget);
    // 1,601 t = 1601 kg → STOP, tak samo jak w kg.
    await _enter(tester, 'rig-mass', '1,601');
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
    await _tap(tester, 'rig-unit-kg');
    expect(_field(tester, 'rig-mass'), '1601');
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
  });

  testWidgets('brak etykiety → STOP mimo koloru i zapasu nośności',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-straight');
    await _greenSling(tester, '100');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    await _tap(tester, 'rig-label-missing');
    expect(_verdict(RiggingVerdict.noLabel), findsOneWidget);
    expect(_k('rig-label-stop'), findsOneWidget);
    expect(find.textContaining('Decyduje etykieta, nie kolor'), findsOneWidget);
    expect(_k('rig-ready-${LiftReadiness.stop.name}'), findsOneWidget);
    // Kolor niezgodny z WLL — ostrzeżenie.
    await _enter(tester, 'rig-wll', '3000');
    expect(_k('rig-colour-mismatch'), findsOneWidget);
  });

  testWidgets('ładunek niesymetryczny → jak jedno cięgno', (tester) async {
    await _pump(tester);
    await _greenSling(tester, '2500', perLeg: true);
    await _enter(tester, 'rig-angle', '30');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    await _tap(tester, 'rig-asym');
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
    expect(_k('rig-asym-note'), findsOneWidget);
    expect(_k('rig-tension'), findsNothing);
  });

  testWidgets('masa z rury: DN15 z listy, 168,3 × 7,11, 6 m + 50 kg → 220 kg',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mass-pipe');
    await _tap(tester, 'rig-pipe-dn');
    await tester.tap(find.text('DN15 · 21,3 mm (1/2")').last);
    await tester.pumpAndSettle();
    expect(_field(tester, 'rig-pipe-od'), '21,3');
    await _enter(tester, 'rig-pipe-od', '168,3');
    await _enter(tester, 'rig-pipe-wall', '7,11');
    expect(_k('rig-pipe-problem'), findsOneWidget); // brak długości
    await _enter(tester, 'rig-pipe-length', '6');
    await _enter(tester, 'rig-pipe-extra', '50');
    expect(_kvValue(tester, 'rig-pipe-total'), '220 kg (0,22 t)');
    expect(_kvValue(tester, 'rig-mass-used'), '220 kg (0,22 t)');
  });

  testWidgets(
      'lista: niezaznaczona ≠ OK, komplet → można podnosić, wada → '
      'nie podnoś', (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-straight');
    await _greenSling(tester, '1000');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(_k('rig-checklist-${ChecklistVerdict.incomplete.name}'),
        findsOneWidget);
    expect(_k('rig-ready-${LiftReadiness.notReady.name}'), findsOneWidget);
    // Etykieta na liście = ten sam stan co w kalkulatorze (już OK).
    final label = tester.widget<ChoiceChip>(_k('rig-check-label-ok'));
    expect(label.selected, isTrue);
    for (final c in riggingChecksFor(SlingType.webbing)) {
      if (c.id == kRiggingLabelCheckId) continue;
      await _tap(tester, 'rig-check-${c.id}-ok');
    }
    expect(
        _k('rig-checklist-${ChecklistVerdict.complete.name}'), findsOneWidget);
    expect(_k('rig-ready-${LiftReadiness.go.name}'), findsOneWidget);
    await _tap(tester, 'rig-check-tx-heat-defect');
    expect(
        _k('rig-checklist-${ChecklistVerdict.rejected.name}'), findsOneWidget);
    expect(_k('rig-ready-${LiftReadiness.stop.name}'), findsOneWidget);
    expect(find.textContaining('Zawiesie do wycofania'), findsWidgets);
    await _tap(tester, 'rig-checklist-reset');
    expect(_k('rig-checklist-${ChecklistVerdict.incomplete.name}'),
        findsOneWidget);
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget,
        reason: 'reset zeruje też potwierdzenie etykiety');
  });

  testWidgets('po ponownym otwarciu WLL, masa i kolor są puste → brak werdyktu',
      (tester) async {
    // Wczoraj: czerwony pas 5 t, 4000 kg prosto — OK.
    await _pump(tester);
    await _tap(tester, 'rig-mode-straight');
    await _enter(tester, 'rig-mass', '4000');
    await _tap(tester, 'rig-colour-red');
    await _tap(tester, 'rig-colour-fill');
    await _tap(tester, 'rig-label-readable');
    await _tap(tester, 'rig-check-tx-cuts-ok');
    expect(_field(tester, 'rig-wll'), '5000');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);

    // Dziś: inny pas. Wracają tylko ustawienia, nie liczby ani kolor.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(_selected(tester, 'rig-mode-straight'), isTrue);
    expect(_field(tester, 'rig-wll'), '');
    expect(_field(tester, 'rig-mass'), '');
    expect(_selected(tester, 'rig-colour-red'), isFalse);
    expect(_selected(tester, 'rig-check-tx-cuts-ok'), isFalse);
    // Monter wpisuje masę i klika „etykieta czytelna” — bez WLL nie ma OK.
    await _enter(tester, 'rig-mass', '900');
    await _tap(tester, 'rig-label-readable');
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
    expect(_verdictText(tester, RiggingVerdict.incomplete),
        contains('WLL z etykiety'));
  });

  testWidgets('zmiana rodzaju zawiesia czyści WLL, kolor i etykietę',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-straight');
    await _greenSling(tester, '1000');
    expect(find.textContaining('WLL podnoszenia prostego z etykiety'),
        findsOneWidget);
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    await _tap(tester, 'rig-sling-roundsling');
    expect(_field(tester, 'rig-wll'), '');
    expect(_selected(tester, 'rig-colour-green'), isFalse);
    expect(_selected(tester, 'rig-label-readable'), isFalse);
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
  });

  testWidgets('zawieszka 2,8 t zespołu, 2 cięgna β 30° — bez mnożenia',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-sling-chain'); // domyślnie 2 cięgna
    await _enter(tester, 'rig-mass', '3000');
    await _enter(tester, 'rig-wll', '2800');
    await _enter(tester, 'rig-angle', '30');
    await _tap(tester, 'rig-label-readable');
    // Bez wyboru, co podaje zawieszka — brak werdyktu.
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
    expect(_verdictText(tester, RiggingVerdict.incomplete),
        contains('co podaje zawieszka'));
    await _tap(tester, 'rig-wll-basis-assembly');
    expect(_verdictText(tester, RiggingVerdict.incomplete),
        contains('zakres kąta'));
    await _tap(tester, 'rig-tag-range-upTo45');
    // 2800 kg zespołu < 3000 kg — STOP (nie 2,8 × 1,4 = 3,92 t).
    expect(_verdict(RiggingVerdict.overload), findsOneWidget);
    expect(
        find.descendant(of: _k('rig-capacity'), matching: find.text('2 800')),
        findsOneWidget);
    expect(find.textContaining('Potrzebne WLL zespołu co najmniej 3 000 kg'),
        findsOneWidget);
    // Ta sama liczba jako WLL jednego cięgna — mnożona.
    await _tap(tester, 'rig-wll-basis-perLeg');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(
        find.descendant(of: _k('rig-capacity'), matching: find.text('3 920')),
        findsOneWidget);
    // Wartość dla 0–45° nie obowiązuje przy β 50°.
    await _tap(tester, 'rig-wll-basis-assembly');
    await _tap(tester, 'rig-tag-range-upTo45');
    await _enter(tester, 'rig-angle', '50');
    expect(_verdictText(tester, RiggingVerdict.incomplete),
        contains('poza zakresem z zawieszki'));
    // Zmiana konfiguracji czyści WLL zespołu (to nie WLL jednego cięgna).
    await _tap(tester, 'rig-mode-straight');
    expect(_field(tester, 'rig-wll'), '');
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
  });

  testWidgets('„12,500” w kg → brak werdyktu; masa do obliczeń jednoznacznie',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-mode-straight');
    await _enter(tester, 'rig-wll', '20000');
    await _tap(tester, 'rig-label-readable');
    await _enter(tester, 'rig-mass', '12,500');
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
    expect(_verdictText(tester, RiggingVerdict.incomplete),
        contains('niejednoznaczny zapis masy'));
    expect(find.textContaining('Niejednoznaczny zapis — wpisz bez separatora'),
        findsOneWidget);
    expect(_k('rig-mass-used'), findsNothing);
    await _enter(tester, 'rig-mass', '12500');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(_kvValue(tester, 'rig-mass-used'), '12 500 kg (12,5 t)');
    expect(find.text('Do obliczeń: 12 500 kg (12,5 t)'), findsOneWidget);
    // W tonach „12,500” to jednoznacznie 12,5 t.
    await _tap(tester, 'rig-unit-t');
    await _enter(tester, 'rig-mass', '12,500');
    expect(_verdict(RiggingVerdict.ok), findsOneWidget);
    expect(_kvValue(tester, 'rig-mass-used'), '12 500 kg (12,5 t)');
    // Ponad 1000 t — literówka.
    await _enter(tester, 'rig-mass', '1001');
    expect(find.text('Najwyżej 1000 t — sprawdź zera'), findsOneWidget);
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
  });

  testWidgets('uszkodzony zapis → wartości domyślne i informacja, bez awarii',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {RiggingStore.key: '{"v":1,"sling":"konopie'});
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(_k('rig-restore-damaged'), findsOneWidget);
    expect(_field(tester, 'rig-mass'), '');
    expect(tester.widget<ChoiceChip>(_k('rig-sling-webbing')).selected, isTrue);
    expect(_verdict(RiggingVerdict.incomplete), findsOneWidget);
  });

  testWidgets('wersja EN', (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Slings and rigging'), findsOneWidget);
    await _tap(tester, 'rig-mode-choke');
    await _greenSling(tester, '1601');
    expect(
        find.descendant(
            of: _verdict(RiggingVerdict.overload),
            matching: find.textContaining('STOP — overload')),
        findsOneWidget);
    expect(find.text('Pre-lift checklist'.toUpperCase()), findsOneWidget);
    expect(find.textContaining('Needed WLL at least 2,002 kg'), findsOneWidget);
  });

  testWidgets('wąski ekran 360×640, tekst ×1,5 — bez overflow', (tester) async {
    await _pump(tester, size: const Size(360, 640), textScale: 1.5);
    expect(tester.takeException(), isNull);
    await _tap(tester, 'rig-mass-pipe');
    await _enter(tester, 'rig-pipe-od', '168,3');
    await _enter(tester, 'rig-pipe-wall', '7,11');
    await _enter(tester, 'rig-pipe-length', '12');
    await _enter(tester, 'rig-pipe-extra', '12,500'); // błąd pola
    await _tap(tester, 'rig-wll-basis-assembly');
    await _tap(tester, 'rig-tag-range-upTo60');
    await _tap(tester, 'rig-sling-wireRope');
    await _tap(tester, 'rig-mode-basketAngled');
    await _enter(tester, 'rig-angle', '50');
    await _tap(tester, 'rig-asym');
    await _tap(tester, 'rig-label-missing');
    await _enter(tester, 'rig-wll', '1000');
    expect(tester.takeException(), isNull);
    // Cała lista od góry do dołu, krokami — każdy element przechodzi layout.
    Future<void> sweep() async {
      await tester.drag(find.byType(ListView).first, const Offset(0, 20000));
      await tester.pumpAndSettle();
      for (var i = 0; i < 80; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -250));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
    }

    await sweep();
    expect(_k('rig-disclaimer'), findsOneWidget);
    // Inne układy: łańcuch, 3–4 cięgna na zadusznik, kąt wierzchołkowy, pas
    // z kolorem.
    await _tap(tester, 'rig-sling-chain');
    await _tap(tester, 'rig-mode-multiLeg');
    await _tap(tester, 'rig-choked-legs');
    await _tap(tester, 'rig-wll-basis-assembly');
    await _tap(tester, 'rig-tag-range-upTo45');
    await _enter(tester, 'rig-wll', '4200');
    await _tap(tester, 'rig-angle-kind-included');
    await sweep();
    await _tap(tester, 'rig-mode-basketParallel');
    expect(_k('rig-chain-basket'), findsOneWidget);
    await _tap(tester, 'rig-sling-roundsling');
    await _tap(tester, 'rig-colour-orange');
    await _tap(tester, 'rig-colour-fill');
    await sweep();
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    await _tap(tester, 'rig-colour-green');
    final keys = [
      'rig-mass-manual',
      'rig-mass-pipe',
      for (final u in MassUnit.values) 'rig-unit-${u.name}',
      'rig-mass',
      for (final s in SlingType.values) 'rig-sling-${s.name}',
      'rig-label-readable',
      'rig-label-missing',
      'rig-colour-green',
      'rig-colour-fill',
      for (final b in WllBasis.values) 'rig-wll-basis-${b.name}',
      'rig-wll',
      for (final m in HitchMode.values) 'rig-mode-${m.name}',
      'rig-choked-legs',
      for (final k in AngleKind.values) 'rig-angle-kind-${k.name}',
      'rig-angle',
      'rig-asym',
      'rig-check-label-ok',
      'rig-check-tx-cuts-defect',
      'rig-check-site-edges-na',
      'rig-checklist-reset',
    ];
    for (final k in keys) {
      await _show(tester, k);
      final size = tester.getSize(_k(k));
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    // Zakres kąta z zawieszki — widoczny po wyborze „WLL zespołu”.
    await _tap(tester, 'rig-mode-twoLeg');
    await _tap(tester, 'rig-wll-basis-assembly');
    for (final r in TagAngleRange.values) {
      final k = 'rig-tag-range-${r.name}';
      await _show(tester, k);
      expect(tester.getSize(_k(k)).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });
}

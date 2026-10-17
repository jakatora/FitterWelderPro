// Ekran „Tarcze i szlifierki”: brak danych ≠ OK, pełny zestaw → zgodne,
// za szybka szlifierka / za duża tarcza / po terminie → STOP, pasek barwny
// tylko podpowiada, „moje szlifierki” (zapis, wczytanie, usunięcie
// z cofnięciem), uszkodzony zapis → baner i kopia, lista kontrolna
// (niezaznaczone ≠ OK), EN, 360×640 z czcionką ×1,5, cele dotyku ≥ 48 dp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/domain/grinding/grinding_check.dart'
    show SpindleThread, kNbsp;
import 'package:cut_list_app/domain/grinding/grinding_checklist.dart';
import 'package:cut_list_app/features/grinding/grinding_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 18, 9);

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(420, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var n = 0;
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(language),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: GrindingPage(now: () => _now, newId: () => 'g${++n}'),
    ),
  ));
  await tester.pumpAndSettle();
}

const _lists = ['gr-check-list', 'gr-list-list', 'gr-sources-list'];

Finder _scrollable() {
  for (final l in _lists) {
    final f = find.descendant(
        of: find.byKey(ValueKey(l)), matching: find.byType(Scrollable));
    if (f.evaluate().isNotEmpty) return f.first;
  }
  throw StateError('no list');
}

/// Pokazuje element o kluczu [key] — od góry listy w dół.
Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    await tester.drag(_scrollable(), const Offset(0, 40000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(f, 200, scrollable: _scrollable());
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  return f;
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = await _show(tester, key);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = await _show(tester, key);
  await tester.enterText(
      find.descendant(of: f, matching: find.byType(EditableText)), text);
  await tester.pumpAndSettle();
}

Future<String> _verdict(WidgetTester tester) async {
  final f = await _show(tester, 'gr-verdict');
  return tester.widget<Text>(f).data!;
}

String _fieldText(WidgetTester tester, String key) => tester
    .widget<EditableText>(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)))
    .controller
    .text;

/// Zestaw zgodny: Ø125 / 11 000 / M14, tarcza 41 Ø125 80 m/s, otwór 22,23,
/// V 07/2027, cięcie z osłoną, stal węglowa.
Future<void> _fillOk(WidgetTester tester) async {
  await _enter(tester, 'gr-grinder-rpm', '11000');
  await _enter(tester, 'gr-grinder-d', '125');
  await _tap(tester, 'gr-thread-m14');
  await _tap(tester, 'gr-type-t41');
  await _enter(tester, 'gr-disc-d', '125');
  await _enter(tester, 'gr-disc-v', '80');
  await _tap(tester, 'gr-mount-bore2223');
  await _enter(tester, 'gr-expiry', 'V 07/2027');
  await _tap(tester, 'gr-op-cutting');
  await _tap(tester, 'gr-guard-yes');
  await _tap(tester, 'gr-material-carbonSteel');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('domyślnie PL: bez danych — brak werdyktu, nie OK',
      (tester) async {
    await _pump(tester);
    expect(find.text('Tarcze i szlifierki'), findsOneWidget);
    expect(await _verdict(tester), 'Brak werdyktu — uzupełnij dane z etykiety');
    expect(find.textContaining('Zgodne'), findsNothing);
  });

  testWidgets('pełny zestaw → zgodne; szlifierka 13 000 obr./min → STOP',
      (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    expect(
        await _verdict(tester), 'Zgodne — tarcza pasuje do szlifierki i pracy');
    final allowed = await _show(tester, 'gr-allowed-rpm');
    expect(tester.widget<Text>(allowed).data, '12${kNbsp}223 obr./min');
    final rim = await _show(tester, 'gr-rim-speed');
    expect(tester.widget<Text>(rim).data, '72 m/s');

    await _enter(tester, 'gr-grinder-rpm', '13000');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
  });

  testWidgets('tarcza 230 mm na szlifierce 125 mm → STOP mimo braków',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'gr-grinder-d', '125');
    await _enter(tester, 'gr-disc-d', '230');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
    expect(find.textContaining('Ø230 mm > Ø125 mm', skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('tarcza 8 500 obr./min (bez m/s) na szlifierce 11 000 → STOP',
      (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _enter(tester, 'gr-disc-v', '');
    await _enter(tester, 'gr-disc-n', '8500');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
  });

  testWidgets(
      'pasek barwny tylko podpowiada: bez nadruku brak werdyktu, '
      'przycisk wpisuje m/s', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _enter(tester, 'gr-disc-v', '');
    await _tap(tester, 'gr-stripe-red');
    expect(await _verdict(tester), 'Brak werdyktu — uzupełnij dane z etykiety');
    await _tap(tester, 'gr-stripe-apply');
    expect(_fieldText(tester, 'gr-disc-v'), '80');
    expect(
        await _verdict(tester), 'Zgodne — tarcza pasuje do szlifierki i pracy');
    // Inny pasek niż nadruk → ostrzeżenie.
    await _tap(tester, 'gr-stripe-green');
    expect(await _verdict(tester), 'Uwaga — przeczytaj ostrzeżenia');
  });

  testWidgets(
      'data ważności: po terminie → STOP, nieczytelna → brak '
      'werdyktu, brak daty na tarczy 41 → STOP', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _enter(tester, 'gr-expiry', '10/2026');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
    await _enter(tester, 'gr-expiry', '13/2027');
    expect(find.text('Nie rozpoznano daty — wpisz MM/RRRR'), findsOneWidget);
    expect(await _verdict(tester), 'Brak werdyktu — uzupełnij dane z etykiety');
    await _enter(tester, 'gr-expiry', '');
    await _tap(tester, 'gr-no-expiry');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
  });

  testWidgets(
      'nierdzewka: tarcza po stali węglowej → STOP, odsyłacz do '
      'modułów', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _tap(tester, 'gr-material-stainless');
    expect(await _verdict(tester), 'Brak werdyktu — uzupełnij dane z etykiety');
    await _tap(tester, 'gr-marked-yes');
    await _tap(tester, 'gr-carbon-yes');
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
    await _tap(tester, 'gr-carbon-no');
    expect(
        await _verdict(tester), 'Zgodne — tarcza pasuje do szlifierki i pracy');
    final note = await _show(tester, 'gr-material-note');
    expect(tester.widget<Text>(note).data, contains('„Trawienie i pasywacja”'));
  });

  testWidgets('moje szlifierki: zapis, wczytanie, usunięcie z cofnięciem',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'gr-grinder-rpm', '11000');
    await _enter(tester, 'gr-grinder-d', '125');
    await _tap(tester, 'gr-thread-m14');
    await _tap(tester, 'gr-save-grinder');
    expect(find.byKey(const ValueKey('gr-grinder-name')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('gr-grinder-name')), 'Bosch 125');
    await tester.tap(find.byKey(const ValueKey('gr-grinder-name-save')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
        decodeGrinders(prefs.getString(kGrindersPrefsKey)!)
            .grinders
            .single
            .name,
        'Bosch 125');

    // Nowy ekran: szlifierka na liście, dotknięcie wypełnia pola.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(_fieldText(tester, 'gr-grinder-rpm'), '');
    await _tap(tester, 'gr-grinder-g1');
    expect(_fieldText(tester, 'gr-grinder-rpm'), '11000');
    expect(_fieldText(tester, 'gr-grinder-d'), '125');

    await _tap(tester, 'gr-grinder-del-g1');
    expect(find.byKey(const ValueKey('gr-grinder-g1')), findsNothing);
    expect(
        decodeGrinders(prefs.getString(kGrindersPrefsKey)!).grinders, isEmpty);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gr-grinder-g1'), skipOffstage: false),
        findsOneWidget);
    expect(decodeGrinders(prefs.getString(kGrindersPrefsKey)!).grinders,
        hasLength(1));
  });

  testWidgets('uszkodzony zapis szlifierek → baner, kopia, nic nie znika',
      (tester) async {
    const raw = '[{"id":"a","name":"A","rpm":11000,"d":125},{"id":"x"}]';
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: raw});
    await _pump(tester);
    expect(find.byKey(const ValueKey('gr-grinders-damaged')), findsOneWidget);
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), raw);
  });

  testWidgets('lista kontrolna: niezaznaczone ≠ OK, wszystkie → gotowe',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('gr-tab-list')));
    await tester.pumpAndSettle();
    String status() => tester
        .widget<Text>(find.byKey(const ValueKey('gr-checklist-status')))
        .data!;
    expect(status(), startsWith('Niekompletna: 0/${kGrindingChecks.length}'));
    for (final c in kGrindingChecks.skip(1)) {
      await _tap(tester, 'gr-check-${c.id}');
    }
    await _show(tester, 'gr-checklist-status');
    expect(
        status(), startsWith('Niekompletna: ${kGrindingChecks.length - 1}/'));
    await _tap(tester, 'gr-check-${kGrindingChecks.first.id}');
    await _show(tester, 'gr-checklist-status');
    expect(
        status(),
        'Gotowe: ${kGrindingChecks.length}/'
        '${kGrindingChecks.length}');

    await tester.tap(find.byKey(const ValueKey('gr-tab-check')));
    await tester.pumpAndSettle();
    final line = await _show(tester, 'gr-verdict-checklist');
    expect(
        tester.widget<Text>(line).data,
        'Przed pracą — lista kontrolna: ${kGrindingChecks.length}/'
        '${kGrindingChecks.length}');

    await tester.tap(find.byKey(const ValueKey('gr-tab-list')));
    await tester.pumpAndSettle();
    await _tap(tester, 'gr-checklist-clear');
    expect(status(), startsWith('Niekompletna: 0/'));
  });

  testWidgets('wersja EN', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Discs and grinders'), findsOneWidget);
    expect(await _verdict(tester), 'No verdict — complete the label data');
    await _fillOk(tester);
    expect(await _verdict(tester),
        'Compatible — disc matches the grinder and the job');
    final allowed = await _show(tester, 'gr-allowed-rpm');
    expect(tester.widget<Text>(allowed).data, '12,223 rpm');
    await tester.tap(find.byKey(const ValueKey('gr-tab-sources')));
    await tester.pumpAndSettle();
    expect(find.textContaining('EN 12413:2019'), findsWidgets);
  });

  testWidgets('wąski ekran 360×640, czcionka 1,5: bez przepełnień',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: encodeGrinders(const [
        GrinderProfile(
            id: 'a',
            name: 'Szlifierka kątowa z hali B — stanowisko prefabrykacji rur',
            maxRpm: 11000,
            diameterMm: 125,
            thread: SpindleThread.m14),
      ]),
    });
    await _pump(tester, size: const Size(360, 640), textScale: 1.5);
    expect(tester.takeException(), isNull);

    Future<void> scrollThrough() async {
      await tester.drag(_scrollable(), const Offset(0, 40000));
      await tester.pumpAndSettle();
      for (var i = 0; i < 200; i++) {
        final s = _scrollable();
        final pos = tester.state<ScrollableState>(s).position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        await tester.drag(s, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    await scrollThrough();
    await _tap(tester, 'gr-grinder-a');
    await _tap(tester, 'gr-type-t42');
    await _enter(tester, 'gr-disc-d', '230');
    await _tap(tester, 'gr-stripe-blueYellow');
    await _tap(tester, 'gr-mount-unc58');
    await _enter(tester, 'gr-expiry', 'V 07/2072');
    await _tap(tester, 'gr-op-cutting');
    await _tap(tester, 'gr-material-stainless');
    expect(tester.takeException(), isNull);
    expect(await _verdict(tester), 'STOP — nie używaj tego zestawu');
    await scrollThrough();

    for (final tab in ['gr-tab-list', 'gr-tab-sources']) {
      // Przy czcionce ×1,5 pasek zakładek się przewija — trzecia zakładka
      // jest częściowo za krawędzią.
      await tester.ensureVisible(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Zakładka naprawdę się przełączyła.
      expect(
          find.byKey(ValueKey(
              tab == 'gr-tab-list' ? 'gr-list-list' : 'gr-sources-list')),
          findsOneWidget);
      await scrollThrough();
    }
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    await _tap(tester, 'gr-op-cutting');
    await _tap(tester, 'gr-material-stainless');
    for (final key in [
      'gr-thread-m14',
      'gr-type-t41',
      'gr-stripe-red',
      'gr-mount-bore2223',
      'gr-no-expiry',
      'gr-op-cutting',
      'gr-guard-yes',
      'gr-guard-no',
      'gr-material-stainless',
      'gr-marked-yes',
      'gr-carbon-no',
      'gr-save-grinder',
    ]) {
      final f = await _show(tester, key);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: key);
      expect(tester.getSize(f).width, greaterThanOrEqualTo(kMinTapTarget),
          reason: key);
    }
    await tester.tap(find.byKey(const ValueKey('gr-tab-list')));
    await tester.pumpAndSettle();
    for (final c in kGrindingChecks) {
      final f = await _show(tester, 'gr-check-${c.id}');
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: c.id);
    }
  });
}

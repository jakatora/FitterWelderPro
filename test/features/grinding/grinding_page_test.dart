// Ekran „Tarcze i szlifierki”: brak danych ≠ OK, pełny zestaw → zgodne,
// za szybka szlifierka / za duża tarcza / po terminie → STOP, pasek barwny
// tylko podpowiada (nie ma przycisku przepisania koloru do danych),
// otwór tarczy wobec kołnierza (tak/nie), nieczytelna data przy każdym
// typie, „moje szlifierki” (zapis, wczytanie, „Zapisz zmiany” po id,
// usunięcie z cofnięciem — także po zamknięciu ekranu, szybkie usunięcia),
// uszkodzony zapis ≠ niedostępna pamięć, lista kontrolna (niezaznaczone
// ≠ OK), EN, 360×640 z czcionką ×1,5 (wszystkie zakładki widoczne), cele
// dotyku ≥ 48 dp.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/grinding/grinder_profile.dart';
import 'package:cut_list_app/domain/grinding/grinding_check.dart'
    show SpindleThread, kNbsp;
import 'package:cut_list_app/domain/grinding/grinding_checklist.dart';
import 'package:cut_list_app/features/grinding/grinding_page.dart';
import 'package:cut_list_app/features/grinding/grinding_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 18, 9);

const _verdictOk = 'Zgodne — tarcza pasuje do szlifierki i pracy';
const _verdictStop = 'STOP — nie używaj tego zestawu';
const _verdictNone = 'Brak werdyktu — uzupełnij dane z etykiety';
const _verdictWarn = 'Uwaga — przeczytaj ostrzeżenia';

Widget _app(Widget home,
        {AppLanguage language = AppLanguage.pl, double textScale = 1.0}) =>
    AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(420, 2400),
  double textScale = 1.0,
  GrinderStore store = const GrinderStore(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var n = 0;
  await tester.pumpWidget(_app(
    GrindingPage(store: store, now: () => _now, newId: () => 'g${++n}'),
    language: language,
    textScale: textScale,
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

Future<List<GrinderProfile>> _saved() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kGrindersPrefsKey);
  return raw == null ? const [] : decodeGrinders(raw).grinders;
}

/// Zestaw zgodny: Ø125 / 11 000 / M14, tarcza 41 Ø125 80 m/s, otwór 22,23
/// pasujący do kołnierza, V 07/2027, cięcie z osłoną, stal węglowa.
Future<void> _fillOk(WidgetTester tester, {String rpm = '11000'}) async {
  await _enter(tester, 'gr-grinder-rpm', rpm);
  await _enter(tester, 'gr-grinder-d', '125');
  await _tap(tester, 'gr-thread-m14');
  await _tap(tester, 'gr-type-t41');
  await _enter(tester, 'gr-disc-d', '125');
  await _enter(tester, 'gr-disc-v', '80');
  await _tap(tester, 'gr-mount-bore2223');
  await _tap(tester, 'gr-bore-yes');
  await _enter(tester, 'gr-expiry', 'V 07/2027');
  await _tap(tester, 'gr-op-cutting');
  await _tap(tester, 'gr-guard-yes');
  await _tap(tester, 'gr-material-carbonSteel');
}

/// Zapisuje szlifierkę z bieżących pól pod nazwą [name].
Future<void> _saveAs(WidgetTester tester, String name,
    {String key = 'gr-save-grinder'}) async {
  await _tap(tester, key);
  await tester.enterText(find.byKey(const ValueKey('gr-grinder-name')), name);
  await tester.tap(find.byKey(const ValueKey('gr-grinder-name-save')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('domyślnie PL: bez danych — brak werdyktu, nie OK',
      (tester) async {
    await _pump(tester);
    expect(find.text('Tarcze i szlifierki'), findsOneWidget);
    expect(await _verdict(tester), _verdictNone);
    expect(find.textContaining('Zgodne'), findsNothing);
  });

  testWidgets('pełny zestaw → zgodne; szlifierka 13 000 obr./min → STOP',
      (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    expect(await _verdict(tester), _verdictOk);
    final allowed = await _show(tester, 'gr-allowed-rpm');
    expect(tester.widget<Text>(allowed).data, '12${kNbsp}223 obr./min');
    final rim = await _show(tester, 'gr-rim-speed');
    expect(tester.widget<Text>(rim).data, '72 m/s');

    await _enter(tester, 'gr-grinder-rpm', '13000');
    expect(await _verdict(tester), _verdictStop);
  });

  testWidgets('tarcza 230 mm na szlifierce 125 mm → STOP mimo braków',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'gr-grinder-d', '125');
    await _enter(tester, 'gr-disc-d', '230');
    expect(await _verdict(tester), _verdictStop);
    expect(find.textContaining('Ø230 mm > Ø125 mm', skipOffstage: false),
        findsOneWidget);
  });

  testWidgets('tarcza 8 500 obr./min (bez m/s) na szlifierce 11 000 → STOP',
      (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _enter(tester, 'gr-disc-v', '');
    await _enter(tester, 'gr-disc-n', '8500');
    expect(await _verdict(tester), _verdictStop);
  });

  testWidgets(
      'pasek ≠ nadruk (63 m/s, pasek czerwony): ostrzeżenie zostaje, liczy '
      'się nadruk, nie ma przycisku przepisania koloru', (tester) async {
    await _pump(tester);
    await _fillOk(tester, rpm: '9000');
    await _enter(tester, 'gr-disc-v', '63');
    expect(await _verdict(tester), _verdictOk);
    await _tap(tester, 'gr-stripe-red');
    expect(find.byKey(const ValueKey('gr-stripe-apply'), skipOffstage: false),
        findsNothing);
    expect(_fieldText(tester, 'gr-disc-v'), '63');
    expect(await _verdict(tester), _verdictWarn);
    // 63·60 000/(π·125) → 9 625 (z paska byłoby 12 223).
    final allowed = await _show(tester, 'gr-allowed-rpm');
    expect(tester.widget<Text>(allowed).data, '9${kNbsp}625 obr./min');
    // Sam pasek bez nadruku nie wystarcza.
    await _enter(tester, 'gr-disc-v', '');
    expect(await _verdict(tester), _verdictNone);
  });

  testWidgets(
      'otwór tarczy: bez odpowiedzi brak werdyktu, „nie pasuje” → STOP, '
      'zmiana otworu kasuje odpowiedź', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    expect(await _verdict(tester), _verdictOk);
    await _tap(tester, 'gr-bore-no');
    expect(await _verdict(tester), _verdictStop);
    await _tap(tester, 'gr-bore-no'); // cofnięcie odpowiedzi = „nie wiem”
    expect(await _verdict(tester), _verdictNone);
    await _tap(tester, 'gr-bore-yes');
    expect(await _verdict(tester), _verdictOk);
    // Ø16 zamiast Ø22,23 — stare „pasuje” nie przechodzi.
    await _tap(tester, 'gr-mount-bore16');
    expect(await _verdict(tester), _verdictNone);
  });

  testWidgets(
      'data ważności: po terminie → STOP, nieczytelna → brak '
      'werdyktu, brak daty na tarczy 41 → STOP', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _enter(tester, 'gr-expiry', '10/2026');
    expect(await _verdict(tester), _verdictStop);
    await _enter(tester, 'gr-expiry', '13/2027');
    expect(find.text('Nie rozpoznano daty — wpisz MM/RRRR'), findsOneWidget);
    expect(await _verdict(tester), _verdictNone);
    await _enter(tester, 'gr-expiry', '');
    await _tap(tester, 'gr-no-expiry');
    expect(await _verdict(tester), _verdictStop);
  });

  testWidgets(
      'tarcza listkowa z nieczytelną datą („07/2O27”) → brak werdyktu, '
      'pusta data → zgodne', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _tap(tester, 'gr-type-flap');
    await _tap(tester, 'gr-op-grinding');
    await _enter(tester, 'gr-expiry', '');
    expect(await _verdict(tester), _verdictOk);
    await _enter(tester, 'gr-expiry', '07/2O27');
    // Znak spoza cyfr nie jest po cichu wycinany z pola.
    expect(_fieldText(tester, 'gr-expiry'), '07/2O27');
    expect(await _verdict(tester), _verdictNone);
    await _enter(tester, 'gr-expiry', '13/2027');
    expect(await _verdict(tester), _verdictNone);
  });

  testWidgets(
      'nierdzewka: tarcza po stali węglowej → STOP, odsyłacz do '
      'modułów', (tester) async {
    await _pump(tester);
    await _fillOk(tester);
    await _tap(tester, 'gr-material-stainless');
    expect(await _verdict(tester), _verdictNone);
    await _tap(tester, 'gr-marked-yes');
    await _tap(tester, 'gr-carbon-yes');
    expect(await _verdict(tester), _verdictStop);
    await _tap(tester, 'gr-carbon-no');
    expect(await _verdict(tester), _verdictOk);
    final note = await _show(tester, 'gr-material-note');
    expect(tester.widget<Text>(note).data, contains('„Trawienie i pasywacja”'));
    // Zmiana na aluminium — inne pytania, odpowiedzi od nowa.
    await _tap(tester, 'gr-material-aluminium');
    expect(await _verdict(tester), _verdictNone);
  });

  testWidgets('moje szlifierki: zapis, wczytanie, usunięcie z cofnięciem',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'gr-grinder-rpm', '11000');
    await _enter(tester, 'gr-grinder-d', '125');
    await _tap(tester, 'gr-thread-m14');
    await _saveAs(tester, 'Bosch 125');
    expect((await _saved()).single.name, 'Bosch 125');

    // Nowy ekran: szlifierka na liście, dotknięcie wypełnia pola.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(_fieldText(tester, 'gr-grinder-rpm'), '');
    await _tap(tester, 'gr-grinder-g1');
    expect(_fieldText(tester, 'gr-grinder-rpm'), '11000');
    expect(_fieldText(tester, 'gr-grinder-d'), '125');

    await _tap(tester, 'gr-grinder-del-g1');
    expect(find.byKey(const ValueKey('gr-grinder-g1')), findsNothing);
    expect(await _saved(), isEmpty);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gr-grinder-g1'), skipOffstage: false),
        findsOneWidget);
    expect(await _saved(), hasLength(1));
  });

  testWidgets(
      'edycja: wczytana szlifierka → „Zapisz zmiany” po id, bez '
      'duplikatu', (tester) async {
    await _pump(tester);
    await _enter(tester, 'gr-grinder-rpm', '11000');
    await _enter(tester, 'gr-grinder-d', '125');
    await _saveAs(tester, 'Bosch 125');
    await _saveAs(tester, 'Druga'); // „Zapisz jako nową” → g2

    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    expect(find.byKey(const ValueKey('gr-update-grinder')), findsNothing);
    await _tap(tester, 'gr-grinder-g1');
    final update = await _show(tester, 'gr-update-grinder');
    expect(find.descendant(of: update, matching: find.textContaining('Bosch')),
        findsOneWidget);
    await _enter(tester, 'gr-grinder-rpm', '10000');
    await _tap(tester, 'gr-thread-m16');
    await _saveAs(tester, 'Bosch 125 (serwis)', key: 'gr-update-grinder');

    final saved = await _saved();
    expect(saved.map((g) => g.id), ['g1', 'g2']);
    expect(saved.first.name, 'Bosch 125 (serwis)');
    expect(saved.first.maxRpm, 10000);
    expect(saved.first.thread, SpindleThread.m16);
    expect(saved.last.maxRpm, 11000);
  });

  testWidgets(
      'dwa szybkie usunięcia: pierwsze nie wraca; „Cofnij” przywraca tylko '
      'ostatnio usunięty', (tester) async {
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: encodeGrinders(const [
        GrinderProfile(id: 'a', name: 'A', maxRpm: 11000, diameterMm: 125),
        GrinderProfile(id: 'b', name: 'B', maxRpm: 8500, diameterMm: 180),
        GrinderProfile(id: 'c', name: 'C', maxRpm: 6600, diameterMm: 230),
      ]),
    });
    await _pump(tester);
    final delA = await _show(tester, 'gr-grinder-del-a');
    final delB = find.byKey(const ValueKey('gr-grinder-del-b'));
    // Bez czekania na zapis pierwszego.
    await tester.tap(delA);
    await tester.tap(delB);
    await tester.pumpAndSettle();
    expect((await _saved()).map((g) => g.id), ['c']);
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsNothing);
    expect(find.byKey(const ValueKey('gr-grinder-b')), findsNothing);

    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect((await _saved()).map((g) => g.id), ['b', 'c']);
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsNothing);
  });

  testWidgets('„Cofnij” po zamknięciu ekranu przywraca usuniętą szlifierkę',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: encodeGrinders(const [
        GrinderProfile(id: 'a', name: 'A', maxRpm: 11000, diameterMm: 125),
        GrinderProfile(id: 'b', name: 'B', maxRpm: 8500, diameterMm: 180),
      ]),
    });
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => GrindingPage(now: () => _now))),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await _tap(tester, 'gr-grinder-del-a');
    expect((await _saved()).map((g) => g.id), ['b']);

    // Zamknięcie ekranu — pasek z „Cofnij” zostaje na poprzednim.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(GrindingPage), findsNothing);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect((await _saved()).map((g) => g.id), ['a', 'b']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uszkodzony zapis szlifierek → baner, kopia, nic nie znika',
      (tester) async {
    const raw = '[{"id":"a","name":"A","rpm":11000,"d":125},{"id":"x"}]';
    SharedPreferences.setMockInitialValues({kGrindersPrefsKey: raw});
    await _pump(tester);
    expect(find.byKey(const ValueKey('gr-grinders-damaged')), findsOneWidget);
    expect(find.byKey(const ValueKey('gr-grinders-unavailable')), findsNothing);
    expect(find.byKey(const ValueKey('gr-grinder-a')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersCorruptPrefsKey), raw);
  });

  testWidgets('zajęta kopia zatrzymuje zapis i pokazuje komunikat',
      (tester) async {
    const broken = 'drugie uszkodzenie';
    const earlier = 'pierwsze uszkodzenie';
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: broken,
      kGrindersCorruptPrefsKey: earlier,
    });
    await _pump(tester);
    await _enter(tester, 'gr-grinder-rpm', '11000');
    await _enter(tester, 'gr-grinder-d', '125');
    await _saveAs(tester, 'Nowa');
    expect(find.textContaining('istniejące dane zachowano'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGrindersPrefsKey), broken);
    expect(prefs.getString(kGrindersCorruptPrefsKey), earlier);
  });

  testWidgets(
      'pamięć niedostępna → osobny baner (nie „uszkodzony zapis”), '
      'sprawdzenie działa', (tester) async {
    await _pump(tester,
        store: GrinderStore(
            openPrefs: () =>
                Future<SharedPreferences>.error(StateError('channel down'))));
    expect(
        find.byKey(const ValueKey('gr-grinders-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('gr-grinders-damaged')), findsNothing);
    expect(find.textContaining('Pamięć aplikacji jest teraz niedostępna'),
        findsOneWidget);
    expect(find.textContaining('kopia'), findsNothing);
    expect(find.byKey(const ValueKey('gr-grinders-retry')), findsOneWidget);
    await _fillOk(tester);
    expect(await _verdict(tester), _verdictOk);
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

  for (final language in AppLanguage.values) {
    testWidgets(
        '360×640, czcionka 1,5 (${language.name}): wszystkie trzy zakładki '
        'widoczne w całości', (tester) async {
      await _pump(tester,
          language: language, size: const Size(360, 640), textScale: 1.5);
      final tabs = ['gr-tab-check', 'gr-tab-list', 'gr-tab-sources'];
      for (final key in tabs) {
        final tab = find.byKey(ValueKey(key));
        final rect = tester.getRect(tab);
        expect(rect.left, greaterThanOrEqualTo(0), reason: key);
        expect(rect.right, lessThanOrEqualTo(360), reason: key);
        final label = find.descendant(of: tab, matching: find.byType(RichText));
        final p = tester.renderObject<RenderParagraph>(label);
        // Etykieta w całości: nie ucięta i nie wygaszona (akapit ma pełną
        // szerokość tekstu) …
        expect(p.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(p.size.width + 0.5),
            reason: key);
        // … a narysowana (po ewentualnym pomniejszeniu) mieści się
        // w zakładce i na ekranie.
        final drawn = tester.getRect(label);
        expect(drawn.left, greaterThanOrEqualTo(rect.left - 0.5), reason: key);
        expect(drawn.right, lessThanOrEqualTo(rect.right + 0.5), reason: key);
        expect(drawn.right, lessThanOrEqualTo(360), reason: key);
      }
      // Zakładki zajmują pasek po równo, bez przewijania.
      expect(
          find.descendant(
              of: find.byType(TabBar), matching: find.byType(Scrollable)),
          findsNothing);
      for (final key in tabs) {
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('gr-sources-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
    await _tap(tester, 'gr-mount-bore16');
    await _tap(tester, 'gr-bore-no');
    await _enter(tester, 'gr-expiry', 'V 07/2072');
    await _tap(tester, 'gr-op-cutting');
    await _tap(tester, 'gr-material-stainless');
    expect(tester.takeException(), isNull);
    expect(await _verdict(tester), _verdictStop);
    await scrollThrough();

    for (final tab in ['gr-tab-list', 'gr-tab-sources']) {
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
    SharedPreferences.setMockInitialValues({
      kGrindersPrefsKey: encodeGrinders(const [
        GrinderProfile(id: 'a', name: 'A', maxRpm: 11000, diameterMm: 125),
      ]),
    });
    await _pump(tester);
    await _tap(tester, 'gr-grinder-a');
    await _tap(tester, 'gr-mount-bore2223');
    await _tap(tester, 'gr-op-cutting');
    await _tap(tester, 'gr-material-stainless');
    for (final key in [
      'gr-grinder-a',
      'gr-grinder-del-a',
      'gr-update-grinder',
      'gr-thread-m14',
      'gr-type-t41',
      'gr-stripe-red',
      'gr-mount-bore2223',
      'gr-bore-yes',
      'gr-bore-no',
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

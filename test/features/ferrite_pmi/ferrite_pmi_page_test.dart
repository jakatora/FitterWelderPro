// Ekran „Ferryt i PMI”: nowy protokół — zakres ze specyfikacji, odczyty
// 28/31/45 (poza zakresem), FN przy wymaganiu w % (brak werdyktu), średnia
// z N, preset typowy dla innego miejsca; PMI 316L z Mo 1,9 (niezgodny /
// do weryfikacji z niepewnością / zgodny bez weryfikacji C); historia
// z limitem, usuwanie z cofnięciem, uszkodzony zapis, udostępnianie tekstu,
// EN, wąski ekran 360×640 z tekstem ×1,5, cele dotyku ≥ 48 dp.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_protocol.dart';
import 'package:cut_list_app/domain/ferrite_pmi/pmi.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_edit_page.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_page.dart';
import 'package:cut_list_app/features/ferrite_pmi/ferrite_pmi_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 18, 9, 30);

/// Preset duplex (spoina i SWC, % ferrytu) używany w teście.
const kTestDuplexPreset = 'iso17781_weld';

/// Magazyn, którego usuwanie zawsze się nie udaje (np. brak miejsca).
class _FailingDeleteStore extends FerritePmiStore {
  const _FailingDeleteStore();
  @override
  Future<void> delete(String id) async =>
      throw StateError('SharedPreferences.setString failed');
}

class _Spy {
  final List<(String, String)> texts = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
}

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

Future<_Spy> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spy = _Spy();
  var n = 0;
  await tester.pumpWidget(_app(
    FerritePmiPage(
      now: () => _now,
      newId: () => 'fp-${++n}',
      shareText: spy.text,
    ),
    language: language,
    textScale: textScale,
  ));
  await tester.pumpAndSettle();
  return spy;
}

Finder _scrollable(String listKey) => find
    .descendant(
        of: find.byKey(ValueKey(listKey)), matching: find.byType(Scrollable))
    .first;

String get _currentList =>
    find.byKey(const ValueKey('fp-edit-list')).evaluate().isNotEmpty
        ? 'fp-edit-list'
        : 'fp-list';

Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    final list = _currentList;
    await tester.drag(_scrollable(list), const Offset(0, 20000));
    await tester.pumpAndSettle();
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(f, 300, scrollable: _scrollable(list));
    }
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  return f;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final f = await _show(tester, key);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = await _show(tester, key);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// Pozycja listy w arkuszu wyboru (przewijanym) — najpierw widoczna.
Future<void> _tapInSheet(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _addReadings(
    WidgetTester tester, int site, List<String> values) async {
  for (final v in values) {
    await _enter(tester, 'fp-site-$site-input', v);
    await _tapKey(tester, 'fp-site-$site-add');
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

bool _has(String key) => find.byKey(ValueKey(key)).evaluate().isNotEmpty;

FerritePmiProtocol _saved(int i) => FerritePmiProtocol(
      id: 'old-$i',
      date: '2026-10-01',
      title: 'Spoina $i',
      customMin: '30',
      customMax: '70',
      sites: [
        FerriteSite(
            id: 'old-$i-s',
            location: FerriteLocation.weld,
            readings: const ['45']),
      ],
      updatedAt: i,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'ferryt ze specyfikacji: 28, 31, 45 przy 30–70 → poza zakresem, zapis '
      'w historii', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-title', 'Linia 4"-P-1001, spoina W-12');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _addReadings(tester, 0, ['28', '31', '45']);
    expect(_has('fp-site-0-verdict-fail'), isTrue);
    expect(_has('fp-ferrite-verdict-fail'), isTrue);
    // Odczyt 28 oznaczony jako poniżej zakresu.
    expect(find.text('28 ↓'), findsOneWidget);

    // Usunięcie odczytu 28 → w zakresie.
    await _tapKey(tester, 'fp-site-0-r-0');
    await tester.tap(find.byKey(const ValueKey('fp-reading-delete')));
    await tester.pumpAndSettle();
    expect(_has('fp-site-0-verdict-pass'), isTrue);
    expect(_has('fp-ferrite-verdict-pass'), isTrue);

    await _back(tester);
    expect(_has('fp-item-0'), isTrue);
    final tile = find.byKey(const ValueKey('fp-item-0-line-0'));
    expect(tester.widget<Text>(tile).data, 'Ferryt: W ZAKRESIE');
  });

  testWidgets('odczyt 29,96 przy min 30 — poza zakresem (bez zaokrąglania)',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _addReadings(tester, 0, ['29,96']);
    expect(_has('fp-site-0-verdict-fail'), isTrue);
    expect(find.text('29,96 ↓'), findsOneWidget);
  });

  testWidgets('FN przy wymaganiu w % → brak werdyktu i ostrzeżenie',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _tapKey(tester, 'fp-req-unit-percent');
    await _addReadings(tester, 0, ['45', '50']);
    expect(_has('fp-unit-mismatch'), isTrue);
    expect(_has('fp-site-0-verdict-none'), isTrue);
    expect(_has('fp-ferrite-verdict-none'), isTrue);
    // Przyrząd przestawiony na % → werdykt.
    await _tapKey(tester, 'fp-read-unit-percent');
    expect(_has('fp-unit-mismatch'), isFalse);
    expect(_has('fp-site-0-verdict-pass'), isTrue);
  });

  testWidgets('średnia z N: mniej odczytów niż N → brak werdyktu',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _tapKey(tester, 'fp-rule-average');
    await _enter(tester, 'fp-min-count', '3');
    await _addReadings(tester, 0, ['28', '45']);
    expect(_has('fp-site-0-verdict-none'), isTrue);
    await _addReadings(tester, 0, ['31']);
    // Średnia 34,67 w zakresie mimo 28 poniżej.
    expect(_has('fp-site-0-verdict-pass'), isTrue);
    final status =
        tester.widget<Text>(find.byKey(const ValueKey('fp-site-0-status')));
    expect(status.data, contains('średnia 34,7'));
    expect(status.data, contains('poza zakresem: 1 z 3'));
  });

  testWidgets('nieczytelny odczyt nie jest dodawany', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-site-0-input', '1,2,3');
    await _tapKey(tester, 'fp-site-0-add');
    expect(find.text('Nieczytelna liczba albo poza skalą (0–100 %)'),
        findsOneWidget);
    expect(_has('fp-site-0-r-0'), isFalse);
  });

  testWidgets(
      'preset typowy: etykieta TYPOWE, źródło; materiał rodzimy → '
      'brak werdyktu', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _tapKey(tester, 'fp-preset-picker');
    await _tapInSheet(tester, 'fp-preset-$kTestDuplexPreset');
    expect(_has('fp-preset-typical'), isTrue);
    expect(find.textContaining('TYPOWE — decyduje specyfikacja projektu'),
        findsOneWidget);
    await _tapKey(tester, 'fp-read-unit-percent');
    await _tapKey(tester, 'fp-site-0-loc-base');
    await _addReadings(tester, 0, ['45']);
    expect(_has('fp-site-0-verdict-none'), isTrue);
    await _tapKey(tester, 'fp-site-0-loc-weld');
    expect(_has('fp-site-0-verdict-pass'), isTrue);
  });

  testWidgets(
      'PMI 316L: Mo 1,9 → niezgodny; ± 0,1 → do weryfikacji; Mo 2,1 → zgodny '
      '(bez weryfikacji C)', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _tapKey(tester, 'fp-part-pmi');
    expect(_has('fp-xrf-carbon'), isTrue);
    await _tapKey(tester, 'fp-pmi-0-grade');
    await _tapInSheet(tester, 'fp-grade-1.4404');
    await _enter(tester, 'fp-pmi-0-cr', '17,0');
    await _enter(tester, 'fp-pmi-0-ni', '10,5');
    expect(_has('fp-pmi-0-verdict-none'), isTrue);
    await _enter(tester, 'fp-pmi-0-mo', '1,9');
    expect(_has('fp-pmi-0-verdict-nonConforming'), isTrue);
    await _enter(tester, 'fp-pmi-0-mo-u', '0,1');
    expect(_has('fp-pmi-0-verdict-toVerify'), isTrue);
    await _enter(tester, 'fp-pmi-0-mo', '2,1');
    expect(_has('fp-pmi-0-verdict-conformingNoCarbon'), isTrue);
    expect(find.textContaining('ZGODNY (bez weryfikacji C)'), findsOneWidget);
    // Kropka zamiast przecinka — ten sam werdykt.
    await _enter(tester, 'fp-pmi-0-mo', '2.1');
    expect(_has('fp-pmi-0-verdict-conformingNoCarbon'), isTrue);
  });

  testWidgets(
      'PMI 304: Mo 2,1 → niezgodny „możliwy 316”; bez odczytu Mo → do '
      'weryfikacji', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _tapKey(tester, 'fp-part-pmi');
    await _tapKey(tester, 'fp-pmi-0-grade');
    await _tapInSheet(tester, 'fp-grade-1.4301');
    await _enter(tester, 'fp-pmi-0-cr', '17,6');
    await _enter(tester, 'fp-pmi-0-ni', '10,3');
    // Bez Mo — nie zielone: nie wyklucza 316.
    expect(_has('fp-pmi-0-verdict-toVerify'), isTrue);
    final moMissing =
        tester.widget<Text>(find.byKey(const ValueKey('fp-pmi-0-mo-status')));
    expect(moMissing.data, contains('brak odczytu Mo — nie wyklucza 316'));
    await _enter(tester, 'fp-pmi-0-mo', '2,1');
    expect(_has('fp-pmi-0-verdict-nonConforming'), isTrue);
    final mo =
        tester.widget<Text>(find.byKey(const ValueKey('fp-pmi-0-mo-status')));
    expect(mo.data, contains('nie występuje w 1.4301 / 304'));
    expect(mo.data, contains('możliwy 1.4401 / 316'));
    // Mo 0,3 — pozostałość pod progiem, nie blokuje.
    await _enter(tester, 'fp-pmi-0-mo', '0,3');
    expect(_has('fp-pmi-0-verdict-conforming'), isTrue);
  });

  testWidgets(
      'preset IOGP S-705: 1 odczyt → brak werdyktu „specyfikacja wymaga ≥ 3 '
      'odczytów”, 3 odczyty → w zakresie', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _tapKey(tester, 'fp-preset-picker');
    await _tapInSheet(tester, 'fp-preset-iogp_s705_fn3_10');
    expect(_has('fp-preset-min-readings'), isTrue);
    await _addReadings(tester, 0, ['6']);
    expect(_has('fp-site-0-verdict-none'), isTrue);
    final status =
        tester.widget<Text>(find.byKey(const ValueKey('fp-site-0-status')));
    expect(status.data, contains('specyfikacja wymaga ≥ 3 odczytów'));
    await _addReadings(tester, 0, ['7', '8']);
    expect(_has('fp-site-0-verdict-pass'), isTrue);
  });

  testWidgets(
      'zakres ręczny: min. odczytów 3 przy 2 odczytach → brak '
      'werdyktu', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _enter(tester, 'fp-min-count', '3');
    await _addReadings(tester, 0, ['45', '50']);
    expect(_has('fp-site-0-verdict-none'), isTrue);
    await _addReadings(tester, 0, ['55']);
    expect(_has('fp-site-0-verdict-pass'), isTrue);
  });

  testWidgets('usunięcie przy błędzie zapisu: komunikat, protokół zostaje',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: jsonEncode(ferritePmiToJson([_saved(1)])),
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(FerritePmiPage(
      store: const _FailingDeleteStore(),
      now: () => _now,
    )));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'fp-menu-0');
    await tester.tap(find.byKey(const ValueKey('fp-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fp-delete-confirm')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_has('fp-delete-failed'), isTrue);
    expect(_has('fp-item-0'), isTrue);
  });

  testWidgets('menu pozycji: usunięcie z cofnięciem', (tester) async {
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: jsonEncode(ferritePmiToJson([_saved(1)])),
    });
    await _pump(tester);
    await _tapKey(tester, 'fp-menu-0');
    await tester.tap(find.byKey(const ValueKey('fp-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fp-delete-confirm')));
    await tester.pumpAndSettle();
    expect(_has('fp-empty'), isTrue);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(_has('fp-item-0'), isTrue);
  });

  testWidgets('historia: ostrzeżenie od 180, przy 200 nowy odrzucony',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: jsonEncode(ferritePmiToJson(
          [for (var i = 0; i < FerritePmiStore.warnAt; i++) _saved(i)])),
    });
    await _pump(tester);
    expect(_has('fp-store-warn'), isTrue);

    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: jsonEncode(ferritePmiToJson(
          [for (var i = 0; i < FerritePmiStore.maxEntries; i++) _saved(i)])),
    });
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _tapKey(tester, 'fp-new');
    expect(_has('fp-store-full'), isTrue);
    expect(_has('fp-edit-list'), isFalse);
  });

  testWidgets('uszkodzony zapis: baner i kopia surowego zapisu',
      (tester) async {
    SharedPreferences.setMockInitialValues({FerritePmiStore.key: 'nie-json'});
    await _pump(tester);
    expect(_has('fp-load-damaged'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.corruptBackupKey), 'nie-json');
  });

  testWidgets('brak miejsca na kopię: komunikat i oryginał bez zmian',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: 'trzecie uszkodzenie',
      FerritePmiStore.corruptBackupKey: 'pierwsze uszkodzenie',
      FerritePmiStore.corruptLastBackupKey: 'drugie uszkodzenie',
    });
    await _pump(tester);
    expect(find.textContaining('nie udało się utworzyć jego kopii'),
        findsOneWidget);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-title', 'Nowy pomiar');
    expect(_has('fp-save-failed'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FerritePmiStore.key), 'trzecie uszkodzenie');
    expect(prefs.getString(FerritePmiStore.corruptBackupKey),
        'pierwsze uszkodzenie');
    expect(prefs.getString(FerritePmiStore.corruptLastBackupKey),
        'drugie uszkodzenie');
  });

  testWidgets('udostępnianie tekstu protokołu', (tester) async {
    final spy = await _pump(tester);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _enter(tester, 'fp-req-max', '70');
    await _addReadings(tester, 0, ['28', '31']);
    await _tapKey(tester, 'fp-share');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Ferryt i PMI — protokół');
    expect(text, contains('FERRYT I PMI — PROTOKÓŁ'));
    expect(text, contains('FN 30–70'));
    expect(text, contains('POZA ZAKRESEM'));
    expect(text, contains('2026-10-18 09:30'));
  });

  testWidgets('EN: etykiety po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Ferrite and PMI'), findsOneWidget);
    await _tapKey(tester, 'fp-new');
    await _enter(tester, 'fp-req-min', '30');
    await _addReadings(tester, 0, ['28.5']);
    final status =
        tester.widget<Text>(find.byKey(const ValueKey('fp-site-0-status')));
    expect(status.data, startsWith('OUT OF RANGE'));
  });

  testWidgets('wąski ekran 360×640, tekst ×1,5: bez przepełnień',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      FerritePmiStore.key: jsonEncode(ferritePmiToJson([
        _saved(1).copyWith(
            title: 'Rafineria — instalacja hydroodsiarczania, estakada E-4, '
                'spoina W-1234 po stronie tłocznej pompy P-101A'),
      ])),
    });
    await _pump(tester, size: const Size(360, 640), textScale: 1.5);
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'fp-open-0');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'fp-req-unit-percent');
    await _addReadings(tester, 0, ['45', '28']);
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'fp-rule-average');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'fp-preset-picker');
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _tapKey(tester, 'fp-part-pmi');
    // Zapisany protokół nie ma pozycji PMI — dodajemy.
    await _tapKey(tester, 'fp-pmi-add');
    await _tapKey(tester, 'fp-pmi-0-grade');
    await _tapInSheet(tester, 'fp-grade-1.4462');
    await _enter(tester, 'fp-pmi-0-cr', '22,4');
    await _enter(tester, 'fp-pmi-0-mo-u', '0,05');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'fp-sources');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byKey(const ValueKey('fp-new'))).height,
        greaterThanOrEqualTo(kMinTapTarget));
    await _tapKey(tester, 'fp-new');
    await _addReadings(tester, 0, ['45']);
    for (final k in [
      'fp-date',
      'fp-preset-picker',
      'fp-req-unit-fn',
      'fp-read-unit-percent',
      'fp-rule-average',
      'fp-site-0-del',
      'fp-site-0-loc-hazA',
      'fp-site-0-add',
      'fp-site-0-r-0',
      'fp-add-site-base',
      'fp-share',
      'fp-part',
    ]) {
      final f = await _show(tester, k);
      final s = tester.getSize(f);
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    for (final k in ['fp-site-0-del', 'fp-site-0-add']) {
      expect(tester.getSize(find.byKey(ValueKey(k))).width,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
    await _tapKey(tester, 'fp-part-pmi');
    for (final k in ['fp-pmi-0-grade', 'fp-pmi-0-del', 'fp-pmi-add']) {
      final f = await _show(tester, k);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });

  testWidgets('ekran edycji otwierany wprost z initial (test dymny)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(FerritePmiEditPage(
      initial: FerritePmiProtocol.blank(id: 'x', now: _now),
      now: () => _now,
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_has('fp-edit-list'), isTrue);
    expect(PmiElement.values.length, greaterThanOrEqualTo(8));
  });

  for (final (date, expected) in [
    ('1999-12-31', DateTime(2000)),
    ('2027-01-01', DateTime(2026, 10, 19)),
  ]) {
    testWidgets('kalendarz ogranicza datę początkową ferrytu $date',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(FerritePmiEditPage(
        initial:
            FerritePmiProtocol.blank(id: 'x', now: _now).copyWith(date: date),
        now: () => _now,
      )));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'fp-date');
      expect(tester.takeException(), isNull);
      expect(
          tester
              .widget<DatePickerDialog>(find.byType(DatePickerDialog))
              .initialDate,
          expected);
    });
  }
}

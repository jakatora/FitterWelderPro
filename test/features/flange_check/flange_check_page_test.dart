// Odbiór połączenia kołnierzowego na ekranie: werdykt na żywo, zapis do
// historii, duplikat, usunięcie z cofnięciem, cale, tolerancje zakładu,
// udostępnianie przez wstrzykniętą funkcję, wąski ekran i cele dotyku.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/flange/flange_check.dart';
import 'package:cut_list_app/features/flange_check/flange_check_page.dart';
import 'package:cut_list_app/features/flange_check/flange_check_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/bolt_torque_screen.dart';
import 'package:cut_list_app/services/flange_check_export.dart';
import 'package:cut_list_app/theme/app_theme.dart';

Future<void> _noShare(FlangeCheck c, FlangeShareFormat f, bool en) async {}

/// Magazyn, którego zapis zawsze się nie udaje (pełna pamięć itp.).
class _FailingStore extends FlangeCheckStore {
  const _FailingStore();

  @override
  Future<void> save(List<FlangeCheck> checks) async =>
      throw StateError('brak miejsca');
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(800, 6000),
  double textScale = 1.0,
  Map<String, Object> prefs = const {},
  FlangeShareFn share = _noShare,
  FlangeCheckStore store = const FlangeCheckStore(),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
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
      home: FlangeCheckPage(
          share: share, store: store, clock: () => DateTime(2026, 10, 17, 8)),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _pill(String criterion, String text) =>
    find.descendant(of: _key('flange-v-$criterion'), matching: find.text(text));

String _verdict(WidgetTester tester) =>
    tester.widget<Text>(_key('flange-verdict')).data!;

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(_key(key), text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _tickAll(WidgetTester tester) async {
  for (final i in FlangeChecklistItem.values) {
    await _tap(tester, 'flange-item-${i.name}');
  }
}

Future<void> _measureAllOk(WidgetTester tester) async {
  await _enter(tester, 'flange-gasket-t', '4,5');
  await _enter(tester, 'flange-centerline', '1');
  await _enter(tester, 'flange-rotation', '2');
  const gaps = ['3', '3,4', '3,2', '3,6'];
  for (var i = 0; i < gaps.length; i++) {
    await _enter(tester, 'flange-gap-$i', gaps[i]);
  }
  await _tap(tester, 'flange-force-light');
}

/// SnackBar trzyma licznik czasu — test kończy się po jego wygaśnięciu.
Future<void> _drainSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

FlangeCheck _saved(String id, String tag, int updatedAt) => FlangeCheck(
      id: id,
      joint: FlangeJoint(
          tag: tag, dn: 100, rating: 'CL150', date: '2026-10-1$updatedAt'),
      measurements: const FlangeMeasurements(centerlineMm: 0.5),
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

void main() {
  testWidgets('wpisanie pomiarów zmienia werdykt', (tester) async {
    await _pump(tester);
    expect(_verdict(tester), 'Niekompletny');
    expect(_pill('centerline', 'Brak pomiaru'), findsOneWidget);
    expect(find.text('Data: 2026-10-17'), findsOneWidget);

    await _enter(tester, 'flange-centerline', '1,5');
    expect(_pill('centerline', 'OK'), findsOneWidget);
    expect(find.text('1,5 mm ≤ 1,5 mm (1/16")'), findsOneWidget);
    expect(_verdict(tester), 'Niekompletny');

    await _enter(tester, 'flange-centerline', '1,6');
    expect(_pill('centerline', 'Poza tolerancją'), findsOneWidget);
    expect(_verdict(tester), 'Niezgodny — popraw osiowanie');

    // Szczelina: 0,8 mm różnicy na granicy, potem klin 0,9 mm.
    await _enter(tester, 'flange-centerline', '1');
    for (final (i, g) in ['2,3', '3,1', '2,7', '2,9'].indexed) {
      await _enter(tester, 'flange-gap-$i', g);
    }
    expect(_pill('parallelism', 'OK'), findsOneWidget);
    expect(_pill('spacing', 'Brak pomiaru'), findsOneWidget);
    await _enter(tester, 'flange-gasket-t', '1,5');
    expect(_pill('spacing', 'Poza tolerancją'), findsOneWidget);
    await _enter(tester, 'flange-gasket-t', '4,5');
    expect(_pill('spacing', 'OK'), findsOneWidget);
    await _enter(tester, 'flange-gap-1', '3,2');
    expect(_pill('parallelism', 'Poza tolerancją'), findsOneWidget);
  });

  testWidgets('komplet odhaczeń bez pomiaru — nie zielony', (tester) async {
    await _pump(tester);
    await _tickAll(tester);
    expect(_verdict(tester), 'Niekompletny');
    expect(find.textContaining('brak pomiarów: 5'), findsOneWidget);

    await _measureAllOk(tester);
    expect(_verdict(tester), 'Zgodny — można skręcać');

    // „Brak oceny siły” to znowu brak, nie OK.
    await _tap(tester, 'flange-force-light');
    expect(_pill('force', 'Brak pomiaru'), findsOneWidget);
    expect(_verdict(tester), 'Niekompletny');
  });

  testWidgets('zapis bez oznaczenia — komunikat, nic nie zapisane',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'flange-save');
    expect(find.text('Podaj oznaczenie połączenia (nr linii / kołnierza).'),
        findsOneWidget);
    expect(find.text('Wymagane do zapisu'), findsOneWidget);
    expect(find.text('Historia (0)'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FlangeCheckStore.key), isNull);
    await _drainSnackBars(tester);
  });

  testWidgets('zapis → historia; duplikat bez pomiarów i odhaczeń',
      (tester) async {
    await _pump(tester);
    await _enter(tester, 'flange-tag', 'L-101-F1');
    await tester.tap(_key('flange-dn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DN150 / 6"').last);
    await tester.pumpAndSettle();
    await _enter(tester, 'flange-rating', 'CL300');
    // ASME B16.5: DN150 klasa 300 → 12 śrub, wpisane w puste pole.
    expect(_field(tester, 'flange-bolt-count'), '12');
    await _enter(tester, 'flange-centerline', '1');
    await _tap(tester, 'flange-item-faces');
    await _tap(tester, 'flange-save');
    expect(find.text('Zapisano protokół.'), findsOneWidget);
    expect(find.text('Historia (1)'), findsOneWidget);

    final stored = decodeFlangeChecks((await SharedPreferences.getInstance())
        .getString(FlangeCheckStore.key));
    expect(stored, hasLength(1));
    expect(stored.single.joint.tag, 'L-101-F1');
    expect(stored.single.joint.boltCount, 12);
    expect(stored.single.measurements.centerlineMm, 1);

    await _tap(tester, 'flange-tab-history');
    expect(find.text('L-101-F1'), findsOneWidget);
    expect(find.text('DN150 / 6" · CL300 · 2026-10-17'), findsOneWidget);

    await tester.tap(find.byTooltip('Duplikuj (jak ten)'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'flange-tag'), 'L-101-F2');
    expect(_field(tester, 'flange-rating'), 'CL300');
    expect(_field(tester, 'flange-bolt-count'), '12');
    expect(_field(tester, 'flange-centerline'), '');
    expect(tester.widget<CheckboxListTile>(_key('flange-item-faces')).value,
        isFalse);
    expect(_verdict(tester), 'Niekompletny');
    // Kopia nie jest zapisana, dopóki monter jej nie zapisze.
    expect(find.text('Historia (1)'), findsOneWidget);
    await _drainSnackBars(tester);
  });

  testWidgets('usunięcie z cofnięciem', (tester) async {
    await _pump(tester, prefs: {
      FlangeCheckStore.key:
          encodeFlangeChecks([_saved('a', 'F-1', 1), _saved('b', 'F-2', 2)]),
    });
    expect(find.text('Historia (2)'), findsOneWidget);
    await _tap(tester, 'flange-tab-history');
    expect(find.text('F-1'), findsOneWidget);

    await _tap(tester, 'flange-h-menu-a');
    await tester.tap(find.text('Usuń'));
    await tester.pumpAndSettle();
    expect(find.text('F-1'), findsNothing);
    expect(find.text('Historia (1)'), findsOneWidget);
    var stored = decodeFlangeChecks((await SharedPreferences.getInstance())
        .getString(FlangeCheckStore.key));
    expect(stored.map((c) => c.id), ['b']);

    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('F-1'), findsOneWidget);
    expect(find.text('Historia (2)'), findsOneWidget);
    stored = decodeFlangeChecks((await SharedPreferences.getInstance())
        .getString(FlangeCheckStore.key));
    expect(stored.map((c) => c.id), ['a', 'b']);
    await _drainSnackBars(tester);
  });

  testWidgets('otwarcie z historii i ponowny zapis nadpisuje ten sam wpis',
      (tester) async {
    await _pump(tester, prefs: {
      FlangeCheckStore.key: encodeFlangeChecks([_saved('a', 'F-1', 1)]),
    });
    await _tap(tester, 'flange-tab-history');
    await tester.tap(find.text('F-1'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'flange-tag'), 'F-1');
    expect(_field(tester, 'flange-centerline'), '0,5');
    await _enter(tester, 'flange-centerline', '2');
    await _tap(tester, 'flange-save');
    final stored = decodeFlangeChecks((await SharedPreferences.getInstance())
        .getString(FlangeCheckStore.key));
    expect(stored, hasLength(1));
    expect(stored.single.measurements.centerlineMm, 2);
    await _drainSnackBars(tester);
  });

  testWidgets('uszkodzony JSON w pamięci — pusta historia, ekran działa',
      (tester) async {
    await _pump(tester, prefs: {FlangeCheckStore.key: '{"v":1,"checks":[{'});
    expect(tester.takeException(), isNull);
    expect(find.text('Historia (0)'), findsOneWidget);
    await _tap(tester, 'flange-tab-history');
    expect(find.textContaining('Brak zapisanych protokołów'), findsOneWidget);
  });

  testWidgets('wersja EN: kropka dziesiętna i teksty angielskie',
      (tester) async {
    await _pump(tester, lang: AppLanguage.en);
    expect(find.text('Flange check'), findsOneWidget);
    expect(_verdict(tester), 'Incomplete');
    await _enter(tester, 'flange-centerline', '2.0');
    expect(_pill('centerline', 'Out of tolerance'), findsOneWidget);
    expect(find.text('2 mm ≤ 1.5 mm (1/16")'), findsOneWidget);
    expect(_verdict(tester), 'Rejected — correct alignment');
    await _tap(tester, 'flange-tab-history');
    expect(find.textContaining('No saved protocols yet'), findsOneWidget);
  });

  testWidgets('cale: bez pomiarów zmiana bez pytania, 1/16" na granicy',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'flange-unit-inch');
    expect(find.text('Zmienić jednostkę?'), findsNothing);
    await _enter(tester, 'flange-centerline', '0,0625');
    expect(_pill('centerline', 'OK'), findsOneWidget);
    expect(find.text('0,0625" ≤ 1/16" (1,5 mm)'), findsOneWidget);
  });

  testWidgets(
      'B1: zmiana jednostki przy pomiarach pyta i czyści — werdykt nie '
      'zielenieje po cichu', (tester) async {
    await _pump(tester);
    await _tickAll(tester);
    await _measureAllOk(tester);
    expect(_verdict(tester), 'Zgodny — można skręcać');
    // 1,55 mm: poza w mm; ta sama liczba w calach (granica 1/16" = 1,5875 mm)
    // przeszłaby, gdyby przełączenie zostawiło wartość.
    await _enter(tester, 'flange-centerline', '1,55');
    expect(_verdict(tester), 'Niezgodny — popraw osiowanie');

    await _tap(tester, 'flange-unit-inch');
    expect(find.text('Zmienić jednostkę?'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'flange-centerline'), '1,55');
    expect(_pill('centerline', 'Poza tolerancją'), findsOneWidget);
    expect(_verdict(tester), 'Niezgodny — popraw osiowanie');

    await _tap(tester, 'flange-unit-inch');
    await _tap(tester, 'flange-unit-confirm');
    expect(_field(tester, 'flange-centerline'), '');
    expect(_field(tester, 'flange-gap-0'), '');
    expect(_pill('centerline', 'Brak pomiaru'), findsOneWidget);
    expect(_verdict(tester), 'Niekompletny');
    // Grubość uszczelki zostaje (w calach), ocena siły też.
    expect(_field(tester, 'flange-gasket-t'), '0,1772');
    expect(_pill('force', 'OK'), findsOneWidget);
  });

  testWidgets('B2: 8 → 4 punkty z odczytami z 45° pyta i dopiero wtedy usuwa',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'flange-points-8');
    const gaps = ['3', '2,1', '3', '3', '3', '3', '3', '3'];
    for (var i = 0; i < gaps.length; i++) {
      await _enter(tester, 'flange-gap-$i', gaps[i]);
    }
    expect(_pill('parallelism', 'Poza tolerancją'), findsOneWidget);

    await _tap(tester, 'flange-points-4');
    expect(find.text('Przejść na 4 punkty?'), findsOneWidget);
    expect(find.textContaining('45° (2,1 mm)'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(_key('flange-gap-7'), findsOneWidget);
    expect(_pill('parallelism', 'Poza tolerancją'), findsOneWidget);

    await _tap(tester, 'flange-points-4');
    await _tap(tester, 'flange-points-confirm');
    expect(_key('flange-gap-4'), findsNothing);
    expect(_field(tester, 'flange-gap-1'), '3');
    expect(_pill('parallelism', 'OK'), findsOneWidget);
  });

  testWidgets('B2: 8 → 4 z odczytami tylko w 0/90/180/270° — bez pytania',
      (tester) async {
    await _pump(tester);
    await _tap(tester, 'flange-points-8');
    await _enter(tester, 'flange-gap-2', '3');
    await _tap(tester, 'flange-points-4');
    expect(find.text('Przejść na 4 punkty?'), findsNothing);
    expect(_field(tester, 'flange-gap-1'), '3');
  });

  testWidgets(
      'B3: literówka 15 zamiast 1,5 — błąd pola i brak zieleni; luźniejsze '
      'niż PCC-1 — ostrzeżenie', (tester) async {
    await _pump(tester);
    await _tickAll(tester);
    await _measureAllOk(tester);
    expect(_verdict(tester), 'Zgodny — można skręcać');
    expect(_key('flange-looser'), findsNothing);

    await _tap(tester, 'flange-tol-tile');
    await _enter(tester, 'flange-tol-centerline', '15');
    expect(find.text('Wpisz wartość większą od 0, najwyżej 10 mm'),
        findsOneWidget);
    expect(_verdict(tester), 'Niekompletny');
    expect(_key('flange-problem-tolerances'), findsOneWidget);

    await _enter(tester, 'flange-tol-centerline', '1,6');
    expect(_verdict(tester), 'Zgodny — można skręcać');
    expect(
        tester.widget<Text>(_key('flange-looser')).data,
        'UWAGA: tolerancje luźniejsze niż PCC-1 '
        '(Przesunięcie osi (high/low)).');
    expect(find.text('Własne — luźniejsze niż PCC-1'), findsOneWidget);

    await _enter(tester, 'flange-tol-centerline', '1,5');
    await _enter(tester, 'flange-tol-factor', '100');
    expect(
        find.text('Wpisz wartość większą od 0, najwyżej 10'), findsOneWidget);
    expect(_verdict(tester), 'Niekompletny');
  });

  testWidgets(
      'B4: uszkodzone tolerancje w zapisie — Niekompletny z komunikatem, '
      'nie PCC-1', (tester) async {
    final strict = _saved('a', 'F-1', 1).copyWith(
      tolerances: FlangeTolerances.pcc1
          .copyWith(centerline: DualLimit.entered(0.8, LengthUnit.mm)),
      checked: FlangeChecklistItem.values.toSet(),
    );
    final json = strict.toJson();
    json['tolerances'] = {
      ...(json['tolerances']! as Map<String, Object?>),
      'centerline': 'zepsute',
    };
    await _pump(tester, prefs: {
      FlangeCheckStore.key: jsonEncode({
        'v': 1,
        'checks': [json]
      }),
    });
    // Nowy protokół nie dziedziczy nieważnych tolerancji.
    expect(find.text('ASME PCC-1-2019 zał. E'), findsOneWidget);

    await _tap(tester, 'flange-tab-history');
    await tester.tap(find.text('F-1'));
    await tester.pumpAndSettle();
    expect(_verdict(tester), 'Niekompletny');
    expect(_key('flange-problem-tolerances'), findsOneWidget);
    expect(find.text('Nieważne — popraw albo przywróć PCC-1'), findsOneWidget);
    expect(_pill('centerline', 'Brak pomiaru'), findsOneWidget);
  });

  testWidgets('B5: nieudany zapis — protokół zostaje niezapisany, wyjście pyta',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FlangeCheckPage(
                        share: _noShare, store: _FailingStore()))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _enter(tester, 'flange-tag', 'X-1');
    await _tap(tester, 'flange-save');
    expect(find.text('Nie udało się zapisać na telefonie.'), findsOneWidget);
    expect(find.text('Historia (0)'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Niezapisane zmiany'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.byType(FlangeCheckPage), findsOneWidget);
    await _drainSnackBars(tester);
  });

  testWidgets('B6: uszkodzona historia — komunikat i kopia przed nadpisaniem',
      (tester) async {
    const raw = '{"v":1,"checks":[{';
    await _pump(tester, prefs: {FlangeCheckStore.key: raw});
    await _tap(tester, 'flange-tab-history');
    expect(_key('flange-history-damaged'), findsOneWidget);
    await _tap(tester, 'flange-tab-check');
    await _enter(tester, 'flange-tag', 'N-1');
    await _tap(tester, 'flange-save');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FlangeCheckStore.corruptKey), raw);
    expect(
        decodeFlangeChecks(prefs.getString(FlangeCheckStore.key))
            .single
            .joint
            .tag,
        'N-1');
    await _drainSnackBars(tester);
  });

  testWidgets('tolerancje zakładu i „przywróć PCC-1”', (tester) async {
    await _pump(tester);
    await _enter(tester, 'flange-centerline', '1,2');
    expect(_pill('centerline', 'OK'), findsOneWidget);
    await _tap(tester, 'flange-tol-tile');
    expect(_field(tester, 'flange-tol-centerline'), '1,5');
    await _enter(tester, 'flange-tol-centerline', '1');
    expect(_pill('centerline', 'Poza tolerancją'), findsOneWidget);
    expect(find.text('Własne (specyfikacja zakładu)'), findsOneWidget);

    await _tap(tester, 'flange-tol-reset');
    expect(find.text('ASME PCC-1-2019 zał. E'), findsOneWidget);
    expect(_field(tester, 'flange-tol-centerline'), '1,5');
    expect(_pill('centerline', 'OK'), findsOneWidget);
  });

  testWidgets('8 punktów: ręcznie i automatycznie dla DN ≥ 300',
      (tester) async {
    await _pump(tester);
    expect(_key('flange-gap-3'), findsOneWidget);
    expect(_key('flange-gap-4'), findsNothing);
    await _tap(tester, 'flange-points-8');
    expect(_key('flange-gap-7'), findsOneWidget);
    expect(find.text('45°'), findsOneWidget);
    await _tap(tester, 'flange-points-4');
    expect(_key('flange-gap-4'), findsNothing);

    await tester.tap(_key('flange-dn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DN300 / 12"').last);
    await tester.pumpAndSettle();
    expect(_key('flange-gap-7'), findsOneWidget);
  });

  testWidgets('udostępnianie: tekst i PDF przez wstrzykniętą funkcję',
      (tester) async {
    final calls = <(String, FlangeShareFormat, bool)>[];
    await _pump(tester, share: (c, f, en) async {
      calls.add((c.joint.tag, f, en));
    });
    await _enter(tester, 'flange-tag', 'K-7');
    await _tap(tester, 'flange-share-text');
    await _tap(tester, 'flange-share-pdf');
    expect(calls, [
      ('K-7', FlangeShareFormat.text, false),
      ('K-7', FlangeShareFormat.pdf, false),
    ]);
  });

  testWidgets('błąd udostępniania — komunikat zamiast wyjątku', (tester) async {
    await _pump(tester, share: (c, f, en) async => throw StateError('x'));
    await _tap(tester, 'flange-share-pdf');
    expect(find.text('Nie udało się udostępnić protokołu.'), findsOneWidget);
    await _drainSnackBars(tester);
  });

  testWidgets('„Moment śrub” otwiera istniejący kalkulator', (tester) async {
    await _pump(tester);
    await _tap(tester, 'flange-torque');
    expect(find.byType(BoltTorqueScreen), findsOneWidget);
  });

  testWidgets('wyjście z niezapisanymi zmianami pyta o odrzucenie',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FlangeCheckPage(share: _noShare))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await _enter(tester, 'flange-tag', 'X-1');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Niezapisane zmiany'), findsOneWidget);
    await _tap(tester, 'flange-discard');
    expect(find.byType(FlangeCheckPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('wąski ekran 320×640, tekst ×1,3 — bez wyjątków (${lang.name})',
        (tester) async {
      await _pump(tester,
          lang: lang, size: const Size(320, 640), textScale: 1.3);
      final scroll = find
          .descendant(
              of: _key('flange-check-list'), matching: find.byType(Scrollable))
          .first;
      for (final k in [
        'flange-unit-inch',
        'flange-points-8',
        'flange-force-heavy',
        'flange-tol-tile',
        'flange-item-sequence',
        'flange-defects',
      ]) {
        await tester.scrollUntilVisible(_key(k), 200, scrollable: scroll);
        await tester.pumpAndSettle();
        await tester.tap(_key(k));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: k);
      }
      for (var i = 0; i < 40; i++) {
        await tester.drag(_key('flange-check-list'), const Offset(0, -300));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(_key('flange-save'), findsOneWidget);
      await _tap(tester, 'flange-tab-history');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wąski ekran: karta historii z długim oznaczeniem',
      (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.3, prefs: {
      FlangeCheckStore.key: encodeFlangeChecks(
          [_saved('a', 'L-2026-0001-FLANGE-INLET-NORTH-F12', 1)]),
    });
    await _tap(tester, 'flange-tab-history');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester, prefs: {
      FlangeCheckStore.key: encodeFlangeChecks([_saved('a', 'F-1', 1)]),
    });
    for (final k in [
      ...FlangeChecklistItem.values.map((i) => 'flange-item-${i.name}'),
      ...AlignmentForce.values.map((f) => 'flange-force-${f.name}'),
      'flange-date',
      'flange-torque',
      'flange-save',
      'flange-share-text',
      'flange-share-pdf',
      'flange-new',
      'flange-tol-tile',
      'flange-defects',
    ]) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    for (final k in [
      'flange-unit-mm',
      'flange-unit-inch',
      'flange-points-4',
      'flange-points-8',
    ]) {
      final button = find.ancestor(
          of: _key(k),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(tester.getSize(button.first).height,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await _tap(tester, 'flange-tab-history');
    for (final k in ['flange-h-dup-a', 'flange-h-menu-a']) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  for (final (date, expected) in [
    ('1999-12-31', DateTime(2000)),
    ('2101-01-01', DateTime(2100)),
  ]) {
    testWidgets('kalendarz ogranicza datę początkową kołnierza $date',
        (tester) async {
      final old = _saved('a', 'F-1', 1);
      await _pump(tester, prefs: {
        FlangeCheckStore.key: encodeFlangeChecks(
            [old.copyWith(joint: old.joint.copyWith(date: date))]),
      });
      await _tap(tester, 'flange-tab-history');
      await tester.tap(find.text('F-1'));
      await tester.pumpAndSettle();
      await _tap(tester, 'flange-date');
      expect(tester.takeException(), isNull);
      expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .initialDate, expected);
    });
  }
}

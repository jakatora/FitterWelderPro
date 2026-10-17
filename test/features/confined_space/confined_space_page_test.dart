// Ekran „Przestrzeń zamknięta: wejście i spawanie”: odhaczenie → pomiar →
// werdykt, STOP (tlen za mało / za dużo), brak odczytu gazu ≠ OK,
// najpóźniejszy pomiar decyduje, remis w minucie zgłoszony, progi tylko
// w bezpieczną stronę (błędny tekst nie kasuje progu), mg/m³ jak wpisano,
// „Cofnij” po zamknięciu ekranu przez magazyn, uszkodzony zapis → baner
// i kopia, historia, „jak wczoraj”, udostępnianie (wstrzyknięte), EN,
// 320×640 z czcionką ×1,3, cele dotyku ≥ 48 dp.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/confined_space/confined_space_checklist.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_gas.dart';
import 'package:cut_list_app/domain/confined_space/confined_space_record.dart';
import 'package:cut_list_app/features/confined_space/confined_space_page.dart';
import 'package:cut_list_app/features/confined_space/confined_space_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

class _Spy {
  final List<(String, String)> texts = [];
  final List<(ConfinedSpaceRecord, bool)> pdfs = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(ConfinedSpaceRecord r, bool en) async => pdfs.add((r, en));
}

Future<_Spy> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  DateTime Function()? now,
  TimeOfDay? Function()? pickTime,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final spy = _Spy();
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
      home: ConfinedSpacePage(
        now: now ?? () => _now,
        newId: () => 'cs-${++n}',
        shareText: spy.text,
        sharePdf: spy.pdf,
        pickTime: (_, initial) async =>
            pickTime == null ? initial : pickTime(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return spy;
}

Finder _scrollable(String listKey) => find
    .descendant(
        of: find.byKey(ValueKey(listKey)), matching: find.byType(Scrollable))
    .first;

String get _currentList =>
    find.byKey(const ValueKey('cs-edit-list')).evaluate().isNotEmpty
        ? 'cs-edit-list'
        : 'cs-list';

/// Pokazuje element o kluczu [key] (przewija w górę lub w dół).
Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    final list = _currentList;
    await tester.drag(_scrollable(list), const Offset(0, 40000));
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

Future<String> _status(WidgetTester tester) async {
  final f = await _show(tester, 'cs-status-text');
  return tester.widget<Text>(f).data!;
}

Future<String> _textOf(WidgetTester tester, String key) async {
  final f = await _show(tester, key);
  return tester.widget<Text>(f).data!;
}

/// Wiersz pomiaru [i] (tekst w kolejności czasu).
Future<String> _row(WidgetTester tester, int i) async {
  final f = await _show(tester, 'cs-meas-$i');
  final texts = tester
      .widgetList<Text>(find.descendant(of: f, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .toList();
  return texts.join(' ');
}

Future<void> _reading(
  WidgetTester tester, {
  String? o2,
  String? lel,
  String? co,
  String? h2s,
  String? place,
}) async {
  if (o2 != null) await _enter(tester, 'cs-meas-o2', o2);
  if (lel != null) await _enter(tester, 'cs-meas-lel', lel);
  if (co != null) await _enter(tester, 'cs-meas-co', co);
  if (h2s != null) await _enter(tester, 'cs-meas-h2s', h2s);
  if (place != null) await _enter(tester, 'cs-meas-place', place);
  await _tapKey(tester, 'cs-meas-add');
}

Future<void> _fullReading(WidgetTester tester, {String o2 = '20,9'}) =>
    _reading(tester, o2: o2, lel: '0', co: '0', h2s: '0');

Future<void> _tickAllBefore(WidgetTester tester) async {
  for (final c in confinedSpaceChecksIn(ConfinedSpacePhase.before)) {
    await _tapKey(tester, 'cs-check-${c.id}');
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

int _at(int h, int m) => DateTime(2026, 10, 16, h, m).millisecondsSinceEpoch;

ConfinedSpaceRecord _yesterday() => ConfinedSpaceRecord(
      id: 'old',
      permitNo: 'PZ/6/2026',
      location: 'Zbiornik T-101, właz M1',
      description: 'Spawanie króćca DN80 od środka',
      processes: const {CsProcess.tig},
      date: '2026-10-16',
      validFrom: '07:00',
      validTo: '15:00',
      entrants: 'Jan Kowalski',
      attendant: 'Adam Nowak',
      supervisor: 'Ewa Zając',
      issuer: 'Piotr Wiśniewski',
      rescue: 'Trójnóg T-2',
      limits: CsLimits.defaults
          .withLimit(CsBound.lelMax, const CsQty(5, CsUnit.pctLel)),
      measurements: [
        CsMeasurement(time: '06:50', at: _at(6, 50), values: const {
          CsGas.o2: CsQty(20.9, CsUnit.pctVol),
          CsGas.lel: CsQty(0, CsUnit.pctLel),
          CsGas.co: CsQty(0, CsUnit.ppm),
          CsGas.h2s: CsQty(0, CsUnit.ppm),
        }),
      ],
      checked: {for (final c in kConfinedSpaceChecks) c.id},
      createdAt: 1,
      updatedAt: 1,
    );

Future<ConfinedSpaceLoad> _load() => const ConfinedSpaceStore().load();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('nowy protokół: odhaczenie → pomiar → werdykt, zapis i historia',
      (tester) async {
    await _pump(tester);
    expect(find.text('Przestrzeń zamknięta: wejście i spawanie'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cs-empty')), findsOneWidget);

    await _tapKey(tester, 'cs-new');
    expect(find.text('Protokół wejścia'), findsOneWidget);
    expect(await _status(tester),
        'Brak odczytu: O₂, DGW, CO, H₂S — brak pomiaru to nie „w normie”.');
    await _enter(tester, 'cs-f-location', 'Zbiornik T-101, właz M1');
    await _tapKey(tester, 'cs-proc-tig');
    await _show(tester, 'cs-warn-inert');

    // Odhaczenie punktu i „nie dotyczy”.
    await _tapKey(tester, 'cs-check-perm-written');
    expect(
        tester
            .widget<Icon>(find.descendant(
                of: find.byKey(const ValueKey('cs-check-perm-written')),
                matching: find.byIcon(Icons.check_box)))
            .color,
        kPass);
    await _tapKey(tester, 'cs-na-clean-sewer');
    expect(find.byKey(const ValueKey('cs-na-res-attendant')), findsNothing);
    expect(find.byKey(const ValueKey('cs-na-perm-written')), findsNothing);

    // Pomiar w normie — atmosfera OK, ale lista niekompletna.
    await _reading(tester,
        o2: '20,9', lel: '0', co: '0', h2s: '0', place: 'dno');
    expect(
        await _row(tester, 0),
        contains('07:30 — dno — O₂ 20,9 % (OK) · 0 % DGW (OK) · CO 0 ppm '
            '(OK) · H₂S 0 ppm (OK)'));
    expect(await _status(tester),
        startsWith('Atmosfera w progach; do odhaczenia przed wejściem:'));

    await _back(tester);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cs-item-status-0')))
            .data,
        'Niekompletne');

    // Ponowne otwarcie — dokończenie listy daje zielony stan.
    await _tapKey(tester, 'cs-open-0');
    for (final c in confinedSpaceChecksIn(ConfinedSpacePhase.before)) {
      if (c.id == 'perm-written' || c.id == 'clean-sewer') continue;
      await _tapKey(tester, 'cs-check-${c.id}');
    }
    expect(await _status(tester),
        'Przygotowane, atmosfera w progach — wejście wg pozwolenia; mierz '
        'dalej w trakcie.');
    await _back(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cs-item-status-0')))
            .data,
        'Gotowe');

    final saved = (await _load()).records.single;
    expect(saved.id, 'cs-1');
    expect(saved.location, 'Zbiornik T-101, właz M1');
    expect(saved.processes, {CsProcess.tig});
    expect(saved.na, {'clean-sewer'});
    expect(saved.measurements.single.time, '07:30');
    expect(saved.measurements.single.place, 'dno');
    expect(saved.measurements.single[CsGas.o2],
        const CsQty(20.9, CsUnit.pctVol));
    expect(saved.limits.isDefault, isTrue);
  });

  testWidgets('wszystko odhaczone, odczyt tylko O₂ — brak odczytu ≠ OK',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);
    await _reading(tester, o2: '20,9');
    expect(await _status(tester), startsWith('Brak odczytu: DGW, CO, H₂S'));
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    // Pozwolenie nie wymaga CO i H₂S — nadal brak gazów palnych.
    await _tapKey(tester, 'cs-req-co');
    await _tapKey(tester, 'cs-req-h2s');
    expect(await _status(tester), startsWith('Brak odczytu: DGW —'));
    await _reading(tester, lel: '0');
    expect(await _status(tester), startsWith('Przygotowane'));
  });

  testWidgets('tlen za mało i za dużo — STOP; pomiar po przewietrzeniu zdejmuje',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 10, 0);
    await _pump(tester, now: () => clock);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);
    await _fullReading(tester, o2: '18');
    expect(await _status(tester),
        startsWith('STOP — tlen 18 % o 10:00 — poniżej 19,5 %, niedotlenienie'));
    expect(find.byIcon(Icons.dangerous_outlined), findsOneWidget);
    expect(await _row(tester, 0), contains('O₂ 18 % (ZA MAŁO)'));

    clock = DateTime(2026, 10, 17, 10, 5);
    await _reading(tester, o2: '24');
    expect(await _status(tester),
        startsWith('STOP — tlen 24 % o 10:05 — powyżej 23,5 %, wzbogacenie'));

    clock = DateTime(2026, 10, 17, 10, 10);
    await _reading(tester, o2: '20,9');
    expect(await _status(tester), startsWith('Przygotowane'));

    // Odczyt spoza skali — przycisk nieaktywny.
    await _enter(tester, 'cs-meas-o2', '150');
    final add = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('cs-meas-add')));
    expect(add.onPressed, isNull);
    expect(find.text('Wpisz liczbę 0–100'), findsOneWidget);
  });

  testWidgets('zaległy pomiar nie zdejmuje STOP; remis w minucie zgłoszony',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 10, 30);
    await _pump(tester, now: () => clock);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);
    await _fullReading(tester, o2: '18');
    expect(await _status(tester), startsWith('STOP'));

    // Pomiar z wcześniejszą chwilą (ta sama ścieżka co godzina wstecz).
    clock = DateTime(2026, 10, 17, 9, 0);
    await _fullReading(tester);
    expect(find.byKey(const ValueKey('cs-meas-backdated')), findsOneWidget);
    expect(await _status(tester), startsWith('STOP'));
    expect(await _row(tester, 0), startsWith('09:00'));

    // Ten sam czas co STOP (10:30) z innym tlenem — remis, decyduje gorszy.
    clock = DateTime(2026, 10, 17, 10, 30, 40);
    await _reading(tester, o2: '20,9');
    expect(find.byKey(const ValueKey('cs-meas-tie')), findsOneWidget);
    expect(await _status(tester), startsWith('STOP — tlen 18 %'));
    await _show(tester, 'cs-tie-o2');
    expect(
        find.textContaining('O₂: różne odczyty z tej samej minuty (10:30)'),
        findsWidgets);
  });

  testWidgets('błędny tekst progu nie kasuje zapisanego progu; puste pole tak',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    await _enter(tester, 'cs-f-location', 'Studzienka K-3');
    await _enter(tester, 'cs-limit-lelMax', '5');
    expect(await _textOf(tester, 'cs-gas-value-lel'),
        'brak odczytu — wymagany');
    expect((await _load()).records.single.limits[CsBound.lelMax],
        const CsQty(5, CsUnit.pctLel));

    // Łagodniej niż przepis — błąd, zapisany próg zostaje.
    await _enter(tester, 'cs-limit-lelMax', '15');
    expect(find.textContaining('Obowiązuje nadal: 5 % DGW'), findsOneWidget);
    expect((await _load()).records.single.limits[CsBound.lelMax],
        const CsQty(5, CsUnit.pctLel));

    // Dolny próg tlenu tylko w górę.
    await _enter(tester, 'cs-limit-o2Min', '18');
    expect(find.textContaining('Obowiązuje nadal: 19,5 %'), findsOneWidget);
    await _enter(tester, 'cs-limit-o2Min', '20');
    expect((await _load()).records.single.limits[CsBound.o2Min],
        const CsQty(20, CsUnit.pctVol));

    // Puste pole kasuje próg — gazu nie da się ocenić.
    await _enter(tester, 'cs-limit-lelMax', '');
    expect((await _load()).records.single.limits[CsBound.lelMax], isNull);
    await _fullReading(tester);
    expect(await _status(tester), startsWith('Wpisz próg z pozwolenia dla: DGW'));
    // Pusty próg nie łagodzi: 50 % DGW to STOP wg granicy 10 % DGW.
    await _reading(tester, lel: '50');
    expect(await _status(tester),
        startsWith('STOP — Gazy palne 50 % DGW o 07:30 — powyżej progu 10 % '
            'DGW (granica twarda'));
  });

  testWidgets('mg/m³: odczyt i próg tak, jak wpisano; werdykt w ppm',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);
    await _tapKey(tester, 'cs-meas-unit-co');
    await _tapKey(tester, 'cs-meas-unit-h2s');
    // Podgląd przeliczenia pod polem w mg/m³.
    await _enter(tester, 'cs-meas-h2s', '7');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cs-meas-h2s')),
            matching: find.text('≈ 4,94 ppm')),
        findsOneWidget);
    // Próg H₂S (7 mg/m³) ma ten sam podgląd.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cs-limit-h2sMax')),
            matching: find.text('≈ 4,94 ppm')),
        findsOneWidget);
    await _reading(tester, o2: '20,9', lel: '0', co: '23', h2s: '7');
    final row = await _row(tester, 0);
    expect(row, contains('CO 23 mg/m³ (OK)'));
    expect(row, contains('H₂S 7 mg/m³ (OK)'));
    expect(await _status(tester), startsWith('Przygotowane'));

    // Po dodaniu jednostka wraca do ppm — 5 ppm H₂S > 7 mg/m³ (≈ 4,94 ppm)
    // — STOP.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('cs-meas-unit-h2s')),
            matching: find.text('ppm')),
        findsOneWidget);
    await _reading(tester, h2s: '5');
    expect(await _row(tester, 1), contains('H₂S 5 ppm (POWYŻEJ PROGU)'));
    expect(await _status(tester), startsWith('STOP — H₂S 5 ppm'));

    // Próg H₂S zapisany jako 7 mg/m³ — przełączenie na ppm przy „7” jest
    // łagodniejsze: błąd, próg zostaje; „4” ppm — ostrzej, przyjęte.
    await _tapKey(tester, 'cs-limit-unit-h2sMax');
    expect(find.textContaining('Obowiązuje nadal: 7 mg/m³'), findsOneWidget);
    await _enter(tester, 'cs-limit-h2sMax', '4');
    final saved = (await _load()).records.single;
    expect(saved.limits[CsBound.h2sMax], const CsQty(4, CsUnit.ppm));
    expect(saved.measurements.first[CsGas.co], const CsQty(23, CsUnit.mgM3));
  });

  testWidgets('usunięty pomiar: „Cofnij” po zamknięciu ekranu przez magazyn',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    // Tylko pomiar — po usunięciu protokół jest pusty i wypada z historii.
    await _fullReading(tester);
    expect((await _load()).records.single.measurements, hasLength(1));
    await _tapKey(tester, 'cs-meas-del-0');
    await _back(tester);
    expect(find.byKey(const ValueKey('cs-empty')), findsOneWidget);
    expect((await _load()).records, isEmpty);

    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    final restored = (await _load()).records.single;
    expect(restored.id, 'cs-1');
    expect(restored.measurements.single.time, '07:30');
    // Lista odświeża się sama po zapisie z „Cofnij”.
    await tester.pumpAndSettle();
    expect(find.text('HISTORIA (1)'), findsOneWidget);
  });

  testWidgets('uszkodzony pomiar w zapisie: baner, kopia surowego zapisu',
      (tester) async {
    final json = _yesterday().toJson();
    json['measurements'] = [
      ...(json['measurements'] as List),
      {'time': '07:10', 'at': 'wczoraj', 'o2': {'v': 20.9, 'u': 'pctVol'}},
    ];
    final raw = jsonEncode([json]);
    SharedPreferences.setMockInitialValues({ConfinedSpaceStore.key: raw});
    await _pump(tester);
    await _show(tester, 'cs-load-damaged');
    expect(find.textContaining('pominięto 0 protokołów i 1 pomiarów'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ConfinedSpaceStore.corruptBackupKey), raw);
    await _tapKey(tester, 'cs-open-0');
    await _show(tester, 'cs-damaged-notice');
  });

  testWidgets('jak wczoraj: kopia danych bez pomiarów i odhaczeń',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key:
          jsonEncode(confinedSpaceRecordsToJson([_yesterday()])),
    });
    await _pump(tester);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cs-item-status-0')))
            .data,
        'Zamknięte · nieaktualne');

    await _tapKey(tester, 'cs-dup-last');
    expect(find.byKey(const ValueKey('cs-old-notice')), findsNothing);
    expect(await _status(tester), startsWith('Brak odczytu'));
    await _show(tester, 'cs-meas-empty');
    final f = await _show(tester, 'cs-check-perm-written');
    expect(
        find.descendant(
            of: f, matching: find.byIcon(Icons.check_box_outline_blank)),
        findsOneWidget);
    await _back(tester);

    expect(find.text('HISTORIA (2)'), findsOneWidget);
    final saved = (await _load()).records;
    expect(saved.map((r) => r.id), ['cs-1', 'old']);
    final copy = saved.first;
    expect(copy.date, '2026-10-17');
    expect(copy.attendant, 'Adam Nowak');
    expect(copy.limits[CsBound.lelMax], const CsQty(5, CsUnit.pctLel));
    expect(copy.checked, isEmpty);
    expect(copy.measurements, isEmpty);
    expect(copy.permitNo, isEmpty);
    expect(saved.last.checked.length, kConfinedSpaceChecks.length);

    await _tapKey(tester, 'cs-open-1');
    expect(find.byKey(const ValueKey('cs-old-notice')), findsOneWidget);
  });

  testWidgets('menu pozycji: duplikat i usunięcie z cofnięciem',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key:
          jsonEncode(confinedSpaceRecordsToJson([_yesterday()])),
    });
    await _pump(tester);
    await _tapKey(tester, 'cs-menu-0');
    await tester.tap(find.byKey(const ValueKey('cs-menu-dup')));
    await tester.pumpAndSettle();
    expect(find.text('Protokół wejścia'), findsOneWidget);
    await _back(tester);
    expect(find.text('HISTORIA (2)'), findsOneWidget);

    await _tapKey(tester, 'cs-menu-0');
    await tester.tap(find.byKey(const ValueKey('cs-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cs-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect((await _load()).records.single.id, 'old');
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('HISTORIA (2)'), findsOneWidget);
  });

  testWidgets('pusty protokół nie trafia do historii', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    await _back(tester);
    expect(find.byKey(const ValueKey('cs-empty')), findsOneWidget);
    expect((await _load()).records, isEmpty);
  });

  testWidgets('udostępnianie: tekst protokołu i PDF przez wstrzyknięte funkcje',
      (tester) async {
    final spy = await _pump(tester);
    await _tapKey(tester, 'cs-new');
    await _enter(tester, 'cs-f-location', 'Zbiornik T-101');
    await _tapKey(tester, 'cs-share-text');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Przestrzeń zamknięta — protokół wejścia i spawania');
    expect(text, contains('Przestrzeń: Zbiornik T-101'));
    expect(text, contains('— brak pomiaru —'));
    expect(text, contains('ogólnych przepisów BHP'));

    await _tapKey(tester, 'cs-share-pdf-btn');
    expect(spy.pdfs, hasLength(1));
    expect(spy.pdfs.single.$1.location, 'Zbiornik T-101');
    expect(spy.pdfs.single.$2, isFalse);
  });

  testWidgets('po angielsku', (tester) async {
    final spy = await _pump(tester, language: AppLanguage.en);
    expect(find.text('Confined space: entry and welding'), findsOneWidget);
    await _tapKey(tester, 'cs-new');
    expect(find.text('Entry record'), findsOneWidget);
    expect(await _status(tester),
        'No reading for: O₂, LEL, CO, H₂S — a missing reading is never OK.');
    final before = await _show(tester, 'cs-phase-before');
    expect(find.descendant(of: before, matching: find.text('BEFORE ENTRY')),
        findsOneWidget);
    await _reading(tester, o2: '18.5');
    expect(await _status(tester), startsWith('STOP — oxygen 18.5 %'));
    await _tapKey(tester, 'cs-share-text');
    expect(spy.texts.single.$1,
        startsWith('CONFINED SPACE — ENTRY AND WELDING RECORD'));
  });

  testWidgets('wąski ekran 320×640, czcionka 1,3: bez przepełnień',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key: jsonEncode(confinedSpaceRecordsToJson([
        _yesterday().copyWith(
            location: 'Rafineria — instalacja hydroodsiarczania, zbiornik '
                'buforowy T-101, właz dolny M2 po stronie ssawnej pompy'),
      ])),
    });
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);

    Future<void> scrollThrough() async {
      final s = _scrollable(_currentList);
      for (var i = 0; i < 200; i++) {
        final pos = tester.state<ScrollableState>(s).position;
        if (pos.pixels >= pos.maxScrollExtent) break;
        await tester.drag(s, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    await scrollThrough();
    await _tapKey(tester, 'cs-open-0');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'cs-proc-purge');
    await _tapKey(tester, 'cs-meas-unit-co');
    await _reading(tester, o2: '18', lel: '12,5', co: '117', h2s: '0');
    expect(tester.takeException(), isNull);
    expect(await _status(tester), startsWith('STOP'));
    await tester.drag(_scrollable('cs-edit-list'), const Offset(0, 40000));
    await tester.pumpAndSettle();
    await scrollThrough();
    await _back(tester);
    await _tapKey(tester, 'cs-new');
    expect(tester.takeException(), isNull);
    await scrollThrough();
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byKey(const ValueKey('cs-new'))).height,
        greaterThanOrEqualTo(kMinTapTarget));
    await _tapKey(tester, 'cs-new');
    for (final c in kConfinedSpaceChecks) {
      final f = await _show(tester, 'cs-check-${c.id}');
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: c.id);
      if (c.naAllowed) {
        final na = find.byKey(ValueKey('cs-na-${c.id}'));
        expect(tester.getSize(na).height, greaterThanOrEqualTo(kMinTapTarget),
            reason: c.id);
        expect(tester.getSize(na).width, greaterThanOrEqualTo(kMinTapTarget),
            reason: c.id);
      }
    }
    await _fullReading(tester);
    for (final k in [
      'cs-meas-add',
      'cs-meas-del-0',
      'cs-meas-time',
      'cs-meas-unit-co',
      'cs-limit-unit-h2sMax',
      'cs-req-co',
      'cs-proc-tig',
      'cs-date',
      'cs-from',
      'cs-share-pdf-btn',
    ]) {
      final f = await _show(tester, k);
      final size = tester.getSize(f);
      expect(size.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(size.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  testWidgets('pomiar starszy niż 30 min i protokół z wczoraj — bez zieleni',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 7, 30);
    await _pump(tester, now: () => clock);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);
    await _fullReading(tester);
    expect(await _status(tester), startsWith('Przygotowane'));

    // 31 min później, bez dotykania ekranu — stan przelicza się sam.
    clock = DateTime(2026, 10, 17, 8, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(await _status(tester),
        startsWith('Pomiar nieaktualny: O₂ z 07:30, DGW z 07:30'));
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    await _back(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cs-item-status-0')))
            .data,
        'Pomiar nieaktualny');

    // Następny dzień — protokół nieaktualny, nawet ze świeżym pomiarem.
    clock = DateTime(2026, 10, 18, 7, 0);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('cs-item-status-0')))
            .data,
        'Nieaktualne');
    await _tapKey(tester, 'cs-open-0');
    await _fullReading(tester);
    expect(await _status(tester),
        startsWith('Protokół z dnia 2026-10-17 — nieaktualny'));
    expect(find.byKey(const ValueKey('cs-old-notice')), findsOneWidget);
    // Pomiar z innego dnia niż data protokołu — z datą.
    expect(await _row(tester, 1), startsWith('2026-10-18 07:00'));
  });

  testWidgets('ręczna godzina: z przyszłości odrzucona; STOP wpisany później '
      'blokuje zieleń', (tester) async {
    var clock = DateTime(2026, 10, 17, 14, 0);
    TimeOfDay? picked;
    await _pump(tester, now: () => clock, pickTime: () => picked);
    await _tapKey(tester, 'cs-new');
    await _tickAllBefore(tester);

    // 14:05 przy zegarze 14:00 — odrzucone, nic nie zapisano.
    picked = const TimeOfDay(hour: 14, minute: 5);
    await _tapKey(tester, 'cs-meas-time');
    await _fullReading(tester);
    expect(find.byKey(const ValueKey('cs-meas-future')), findsOneWidget);
    await _show(tester, 'cs-meas-empty');

    // 13:58 — przyjęte (pola zostały wypełnione).
    picked = const TimeOfDay(hour: 13, minute: 58);
    await _tapKey(tester, 'cs-meas-time');
    await _tapKey(tester, 'cs-meas-add');
    expect(await _status(tester), startsWith('Przygotowane'));

    // O 14:03 wpisany zaległy pomiar z 13:55 z alarmem O₂ 17 % — wpis
    // późniejszy niż decydujący blokuje zieleń.
    clock = DateTime(2026, 10, 17, 14, 3);
    picked = const TimeOfDay(hour: 13, minute: 55);
    await _tapKey(tester, 'cs-meas-time');
    await _reading(tester, o2: '17');
    expect(await _status(tester),
        startsWith('STOP — tlen 17 % o 13:55 (wpisany po odczycie z 13:58)'));
    final saved = (await _load()).records.single;
    expect(saved.measurements.map((m) => m.enteredAt), [
      DateTime(2026, 10, 17, 14, 3).millisecondsSinceEpoch,
      DateTime(2026, 10, 17, 14, 0).millisecondsSinceEpoch,
    ]);
  });

  testWidgets('ręczna godzina z wczoraj wymaga potwierdzenia', (tester) async {
    final clock = DateTime(2026, 10, 18, 0, 12);
    TimeOfDay? picked = const TimeOfDay(hour: 23, minute: 50);
    await _pump(tester, now: () => clock, pickTime: () => picked);
    await _tapKey(tester, 'cs-new');
    await _tapKey(tester, 'cs-meas-time');
    await _fullReading(tester);
    expect(find.text('Pomiar wczoraj?'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    await _show(tester, 'cs-meas-empty');

    await _tapKey(tester, 'cs-meas-add');
    await tester.tap(find.byKey(const ValueKey('cs-yesterday-confirm')));
    await tester.pumpAndSettle();
    expect(await _row(tester, 0), startsWith('2026-10-17 23:50'));
    expect((await _load()).records.single.measurements.single.at,
        DateTime(2026, 10, 17, 23, 50).millisecondsSinceEpoch);
  });

  testWidgets('historia: ostrzeżenie od 180 protokołów, przy 200 nowy odrzucony',
      (tester) async {
    List<ConfinedSpaceRecord> many(int n) => [
          for (var i = 0; i < n; i++)
            ConfinedSpaceRecord.fromJson(
                {..._yesterday().toJson(), 'id': 'p$i'})!,
        ];
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key: jsonEncode(confinedSpaceRecordsToJson(
          many(ConfinedSpaceStore.warnAt))),
    });
    await _pump(tester);
    await _show(tester, 'cs-store-warn');
    expect(find.textContaining('Historia: 180/200'), findsOneWidget);

    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key: jsonEncode(confinedSpaceRecordsToJson(
          many(ConfinedSpaceStore.maxEntries))),
    });
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _tapKey(tester, 'cs-new');
    expect(find.byKey(const ValueKey('cs-store-full')), findsOneWidget);
    expect(find.text('Protokół wejścia'), findsNothing);
    // Magazyn też nie przyjmie nowego — stare nie wypadają po cichu.
    await expectLater(
        const ConfinedSpaceStore().upsert(ConfinedSpaceRecord.fromJson(
            {..._yesterday().toJson(), 'id': 'nowy'})!),
        throwsA(isA<ConfinedSpaceStoreFull>()));
    expect((await _load()).records, hasLength(ConfinedSpaceStore.maxEntries));
  });

  testWidgets('„Cofnij” usunięcia protokołu działa także przy pełnej historii',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key: jsonEncode(confinedSpaceRecordsToJson([
        for (var i = 0; i < ConfinedSpaceStore.maxEntries; i++)
          ConfinedSpaceRecord.fromJson(
              {..._yesterday().toJson(), 'id': 'p$i'})!,
      ])),
    });
    await _pump(tester);
    await _tapKey(tester, 'cs-menu-0');
    await tester.tap(find.byKey(const ValueKey('cs-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cs-delete-confirm')));
    await tester.pumpAndSettle();
    final deleted = {
      for (var i = 0; i < ConfinedSpaceStore.maxEntries; i++) 'p$i'
    }.difference((await _load()).records.map((r) => r.id).toSet()).single;
    // W międzyczasie historia znów doszła do 200.
    await const ConfinedSpaceStore().upsert(ConfinedSpaceRecord.fromJson(
        {..._yesterday().toJson(), 'id': 'inny'})!);
    expect((await _load()).records, hasLength(ConfinedSpaceStore.maxEntries));
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    final ids = (await _load()).records.map((r) => r.id).toSet();
    expect(ids, contains(deleted));
    expect(ids, hasLength(ConfinedSpaceStore.maxEntries + 1));
  });

  test('nieczytelna historia: pusta lista, flaga i kopia przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues(
        {ConfinedSpaceStore.key: '[{"id": "x"'});
    const store = ConfinedSpaceStore();
    final load = await store.load();
    expect(load.records, isEmpty);
    expect(load.unreadable, isTrue);
    await store.upsert(_yesterday());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ConfinedSpaceStore.corruptBackupKey), '[{"id": "x"');
    expect((await store.load()).records.single.id, 'old');
    expect((await store.load()).damaged, isFalse);
  });

  test('pełna historia: zmiana zapisanego działa, nowy odrzucony, nic nie '
      'wypada', () async {
    SharedPreferences.setMockInitialValues({
      ConfinedSpaceStore.key: jsonEncode(confinedSpaceRecordsToJson([
        for (var i = 0; i < ConfinedSpaceStore.maxEntries; i++)
          ConfinedSpaceRecord.fromJson(
              {..._yesterday().toJson(), 'id': 'p$i', 'date': '2020-01-01'})!,
      ])),
    });
    const store = ConfinedSpaceStore();
    final first = (await store.load()).records.first;
    await store.upsert(first.copyWith(notes: 'zmiana'));
    expect((await store.load()).records.firstWhere((r) => r.id == first.id)
        .notes, 'zmiana');
    await expectLater(
        store.upsert(ConfinedSpaceRecord.fromJson(
            {..._yesterday().toJson(), 'id': 'nowy'})!),
        throwsA(isA<ConfinedSpaceStoreFull>()));
    final ids = (await store.load()).records.map((r) => r.id).toSet();
    expect(ids, hasLength(ConfinedSpaceStore.maxEntries));
    expect(ids, isNot(contains('nowy')));
  });
}

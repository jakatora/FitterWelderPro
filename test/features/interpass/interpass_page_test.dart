import '../../support/test_account.dart';
// Ekran „Temperatura podgrzania i międzyściegowa”: ustawienia → pomiary →
// werdykt (zielony tylko z kompletem ściegów w limitach), przekroczenie =
// czerwony, przełączenie °F nie zmienia danych ani werdyktu, kredka (próg
// i wynik), pomiar wsteczny, wybór spoiny z dziennika (wstrzyknięty),
// udostępnianie (wstrzyknięte), EN, 320×640 z czcionką ×1,3, cele dotyku.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/welding/interpass_log.dart';
import 'package:cut_list_app/domain/welding/interpass_text.dart';
import 'package:cut_list_app/features/interpass/interpass_page.dart';
import 'package:cut_list_app/features/interpass/interpass_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

/// Zegar domyślny testów: start 07:30, każdy dodany pomiar przesuwa go
/// o 5 min (sąsiednie ściegi muszą być odległe o co najmniej 1 min).
DateTime _clock = _now;

class _Spy {
  final List<(String, String)> texts = [];
  final List<(InterpassWeld, bool, InterpassUnit)> pdfs = [];
  Future<void> text(String t, String subject) async {
    texts.add((t, subject));
    _lastShared = t;
  }

  Future<void> pdf(InterpassWeld w, bool en, InterpassUnit u) async =>
      pdfs.add((w, en, u));
}

const _journalWeld = WeldEntry(
  id: 'j1',
  weldNo: 'W-07',
  projectName: 'Projekt A',
  pipeName: '100-P-12',
  material: 'P91',
  od: '168.3',
  t: '18.26',
  method: '141/111',
  welder: 'Jan Kowalski',
  date: '2026-10-17',
  notes: '',
  status: 'done',
  isoDrawing: 'ISO-12',
  wpsRef: 'WPS-091',
);

Future<_Spy> _pump(
  WidgetTester tester, {
  AppLanguage language = AppLanguage.pl,
  Size size = const Size(1080, 2400),
  double textScale = 1.0,
  DateTime Function()? now,
  InterpassJournalSource? loadWelds,
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
      home: InterpassPage(
        now: now ?? () => _clock,
        newId: () => 'ip-${++n}',
        shareText: spy.text,
        sharePdf: spy.pdf,
        loadWelds: loadWelds ?? () async => const [_journalWeld],
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
    find.byKey(const ValueKey('ip-edit-list')).evaluate().isNotEmpty
        ? 'ip-edit-list'
        : 'ip-list';

/// Pokazuje element o kluczu [key] (przewija w górę lub w dół).
Future<Finder> _show(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  if (f.evaluate().isEmpty) {
    final list = _currentList;
    // Na górę listy (także na małym ekranie), potem w dół do elementu.
    tester.state<ScrollableState>(_scrollable(list)).position.jumpTo(0);
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
  final f = await _show(tester, 'ip-status-text');
  return tester.widget<Text>(f).data!;
}

Color? _statusColor(WidgetTester tester) =>
    tester.widget<Icon>(find.byKey(const ValueKey('ip-status-icon'))).color;

Future<String> _head(WidgetTester tester, int i) async {
  final f = await _show(tester, 'ip-r-head-$i');
  return tester.widget<Text>(f).data!;
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

Future<void> _addReading(WidgetTester tester, String temp,
    {String? pass}) async {
  if (pass != null) await _enter(tester, 'ip-m-pass', pass);
  await _enter(tester, 'ip-m-temp', temp);
  await _tapKey(tester, 'ip-m-add');
  _clock = _clock.add(const Duration(minutes: 5));
}

/// Nowa spoina z limitami 100 / 250 °C i liczbą ściegów [passes].
Future<void> _newWeld(WidgetTester tester, {String passes = '2'}) async {
  await _tapKey(tester, 'ip-new');
  await _enter(tester, 'ip-f-weldNo', 'S-12');
  await _enter(tester, 'ip-f-preMin', '100');
  await _enter(tester, 'ip-f-intMax', '250');
  if (passes.isNotEmpty) await _enter(tester, 'ip-f-passes', passes);
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// Jedyna zapisana spoina.
Future<InterpassWeld> _savedWeld() async =>
    (await const InterpassStore().load()).welds.single;

/// Protokół tekstowy otwartej spoiny (przez wstrzykniętą funkcję).
Future<String?> _shareTextOf(WidgetTester tester) async {
  _lastShared = null;
  await _tapKey(tester, 'ip-share-text');
  return _lastShared;
}

/// Ostatni tekst przekazany do wstrzykniętego udostępniania.
String? _lastShared;

void main() {
  useGuestAccount();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _clock = _now;
  });

  testWidgets('zły tekst w polu limitu nie kasuje zapisanego limitu',
      (tester) async {
    await _pump(tester);
    await _newWeld(tester);
    await _addReading(tester, '120');
    await _addReading(tester, '300');
    expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 2'));
    final saved = await _savedWeld();
    final protocolBefore = (await _shareTextOf(tester))!;

    // „2500” (poza zakresem) i „-” — limit 250 °C zostaje, pomiar czerwony.
    for (final bad in ['2500', '-']) {
      await _enter(tester, 'ip-f-intMax', bad);
      expect(find.text('Wpisz -60…1000 °C — zapisany limit bez zmian: 250 °C'),
          findsOneWidget,
          reason: bad);
      expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 2'));
      expect(_statusColor(tester), kFail);
      expect((await _savedWeld()).limits, saved.limits);
    }
    // Protokół też bez zmian (dalej czerwony, z limitem 250 °C).
    final protocolAfter = (await _shareTextOf(tester))!;
    expect(protocolAfter, contains('Maks. międzyściegowa: ≤ 250 °C'));
    expect(protocolAfter, contains('POWYŻEJ MAKS.'));
    expect(protocolAfter.split('\n').where((l) => l.contains('≤ 250 °C')),
        protocolBefore.split('\n').where((l) => l.contains('≤ 250 °C')));

    // Liczba ściegów: „0” nie kasuje zapisanych 2.
    await _enter(tester, 'ip-f-passes', '0');
    expect(find.text('Wpisz 1–999 — zapisane bez zmian: 2'), findsOneWidget);
    expect((await _savedWeld()).passCount, 2);

    // Dopiero puste pole kasuje limit — wtedy „brak limitu z WPS”.
    await _enter(tester, 'ip-f-intMax', '');
    expect((await _savedWeld()).limits.interpassMax, isNull);
    expect(await _head(tester, 1), 'Ścieg 2 · 300 °C · brak limitu z WPS');
  });

  testWidgets('400 °F wpisane w °F zostaje 400 °F w polu, tekście i PDF',
      (tester) async {
    final spy = await _pump(tester);
    await _tapKey(tester, 'ip-new');
    await _tapKey(tester, 'ip-unit-f');
    await _enter(tester, 'ip-f-weldNo', 'S-F');
    await _enter(tester, 'ip-f-preMin', '375');
    await _enter(tester, 'ip-f-intMax', '400');
    await _enter(tester, 'ip-f-passes', '1');
    await _addReading(tester, '400');
    expect(await _head(tester, 0), 'Ścieg 1 · 400 °F · OK');

    // W °C — przeliczone; z powrotem w °F — dokładnie wpisane liczby.
    await _tapKey(tester, 'ip-unit-c');
    expect(_field(tester, 'ip-f-intMax'), '204,444');
    expect(
        await _head(tester, 0), 'Ścieg 1 · 204,444 °C (wpisano 400 °F) · OK');
    await _tapKey(tester, 'ip-unit-f');
    expect(_field(tester, 'ip-f-preMin'), '375');
    expect(_field(tester, 'ip-f-intMax'), '400');

    await _tapKey(tester, 'ip-share-text');
    final text = spy.texts.single.$1;
    expect(text, contains('Min. podgrzanie: ≥ 375 °F'));
    expect(text, contains('Maks. międzyściegowa: ≤ 400 °F'));
    expect(text, isNot(contains('399,99')));
    expect(text, isNot(contains('375,01')));
    await _tapKey(tester, 'ip-share-pdf-btn');
    final (weld, _, unit) = spy.pdfs.single;
    expect(unit, InterpassUnit.f);
    expect(interpassReadingRows(weld, unit, en: false).single[2], '400 °F');
    expect(interpassWeldLines(weld, unit, en: false)[4].value, '≤ 400 °F');
  });

  testWidgets('„Cofnij” po usunięciu pomiaru działa także po zamknięciu ekranu',
      (tester) async {
    await _pump(tester);
    await _newWeld(tester);
    await _addReading(tester, '120');
    await _addReading(tester, '200');
    expect(await _status(tester), startsWith('Wszystkie ściegi (2)'));
    await _tapKey(tester, 'ip-r-del-1');
    expect((await _savedWeld()).readings, hasLength(1));
    // Ekran spoiny zamknięty — snackbar wisi nad listą.
    await _back(tester);
    expect(find.byKey(const ValueKey('ip-removed')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ip-item-status-0')))
            .data,
        'Brak pomiaru');
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    final w = await _savedWeld();
    expect(w.readings.map((r) => r.tempC), [120, 200]);
    // Lista odświeżona.
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ip-item-status-0')))
            .data,
        'OK — w limitach');
  });

  testWidgets('pominięty uszkodzony pomiar: baner, brak zieleni, potwierdzenie',
      (tester) async {
    final good = InterpassWeld(
      id: 'lost',
      weldNo: 'S-L',
      limits: InterpassLimits.celsius(preheatMinC: 100, interpassMaxC: 250),
      passCount: 2,
      readings: [
        InterpassReading(
            pass: 1,
            temp: const InterpassTemp.c(120),
            at: _now.millisecondsSinceEpoch,
            recordedAt: _now.millisecondsSinceEpoch),
        InterpassReading(
            pass: 2,
            temp: const InterpassTemp.c(230),
            at: _now.millisecondsSinceEpoch + 600000,
            recordedAt: _now.millisecondsSinceEpoch + 600000),
      ],
      createdAt: 1,
      updatedAt: 2,
    ).toJson();
    final raw = jsonEncode({
      'v': 2,
      'welds': [
        {
          ...good,
          'readings': [
            ...(good['readings'] as List),
            // Najpóźniejszy, gorący pomiar — nieczytelny.
            {
              'pass': 2,
              'temp': {'v': 290, 'u': 'c'},
              'bound': '?'
            },
          ],
        },
      ],
    });
    SharedPreferences.setMockInitialValues({InterpassStore.key: raw});
    await _pump(tester);
    expect(find.byKey(const ValueKey('ip-corrupt')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ip-item-status-0')))
            .data,
        'Pominięte pomiary — sprawdź');
    await _tapKey(tester, 'ip-open-0');
    expect(await _status(tester),
        startsWith('Przy odczycie zapisu pominięto uszkodzone pomiary: 1'));
    expect(_statusColor(tester), kWarn);
    await _tapKey(tester, 'ip-lost-confirm');
    expect(await _status(tester), startsWith('Wszystkie ściegi (2)'));
    final w = await _savedWeld();
    expect(w.lostReadings, 0);
    expect(w.lostConfirmed, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey), raw);
  });

  testWidgets(
      'pusta min. międzyściegowa: podpowiedź i „ustaw = min. podgrzania”',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'ip-new');
    await _enter(tester, 'ip-f-preMin', '150');
    await _enter(tester, 'ip-f-intMax', '250');
    await _enter(tester, 'ip-f-passes', '2');
    final field = await _show(tester, 'ip-f-intMin');
    expect(
        find.descendant(
            of: field, matching: find.textContaining('NIE jest kontrolowany')),
        findsOneWidget);
    await _addReading(tester, '160');
    await _addReading(tester, '60');
    // Zachowanie bez zmian — OK — ale wyraźna podpowiedź w statusie.
    expect(await _status(tester), startsWith('Wszystkie ściegi (2)'));
    final note = await _show(tester, 'ip-status-nomin');
    expect(tester.widget<Text>(note).data,
        startsWith('Ścieg 2: poniżej min. podgrzania 150 °C — NIE oceniany'));
    await _tapKey(tester, 'ip-intmin-from-preheat');
    expect(_field(tester, 'ip-f-intMin'), '150');
    expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 2'));
    expect(find.byKey(const ValueKey('ip-intmin-from-preheat')), findsNothing);
    expect((await _savedWeld()).limits.interpassMinC, 150);
  });

  testWidgets('ustawienia → pomiary → werdykt; równość z limitem = OK',
      (tester) async {
    await _pump(tester);
    expect(find.text('Podgrzanie i międzyściegowa'), findsOneWidget);
    expect(find.byKey(const ValueKey('ip-empty')), findsOneWidget);

    await _tapKey(tester, 'ip-new');
    expect(await _status(tester),
        'Brak pomiarów — zmierz przed pierwszym ściegiem (podgrzanie).');
    await _enter(tester, 'ip-f-weldNo', 'S-12');
    await _enter(tester, 'ip-f-preMin', '100');
    await _enter(tester, 'ip-f-intMax', '250');
    await _enter(tester, 'ip-f-passes', '2');

    // Przed ściegiem 1 — podgrzanie 120 °C.
    expect(_field(tester, 'ip-m-pass'), '1');
    await _addReading(tester, '120');
    expect(await _head(tester, 0), 'Ścieg 1 · 120 °C · OK');
    expect(await _status(tester), 'Brak pomiaru przed ściegiem 2.');
    expect(_statusColor(tester), kWarn);

    // Następny ścieg podpowiedziany; 250 °C = maks. — OK (granica).
    expect(_field(tester, 'ip-m-pass'), '2');
    await _addReading(tester, '250');
    expect(await _head(tester, 1), 'Ścieg 2 · 250 °C · OK');
    expect(
        await _status(tester),
        'Wszystkie ściegi (2) mają pomiar przed rozpoczęciem i wszystkie są '
        'w limitach z WPS.');
    expect(_statusColor(tester), kPass);

    await _back(tester);
    expect(find.text('SPOINY (1)'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('ip-item-status-0')))
            .data,
        'OK — w limitach');
    final saved = (await const InterpassStore().load()).welds.single;
    expect(saved.id, 'ip-1');
    expect(saved.weldNo, 'S-12');
    expect(saved.limits.preheatMinC, 100);
    expect(saved.limits.interpassMaxC, 250);
    expect(saved.passCount, 2);
    expect(saved.readings.map((r) => (r.pass, r.tempC)), [(1, 120), (2, 250)]);
    expect(saved.readings.first.at, _now.millisecondsSinceEpoch);
  });

  testWidgets('przekroczenie maks. → czerwony; ponowny pomiar po odczekaniu',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 8, 0);
    await _pump(tester, now: () => clock);
    await _newWeld(tester);
    await _addReading(tester, '120');
    clock = DateTime(2026, 10, 17, 8, 40);
    await _addReading(tester, '260');
    expect(await _head(tester, 1), 'Ścieg 2 · 260 °C · POWYŻEJ MAKS.');
    expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 2'));
    expect(_statusColor(tester), kFail);
    expect(find.byIcon(Icons.dangerous_outlined), findsOneWidget);
    // Po przekroczeniu podpowiedź: ten sam ścieg (ponowny pomiar).
    expect(_field(tester, 'ip-m-pass'), '2');

    // Odczekano — 240 °C decyduje; przekroczenie zostaje w protokole.
    clock = DateTime(2026, 10, 17, 8, 50);
    await _addReading(tester, '240');
    expect(await _status(tester), startsWith('Wszystkie ściegi (2)'));
    expect(_statusColor(tester), kPass);
    await _show(tester, 'ip-status-superseded');
    expect(await _head(tester, 1), 'Ścieg 2 · 260 °C · POWYŻEJ MAKS.');

    // Za zimno przed ściegiem 1 też jest czerwone.
    await _enter(tester, 'ip-f-preMin', '130');
    expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 1'));
  });

  testWidgets('przełączenie °F nie zmienia danych ani werdyktu',
      (tester) async {
    await _pump(tester);
    await _newWeld(tester);
    await _addReading(tester, '120');
    await _addReading(tester, '260');
    final statusC = await _status(tester);
    expect(statusC, startsWith('POZA LIMITEM'));
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(InterpassStore.key);

    await _tapKey(tester, 'ip-unit-f');
    expect(_field(tester, 'ip-f-preMin'), '212');
    expect(_field(tester, 'ip-f-intMax'), '482');
    expect(await _head(tester, 1),
        'Ścieg 2 · 500 °F (wpisano 260 °C) · POWYŻEJ MAKS.');
    expect(await _status(tester), statusC);
    expect(_statusColor(tester), kFail);
    expect(prefs.getString(InterpassStore.key), before);
    expect(prefs.getString(InterpassStore.unitKey), 'f');

    // Pomiar wpisany w °F: 482 °F = 250 °C — równość z limitem, OK.
    await _addReading(tester, '482', pass: '2');
    expect(await _status(tester), startsWith('Wszystkie ściegi (2)'));
    final saved = (await const InterpassStore().load()).welds.single;
    expect(saved.readings.last.tempC, 250);
    expect(saved.limits.interpassMaxC, 250);

    // Z powrotem w °C — te same liczby co wpisane.
    await _tapKey(tester, 'ip-unit-c');
    expect(_field(tester, 'ip-f-intMax'), '250');
    expect(await _head(tester, 2), 'Ścieg 2 · 250 °C (wpisano 482 °F) · OK');

    // Lista spoin pamięta jednostkę; ponowne otwarcie — pola w °F.
    await _tapKey(tester, 'ip-unit-f');
    await _back(tester);
    await _tapKey(tester, 'ip-open-0');
    expect(_field(tester, 'ip-f-intMax'), '482');
  });

  testWidgets('brak limitu z WPS — neutralnie, nie zielony i nie czerwony',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'ip-new');
    await _enter(tester, 'ip-f-passes', '1');
    await _addReading(tester, '20');
    expect(await _head(tester, 0), 'Ścieg 1 · 20 °C · brak limitu z WPS');
    expect(await _status(tester), startsWith('Brak limitu z WPS dla ściegu 1'));
    expect(_statusColor(tester), kTextSec);
  });

  testWidgets('kredka: próg i wynik — bez wyniku nie da się dodać',
      (tester) async {
    await _pump(tester);
    await _newWeld(tester, passes: '1');
    await _tapKey(tester, 'ip-method-crayon');
    await _show(tester, 'ip-method-note');
    expect(find.textContaining('TOPI SIĘ'), findsOneWidget);
    await _enter(tester, 'ip-m-temp', '100');
    final add = await _show(tester, 'ip-m-add');
    expect(tester.widget<ButtonStyleButton>(add).onPressed, isNull);
    await _tapKey(tester, 'ip-m-melted');
    await _tapKey(tester, 'ip-m-add');
    expect(await _head(tester, 0), 'Ścieg 1 · ≥ 100 °C · OK');
    expect(await _status(tester), startsWith('Wszystkie ściegi (1)'));

    // Kredka 100 NIE stopiona przed ściegiem 1 → za zimno.
    await _enter(tester, 'ip-m-pass', '1');
    await _enter(tester, 'ip-m-temp', '100');
    await _tapKey(tester, 'ip-m-notmelted');
    await _tapKey(tester, 'ip-m-add');
    expect(await _status(tester), startsWith('POZA LIMITEM — ścieg 1'));
    final saved = (await const InterpassStore().load()).welds.single;
    expect(saved.readings.map((r) => r.bound),
        [InterpassBound.atLeast, InterpassBound.below]);
    expect(saved.readings.every((r) => r.method == InterpassMethod.crayon),
        isTrue);
  });

  testWidgets('pomiar wsteczny: lista wg czasu i ostrzeżenie', (tester) async {
    var clock = DateTime(2026, 10, 17, 10, 30);
    await _pump(tester, now: () => clock);
    await _newWeld(tester);
    await _addReading(tester, '120');
    // Pomiar z chwilą wcześniejszą niż ostatni (zegar 10:00 — ta sama
    // ścieżka co ręcznie wybrana godzina wstecz).
    clock = DateTime(2026, 10, 17, 10, 0);
    await _addReading(tester, '200');
    expect(find.byKey(const ValueKey('ip-backdated')), findsOneWidget);
    expect(await _head(tester, 0), startsWith('Ścieg 2'));
    expect(await _status(tester), startsWith('Godziny pomiarów nie zgadzają'));
  });

  testWidgets('wybór spoiny z dziennika (wstrzyknięty)', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'ip-new');
    await _tapKey(tester, 'ip-pick-journal');
    await tester.tap(find.byKey(const ValueKey('ip-journal-j1')));
    await tester.pumpAndSettle();
    expect(_field(tester, 'ip-f-weldNo'), 'W-07');
    expect(_field(tester, 'ip-f-desc'), 'Projekt A · ISO-12 · P91');
    expect(_field(tester, 'ip-f-wps'), 'WPS-091');
    expect(find.text('Spoina W-07'), findsOneWidget);
    final saved = (await const InterpassStore().load()).welds.single;
    expect(saved.journalWeldId, 'j1');
  });

  testWidgets('dziennik niedostępny — komunikat, wpis ręczny', (tester) async {
    await _pump(tester, loadWelds: () async => throw StateError('db'));
    await _tapKey(tester, 'ip-new');
    await _tapKey(tester, 'ip-pick-journal');
    expect(find.byKey(const ValueKey('ip-journal-failed')), findsOneWidget);
  });

  testWidgets('udostępnianie przez wstrzyknięte funkcje: tekst i PDF',
      (tester) async {
    final spy = await _pump(tester);
    await _newWeld(tester);
    await _addReading(tester, '120');
    await _tapKey(tester, 'ip-share-text');
    final (text, subject) = spy.texts.single;
    expect(subject, 'Protokół temperatury podgrzania i międzyściegowej');
    expect(text, contains('Nr spoiny: S-12'));
    expect(text, contains('Min. podgrzanie: ≥ 100 °C'));
    expect(text, contains('Ścieg 1 · 2026-10-17 07:30 · 120 °C'));
    expect(text, contains('WERDYKT: Brak pomiaru przed ściegiem 2.'));

    await _tapKey(tester, 'ip-share-pdf-btn');
    final (weld, en, unit) = spy.pdfs.single;
    expect(weld.weldNo, 'S-12');
    expect(weld.readings, hasLength(1));
    expect(en, isFalse);
    expect(unit, InterpassUnit.c);
  });

  testWidgets('po angielsku — te same liczby', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Preheat and interpass'), findsOneWidget);
    await _tapKey(tester, 'ip-new');
    expect(find.text('Temperature readings'), findsOneWidget);
    expect(await _status(tester),
        'No readings — measure before the first run (preheat).');
    await _newWeldEn(tester);
    await _addReading(tester, '90');
    expect(await _head(tester, 0), 'Pass 1 · 90 °C · BELOW MIN');
    expect(await _status(tester), startsWith('OUT OF LIMITS — pass 1'));
  });

  testWidgets('320×640, czcionka 1,3: bez przepełnień', (tester) async {
    final long = InterpassWeld(
      id: 'long',
      weldNo: 'S-1234/ISO-100-P-12-0042-ARK-07/REW.C',
      description: 'Rafineria — instalacja hydroodsiarczania, rurociąg '
          'parowy P91 Ø273 × 25, estakada E-4, strona ssawna pompy P-101',
      wpsRef: 'WPS-P91-141/111-0091 rev C (kwalifikacja PQR-77)',
      limits: InterpassLimits.celsius(
          preheatMinC: 200, interpassMaxC: 300, interpassMinC: 200),
      method: InterpassMethod.crayon,
      passCount: 12,
      readings: [
        InterpassReading(
            pass: 1,
            temp: InterpassTemp.entered(392, InterpassUnit.f),
            bound: InterpassBound.atLeast,
            method: InterpassMethod.crayon,
            at: _now.millisecondsSinceEpoch,
            recordedAt: _now.millisecondsSinceEpoch + 3600000,
            note: 'Kredka po stronie przeciwnej, 4t od rowka, odczekano '
                '2 min na 25 mm'),
        InterpassReading(
            pass: 2,
            temp: const InterpassTemp.c(321.25),
            at: _now.millisecondsSinceEpoch + 60000,
            recordedAt: _now.millisecondsSinceEpoch + 60000),
      ],
      createdAt: 1,
      updatedAt: 2,
    );
    SharedPreferences.setMockInitialValues({
      InterpassStore.key: jsonEncode(interpassLogToJson([long])),
    });
    await _pump(tester, size: const Size(320, 640), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'ip-open-0');
    expect(tester.takeException(), isNull);
    // Cały ekran edycji, kawałek po kawałku.
    for (var i = 0; i < 40; i++) {
      await tester.drag(_scrollable('ip-edit-list'), const Offset(0, -250));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    await _tapKey(tester, 'ip-unit-f');
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'ip-pick-journal');
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _back(tester);
    await _tapKey(tester, 'ip-new');
    expect(tester.takeException(), isNull);
    // Pusta min. międzyściegowa: długa podpowiedź, przycisk i błąd pola.
    await _enter(tester, 'ip-f-preMin', '150');
    await _enter(tester, 'ip-f-intMax', '2500');
    await _show(tester, 'ip-intmin-from-preheat');
    expect(tester.takeException(), isNull);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('ip-intmin-from-preheat')))
            .height,
        greaterThanOrEqualTo(kMinTapTarget));
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica), „Dodaj pomiar” duży',
      (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byKey(const ValueKey('ip-new'))).height,
        greaterThanOrEqualTo(kMinTapTarget));
    await _newWeld(tester);
    await _addReading(tester, '120');
    final add = await _show(tester, 'ip-m-add');
    expect(tester.getSize(add).height, greaterThanOrEqualTo(56));
    for (final k in [
      'ip-m-pass-minus',
      'ip-m-pass-plus',
      'ip-m-date',
      'ip-m-time',
      'ip-r-del-0',
      'ip-pick-journal',
      'ip-method-contact',
      'ip-method-crayon',
      'ip-method-pyrometer',
      'ip-share-text-btn',
      'ip-share-pdf-btn',
    ]) {
      final f = await _show(tester, k);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
    for (final k in ['ip-m-pass-minus', 'ip-m-pass-plus', 'ip-r-del-0']) {
      expect(tester.getSize(find.byKey(ValueKey(k))).width,
          greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
    await _show(tester, 'ip-unit');
    final seg = find.ancestor(
        of: find.byKey(const ValueKey('ip-unit-f')),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(
        tester.getSize(seg.first).height, greaterThanOrEqualTo(kMinTapTarget));
    await _tapKey(tester, 'ip-method-crayon');
    for (final k in ['ip-m-melted', 'ip-m-notmelted']) {
      final f = await _show(tester, k);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });

  testWidgets('usunięcie pomiaru i spoiny z cofnięciem; uszkodzony zapis',
      (tester) async {
    SharedPreferences.setMockInitialValues({InterpassStore.key: '[zepsute'});
    await _pump(tester);
    expect(find.byKey(const ValueKey('ip-corrupt')), findsOneWidget);
    await _newWeld(tester);
    await _addReading(tester, '120');
    await _tapKey(tester, 'ip-r-del-0');
    expect(find.byKey(const ValueKey('ip-readings-empty')), findsOneWidget);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(await _head(tester, 0), 'Ścieg 1 · 120 °C · OK');
    await _back(tester);

    await _tapKey(tester, 'ip-del-0');
    await tester.tap(find.byKey(const ValueKey('ip-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ip-empty')), findsOneWidget);
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('SPOINY (1)'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(InterpassStore.corruptBackupKey), '[zepsute');
  });

  testWidgets('kalendarz międzyściegowy po cofnięciu zegara nadal się otwiera',
      (tester) async {
    var now = DateTime(2026, 10, 18, 9);
    await _pump(tester, now: () => now);
    await _tapKey(tester, 'ip-new');
    await _tapKey(tester, 'ip-m-date');
    Navigator.of(tester.element(find.byType(DatePickerDialog)))
        .pop(DateTime(2026, 10, 18));
    await tester.pumpAndSettle();

    now = DateTime(2026, 10, 17, 9);
    await _tapKey(tester, 'ip-m-date');
    expect(tester.takeException(), isNull);
    expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog))
        .initialDate, DateTime(2026, 10, 17));
  });
}

/// Limity 100 / 250 w już otwartej nowej spoinie (wersja EN).
Future<void> _newWeldEn(WidgetTester tester) async {
  await _enter(tester, 'ip-f-preMin', '100');
  await _enter(tester, 'ip-f-intMax', '250');
  await _enter(tester, 'ip-f-passes', '2');
}

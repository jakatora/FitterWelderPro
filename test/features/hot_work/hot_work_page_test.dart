// Ekran „Prace pożarowo niebezpieczne”: nowy protokół — odhaczanie punktów,
// pomiar atmosfery (bez pomiaru nie ma zielonego stanu, pomiar powyżej
// progu = STOP), zapis w SharedPreferences i historia, „jak wczoraj”
// (kopia bez zaznaczeń i pomiarów), usuwanie z cofnięciem, udostępnianie
// (wstrzyknięte), EN, wąski ekran z czcionką ×1,3, cele dotyku.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/hot_work/hot_work_checklist.dart';
import 'package:cut_list_app/domain/hot_work/hot_work_permit.dart';
import 'package:cut_list_app/features/hot_work/hot_work_page.dart';
import 'package:cut_list_app/features/hot_work/hot_work_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/theme/app_theme.dart';

final _now = DateTime(2026, 10, 17, 7, 30);

class _Spy {
  final List<(String, String)> texts = [];
  final List<(HotWorkPermit, bool)> pdfs = [];
  Future<void> text(String t, String subject) async => texts.add((t, subject));
  Future<void> pdf(HotWorkPermit p, bool en) async => pdfs.add((p, en));
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
      home: HotWorkPage(
        now: now ?? () => _now,
        newId: () => 'hw-${++n}',
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

/// Przewijalna lista ekranu (edycji albo historii).
Finder _scrollable(String listKey) => find
    .descendant(
        of: find.byKey(ValueKey(listKey)), matching: find.byType(Scrollable))
    .first;

String get _currentList =>
    find.byKey(const ValueKey('hw-edit-list')).evaluate().isNotEmpty
        ? 'hw-edit-list'
        : 'hw-list';

/// Pokazuje element o kluczu [key] (przewija w górę lub w dół).
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

Future<String> _status(WidgetTester tester) async {
  final f = await _show(tester, 'hw-status-text');
  return tester.widget<Text>(f).data!;
}

Future<void> _tickAllBefore(WidgetTester tester) async {
  for (final c in hotWorkChecksIn(HotWorkPhase.before)) {
    await _tapKey(tester, 'hw-check-${c.id}');
  }
}

Future<void> _back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

HotWorkPermit _yesterday() => HotWorkPermit(
      id: 'old',
      permitNo: 'ZPP/6/2026',
      location: 'Instalacja HDS, kołnierz F-12',
      description: 'Spawanie króćca DN50',
      workTypes: const {HotWorkType.welding},
      date: '2026-10-16',
      validFrom: '07:00',
      validTo: '15:00',
      contractor: 'Jan Kowalski',
      securedBy: 'Adam Nowak',
      fireWatch: 'Piotr Wiśniewski',
      issuer: 'Ewa Zając',
      dgwLimitPct: 5,
      measurements: const [HotWorkMeasurement(time: '06:50', dgwPct: 0)],
      checked: {for (final c in kHotWorkChecks) c.id},
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'nowy protokół: odhaczenie punktów, pomiar, zapis i historia',
      (tester) async {
    await _pump(tester);
    expect(find.text('Prace pożarowo niebezpieczne'), findsOneWidget);
    expect(find.byKey(const ValueKey('hw-empty')), findsOneWidget);

    await _tapKey(tester, 'hw-new');
    expect(find.text('Protokół prac pożarowych'), findsOneWidget);
    // Nowy protokół: próg 10 % DGW z rozporządzenia, brak pomiaru.
    expect(await _status(tester),
        'Brak pomiaru atmosfery — wpisz wynik (% DGW) i godzinę.');
    await _enter(tester, 'hw-f-location', 'Instalacja HDS, kołnierz F-12');
    await _tapKey(tester, 'hw-type-welding');

    // Odhaczenie punktu i „nie dotyczy”.
    await _tapKey(tester, 'hw-check-comb-remove');
    expect(
        tester
            .widget<Icon>(find.descendant(
                of: find.byKey(const ValueKey('hw-check-comb-remove')),
                matching: find.byIcon(Icons.check_box)))
            .color,
        kPass);
    await _tapKey(tester, 'hw-na-cyl-flashback');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hw-check-cyl-flashback')),
            matching: find.byIcon(Icons.indeterminate_check_box_outlined)),
        findsOneWidget);
    // Punkt podstawowy nie ma przycisku „n/d”.
    expect(find.byKey(const ValueKey('hw-na-comb-remove')), findsNothing);
    expect(find.byKey(const ValueKey('hw-na-ext-ready')), findsNothing);

    // Pomiar 0 % DGW.
    await _enter(tester, 'hw-meas-dgw', '0');
    await _enter(tester, 'hw-meas-note', 'studzienka K-3');
    await _tapKey(tester, 'hw-meas-add');
    expect(find.text('07:30 — 0 % DGW — studzienka K-3 (OK)'), findsOneWidget);
    expect(await _status(tester), startsWith('Do odhaczenia przed'));

    await _back(tester);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect(find.text('Instalacja HDS, kołnierz F-12'), findsWidgets);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hw-item-status-0')))
            .data,
        'Niekompletne');

    final saved = await const HotWorkStore().load();
    expect(saved, hasLength(1));
    final p = saved.single;
    expect(p.id, 'hw-1');
    expect(p.location, 'Instalacja HDS, kołnierz F-12');
    expect(p.workTypes, {HotWorkType.welding});
    expect(p.checked, {'comb-remove'});
    expect(p.na, {'cyl-flashback'});
    expect(p.measurements.single.dgwPct, 0);
    expect(p.measurements.single.time, '07:30');
    expect(p.dgwLimitPct, 10);

    // Ponowne otwarcie z historii — zaznaczenia na miejscu, dokończenie
    // listy daje zielony stan.
    await _tapKey(tester, 'hw-open-0');
    for (final c in hotWorkChecksIn(HotWorkPhase.before)) {
      if (c.id == 'comb-remove' || c.id == 'cyl-flashback') continue;
      await _tapKey(tester, 'hw-check-${c.id}');
    }
    expect(await _status(tester),
        'Stanowisko przygotowane — zezwolenie może zostać podpisane.');
    await _back(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hw-item-status-0')))
            .data,
        'Gotowe');
  });

  testWidgets('wszystkie punkty odhaczone, brak pomiaru — nie zielony',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);
    expect(await _status(tester),
        'Brak pomiaru atmosfery — wpisz wynik (% DGW) i godzinę.');
    final card = tester.widget<Material>(find.byKey(const ValueKey('hw-status')));
    expect(card.color, isNot(kPass.withValues(alpha: 0.10)));
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    await _show(tester, 'hw-meas-empty');
  });

  testWidgets('pomiar powyżej progu z zezwolenia — STOP; nowy pomiar zdejmuje',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);
    await _enter(tester, 'hw-limit', '5');
    await _enter(tester, 'hw-meas-dgw', '7');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('STOP — ostatni pomiar 7 % DGW'));
    expect(find.byIcon(Icons.dangerous_outlined), findsOneWidget);

    // Po przewietrzeniu: 0 % — decyduje ostatni pomiar.
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('Stanowisko przygotowane'));

    // Usunięcie ostatniego pomiaru wraca do STOP; „Cofnij” przywraca.
    await _tapKey(tester, 'hw-meas-del-1');
    expect(await _status(tester), startsWith('STOP'));
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(await _status(tester), startsWith('Stanowisko przygotowane'));

    // Wartość spoza skali — przycisk nieaktywny.
    await _enter(tester, 'hw-meas-dgw', '150');
    final add = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('hw-meas-add')));
    expect(add.onPressed, isNull);
    expect(find.text('Wpisz liczbę 0–100'), findsOneWidget);
  });

  testWidgets('jak wczoraj: kopia danych bez zaznaczeń i pomiarów',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      HotWorkStore.key: jsonEncode(hotWorkPermitsToJson([_yesterday()])),
    });
    await _pump(tester);
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hw-item-status-0')))
            .data,
        'Zamknięte · nieaktualne');

    await _tapKey(tester, 'hw-dup-last');
    // Edytor kopii: dane zostały, lista i pomiar od nowa.
    expect(find.text('Instalacja HDS, kołnierz F-12'), findsWidgets);
    expect(find.byKey(const ValueKey('hw-old-notice')), findsNothing);
    expect(await _status(tester),
        'Brak pomiaru atmosfery — wpisz wynik (% DGW) i godzinę.');
    await _show(tester, 'hw-meas-empty');
    final f = await _show(tester, 'hw-check-comb-remove');
    expect(
        find.descendant(
            of: f, matching: find.byIcon(Icons.check_box_outline_blank)),
        findsOneWidget);
    await _back(tester);

    expect(find.text('HISTORIA (2)'), findsOneWidget);
    final saved = await const HotWorkStore().load();
    expect(saved.map((p) => p.id), ['hw-1', 'old']);
    final copy = saved.first;
    expect(copy.date, '2026-10-17');
    expect(copy.location, 'Instalacja HDS, kołnierz F-12');
    expect(copy.fireWatch, 'Piotr Wiśniewski');
    expect(copy.dgwLimitPct, 5);
    expect(copy.checked, isEmpty);
    expect(copy.measurements, isEmpty);
    expect(copy.permitNo, isEmpty);
    // Oryginał nietknięty.
    expect(saved.last.checked.length, kHotWorkChecks.length);

    // Stary protokół otwarty z historii ostrzega, że jest z innego dnia.
    await _tapKey(tester, 'hw-open-1');
    expect(find.byKey(const ValueKey('hw-old-notice')), findsOneWidget);
  });

  testWidgets('menu pozycji: duplikat i usunięcie z cofnięciem',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      HotWorkStore.key: jsonEncode(hotWorkPermitsToJson([_yesterday()])),
    });
    await _pump(tester);
    await _tapKey(tester, 'hw-menu-0');
    await tester.tap(find.byKey(const ValueKey('hw-menu-dup')));
    await tester.pumpAndSettle();
    expect(find.text('Protokół prac pożarowych'), findsOneWidget);
    await _back(tester);
    expect(find.text('HISTORIA (2)'), findsOneWidget);

    // Usunięcie kopii (najnowsza na górze) i cofnięcie.
    await _tapKey(tester, 'hw-menu-0');
    await tester.tap(find.byKey(const ValueKey('hw-menu-del')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hw-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('HISTORIA (1)'), findsOneWidget);
    expect((await const HotWorkStore().load()).single.id, 'old');
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(find.text('HISTORIA (2)'), findsOneWidget);
  });

  testWidgets('pusty protokół nie trafia do historii', (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'hw-new');
    await _back(tester);
    expect(find.byKey(const ValueKey('hw-empty')), findsOneWidget);
    expect(await const HotWorkStore().load(), isEmpty);
  });

  testWidgets('udostępnianie: tekst protokołu i PDF', (tester) async {
    final spy = await _pump(tester);
    await _tapKey(tester, 'hw-new');
    await _enter(tester, 'hw-f-location', 'Zbiornik T-101');
    await _tapKey(tester, 'hw-share-text');
    expect(spy.texts, hasLength(1));
    final (text, subject) = spy.texts.single;
    expect(subject, 'Prace pożarowo niebezpieczne — protokół');
    expect(text, contains('Miejsce pracy: Zbiornik T-101'));
    expect(text, contains('— brak pomiaru —'));
    expect(text, contains('rozporządzenie MSWiA'));

    await _tapKey(tester, 'hw-share-pdf-btn');
    expect(spy.pdfs, hasLength(1));
    expect(spy.pdfs.single.$1.location, 'Zbiornik T-101');
    expect(spy.pdfs.single.$2, isFalse);
  });

  testWidgets('po angielsku', (tester) async {
    await _pump(tester, language: AppLanguage.en);
    expect(find.text('Hot work permit'), findsOneWidget);
    await _tapKey(tester, 'hw-new');
    expect(find.text('Hot work record'), findsOneWidget);
    expect(await _status(tester),
        'No gas test result — enter the reading (% LEL) and its time.');
    final before = await _show(tester, 'hw-phase-before');
    expect(find.descendant(of: before, matching: find.text('BEFORE WORK STARTS')),
        findsOneWidget);
  });

  testWidgets('wąski ekran, czcionka 1,3: bez przepełnień', (tester) async {
    SharedPreferences.setMockInitialValues({
      HotWorkStore.key: jsonEncode(hotWorkPermitsToJson([
        _yesterday().copyWith(
            location: 'Rafineria — instalacja hydroodsiarczania oleju '
                'napędowego, estakada E-4, kołnierz F-12 po stronie ssawnej'),
      ])),
    });
    await _pump(tester, size: const Size(360, 12000), textScale: 1.3);
    expect(tester.takeException(), isNull);
    await _tapKey(tester, 'hw-open-0');
    expect(tester.takeException(), isNull);
    await _enter(tester, 'hw-meas-dgw', '12,5');
    await _tapKey(tester, 'hw-meas-add');
    expect(tester.takeException(), isNull);
    expect(await _status(tester), startsWith('STOP'));
    await _back(tester);
    await _tapKey(tester, 'hw-new');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawica)', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byKey(const ValueKey('hw-new'))).height,
        greaterThanOrEqualTo(kMinTapTarget));
    await _tapKey(tester, 'hw-new');
    for (final c in kHotWorkChecks) {
      final f = await _show(tester, 'hw-check-${c.id}');
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: c.id);
      if (c.naAllowed) {
        final na = find.byKey(ValueKey('hw-na-${c.id}'));
        expect(tester.getSize(na).height, greaterThanOrEqualTo(kMinTapTarget),
            reason: c.id);
        expect(tester.getSize(na).width, greaterThanOrEqualTo(kMinTapTarget),
            reason: c.id);
      }
    }
    for (final k in ['hw-meas-add', 'hw-date', 'hw-from', 'hw-meas-time']) {
      final f = await _show(tester, k);
      expect(tester.getSize(f).height, greaterThanOrEqualTo(kMinTapTarget),
          reason: k);
    }
  });

  testWidgets('zaległy pomiar 0 % po 15 % — nadal STOP i ostrzeżenie',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 10, 30);
    await _pump(tester, now: () => clock);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);
    await _enter(tester, 'hw-meas-dgw', '15');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('STOP'));

    // Pomiar wpisany z chwilą wcześniejszą niż ostatni (tu: zegar 09:00 —
    // ta sama ścieżka co ręcznie wybrana godzina wstecz).
    clock = DateTime(2026, 10, 17, 9, 0);
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(find.byKey(const ValueKey('hw-meas-backdated')), findsOneWidget);
    expect(await _status(tester), startsWith('STOP'));
    // Lista w kolejności czasu: 09:00 nad 10:30.
    final row0 = await _show(tester, 'hw-meas-0');
    expect(
        find.descendant(of: row0, matching: find.textContaining('09:00')),
        findsOneWidget);
  });

  testWidgets('próg powyżej 10 % DGW — błąd pola i brak zielonego',
      (tester) async {
    await _pump(tester);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('Stanowisko przygotowane'));
    await _enter(tester, 'hw-limit', '100');
    expect(
        find.text('Wpisz 0–10 — przepis nie pozwala na więcej niż 10 % DGW'),
        findsOneWidget);
    expect(await _status(tester), isNot(startsWith('Stanowisko przygotowane')));
  });

  test('uszkodzona historia: kopia surowego zapisu przed nadpisaniem',
      () async {
    SharedPreferences.setMockInitialValues({HotWorkStore.key: '[{"id": "x"'});
    const store = HotWorkStore();
    expect(await store.load(), isEmpty);
    await store.upsert(_yesterday());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HotWorkStore.corruptBackupKey), '[{"id": "x"');
    expect((await store.load()).single.id, 'old');
  });

  testWidgets('pomiar starszy niż 30 min i protokół z wczoraj — bez zieleni',
      (tester) async {
    var clock = DateTime(2026, 10, 17, 7, 30);
    await _pump(tester, now: () => clock);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('Stanowisko przygotowane'));

    // 31 min później, bez dotykania ekranu — stan przelicza się sam.
    clock = DateTime(2026, 10, 17, 8, 1);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(await _status(tester),
        'Pomiar nieaktualny (z 07:30, ważny 30 min) — zmierz ponownie.');
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
    await _back(tester);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hw-item-status-0')))
            .data,
        'Pomiar nieaktualny');

    // Następny dzień — protokół nieaktualny, nawet ze świeżym pomiarem.
    clock = DateTime(2026, 10, 18, 7, 0);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hw-item-status-0')))
            .data,
        'Nieaktualne');
    await _tapKey(tester, 'hw-open-0');
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester),
        startsWith('Protokół z dnia 2026-10-17 — nieaktualny'));
    expect(find.byKey(const ValueKey('hw-old-notice')), findsOneWidget);
    final row = await _show(tester, 'hw-meas-1');
    expect(
        find.descendant(
            of: row, matching: find.textContaining('2026-10-18 07:00')),
        findsOneWidget);
  });

  testWidgets('ręczna godzina: z przyszłości odrzucona, z wczoraj po '
      'potwierdzeniu', (tester) async {
    var clock = DateTime(2026, 10, 17, 14, 0);
    TimeOfDay? picked;
    await _pump(tester, now: () => clock, pickTime: () => picked);
    await _tapKey(tester, 'hw-new');
    await _tickAllBefore(tester);

    picked = const TimeOfDay(hour: 14, minute: 5);
    await _tapKey(tester, 'hw-meas-time');
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(find.byKey(const ValueKey('hw-meas-future')), findsOneWidget);
    await _show(tester, 'hw-meas-empty');

    // Zaległy pomiar ponad próg wpisany po pomiarze z późniejszą godziną —
    // STOP (wpis późniejszy niż decydujący).
    picked = const TimeOfDay(hour: 13, minute: 58);
    await _tapKey(tester, 'hw-meas-time');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester), startsWith('Stanowisko przygotowane'));
    clock = DateTime(2026, 10, 17, 14, 3);
    picked = const TimeOfDay(hour: 13, minute: 55);
    await _tapKey(tester, 'hw-meas-time');
    await _enter(tester, 'hw-meas-dgw', '15');
    await _tapKey(tester, 'hw-meas-add');
    expect(await _status(tester),
        startsWith('STOP — pomiar 15 % DGW wpisany po pomiarze z 13:58'));

    // Po północy godzina 23:50 to wczoraj — tylko po potwierdzeniu.
    clock = DateTime(2026, 10, 18, 0, 12);
    picked = const TimeOfDay(hour: 23, minute: 50);
    await _tapKey(tester, 'hw-meas-time');
    await _enter(tester, 'hw-meas-dgw', '0');
    await _tapKey(tester, 'hw-meas-add');
    expect(find.text('Pomiar wczoraj?'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect((await const HotWorkStore().load()).single.measurements,
        hasLength(2));
    await _tapKey(tester, 'hw-meas-add');
    await tester.tap(find.byKey(const ValueKey('hw-yesterday-confirm')));
    await tester.pumpAndSettle();
    final saved = (await const HotWorkStore().load()).single.measurements;
    expect(saved, hasLength(3));
    expect(saved.map((m) => m.enteredAt), everyElement(isNotNull));
  });

  testWidgets('uszkodzony i przyszły pomiar w zapisie: baner, kopia surowego '
      'zapisu', (tester) async {
    final json = _yesterday().toJson();
    json['measurements'] = [
      ...(json['measurements'] as List),
      {'time': '07:10', 'dgw': -1},
      {
        'time': '09:00',
        'at': DateTime(2030, 1, 1).millisecondsSinceEpoch,
        'dgw': 0,
      },
    ];
    final raw = jsonEncode([json]);
    SharedPreferences.setMockInitialValues({HotWorkStore.key: raw});
    await _pump(tester);
    await _show(tester, 'hw-load-damaged');
    expect(find.textContaining('pominięto 0 protokołów i 2 pomiarów'),
        findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(HotWorkStore.corruptBackupKey), raw);
    await _tapKey(tester, 'hw-open-0');
    await _show(tester, 'hw-damaged-notice');
  });

  testWidgets('historia: ostrzeżenie od 180 protokołów, przy 200 nowy odrzucony',
      (tester) async {
    List<HotWorkPermit> many(int n) => [
          for (var i = 0; i < n; i++)
            HotWorkPermit.fromJson({..._yesterday().toJson(), 'id': 'p$i'})!,
        ];
    SharedPreferences.setMockInitialValues({
      HotWorkStore.key:
          jsonEncode(hotWorkPermitsToJson(many(HotWorkStore.warnAt))),
    });
    await _pump(tester);
    await _show(tester, 'hw-store-warn');
    expect(find.textContaining('Historia: 180/200'), findsOneWidget);

    SharedPreferences.setMockInitialValues({
      HotWorkStore.key:
          jsonEncode(hotWorkPermitsToJson(many(HotWorkStore.maxEntries))),
    });
    await tester.pumpWidget(const SizedBox());
    await _pump(tester);
    await _tapKey(tester, 'hw-new');
    expect(find.byKey(const ValueKey('hw-store-full')), findsOneWidget);
    expect(find.text('Protokół prac pożarowych'), findsNothing);
  });

  test('pełna historia: zmiana zapisanego działa, nowy odrzucony, nic nie '
      'wypada', () async {
    SharedPreferences.setMockInitialValues({
      HotWorkStore.key: jsonEncode(hotWorkPermitsToJson([
        for (var i = 0; i < HotWorkStore.maxEntries; i++)
          HotWorkPermit.fromJson(
              {..._yesterday().toJson(), 'id': 'p$i', 'date': '2020-01-01'})!,
      ])),
    });
    const store = HotWorkStore();
    final first = (await store.load()).first;
    await store.upsert(first.copyWith(notes: 'zmiana'));
    expect((await store.load()).firstWhere((p) => p.id == first.id).notes,
        'zmiana');
    await expectLater(
        store.upsert(HotWorkPermit.fromJson(
            {..._yesterday().toJson(), 'id': 'nowy'})!),
        throwsA(isA<HotWorkStoreFull>()));
    final ids = (await store.load()).map((p) => p.id).toSet();
    expect(ids, hasLength(HotWorkStore.maxEntries));
    expect(ids, isNot(contains('nowy')));
  });
}

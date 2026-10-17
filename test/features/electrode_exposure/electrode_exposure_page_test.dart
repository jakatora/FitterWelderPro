// Elektrody zasadowe na ekranie: dodanie partii i odliczanie, przesunięcie
// zegara do „przekroczony”, akcje (piecyk, wyjęte ponownie, suszenie,
// złom), dziennik z filtrem i udostępnianiem, przypomnienia na atrapie
// platformy, wersja EN, wąski ekran z większą czcionką, cele ≥ 48 dp.
//
// Zegar wstrzykiwany: E7018 wyjęte 07:00 → limit 4 h (AWS D1.1 Tab. 7.1)
// → koniec 11:00, ostrzeżenie od 10:30.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/domain/qualification/reminder_plan.dart';
import 'package:cut_list_app/domain/welding/electrode_exposure.dart';
import 'package:cut_list_app/features/electrode_exposure/electrode_exposure_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/qualification_reminders.dart';

class _FakePlatform implements ReminderPlatform {
  @override
  bool get supported => true;
  int permissionRequests = 0;
  final List<List<DateTime>> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> schedule(List<PlannedReminder> reminders) async {
    scheduled.add([for (final r in reminders) r.fireAt]);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async => cancelled.addAll(ids);
}

class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

DateTime at(int h, [int m = 0, int day = 17]) => DateTime(2026, 10, day, h, m);

ElectrodeBatch _seed(String id,
        {ElectrodeClass c = ElectrodeClass.e7018, DateTime? out}) =>
    ElectrodeBatch.takenOut(
      id: id,
      electrode: c,
      at: out ?? at(7),
      diameterMm: 3.2,
      quantity: '40 szt.',
      location: 'hala B',
    );

String _remaining(WidgetTester tester, String id) => tester
    .widget<Text>(
        find.byKey(ValueKey('electrode-remaining-$id'), skipOffstage: false))
    .data!;

Finder _state(String id, ExposureState s) =>
    find.byKey(ValueKey('electrode-state-$id-${s.name}'), skipOffstage: false);

void main() {
  late _Clock clock;
  late _FakePlatform platform;
  late QualificationReminders reminders;

  setUp(() {
    clock = _Clock(at(7));
    platform = _FakePlatform();
    reminders = QualificationReminders(
      platform: platform,
      enabledKey: 'electrode_reminders_enabled_v1',
      idsKey: 'electrode_reminder_ids_v1',
    );
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seed(List<ElectrodeBatch> batches,
      {bool remindersOn = false}) async {
    SharedPreferences.setMockInitialValues({
      kElectrodeBatchesPrefsKey: encodeBatches(batches),
      if (remindersOn) 'electrode_reminders_enabled_v1': true,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    AppLanguage lang = AppLanguage.pl,
    double textScale = 1.0,
    Size logical = const Size(400, 860),
    ElectrodeShareText? shareText,
    ElectrodeSharePdf? sharePdf,
  }) async {
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(lang),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ElectrodeExposurePage(
          now: clock.call,
          reminders: reminders,
          shareText: shareText,
          sharePdf: sharePdf,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Przesuwa zegar i czeka na tyknięcie licznika na ekranie.
  Future<void> advance(WidgetTester tester, DateTime to) async {
    clock.now = to;
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    // Przewijamy tylko, gdy element nie mieści się na ekranie (także gdy
    // leży w buforze listy — finder domyślny go wtedy nie widzi), i to na
    // środek, żeby nie trafić pod przycisk pływający.
    final element =
        tester.element(find.byKey(ValueKey(key), skipOffstage: false));
    final box = element.renderObject! as RenderBox;
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    // Bez paska aplikacji z zakładkami u góry i przycisku pływającego u dołu.
    final safe = Rect.fromLTRB(0, 110, size.width, size.height - 100);
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!safe.contains(rect.topLeft) ||
        !safe.contains(rect.bottomRight - const Offset(1, 1))) {
      await Scrollable.ensureVisible(element, alignment: 0.5);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('dodanie partii → odliczanie na żywo i zapis', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('electrode-empty')), findsOneWidget);

    await tapKey(tester, 'electrode-add');
    expect(find.text('Wyjąłem elektrody'), findsWidgets);
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('electrode-time'))).data,
        'dziś 07:00');
    // Klasa z tabeli: E8018-X → 2 h, potem z powrotem E7018 → 4 h.
    await tapKey(tester, 'electrode-class-e8018X');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('electrode-limit')))
            .controller!
            .text,
        '2');
    // EN z opakowania próżniowego: 8 h wg producenta, 2 suszenia.
    await tapKey(tester, 'electrode-class-enIso2560B');
    await tapKey(tester, 'electrode-source-hermeticPack');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('electrode-limit')))
            .controller!
            .text,
        '8');
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('electrode-max-redries')))
            .controller!
            .text,
        '2');
    expect(find.textContaining('SAHARA ReadyPack 8 h'), findsOneWidget);
    // AWS z opakowania próżniowego: dalej tabela D1.1 (4 h) i podpowiedź H4R.
    await tapKey(tester, 'electrode-class-e7018');
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('electrode-limit')))
            .controller!
            .text,
        '4');
    expect(
        find.textContaining('wybierz „E7018 H4R / H8R” (9 h)'), findsOneWidget);
    await tapKey(tester, 'electrode-source-oven');
    await tester.enterText(
        find.byKey(const ValueKey('electrode-qty')), '40 szt.');
    await tester.enterText(
        find.byKey(const ValueKey('electrode-location')), 'hala B');
    await tapKey(tester, 'electrode-save');

    final id = 'b${at(7).millisecondsSinceEpoch}';
    expect(find.byKey(ValueKey('electrode-card-$id')), findsOneWidget);
    expect(find.text('E7018 · Ø3,2 · 40 szt.'), findsOneWidget);
    expect(_remaining(tester, id), 'zostało 4 h 00 min');
    expect(_state(id, ExposureState.ok), findsOneWidget);

    await advance(tester, at(8, 15));
    expect(_remaining(tester, id), 'zostało 2 h 45 min');

    final prefs = await SharedPreferences.getInstance();
    final saved = decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey));
    expect(saved.single.id, id);
    expect(saved.single.location, 'hala B');
    expect(saved.single.limitMinutes, 240);
  });

  testWidgets('przesunięcie zegara: OK → kończy się → przekroczony',
      (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(10);
    await pump(tester);
    expect(_state('b1', ExposureState.ok), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'zostało 1 h 00 min');

    await advance(tester, at(10, 45));
    expect(_state('b1', ExposureState.endingSoon), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'zostało 15 min');

    await advance(tester, at(11, 1));
    expect(_state('b1', ExposureState.exceeded), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'PRZEKROCZONO o 1 min');
    expect(find.textContaining('Do ponownego suszenia: 260–430 °C'),
        findsOneWidget);
    expect(find.textContaining('suszenie nr 1 z 1'), findsOneWidget);
    // Po przekroczeniu: suszenie albo złom — „Do piecyka” znika.
    expect(find.byKey(const ValueKey('electrode-redry-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('electrode-scrap-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('electrode-oven-b1')), findsNothing);
  });

  testWidgets('akcje: piecyk, reset po 4 h, suszenie, limit suszeń, złom',
      (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(9);
    await pump(tester);

    await tapKey(tester, 'electrode-oven-b1');
    expect(_state('b1', ExposureState.inOven), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'W piecyku od 09:00');
    expect(find.textContaining('jeszcze 4 h 00 min', skipOffstage: false),
        findsOneWidget);

    await advance(tester, at(13));
    await tapKey(tester, 'electrode-out-again-b1');
    expect(find.textContaining('Limit od nowa'), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'zostało 4 h 00 min');

    await advance(tester, at(17, 30));
    expect(_state('b1', ExposureState.exceeded), findsOneWidget);
    await tapKey(tester, 'electrode-redry-b1');
    expect(_state('b1', ExposureState.ok), findsOneWidget);
    expect(find.textContaining('suszenia 1/1', skipOffstage: false),
        findsOneWidget);

    await advance(tester, at(22));
    expect(
        find.textContaining('Limit suszeń wyczerpany (1/1) — na złom',
            skipOffstage: false),
        findsOneWidget);
    await tapKey(tester, 'electrode-redry-b1');
    expect(find.text('Limit suszeń wyczerpany'), findsOneWidget);
    await tapKey(tester, 'electrode-redry-cancel');
    expect(find.textContaining('suszenia 1/1', skipOffstage: false),
        findsOneWidget);

    await tapKey(tester, 'electrode-scrap-b1');
    expect(find.byKey(const ValueKey('electrode-card-b1')), findsNothing);
    expect(find.text('Partia na złom.'), findsOneWidget);

    await tapKey(tester, 'electrode-tab-log');
    final log = find.byKey(const ValueKey('electrode-log-b1'));
    expect(log, findsOneWidget);
    for (final line in [
      'Wyjęte z piecyka',
      'Do piecyka (na powietrzu 2 h 00 min)',
      'Wyjęte ponownie — limit od nowa (min. 4 h w piecyku)',
      'Ponownie wysuszone (nr 1 z 1), wcześniej na powietrzu 4 h 30 min',
      'Złom (na powietrzu 4 h 30 min)',
    ]) {
      expect(
          find.descendant(of: log, matching: find.text(line)), findsOneWidget,
          reason: line);
    }
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('wyjęte z piecyka po < 4 h — licznik liczy dalej',
      (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(9);
    await pump(tester);
    await tapKey(tester, 'electrode-oven-b1');
    await advance(tester, at(10));
    await tapKey(tester, 'electrode-out-again-b1');
    expect(find.textContaining('licznik liczy dalej od 2 h 00 min'),
        findsOneWidget);
    expect(_remaining(tester, 'b1'), 'zostało 2 h 00 min');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('zmiana limitu na ostrzejszy z WPS', (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(9);
    await pump(tester);
    await tapKey(tester, 'electrode-more-b1');
    await tester.tap(find.text('Zmień limit / suszenia'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('electrode-limit-edit')), '1,5');
    await tester.pump();
    await tapKey(tester, 'electrode-limit-save');
    expect(_state('b1', ExposureState.exceeded), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'PRZEKROCZONO o 30 min');
  });

  testWidgets('dziennik: filtr dziś / 7 dni / wszystko i udostępnianie',
      (tester) async {
    final today = _seed('dzis').close(at(9), BatchClosure.consumed);
    final threeDays = _seed('trzy', out: at(7, 0, 14))
        .close(at(9, 0, 14), BatchClosure.scrapped);
    final old = _seed('stara', out: DateTime(2026, 9, 1, 7))
        .close(DateTime(2026, 9, 1, 9), BatchClosure.consumed);
    await seed([today, threeDays, old]);
    clock.now = at(12);
    String? sharedText;
    (List<ElectrodeBatch>, LogRange, DateTime)? sharedPdf;
    await pump(
      tester,
      shareText: (t) async => sharedText = t,
      sharePdf: (l, r, n) async => sharedPdf = (l, r, n),
    );
    await tapKey(tester, 'electrode-tab-log');

    Finder card(String id) => find.byKey(ValueKey('electrode-log-$id'));
    expect(card('dzis'), findsOneWidget);
    expect(card('trzy'), findsNothing);

    await tapKey(tester, 'electrode-range-week');
    expect(card('trzy'), findsOneWidget);
    expect(card('stara'), findsNothing);

    await tapKey(tester, 'electrode-range-all');
    expect(card('stara'), findsOneWidget);

    await tapKey(tester, 'electrode-share-text');
    expect(sharedText, contains('DZIENNIK ELEKTROD ZASADOWYCH'));
    expect(sharedText, contains('Zakres: wszystko · partie: 3'));
    expect(sharedText,
        contains('2026-10-14 09:00  Złom (na powietrzu 2 h 00 min)'));

    await tapKey(tester, 'electrode-range-today');
    await tapKey(tester, 'electrode-share-pdf');
    expect(sharedPdf!.$1.map((b) => b.id), ['dzis']);
    expect(sharedPdf!.$2, LogRange.today);
    expect(sharedPdf!.$3, at(12));
  });

  testWidgets('przypomnienia: plan po każdej zmianie partii', (tester) async {
    await seed([_seed('b1')], remindersOn: true);
    clock.now = at(8);
    await pump(tester);
    // Po otwarciu: 30 min przed końcem i w chwili końca.
    expect(platform.scheduled.last, [at(10, 30), at(11)]);

    await tapKey(tester, 'electrode-oven-b1');
    expect(platform.scheduled.last, isEmpty, reason: 'w piecyku nic nie gra');
    expect(platform.cancelled, hasLength(2));

    await advance(tester, at(8, 30));
    await tapKey(tester, 'electrode-out-again-b1');
    // Krócej niż 4 h w piecyku: zostały 3 h → koniec 11:30.
    expect(platform.scheduled.last, [at(11), at(11, 30)]);

    await tapKey(tester, 'electrode-more-b1');
    await tester.tap(find.text('Usuń z dziennika'));
    await tester.pumpAndSettle();
    expect(platform.scheduled.last, isEmpty, reason: 'usunięta partia');
    expect(platform.permissionRequests, 0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('przełącznik przypomnień pyta o zgodę i planuje', (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(8);
    await pump(tester);
    expect(platform.scheduled, isEmpty);
    await tapKey(tester, 'electrode-reminders');
    expect(platform.permissionRequests, 1);
    expect(platform.scheduled.last, [at(10, 30), at(11)]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('electrode_reminders_enabled_v1'), isTrue);
  });

  testWidgets('wersja EN', (tester) async {
    await seed([_seed('b1')]);
    clock.now = at(10, 45);
    await pump(tester, lang: AppLanguage.en);
    expect(find.text('Low-hydrogen electrodes'), findsOneWidget);
    expect(find.text('Took electrodes out'), findsOneWidget);
    expect(_remaining(tester, 'b1'), '15 min left');
    expect(find.text('Exposed — ending soon'), findsOneWidget);
    expect(find.text('Back to oven'), findsOneWidget);
    await tapKey(tester, 'electrode-tab-log');
    expect(find.text('QC log'), findsOneWidget);
    expect(find.text('Taken out of the oven'), findsOneWidget);
  });

  testWidgets('wąski ekran 320×640, tekst ×1,3 — bez overflow (PL i EN)',
      (tester) async {
    for (final lang in AppLanguage.values) {
      final over = _seed('przekr', c: ElectrodeClass.e8018X)
          .redried(at(7, 10))
          .redried(at(7, 20));
      final oven = _seed('piecyk').returnToOven(at(8));
      final vac = ElectrodeBatch.takenOut(
        id: 'vac',
        electrode: ElectrodeClass.enIso18275E62,
        source: ElectrodeSource.hermeticPack,
        at: at(9),
        quantity: 'pół paczki, rurociąg technologiczny',
        location: 'estakada E-12, poziom +14,5 m',
      );
      await seed([over, oven, vac, _seed('ok')]);
      clock.now = at(10);
      await pump(tester,
          lang: lang, textScale: 1.3, logical: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byKey(const ValueKey('electrode-active-list')),
          const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tapKey(tester, 'electrode-tab-log');
      await tester.drag(find.byKey(const ValueKey('electrode-log-list')),
          const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tapKey(tester, 'electrode-add');
      for (final c in ElectrodeClass.values) {
        await tapKey(tester, 'electrode-class-${c.name}');
      }
      await tapKey(tester, 'electrode-source-hermeticPack');
      await tester.drag(find.byKey(const ValueKey('electrode-form-list')),
          const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }
  });

  testWidgets('cele dotyku ≥ 48 dp (rękawice)', (tester) async {
    await seed([
      _seed('ok'),
      _seed('piecyk').returnToOven(at(8)),
      _seed('przekr', c: ElectrodeClass.e8018X),
    ]);
    clock.now = at(10);
    await pump(tester);

    void checkAll() {
      final targets = find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> &&
            k.value.startsWith('electrode-') &&
            (w is ButtonStyleButton ||
                w is ChoiceChip ||
                w is FloatingActionButton ||
                w is PopupMenuButton ||
                w is SwitchListTile);
      });
      expect(targets, findsWidgets);
      for (final e in targets.evaluate()) {
        final size = tester.getSize(find.byWidget(e.widget));
        expect(size.height, greaterThanOrEqualTo(48),
            reason: '${e.widget.key} wysokość ${size.height}');
        expect(size.width, greaterThanOrEqualTo(48),
            reason: '${e.widget.key} szerokość ${size.width}');
      }
    }

    checkAll();
    await tapKey(tester, 'electrode-tab-log');
    checkAll();
    await tapKey(tester, 'electrode-add');
    checkAll();
  });

  // ── Regresje z przeglądu kodu (A1, A3–A6) ─────────────────────────────

  TextButton saveButton(WidgetTester tester) => tester
      .widget<TextButton>(find.byKey(const ValueKey('electrode-limit-save')));

  testWidgets('A1: przekroczonej partii nie da się ożywić podniesieniem limitu',
      (tester) async {
    // E8018-X: 2 h → o 09:30 przekroczona o 30 min.
    await seed([_seed('b1', c: ElectrodeClass.e8018X)]);
    clock.now = at(9, 30);
    await pump(tester);
    expect(_state('b1', ExposureState.exceeded), findsOneWidget);

    await tapKey(tester, 'electrode-more-b1');
    await tester.tap(find.text('Zmień limit / suszenia'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('electrode-limit-locked')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('electrode-limit-edit')), '168');
    await tester.pump();
    expect(find.textContaining('partia przekroczona'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    // Obniżyć wolno — partia zostaje przekroczona, wpis to odnotowuje.
    await tester.enterText(
        find.byKey(const ValueKey('electrode-limit-edit')), '1');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);
    await tapKey(tester, 'electrode-limit-save');
    expect(_state('b1', ExposureState.exceeded), findsOneWidget);
    expect(_remaining(tester, 'b1'), 'PRZEKROCZONO o 1 h 30 min');
    // Ani piecyka, ani „OK” — tylko suszenie albo złom.
    expect(find.byKey(const ValueKey('electrode-oven-b1')), findsNothing);

    await tapKey(tester, 'electrode-tab-log');
    expect(
        find.text('Zmieniono limit na 1 h 00 min (partia była przekroczona)'),
        findsOneWidget);
  });

  testWidgets('A3: „Cofnij” przywraca tylko jedną partię', (tester) async {
    await seed([_seed('a'), _seed('b')]);
    clock.now = at(9);
    await pump(tester);

    await tapKey(tester, 'electrode-scrap-a');
    expect(find.byKey(const ValueKey('electrode-card-a')), findsNothing);
    // W międzyczasie inna partia idzie do piecyka (snackbar „Cofnij” A
    // dalej wisi).
    await tapKey(tester, 'electrode-oven-b');
    expect(_state('b', ExposureState.inOven), findsOneWidget);

    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(_state('a', ExposureState.ok), findsOneWidget);
    expect(_state('b', ExposureState.inOven), findsOneWidget,
        reason: 'cofnięcie A nie rusza B');
    final prefs = await SharedPreferences.getInstance();
    final saved = decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey));
    expect(saved.firstWhere((x) => x.id == 'a').isClosed, isFalse);
    expect(saved.firstWhere((x) => x.id == 'b').isInOven, isTrue);
  });

  testWidgets('A3: „Cofnij” po wyjściu z ekranu — bez setState po dispose',
      (tester) async {
    await seed([_seed('a'), _seed('b')]);
    clock.now = at(9);
    tester.view.physicalSize = const Size(1200, 2580);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ElectrodeExposurePage(
                        now: clock.call, reminders: reminders))),
                child: const Text('otwórz'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('otwórz'));
    await tester.pumpAndSettle();

    await tapKey(tester, 'electrode-scrap-a');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ElectrodeExposurePage), findsNothing);

    // Snackbar żyje dalej w ScaffoldMessengerze aplikacji.
    await tester.tap(find.text('Cofnij'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final prefs = await SharedPreferences.getInstance();
    final saved = decodeBatches(prefs.getString(kElectrodeBatchesPrefsKey));
    expect(saved.map((x) => x.id), ['a', 'b']);
    expect(saved.firstWhere((x) => x.id == 'a').isClosed, isFalse);
  });

  testWidgets(
      'A4/A5: niespójny zapis i nieznane zdarzenie nie wywalają '
      'ekranu, kopia zostaje', (tester) async {
    final open = _seed('bez-stanu').toJson()..remove('start');
    final withUnknown = _seed('nowsza').toJson();
    withUnknown['ev'] = [
      ...(withUnknown['ev']! as List),
      {'k': 'zdarzenieZNowszejWersji', 'at': at(8).millisecondsSinceEpoch},
    ];
    final raw = jsonEncode({
      'v': 1,
      'batches': [open, withUnknown]
    });
    SharedPreferences.setMockInitialValues({kElectrodeBatchesPrefsKey: raw});
    clock.now = at(10);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(
        find.byKey(const ValueKey('electrode-card-bez-stanu')), findsOneWidget);
    expect(_remaining(tester, 'bez-stanu'), 'zostało 1 h 00 min');
    expect(_remaining(tester, 'nowsza'), 'zostało 1 h 00 min');

    await tapKey(tester, 'electrode-tab-log');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('electrode-log-nowsza')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kElectrodeBatchesCorruptPrefsKey), raw);
  });

  testWidgets('A6: krótki limit — przypomnienie w połowie i nota o opóźnieniu',
      (tester) async {
    await seed([_seed('s', c: ElectrodeClass.e11018X)], remindersOn: true);
    clock.now = at(7, 5);
    await pump(tester);
    expect(platform.scheduled.last, [at(7, 15), at(7, 20), at(7, 30)]);
    expect(
        find.byKey(const ValueKey('electrode-reminder-note')), findsOneWidget);
    expect(find.textContaining('kilka minut później'), findsOneWidget);
  });
}

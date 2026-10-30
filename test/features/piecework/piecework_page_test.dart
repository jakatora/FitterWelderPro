// Ekran „Akord: ile zarobiłem": spoiny z dziennika (prawdziwa baza testowa
// przez DAO albo wstrzyknięte) → stawki → kwota z rozbiciem; zmiana okresu
// i spawacza; pominięte spoiny bez wymiaru; EN; 320×640 przy tekście 1,3;
// cele dotyku; udostępnianie przez wstrzyknięte funkcje; PDF.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/piecework/piecework.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/features/piecework/piecework_page.dart';
import 'package:cut_list_app/features/piecework/piecework_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/piecework_export.dart';
import 'package:cut_list_app/theme/app_theme.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

const String nb = ' ';

/// Środa 2026-10-14, po południu.
DateTime _clock() => DateTime(2026, 10, 14, 15, 30);

/// 45 zł/DI, nierdzewna +20%, 5G +10%, 6G +20%.
const PieceworkRates _rates = PieceworkRates(
  rateGrosze: 4500,
  stainlessBp: 2000,
  pos5gBp: 1000,
  pos6gBp: 2000,
);

WeldEntry _w(String id, String welder, String date,
        {String material = 'P235GH',
        String od = '60.3',
        String t = '3.91',
        String position = '',
        String? weldNo}) =>
    weld(id, welder: welder, date: date, material: material, weldNo: weldNo)
        .copyWith(od: od, t: t, position: position);

/// JK-12 w październiku: j1 2" 316L 6G (12 600 gr), j2 4" PH (19 800 gr),
/// j3 bez OD (pominięta). AB-03: a1 2" (9 000 gr). JK-12 we wrześniu: s1 6"
/// (27 000 gr).
List<WeldEntry> _welds() => [
      _w('j1', 'JK-12', '2026-10-14', material: '316L', position: '6G'),
      _w('j2', 'JK-12', '2026-10-13', od: '114.3', t: '6.02', position: 'PH'),
      _w('j3', 'JK-12', '2026-10-14', od: '', weldNo: 'W-15'),
      _w('a1', 'AB-03', '2026-10-14'),
      _w('s1', 'JK-12', '2026-09-10', od: '168.3'),
    ];

Future<void> _noText(String text, String subject) async {}
Future<void> _noPdf(PieceworkReport report, bool english) async {}

class _FailOnceRatesStore extends PieceworkRatesStore {
  bool failed = false;

  @override
  Future<void> save(PieceworkRates rates, {bool afterFailedRead = false}) {
    if (!failed) {
      failed = true;
      return Future<void>.error(StateError('odmowa zapisu'));
    }
    return super.save(rates, afterFailedRead: afterFailedRead);
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder,
    {bool visible = true}) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
    if ((finder.evaluate().isNotEmpty) == visible) return;
  }
  fail('Nie doczekano się zmiany stanu: $finder');
}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(800, 6000),
  double textScale = 1.0,
  Map<String, Object> prefs = const {},
  List<WeldEntry>? welds,
  String? identity = 'JK-12',
  int? hourlyMin,
  PieceworkShareText shareText = _noText,
  PieceworkSharePdf sharePdf = _noPdf,
  PieceworkRatesStore? store,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = welds == null
      ? PieceworkPage(
          clock: _clock,
          loadIdentity: () async => identity,
          loadHourlyMinimum: () async => hourlyMin,
          store: store,
          shareText: shareText,
          sharePdf: sharePdf,
        )
      : PieceworkPage(
          clock: _clock,
          loadWelds: () async => welds,
          loadIdentity: () async => identity,
          loadHourlyMinimum: () async => hourlyMin,
          store: store,
          shareText: shareText,
          sharePdf: sharePdf,
        );
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: page,
    ),
  ));
  if (welds == null) {
    for (var i = 0; i < 6; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  await tester.pumpAndSettle();
}

Map<String, Object> _saved(PieceworkRates r) =>
    {PieceworkRatesStore.key: r.encode()};

Finder _key(String k) => find.byKey(ValueKey(k));

Finder _total(String text) =>
    find.descendant(of: _key('piecework-total'), matching: find.text(text));

Finder _field(String key) =>
    find.descendant(of: _key(key), matching: find.byType(TextField));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

Future<void> _pickWelder(WidgetTester tester, String label) async {
  await _tap(tester, 'piecework-welder');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  testWidgets(
      'dziennik z bazy (DAO): naprawa R1 potrąca, spoina bez OD pominięta, '
      'kwota w groszach', (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      for (final t in [
        'weld_journal',
        'weld_journal_history',
        'weld_repairs',
        'weld_journal_projects',
      ]) {
        await db.delete(t);
      }
      final dao = WeldJournalDao();
      for (final w in _welds()) {
        await dao.insert(w, by: 'JK-12');
      }
      await dao.addRepair('j2',
          date: '2026-10-14', reason: 'brak przetopu', by: 'JK-12');
    });
    await _pump(tester,
        prefs: _saved(
            _rates.copyWith(rejectBp: 5000, repairPaid: true, repairBp: 2500)));

    // j1 12 600 + j2 (19 800 − 50% + 25%) = 12 600 + 14 850.
    expect(_total('274,50${nb}zł'), findsOneWidget);
    expect(
        find.descendant(
            of: _key('piecework-row-reject'),
            matching: find.text('−99,00${nb}zł')),
        findsOneWidget);
    expect(
        find.descendant(
            of: _key('piecework-row-repair'),
            matching: find.text('49,50${nb}zł')),
        findsOneWidget);
    expect(_key('piecework-skipped-j3'), findsOneWidget);
    expect(find.text('• W-15 · 2026-10-14 · L-12 · Blok 4'), findsOneWidget);
  });

  testWidgets(
      'stawki → wynik: wpisana stawka i dopłata liczą kwotę i się zapisują',
      (tester) async {
    await _pump(tester, welds: _welds());
    expect(_total('0,00${nb}zł'), findsOneWidget);
    expect(find.textContaining('Stawka wynosi 0'), findsOneWidget);

    await tester.enterText(_field('piecework-rate-di'), '45');
    await tester.pumpAndSettle();
    // j1 2 DI + j2 4 DI = 6 DI × 45 zł, bez dopłat.
    expect(_total('270,00${nb}zł'), findsOneWidget);
    expect(find.text('Podstawa: 6 DI × 45,00${nb}zł/DI'), findsOneWidget);

    await tester.enterText(_field('piecework-ss'), '20');
    await tester.pumpAndSettle();
    expect(_total('288,00${nb}zł'), findsOneWidget);
    await tester.enterText(_field('piecework-p6g'), '20');
    await tester.enterText(_field('piecework-p5g'), '10');
    await tester.pumpAndSettle();
    expect(_total('324,00${nb}zł'), findsOneWidget);

    await _waitFor(tester, _key('piecework-rates-saving'), visible: false);

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final saved =
        decodePieceworkRates(prefs.getString(PieceworkRatesStore.key));
    expect(saved.intact, isTrue);
    expect(saved.rates, _rates);

    // Tryb za spoinę: 45 zł/szt., spoina bez OD też płatna.
    await _tap(tester, 'piecework-mode-weld');
    await _waitFor(tester, _key('piecework-rates-saving'), visible: false);
    expect(_key('piecework-skipped'), findsNothing);
    // j1 4500 + 20% + 20%, j2 4500 + 10%, j3 4500.
    expect(_total('157,50${nb}zł'), findsOneWidget);
  });

  testWidgets('zmiana okresu: miesiąc → dziś → tydzień → poprzedni miesiąc',
      (tester) async {
    await _pump(tester, welds: _welds(), prefs: _saved(_rates));
    expect(_total('324,00${nb}zł'), findsOneWidget);
    expect(find.text('2026-10-01 – 2026-10-14 · JK-12'), findsOneWidget);

    await _tap(tester, 'piecework-period-today');
    expect(_total('126,00${nb}zł'), findsOneWidget);
    expect(find.text('2026-10-14 (śr) · JK-12'), findsOneWidget);

    await _tap(tester, 'piecework-period-week');
    expect(_total('324,00${nb}zł'), findsOneWidget);

    await _tap(tester, 'piecework-period-lastMonth');
    expect(_total('270,00${nb}zł'), findsOneWidget);
    expect(find.text('2026-09-01 – 2026-09-30 · JK-12'), findsOneWidget);
    expect(_key('piecework-skipped'), findsNothing);
  });

  testWidgets(
      'spoiny bez wymiaru widoczne jako pominięte, kwota ich nie zawiera',
      (tester) async {
    await _pump(tester, welds: _welds(), prefs: _saved(_rates));
    expect(_key('piecework-skipped'), findsOneWidget);
    expect(
        find.textContaining(
            'Pominięte — brak wymiaru (OD): 1 spoina. Kwota ich NIE zawiera.'),
        findsOneWidget);
    expect(find.text('• W-15 · 2026-10-14 · L-12 · Blok 4'), findsOneWidget);
    expect(_key('piecework-fix-journal'), findsOneWidget);
    // Kwota = j1 + j2, bez j3.
    expect(_total('324,00${nb}zł'), findsOneWidget);
    expect(
        find.descendant(
            of: _key('piecework-total'),
            matching: find.text('2 SPOINY · 6 DI')),
        findsOneWidget);
  });

  testWidgets(
      '„ja" z tożsamości spawacza; cała brygada; bez tożsamości brygada',
      (tester) async {
    await _pump(tester, welds: _welds(), prefs: _saved(_rates));
    expect(find.text('Ja (JK-12)'), findsOneWidget);
    expect(_total('324,00${nb}zł'), findsOneWidget);

    await _pickWelder(tester, 'Cała brygada (każda spoina raz)');
    // + a1 9000 gr.
    expect(_total('414,00${nb}zł'), findsOneWidget);
    await _pickWelder(tester, 'AB-03');
    expect(_total('90,00${nb}zł'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, welds: _welds(), prefs: _saved(_rates), identity: null);
    expect(find.text('Cała brygada (każda spoina raz)'), findsOneWidget);
    expect(_total('414,00${nb}zł'), findsOneWidget);
  });

  testWidgets('godziny i porównanie z „Ile brać za godzinę"', (tester) async {
    await _pump(tester,
        welds: _welds(), prefs: _saved(_rates), hourlyMin: 9500);
    expect(_key('piecework-hourly-compare'), findsNothing);
    expect(
        find.descendant(
            of: _key('piecework-per-day'),
            matching: find.text('162,00${nb}zł')),
        findsOneWidget);

    final hours = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('piecework-hours-')),
        matching: find.byType(TextField));
    await tester.enterText(hours, '4');
    await tester.pumpAndSettle();
    // 324 zł / 4 h = 81 zł/h.
    expect(
        find.descendant(
            of: _key('piecework-per-hour'),
            matching: find.text('81,00${nb}zł')),
        findsOneWidget);
    expect(
        find.text('Akord daje 81,00${nb}zł/h, a minimum z „Ile brać za '
            'godzinę" to 95,00${nb}zł/h — 14,00${nb}zł/h mniej.'),
        findsOneWidget);

    // Zmiana okresu czyści wpisane godziny.
    await _tap(tester, 'piecework-period-today');
    expect(_key('piecework-hourly-compare'), findsNothing);
  });

  testWidgets('spoina z datą w przyszłości: uwaga na ekranie, poza kwotą',
      (tester) async {
    await _pump(tester,
        welds: [..._welds(), _w('f1', 'JK-12', '2026-10-20')],
        prefs: _saved(_rates));
    expect(_total('324,00${nb}zł'), findsOneWidget);
    expect(
        find.text('1 spoina z datą po końcu okresu (w przyszłości) — poza tą '
            'kwotą. Sprawdź datę w dzienniku.'),
        findsOneWidget);
  });

  testWidgets('EN: texts and numbers in English', (tester) async {
    await _pump(tester,
        welds: _welds(), prefs: _saved(_rates), lang: AppLanguage.en);
    expect(find.text('Piecework: what I earned'), findsOneWidget);
    expect(find.text('EARNINGS'), findsOneWidget);
    expect(find.text('RATES'), findsOneWidget);
    expect(find.text('Me (JK-12)'), findsOneWidget);
    expect(find.text('Base: 6 DI × 45,00${nb}zł/DI'), findsOneWidget);
    expect(find.text('Surcharge: position 6G +20% (1 weld)'), findsOneWidget);
    expect(
        find.textContaining('Skipped — no size (OD): 1 weld. The amount does '
            'NOT include them.'),
        findsOneWidget);
    expect(find.text('Last month'), findsOneWidget);
    expect(find.textContaining('Ja ('), findsNothing);
  });

  for (final lang in AppLanguage.values) {
    testWidgets(
        '320×640 i tekst 1,3 (${lang.name}): cały ekran bez przepełnień',
        (tester) async {
      await _pump(
        tester,
        lang: lang,
        size: const Size(320, 640),
        textScale: 1.3,
        welds: [
          ..._welds(),
          _w('long', 'JK-12', '2026-10-14',
              od: '', weldNo: 'L-2026-0001-INLET-NORTH-SPOOL-12-W-0042'),
        ],
        hourlyMin: 9500,
        prefs: _saved(_rates.copyWith(
          wallRule: WallRule.mm,
          wallBp: 1500,
          otherMaterialBp: 3000,
          pos2gBp: 500,
          rejectBp: 5000,
          repairPaid: true,
          minDayGrosze: 9999999,
          hoursPerDay: 10,
        )),
      );
      expect(tester.takeException(), isNull);
      expect(_key('piecework-hourly-compare'), findsOneWidget);
      final list = find.descendant(
          of: _key('piecework-list'), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(_key('piecework-share-pdf'), 300,
          scrollable: list.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester,
        welds: _welds(),
        prefs:
            _saved(_rates.copyWith(wallRule: WallRule.mm, repairPaid: true)));
    for (final k in [
      ...PieceworkPeriod.values.map((p) => 'piecework-period-${p.name}'),
      'piecework-welder',
      'piecework-mode-di',
      'piecework-mode-weld',
      'piecework-wall-none',
      'piecework-wall-sch80',
      'piecework-wall-mm',
      'piecework-repair-paid',
      'piecework-fix-journal',
      'piecework-share-text',
      'piecework-share-pdf',
    ]) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('udostępnianie tekstem i PDF przez wstrzyknięte funkcje',
      (tester) async {
    String? text;
    String? subject;
    PieceworkReport? pdf;
    bool? pdfEn;
    var textFails = false;
    String? clip;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await _pump(
      tester,
      welds: _welds(),
      prefs: _saved(_rates),
      shareText: (t, s) async {
        if (textFails) throw PlatformException(code: 'no-share');
        text = t;
        subject = s;
      },
      sharePdf: (r, en) async {
        pdf = r;
        pdfEn = en;
      },
    );

    await _tap(tester, 'piecework-share-text');
    expect(text, startsWith('AKORD — ZAROBEK — 2026-10-01 – 2026-10-14\n'));
    expect(text, contains('Spawacz: JK-12'));
    expect(text, contains('RAZEM: 324,00${nb}zł'));
    expect(text, contains('• W-15 · 2026-10-14 · L-12 · Blok 4'));
    expect(subject, 'Akord — zarobek — 2026-10-01 – 2026-10-14');
    expect(clip, isNull);

    await _tap(tester, 'piecework-share-pdf');
    expect(pdfEn, isFalse);
    expect(pdf!.result.totalGrosze, 32400);
    expect(pdf!.result.skippedNoOd.single.id, 'j3');

    // Udostępnianie niedostępne → schowek i komunikat.
    textFails = true;
    await _tap(tester, 'piecework-share-text');
    expect(clip, text);
    expect(find.text('Skopiowano zestawienie.'), findsOneWidget);
  });

  testWidgets('uszkodzone stawki: komunikat, domyślne pola, kopia przy zmianie',
      (tester) async {
    await _pump(tester,
        welds: _welds(), prefs: {PieceworkRatesStore.key: '{"rate":"x"'});
    expect(_key('piecework-rates-damaged'), findsOneWidget);
    expect(_total('0,00${nb}zł'), findsOneWidget);
    await tester.enterText(_field('piecework-rate-di'), '45');
    await tester.pumpAndSettle();
    await _waitFor(tester, _key('piecework-rates-saving'), visible: false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PieceworkRatesStore.corruptKey), '{"rate":"x"');
    expect(
        decodePieceworkRates(prefs.getString(PieceworkRatesStore.key))
            .rates
            .rateGrosze,
        4500);
  });

  testWidgets('błąd zapisu stawek jest widoczny i można ponowić zapis',
      (tester) async {
    final store = _FailOnceRatesStore();
    await _pump(tester, welds: _welds(), store: store);
    await tester.enterText(_field('piecework-rate-di'), '45');
    await _waitFor(tester, _key('piecework-rates-save-failed'));
    expect(_total('270,00${nb}zł'), findsOneWidget);
    var prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(prefs.getString(PieceworkRatesStore.key), isNull);

    await _tap(tester, 'piecework-rates-retry');
    await _waitFor(tester, _key('piecework-rates-saving'), visible: false);
    expect(_key('piecework-rates-save-failed'), findsNothing);
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    expect(
        decodePieceworkRates(prefs.getString(PieceworkRatesStore.key))
            .rates
            .rateGrosze,
        4500);
  });

  test('PDF: „≈" przy przybliżonym DI w faktach i w tabeli spoin', () {
    final result = computePiecework(
      entries: [
        _w('x', 'JK-12', '2026-10-14', od: '57'),
        _w('y', 'JK-12', '2026-10-14'),
      ],
      rates: _rates,
      range: pieceworkRange(PieceworkPeriod.today, _clock()),
      welder: 'JK-12',
    );
    final report = PieceworkReport(result: result, generatedAt: _clock());
    expect(PieceworkExport.factRows(report, en: false),
        contains(('Spoiny', '2 · ≈ 4,24 DI')));
    expect(PieceworkExport.factRows(report, en: true),
        contains(('Welds', '2 · ≈ 4.24 DI')));
    expect(
        PieceworkExport.weldCells(result.lines.first, en: false)[3], '≈ 2,24');
    expect(PieceworkExport.weldCells(result.lines.last, en: false)[3], '2');
  });

  test('PDF zestawienia renderuje się (PL i EN), także pusty okres', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final rates =
        _rates.copyWith(minDayGrosze: 50000, rejectBp: 5000, repairPaid: true);
    final result = computePiecework(
      entries: _welds(),
      rates: rates,
      range: pieceworkRange(PieceworkPeriod.month, _clock()),
      welder: 'JK-12',
    );
    expect(result.skippedNoOd, hasLength(1));
    for (final en in [false, true]) {
      final doc = PieceworkExport.buildPdfDocument(
        report: PieceworkReport(
          result: result,
          hours: const PieceworkHours(16, PieceworkHoursSource.typed),
          hourlyMinGrosze: 9500,
          generatedAt: _clock(),
        ),
        en: en,
        font: font('Roboto-Regular.ttf'),
        boldFont: font('Roboto-Bold.ttf'),
      );
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
    final empty = PieceworkExport.buildPdfDocument(
      report: PieceworkReport(
        result: computePiecework(
            entries: const [],
            rates: const PieceworkRates(),
            range: pieceworkRange(PieceworkPeriod.today, _clock())),
        generatedAt: _clock(),
      ),
      en: false,
      font: font('Roboto-Regular.ttf'),
    );
    expect(String.fromCharCodes((await empty.save()).take(5)), '%PDF-');
  });
}

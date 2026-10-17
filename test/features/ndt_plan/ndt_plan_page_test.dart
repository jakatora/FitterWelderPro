// Ekran „Plan badań NDT": spoiny z dziennika (prawdziwa baza testowa przez
// DAO albo wstrzyknięte) → reguły → grupy, gotowość linii i lista do
// zlecenia; preset B31.3; uszkodzone reguły; EN; 320×640 przy tekście 1,3;
// cele dotyku; udostępnianie przez wstrzyknięte funkcje; PDF.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/ndt/ndt_plan.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/domain/weld_journal/weld_ndt.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_page.dart';
import 'package:cut_list_app/features/ndt_plan/ndt_plan_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/services/ndt_plan_export.dart';
import 'package:cut_list_app/theme/app_theme.dart';

import '../../support/test_database.dart';
import '../../support/weld_fixtures.dart';

const String nb = ' ';

DateTime _clock() => DateTime(2026, 10, 17, 9, 30);

final WeldNdt _vt = ndtOf(NdtScope.required, NdtResult.ok);
final WeldNdt _rt = ndtOf(NdtScope.selected, NdtResult.ok);

WeldEntry _w(String id,
        {String welder = 'JK-12',
        String line = 'L-12',
        String project = 'Blok 4',
        Map<NdtMethod, WeldNdt> ndt = const {}}) =>
    weld(id, project: project, line: line, welder: welder, ndt: ndt)
        .copyWith(jointType: WeldJointType.butt);

/// Blok 4 · L-12: JK-12 j1–j10 (j1 RT OK), AB-03 a1 (RT OK), a2; wszystkie
/// VT OK. L-14: JK-12 k1–k5 (k5 bez VT), u1 bez spawacza. Browar · L-1: b1.
List<WeldEntry> _welds() => [
      for (var i = 1; i <= 10; i++)
        _w('j$i', ndt: {NdtMethod.vt: _vt, if (i == 1) NdtMethod.rt: _rt}),
      _w('a1', welder: 'AB-03', ndt: {NdtMethod.vt: _vt, NdtMethod.rt: _rt}),
      _w('a2', welder: 'AB-03', ndt: {NdtMethod.vt: _vt}),
      for (var i = 1; i <= 4; i++)
        _w('k$i', line: 'L-14', ndt: {NdtMethod.vt: _vt}),
      _w('k5', line: 'L-14'),
      _w('u1', welder: '', line: 'L-14', ndt: {NdtMethod.vt: _vt}),
      _w('b1',
          welder: 'MN-03',
          line: 'L-1',
          project: 'Browar',
          ndt: {NdtMethod.vt: _vt}),
    ];

Map<String, Object> _saved(String preset, {String project = 'Blok 4'}) =>
    {NdtPlanStore.keyFor(project): NdtRuleSet.fromPreset(preset).encode()};

Future<void> _noText(String text, String subject) async {}
Future<void> _noPdf(NdtOrderReport report, bool english) async {}

Future<void> _pump(
  WidgetTester tester, {
  AppLanguage lang = AppLanguage.pl,
  Size size = const Size(800, 8000),
  double textScale = 1.0,
  Map<String, Object> prefs = const {},
  List<WeldEntry>? welds,
  Map<String, double?> targets = const {},
  NdtShareText shareText = _noText,
  NdtSharePdf sharePdf = _noPdf,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final page = welds == null
      ? NdtPlanPage(
          clock: _clock,
          shareText: shareText,
          sharePdf: sharePdf,
        )
      : NdtPlanPage(
          clock: _clock,
          loadWelds: () async => welds,
          loadTargets: () async => targets,
          loadLastProject: () async => '',
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

Finder _key(String k) => find.byKey(ValueKey(k));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

String _verdict(WidgetTester tester, String lineKey) =>
    tester.widget<Text>(_key('ndt-verdict-$lineKey')).data!;

const String _l12 = 'blok 4|l-12';
const String _l14 = 'blok 4|l-14';

void main() {
  useTestDatabase();

  testWidgets(
      'dziennik z bazy (DAO): naprawa czeka na badanie, linia niegotowa; '
      'reguły z zapisu', (tester) async {
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
      for (final w in _welds().where((w) => w.projectName == 'Blok 4')) {
        await dao.insert(w);
      }
      await dao.addRepair('a1', date: '2026-10-16', reason: 'pory');
    });
    await _pump(tester, prefs: _saved(NdtPreset.rt10vt100));

    // a1 po naprawie: RT i VT czekają na ponowne badanie.
    expect(_verdict(tester, _l12), 'Niegotowa do próby ciśnieniowej');
    expect(_key('ndt-blocker-$_l12-repairsAwaiting'), findsOneWidget);
    expect(find.text('• Naprawy czekają na ponowne badanie: 1'),
        findsOneWidget);
    expect(_key('ndt-ordered-RT-a1'), findsOneWidget);
    expect(find.text('Gotowe: 0 z 2 linii'), findsOneWidget);
  });

  testWidgets('reguły → wynik: bez reguł nic nie jest gotowe; dodana reguła '
      'liczy grupy i się zapisuje', (tester) async {
    await _pump(tester, welds: _welds());
    expect(_key('ndt-no-rules'), findsOneWidget);
    expect(_verdict(tester, _l12), 'Niegotowa do próby ciśnieniowej');
    expect(find.text('• Brak reguł badań — wybierz preset albo dodaj regułę'),
        findsNWidgets(2));

    // Nowa reguła: domyślnie RT 10 % BW, każdy spawacz, każda linia.
    await _tap(tester, 'ndt-rule-add');
    expect(_key('ndt-editor'), findsOneWidget);
    await _tap(tester, 'ndt-edit-save');
    expect(
        find.text('RT 10$nb% · BW · każdy spawacz osobno · każda linia osobno'),
        findsOneWidget);
    expect(_verdict(tester, _l12), 'Gotowa do próby ciśnieniowej');
    expect(find.text('RT 10$nb% BW · L-14 · JK-12'), findsOneWidget);
    expect(find.text('5 spoin · wymagane 1 · zbadane 0 · brakuje 1'),
        findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    final saved =
        decodeNdtRuleSet(prefs.getString(NdtPlanStore.keyFor('Blok 4')));
    expect(saved.intact, isTrue);
    expect(saved.set.rules.single.bp, 1000);

    // Zmiana: 150 % odrzucone (zapis zablokowany), 20 % przyjęte.
    final id = saved.set.rules.single.id;
    await _tap(tester, 'ndt-rule-edit-$id');
    await tester.enterText(_key('ndt-edit-pct'), '150');
    await tester.pumpAndSettle();
    expect(find.text('Od 0 do 100 %'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(_key('ndt-edit-save'))
            .onPressed,
        isNull);
    await tester.enterText(_key('ndt-edit-pct'), '20');
    await tester.pumpAndSettle();
    await _tap(tester, 'ndt-edit-save');
    // JK-12 na L-12: 10 × 20 % = 2, zbadana 1 → linia niegotowa.
    expect(find.text('10 spoin · wymagane 2 · zbadane 1 · brakuje 1'),
        findsOneWidget);
    expect(_verdict(tester, _l12), 'Niegotowa do próby ciśnieniowej');
  });

  testWidgets(
      'preset ASME B31.3: RT 5 % na spawacza (partia = projekt) + VT 100 %',
      (tester) async {
    await _pump(tester, welds: _welds());
    await _tap(tester, 'ndt-preset-${NdtPreset.b313}');
    expect(
        find.text('ASME B31.3 normal fluid service — RT 5 % losowo, '
            'każdy spawacz + VT 100 %'),
        findsOneWidget);
    expect(find.textContaining('§341.4.1(b)(1)'), findsOneWidget);
    expect(
        find.text(
            'RT 5$nb% · BW · każdy spawacz osobno · partia = projekt'),
        findsOneWidget);
    expect(
        find.text('VT 100$nb% · wszystkie spoiny (BW/FW/SW/BR) · spawacze '
            'razem · każda linia osobno'),
        findsOneWidget);
    expect(find.textContaining('§341.4.1(a)(3)'), findsOneWidget);
    // JK-12: 15 spoin w projekcie → 1 RT (j1), VT wszystkich — L-12 gotowa;
    // na L-14 k5 bez VT i u1 bez spawacza.
    expect(find.text('RT 5$nb% BW · cały projekt · JK-12'), findsWidgets);
    expect(_verdict(tester, _l12), 'Gotowa do próby ciśnieniowej');
    expect(_verdict(tester, _l14), 'Niegotowa do próby ciśnieniowej');
    expect(find.text('• Spoiny bez spawacza (nieprzypisane): 1'),
        findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(
        decodeNdtRuleSet(prefs.getString(NdtPlanStore.keyFor('Blok 4'))).set,
        NdtRuleSet.fromPreset(NdtPreset.b313));

    // Inny projekt ma własne reguły (jeszcze żadnych).
    await _tap(tester, 'ndt-project');
    await tester.tap(find.text('Browar').last);
    await tester.pumpAndSettle();
    expect(_key('ndt-no-rules'), findsOneWidget);
    expect(_verdict(tester, 'browar|l-1'), 'Niegotowa do próby ciśnieniowej');
  });

  testWidgets('gotowość linii: gotowa / niegotowa z powodami i grupami',
      (tester) async {
    await _pump(tester,
        welds: _welds(), prefs: _saved(NdtPreset.rt10vt100));
    expect(find.text('Gotowe: 1 z 2 linii'), findsOneWidget);
    expect(_verdict(tester, _l12), 'Gotowa do próby ciśnieniowej');
    expect(
        tester.widget<Text>(_key('ndt-line-numbers-$_l12')).data,
        '12 spoin · grupy kompletne 3/3 · brakuje 0');
    expect(_verdict(tester, _l14), 'Niegotowa do próby ciśnieniowej');
    expect(
        tester.widget<Text>(_key('ndt-line-numbers-$_l14')).data,
        '6 spoin · grupy kompletne 0/3 · brakuje 3');
    for (final b in ['unassigned', 'incompleteGroups', 'missing']) {
      expect(_key('ndt-blocker-$_l14-$b'), findsOneWidget, reason: b);
    }
    expect(find.text('• Grupy niekompletne: 3 z 3'), findsOneWidget);
    expect(find.text('nieprzypisane — brak spawacza'), findsOneWidget);
    expect(_key('ndt-issue-u1'), findsOneWidget);
    expect(find.text('• u1 · L-14 · bez spawacza · BW — bez spawacza'),
        findsOneWidget);
  });

  testWidgets('lista do zlecenia: powtarzalna, „losuj ponownie", zlecone',
      (tester) async {
    final welds = _welds();
    await _pump(tester, welds: welds, prefs: _saved(NdtPreset.rt10vt100));
    NdtPlan plan(int round) => computeNdtPlan(welds,
        rules: NdtRuleSet.fromPreset(NdtPreset.rt10vt100).rules,
        project: 'Blok 4',
        round: round);
    final pick0 = plan(0).toOrder[NdtMethod.rt]!.single.weld.id;
    final pick1 = plan(1).toOrder[NdtMethod.rt]!.single.weld.id;
    expect(find.text('RT — do zlecenia: 1 spoina'), findsOneWidget);
    expect(find.text('VT — do zlecenia: 1 spoina'), findsOneWidget);
    expect(_key('ndt-order-RT-$pick0'), findsOneWidget);
    expect(_key('ndt-order-VT-k5'), findsOneWidget);
    expect(find.text('   losowo 10$nb% · JK-12 · L-14'), findsOneWidget);

    await _tap(tester, 'ndt-reroll');
    expect(_key('ndt-order-RT-$pick1'), findsOneWidget);
    expect(find.text('Losuj ponownie (runda 2)'), findsOneWidget);
  });

  testWidgets('EN: texts in English', (tester) async {
    await _pump(tester,
        welds: _welds(),
        prefs: _saved(NdtPreset.rt10vt100),
        lang: AppLanguage.en,
        targets: {'blok 4': 10});
    expect(find.text('NDT plan'), findsOneWidget);
    expect(find.text('REQUIREMENTS'), findsOneWidget);
    expect(find.text('Ready: 1 of 2 lines'), findsOneWidget);
    expect(_verdict(tester, _l12), 'Ready for the pressure test');
    expect(_verdict(tester, _l14), 'Not ready for the pressure test');
    expect(find.text('• Welds with no welder (unassigned): 1'), findsOneWidget);
    expect(find.text('RT — to order: 1 weld'), findsOneWidget);
    expect(find.text('RT 10$nb% · BW · each welder · each line'),
        findsOneWidget);
    expect(find.textContaining('RT/UT target 10$nb%'), findsOneWidget);
    expect(find.textContaining('Gotowa'), findsNothing);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('320×640 i tekst 1,3 (${lang.name}): ekran i edytor reguły bez '
        'przepełnień', (tester) async {
      await _pump(
        tester,
        lang: lang,
        size: const Size(320, 640),
        textScale: 1.3,
        welds: [
          ..._welds(),
          _w('long', line: 'L-2026-0001-INLET-NORTH-SPOOL-12-HEADER-A')
              .copyWith(
                  weldNo: 'L-2026-0001-INLET-NORTH-SPOOL-12-W-0042',
                  isoDrawing: 'ISO-2026-0001-INLET-NORTH-SHEET-12-REV-C'),
        ],
        targets: {'blok 4': 12.5},
        prefs: {
          // Preset 10 % RT + 100 % VT i długa reguła z materiałem.
          NdtPlanStore.keyFor('Blok 4'): NdtRuleSet(rules: [
            ...NdtRuleSet.fromPreset(NdtPreset.rt10vt100).rules,
            const NdtRule(
              id: 'pt',
              method: NdtMethod.pt,
              bp: 1250,
              joints: [WeldJointType.socket, WeldJointType.fillet],
              material: '1.4404 / 316L / ASTM A312 TP316L',
              perLine: false,
            ),
          ]).encode(),
        },
      );
      expect(tester.takeException(), isNull);
      final list = find.descendant(
          of: _key('ndt-list'), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(_key('ndt-share-pdf'), 300,
          scrollable: list.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(_key('ndt-fix-journal'), 300,
          scrollable: list.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(_key('ndt-rule-edit-pt'), -300,
          scrollable: list.first);
      await _tap(tester, 'ndt-rule-edit-pt');
      expect(tester.takeException(), isNull);
      final sheet = find.descendant(
          of: _key('ndt-editor'), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(_key('ndt-edit-cancel'), 200,
          scrollable: sheet.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(_key('ndt-edit-cancel'));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('cele dotyku ≥ 48 dp', (tester) async {
    await _pump(tester,
        welds: _welds(), prefs: _saved(NdtPreset.rt10vt100));
    final ids = NdtRuleSet.fromPreset(NdtPreset.rt10vt100)
        .rules
        .map((r) => r.id);
    for (final k in [
      ...NdtPreset.values.map((p) => 'ndt-preset-$p'),
      'ndt-project',
      'ndt-journal',
      for (final id in ids) ...['ndt-rule-edit-$id', 'ndt-rule-delete-$id'],
      'ndt-rule-add',
      'ndt-reroll',
      'ndt-share-text',
      'ndt-share-pdf',
      'ndt-fix-journal',
    ]) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await _tap(tester, 'ndt-rule-add');
    for (final k in [
      ...NdtMethod.values.map((m) => 'ndt-edit-method-${m.code}'),
      ...WeldJointType.values.map((j) => 'ndt-edit-joint-$j'),
      'ndt-edit-per-welder',
      'ndt-edit-per-line',
      'ndt-edit-save',
      'ndt-edit-cancel',
    ]) {
      final s = tester.getSize(_key(k));
      expect(s.height, greaterThanOrEqualTo(kMinTapTarget), reason: k);
      expect(s.width, greaterThanOrEqualTo(kMinTapTarget), reason: k);
    }
  });

  testWidgets('udostępnianie tekstem i PDF przez wstrzyknięte funkcje',
      (tester) async {
    String? text;
    String? subject;
    NdtOrderReport? pdf;
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
      prefs: _saved(NdtPreset.rt10vt100),
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

    await _tap(tester, 'ndt-share-text');
    expect(text, startsWith('ZLECENIE BADAŃ NDT — Blok 4\n2026-10-17\n'));
    expect(text, contains('VT — do zlecenia: 1 spoina'));
    expect(text, contains('• k5 · L-14 · JK-12 · BW (100$nb% · L-14)'));
    expect(text, contains('Gotowe do próby ciśnieniowej: 1 z 2 linii'));
    expect(subject, 'Zlecenie badań NDT — Blok 4 — 2026-10-17');
    expect(clip, isNull);

    await _tap(tester, 'ndt-share-pdf');
    expect(pdfEn, isFalse);
    expect(pdf!.project, 'Blok 4');
    expect(pdf!.plan.readyLines, 1);
    expect(pdf!.plan.toOrderCount, 2);

    textFails = true;
    await _tap(tester, 'ndt-share-text');
    expect(clip, text);
    expect(find.text('Skopiowano zlecenie.'), findsOneWidget);
  });

  testWidgets('uszkodzone reguły: komunikat, nic nie jest gotowe, '
      'potwierdzenie zapisuje i robi kopię', (tester) async {
    const raw =
        '{"v":1,"rules":[{"id":"a","method":"RT","pct":10,"joints":["BW"]},'
        '{"id":"b","method":"VT","pct":"sto","joints":["BW"]}]}';
    await _pump(tester,
        welds: _welds(), prefs: {NdtPlanStore.keyFor('Blok 4'): raw});
    expect(_key('ndt-rules-damaged'), findsOneWidget);
    expect(find.textContaining('pominięto: 1'), findsOneWidget);
    expect(_verdict(tester, _l12), 'Niegotowa do próby ciśnieniowej');
    expect(_key('ndt-blocker-$_l12-rulesDamaged'), findsOneWidget);

    await _tap(tester, 'ndt-rules-confirm');
    expect(_key('ndt-rules-damaged'), findsNothing);
    expect(_verdict(tester, _l12), 'Gotowa do próby ciśnieniowej');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(NdtPlanStore.corruptKeyFor('Blok 4')), raw);
    expect(
        decodeNdtRuleSet(prefs.getString(NdtPlanStore.keyFor('Blok 4')))
            .intact,
        isTrue);
  });

  testWidgets('pusty dziennik: zaproszenie do dziennika', (tester) async {
    await _pump(tester, welds: const []);
    expect(_key('ndt-empty'), findsOneWidget);
    expect(_key('ndt-open-journal'), findsOneWidget);
  });

  test('PDF zlecenia renderuje się (PL i EN), także bez reguł', () async {
    pw.Font font(String f) => pw.Font.ttf(
        ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()));
    final plan = computeNdtPlan(_welds(),
        rules: NdtRuleSet.fromPreset(NdtPreset.rt10vt100).rules,
        project: 'Blok 4');
    for (final en in [false, true]) {
      final report = NdtOrderReport(
          project: 'Blok 4', plan: plan, generatedAt: _clock());
      final doc = NdtPlanExport.buildPdfDocument(
        report: report,
        en: en,
        font: font('Roboto-Regular.ttf'),
        boldFont: font('Roboto-Bold.ttf'),
      );
      final bytes = await doc.save();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final first = plan.toOrder[NdtMethod.rt]!.single;
      expect(NdtPlanExport.orderCells(1, first, en: en)[6], 'RT');
    }
    final empty = NdtPlanExport.buildPdfDocument(
      report: NdtOrderReport(
        project: '',
        plan: computeNdtPlan(_welds(), rules: const [], project: ''),
        generatedAt: _clock(),
      ),
      en: false,
      font: font('Roboto-Regular.ttf'),
    );
    expect(String.fromCharCodes((await empty.save()).take(5)), '%PDF-');
  });
}

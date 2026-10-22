// Karta spoiny, v28: sekcja „Szczegóły do kontroli uprawnień” —
// prowadzenie grani, przenoszenie metalu (tylko MIG/MAG) i wyrób rura /
// blacha (rura sama po wpisaniu OD). Bez bazy: DAO i kontrola zgodności są
// podstawione, sprawdzamy, co formularz oddaje do zapisu.

import '../support/test_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_compliance.dart';
import 'package:cut_list_app/domain/weld_journal/weld_entry.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/weld_journal/weld_editor_sheet.dart';
import 'package:cut_list_app/widgets/weld_journal/wj_ui.dart';

/// Zapis bez bazy — zapamiętuje, co formularz oddał.
class _FakeDao extends WeldJournalDao {
  WeldEntry? inserted;

  @override
  Future<void> insert(WeldEntry e, {String by = '', String? warning}) async {
    inserted = e;
  }
}

/// Kontrola bez WPS i rejestru — nic do ostrzeżenia.
Future<WeldCompliance> _noCheck(WeldEntry e, {String? wpsId}) async =>
    WeldCompliance(
      wpsRef: e.wpsRef,
      wps: null,
      wpsIssues: const [],
      welders: const [],
      weldDate: DateTime(2026, 10, 17),
    );

WeldEntry _initial({String method = 'TIG', String od = ''}) => WeldEntry(
      id: 'w-new',
      weldNo: 'W-001',
      projectName: 'Blok 4',
      pipeName: 'L-12',
      material: '',
      od: od,
      t: '',
      method: method,
      welder: 'JK-12',
      date: '2026-09-20',
      notes: '',
      status: WeldStatus.pending,
    );

const _sectionPl = 'Szczegóły do kontroli uprawnień';
const _transferLabelPl = 'Przenoszenie metalu — MIG/MAG (§5.2)';

Finder _chip(String label) => find.widgetWithText(WjChoiceChip, label);

Finder _field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

void main() {
  useGuestAccount();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_FakeDao> openEditor(
    WidgetTester tester, {
    required WeldEntry initial,
    AppLanguage language = AppLanguage.pl,
    Size size = const Size(420, 900),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dao = _FakeDao();
    await tester.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(language),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showWeldEditor(
                  context,
                  initial: initial,
                  isNew: true,
                  journal: const [],
                  journalProjects: const [],
                  stamp: 'JK-12',
                  dao: dao,
                  check: _noCheck,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return dao;
  }

  Future<void> openSection(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(_chip(label));
    await tester.tap(_chip(label));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'sekcja domyślnie zwinięta; wybór grani i blachy zapisuje się, '
      'przenoszenia przy TIG nie ma', (tester) async {
    final dao = await openEditor(tester, initial: _initial());

    expect(find.text(_sectionPl), findsOneWidget);
    expect(_chip('ss nb'), findsNothing, reason: 'domyślnie zwinięta');

    await openSection(tester, _sectionPl);
    expect(_chip('ss nb'), findsOneWidget);
    expect(find.text(_transferLabelPl), findsNothing,
        reason: 'przenoszenie tylko dla MIG/MAG');

    await tapChip(tester, 'ss nb');
    expect(find.byKey(const ValueKey('weld-root-hint')), findsOneWidget);
    expect(find.text('jednostronnie bez podkładki'), findsOneWidget);
    await tapChip(tester, 'blacha (P)');
    await save(tester);

    final saved = dao.inserted!;
    expect(saved.rootBacking, WeldRootBacking.nb);
    expect(saved.productForm, WeldProductKind.plate);
    expect(saved.metalTransfer, isEmpty);
    expect(weldParametersOf(saved).root?.code, 'nb');
  });

  testWidgets(
      'MIG/MAG: przenoszenie widoczne i zapisane; po zmianie procesu na TIG '
      'znika i nie trafia do spoiny', (tester) async {
    final dao = await openEditor(tester, initial: _initial(method: 'MIG/MAG'));
    await openSection(tester, _sectionPl);
    expect(find.text(_transferLabelPl), findsOneWidget);
    await tapChip(tester, 'zwarciowe (dip)');
    expect(find.textContaining('dip'), findsWidgets);

    // Proces → TIG (lista w sekcji „Proces, WPS…”).
    final processDropdown = find.descendant(
        of: find.byType(DropdownButtonFormField<String>),
        matching: find.text('MIG/MAG'));
    await tester.ensureVisible(processDropdown);
    await tester.tap(processDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('TIG').last);
    await tester.pumpAndSettle();
    expect(find.text(_transferLabelPl), findsNothing);

    await save(tester);
    expect(dao.inserted!.method, 'TIG');
    expect(dao.inserted!.metalTransfer, isEmpty,
        reason: 'ukryte przenoszenie nie zostaje w spoinie TIG');
  });

  testWidgets('MIG/MAG: wybrane przenoszenie zapisuje się', (tester) async {
    final dao = await openEditor(tester, initial: _initial(method: 'MIG/MAG'));
    await openSection(tester, _sectionPl);
    await tapChip(tester, 'inne (natrysk, puls)');
    await save(tester);
    expect(dao.inserted!.metalTransfer, WeldMetalTransfer.other);
    expect(weldParametersOf(dao.inserted!).dipTransfer, isFalse);
  });

  testWidgets(
      'wpisane OD ustawia wyrób „rura”, spawacz może zmienić; wyczyszczone '
      'OD wraca do „nie podano”', (tester) async {
    final dao = await openEditor(tester, initial: _initial());
    await openSection(tester, _sectionPl);
    expect(find.byKey(const ValueKey('weld-product-auto')), findsNothing);

    await tester.ensureVisible(_field('OD (mm)'));
    await tester.enterText(_field('OD (mm)'), '60.3');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('weld-product-auto')), findsOneWidget);
    expect(tester.widget<WjChoiceChip>(_chip('rura (T)')).selected, isTrue);

    await tester.enterText(_field('OD (mm)'), '');
    await tester.pumpAndSettle();
    expect(tester.widget<WjChoiceChip>(_chip('rura (T)')).selected, isFalse);

    await tester.enterText(_field('OD (mm)'), '88.9');
    await tester.pumpAndSettle();
    await tapChip(tester, 'blacha (P)');
    // Wybór spawacza — kolejna zmiana OD go nie nadpisuje.
    await tester.enterText(_field('OD (mm)'), '114.3');
    await tester.pumpAndSettle();
    expect(tester.widget<WjChoiceChip>(_chip('blacha (P)')).selected, isTrue);
    expect(find.byKey(const ValueKey('weld-product-auto')), findsNothing);

    await save(tester);
    expect(dao.inserted!.od, '114.3');
    expect(dao.inserted!.productForm, WeldProductKind.plate);
  });

  testWidgets('nowa spoina bez wyboru: wszystkie trzy pola puste (nie podano)',
      (tester) async {
    final dao = await openEditor(tester, initial: _initial(method: 'MIG/MAG'));
    await save(tester);
    final saved = dao.inserted!;
    expect(saved.rootBacking, isEmpty);
    expect(saved.metalTransfer, isEmpty);
    expect(saved.productForm, isEmpty);
    expect(saved.toRow()['root_backing'], isNull);
  });

  testWidgets('EN: sekcja i wybory po angielsku', (tester) async {
    await openEditor(tester,
        initial: _initial(method: 'MIG/MAG'), language: AppLanguage.en);
    await openSection(tester, 'Details for the qualification check');
    expect(find.text('Root / backing — butt welds (Table 11)'), findsOneWidget);
    expect(find.text('Metal transfer — MIG/MAG (cl. 5.2)'), findsOneWidget);
    expect(find.text('Product (cl. 5.3)'), findsOneWidget);
    expect(_chip('not given'), findsNWidgets(3));
    expect(_chip('dip (short-circuit)'), findsOneWidget);
    expect(_chip('pipe (T)'), findsOneWidget);
    expect(find.text(_sectionPl), findsNothing);
  });

  for (final language in AppLanguage.values) {
    testWidgets(
        '320 px i tekst ×1,3 (${language.name}): sekcja rozwinięta bez '
        'przepełnienia', (tester) async {
      await openEditor(tester,
          initial: _initial(method: 'MIG/MAG', od: '60.3'),
          language: language,
          size: const Size(320, 640),
          textScale: 1.3);
      await openSection(
          tester,
          language == AppLanguage.en
              ? 'Details for the qualification check'
              : _sectionPl);
      await tapChip(tester, 'ss gb');
      await tapChip(
          tester,
          language == AppLanguage.en
              ? 'other (spray, pulse)'
              : 'inne (natrysk, puls)');
      // Przewinięcie przez całą sekcję — każdy chip faktycznie się układa.
      await tester.ensureVisible(
          _chip(language == AppLanguage.en ? 'plate (P)' : 'blacha (P)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

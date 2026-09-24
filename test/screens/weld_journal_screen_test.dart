// Ekran dziennika spoin w rękawicach i przed inspektorem:
//  * status nie zmienia się od jednego dotknięcia ikony — tylko wyraźny
//    wybór + potwierdzenie, i zmiana trafia do historii;
//  * usunięcie jest miękkie i odwracalne;
//  * chipy statusu i filtrów mają co najmniej 48 dp;
//  * „Zapisz” jest przyklejony na dole karty spoiny, bez przewijania;
//  * nowy wpis nie dostaje „316L” z automatu;
//  * lista w porządku naturalnym, ostrzeżenie o duplikacie numeru.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/widgets/weld_journal/wj_ui.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

Widget _app(Widget child) => AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(home: child),
    );

/// Lets the real SQLite work finish and the screen rebuild.
Future<void> _settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await flushTestDatabase(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(const WeldJournalScreen()));
  await _settle(tester);
  await tester.pumpAndSettle();
}

Future<void> _seed(WidgetTester tester, List<WeldEntry> welds) =>
    tester.runAsync(() async {
      for (final w in welds) {
        await WeldJournalDao().insert(w, by: 'JK-12');
      }
    });

Future<WeldEntry?> _read(WidgetTester tester, String id) =>
    tester.runAsync<WeldEntry?>(() => WeldJournalDao().getById(id));

void main() {
  useTestDatabase();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {});

  Future<void> clear(WidgetTester tester) => tester.runAsync(() async {
        final db = await AppDatabase.get();
        for (final t in [
          'weld_journal',
          'weld_journal_history',
          'weld_repairs',
          'weld_journal_projects',
        ]) {
          await db.delete(t);
        }
      });

  testWidgets(
      'dotknięcie ikony statusu NIE zmienia statusu — dopiero wybór i '
      'potwierdzenie, a zmiana idzie do historii', (tester) async {
    await clear(tester);
    await _seed(tester, [weld('w1', weldNo: 'W-001', status: 'PENDING')]);
    await _pumpScreen(tester);

    // Stary ekran: jedno dotknięcie = PENDING → OK bez pytania.
    await tester.tap(find.byIcon(Icons.pending_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Status spoiny W-001'), findsOneWidget);
    await _settle(tester, rounds: 2);
    expect((await _read(tester, 'w1'))!.status, 'PENDING');

    // Bez innego wyboru przycisk jest nieaktywny.
    final confirm = find.widgetWithText(FilledButton, 'Zmień status');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect((await _read(tester, 'w1'))!.status, 'PENDING');

    await tester.tap(find.byIcon(Icons.pending_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK — przyjęta'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await _settle(tester);

    expect((await _read(tester, 'w1'))!.status, 'OK');
    final history =
        (await tester.runAsync(() => WeldJournalDao().history('w1')))!;
    expect(history.first.action, WeldHistoryAction.status);
    expect(history.first.oldValue, 'PENDING');
    expect(history.first.newValue, 'OK');
  });

  testWidgets('chipy statusu i filtrów mają co najmniej 48 dp',
      (tester) async {
    await clear(tester);
    await _seed(tester, [weld('w1')]);
    await _pumpScreen(tester);
    final chips = find.byType(WjChoiceChip);
    expect(chips, findsWidgets);
    for (final e in chips.evaluate()) {
      final size = tester.getSize(find.byWidget(e.widget));
      expect(size.height, greaterThanOrEqualTo(48),
          reason: 'chip ${(e.widget as WjChoiceChip).label}');
    }
  });

  testWidgets('usunięcie jest miękkie: znika z listy, zostaje w bazie, '
      '„Cofnij” przywraca', (tester) async {
    await clear(tester);
    await _seed(tester, [weld('w1', weldNo: 'W-001')]);
    await _pumpScreen(tester);

    await tester.tap(find.byTooltip('Akcje spoiny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usuń…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Usuń'));
    await tester.pump();
    await _settle(tester);

    expect(find.text('W-001'), findsNothing);
    final stored = await _read(tester, 'w1');
    expect(stored, isNotNull, reason: 'wiersz nie może zniknąć z bazy');
    expect(stored!.isDeleted, isTrue);

    await tester.pumpAndSettle(); // snackbar fully in
    await tester.tap(find.text('Cofnij'));
    await tester.pump();
    await _settle(tester);
    expect((await _read(tester, 'w1'))!.isDeleted, isFalse);
    expect(find.text('W-001'), findsOneWidget);
  });

  testWidgets('lista w porządku naturalnym: W9 przed W10', (tester) async {
    await clear(tester);
    await _seed(tester, [weld('a', weldNo: 'W10'), weld('b', weldNo: 'W9')]);
    await _pumpScreen(tester);
    final y9 = tester.getTopLeft(find.text('W9')).dy;
    final y10 = tester.getTopLeft(find.text('W10')).dy;
    expect(y9, lessThan(y10));
  });

  testWidgets(
      'karta nowej spoiny: „Zapisz” widoczny bez przewijania, materiał pusty '
      '(nie 316L)', (tester) async {
    await clear(tester);
    await _pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final save = find.widgetWithText(FilledButton, 'Zapisz');
    expect(save, findsOneWidget);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(save);
    expect(rect.bottom, lessThanOrEqualTo(screen.height));
    expect(rect.top, greaterThan(screen.height / 2),
        reason: 'przycisk przyklejony na dole arkusza');

    final material = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Materiał');
    expect(tester.widget<TextField>(material).controller!.text, isEmpty);
  });

  testWidgets(
      '„Zapisz i następna” zapisuje i otwiera kolejną spoinę: numer +1, '
      'projekt, materiał i WPS skopiowane', (tester) async {
    await clear(tester);
    await _pumpScreen(tester);

    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(field('Projekt'), 'Blok 4');
    await tester.enterText(field('Numer spoiny'), 'SP-001-W005');
    await tester.enterText(field('Materiał'), '304L');
    await tester.ensureVisible(field('Nr WPS / pWPS'));
    await tester.enterText(field('Nr WPS / pWPS'), 'WPS-141-01');
    await tester.tap(find.text('Zapisz i następna'));
    await tester.pump();
    await _settle(tester, rounds: 10);
    await tester.pumpAndSettle();

    final saved = (await tester.runAsync(() => WeldJournalDao().listAll()))!;
    expect(saved.map((e) => e.weldNo), ['SP-001-W005']);

    // Druga karta jest już otwarta, z przepisanymi polami.
    expect(find.text('Nowa spoina'), findsOneWidget);
    String text(String label) =>
        tester.widget<TextField>(field(label)).controller!.text;
    expect(text('Numer spoiny'), 'SP-001-W006');
    expect(text('Projekt'), 'Blok 4');
    expect(text('Materiał'), '304L');
    expect(text('Nr WPS / pWPS'), 'WPS-141-01');
  });

  testWidgets('duplikat numeru w projekcie wymaga potwierdzenia',
      (tester) async {
    await clear(tester);
    await _seed(tester, [weld('w1', weldNo: 'W-001', project: 'Blok 4')]);
    await _pumpScreen(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final no = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Numer spoiny');
    final project = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Projekt');
    await tester.enterText(project, 'Blok 4');
    await tester.enterText(no, 'w-001');
    await tester.tap(find.widgetWithText(FilledButton, 'Zapisz'));
    await tester.pumpAndSettle();
    expect(find.text('Numer już użyty w projekcie'), findsOneWidget);

    await tester.tap(find.text('Zmień numer'));
    await tester.pumpAndSettle();
    final all = (await tester.runAsync(() => WeldJournalDao().listAll()))!;
    expect(all, hasLength(1), reason: 'nic nie zapisano');
  });
}

// Checklista przed spawaniem zależna od procesu i materiału (v25):
//  • MMA na stali węglowej nie dostaje punktów TIG / gazu formującego /
//    narzędzi do nierdzewki;
//  • „nie dotyczy” liczy się osobno od „sprawdzone”;
//  • poprawione treści (bez „kupon poradiowany”, bez „brak N₂”);
//  • wykonaną checklistę da się zapisać do spoiny w dzienniku.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_journal_dao.dart';
import 'package:cut_list_app/domain/weld_journal/weld_history.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pre_weld_checklist_screen.dart';

import '../support/test_database.dart';
import '../support/weld_fixtures.dart';

Future<void> _pump(WidgetTester tester, {AppLanguage lang = AppLanguage.en})
    async {
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppLanguageScope(
    controller: AppLanguageController(lang),
    child: const MaterialApp(home: PreWeldChecklistScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabase();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('MMA na stali węglowej: bez punktów TIG i nierdzewki',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('checklist-process-mma')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A106 B'));
    await tester.pumpAndSettle();

    for (final gone in [
      'Backing gas connected, purge dams/plugs fitted',
      'Tungsten electrode sharp, clean, correct diameter',
      'Stainless-only tools used (no iron cross-contamination)',
      "Today's test coupon welded and accepted",
      'Fit-up gap ≈ 0, tubes aligned (no land mismatch)',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.textContaining('Electrodes per WPS'), findsOneWidget);
    expect(find.text('Root gap, bevel and hi-lo mismatch per WPS'),
        findsOneWidget);
    // Poprawiona treść P-No 1.
    expect(find.textContaining('radiograph'), findsNothing);
    expect(find.textContaining('ASME B16.25'), findsOneWidget);
  });

  testWidgets('treść P-No 8 odsyła do WPS, nie zakazuje N₂', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(find.text('316 / 316L'), 150,
        scrollable: find
            .ancestor(
                of: find.text('A106 B'), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('316 / 316L'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no N₂'), findsNothing);
    expect(find.textContaining('ISO 14175 N5'), findsOneWidget);
    expect(find.textContaining('nitric or citric'), findsOneWidget);
  });

  testWidgets('„nie dotyczy” liczone osobno; komplet = sprawdzone + n/d',
      (tester) async {
    await _pump(tester);
    expect(find.text('0/11'), findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey('checklist-na-univ-test-coupon')));
    await tester.pumpAndSettle();
    expect(find.text('0/10'), findsOneWidget);
    expect(find.text('n/a: 1'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => k.startsWith('preweld_na_')), isTrue);
  });

  testWidgets('wykonana checklista trafia do historii spoiny', (tester) async {
    await tester.runAsync(() async {
      final db = await AppDatabase.get();
      await db.delete('weld_journal');
      await db.delete('weld_journal_history');
      await WeldJournalDao().insert(weld('w1', weldNo: 'W-042'));
    });
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('checklist-process-mma')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A106 B'));
    await tester.pumpAndSettle();
    // Wszystko odhaczone.
    final items = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(ListView).last, matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .where((t) => t.length > 12 && !t.startsWith('A106'))
        .toList();
    for (final t in items) {
      await tester.tap(find.text(t).first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checklist-save-to-weld')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('checklist-save-to-weld')));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checklist-weld-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('W-042').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Measured O₂ (ppm)'), '12');
    await tester.enterText(find.widgetWithText(TextField, 'Preheat (°C)'), '20');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await flushTestDatabase(tester);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final h = (await tester.runAsync(() => WeldJournalDao().history('w1')))!;
    final entry =
        h.firstWhere((e) => e.action == WeldHistoryAction.checklist);
    expect(entry.newValue, contains('MMA'));
    expect(entry.newValue, contains('O₂ 12 ppm'));
    expect(entry.newValue, contains('20 °C'));
    await tester.pump(const Duration(seconds: 7));
  });
}

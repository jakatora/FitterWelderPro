import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/features/quotes/quote_edit_page.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await flushTestDatabase(t);
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.pumpAndSettle();
}

Future<void> say(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('assistant-command')), text);
  await t.tap(find.byKey(const Key('assistant-go')));
  await settle(t);
}

void main() {
  useTestDatabase();
  setUp(() async {
    seedFreshInstall();
    AssistantHistoryStore.instance.resetForTest();
    ToolBridge.reset();
    AssistantPanelController.instance.setExpanded(false);
    await (await AppDatabase.get()).delete(WeldQuoteDao.table);
  });
  testWidgets(
      'production chat creates a draft with actual stored rates, opens native editor, undoes and protects a manual edit',
      (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    const store = QuoteSettingsStore();
    final dao = WeldQuoteDao();
    await t.runAsync(() => store.save(const QuoteSettings(
        baseRates: QuoteRates(welderRate: 177.5, fitterRate: 122))));
    await t.pumpWidget(const CutListApp());
    await settle(t);
    await t.tap(find.byTooltip('Powiedz, co zrobić'));
    await settle(t);
    const command =
        'Utwórz wycenę stal nierdzewna TIG + MMA w warsztacie tytuł: Kolektor A';
    await say(t, command);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    expect(await t.runAsync(() => dao.listAll()), isEmpty);
    await say(t, 'tak');
    expect(find.byType(QuoteEditPage), findsOneWidget);
    final editor = t.widget<QuoteEditPage>(find.byType(QuoteEditPage));
    expect(editor.quote.title, 'Kolektor A');
    expect(editor.quote.rates.welderRate, 177.5);
    expect(editor.quote.status, QuoteStatus.draft);
    expect(editor.quote.joints, isEmpty);
    final first = (await t.runAsync(() => dao.listAll()))!.single;
    expect(first.rates.fitterRate, 122);
    await appNavigatorKey.currentState!.maybePop();
    await settle(t);
    await say(t, 'cofnij zapis');
    expect(await t.runAsync(() => dao.listAll()), isEmpty);
    expect((await t.runAsync(() => dao.byId(first.id)))!.isDeleted, true);
    expect(AssistantHistoryStore.instance.entries.single.undone, true);
    await say(t, command);
    await say(t, 'tak');
    await settle(t);
    expect(find.byType(QuoteEditPage), findsOneWidget);
    final title = find.byKey(const ValueKey('quote-title'));
    await t.ensureVisible(title);
    await t.enterText(title, 'Ręczna zmiana');
    await t.pump(const Duration(seconds: 1));
    await settle(t);
    await appNavigatorKey.currentState!.maybePop();
    await settle(t);
    await say(t, 'cofnij zapis');
    final retained = (await t.runAsync(() => dao.listAll()))!.single;
    expect(retained.title, 'Ręczna zmiana');
    expect(retained.isDeleted, false);
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
  });
}

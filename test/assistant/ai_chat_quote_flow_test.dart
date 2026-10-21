import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/weld_quote_dao.dart';
import 'package:cut_list_app/domain/quotes/weld_quote.dart';
import 'package:cut_list_app/features/quotes/quote_edit_page.dart';
import 'package:cut_list_app/services/quote_settings.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount;
import 'global_pipe_slope_flow_test.dart' show settle, say;

void main() {
  useTestDatabase();
  testWidgets(
      'AI-created quote uses real stored rates, waits for confirmation, opens native editor and undoes',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('quote.new',
                'Utwórz wycenę stal nierdzewna TIG + MMA w warsztacie tytuł: Kolektor AI')
          ],
          '');
    });
    final dao = WeldQuoteDao();
    await t.runAsync(() async {
      await (await AppDatabase.get()).delete(WeldQuoteDao.table);
      await const QuoteSettingsStore().save(const QuoteSettings(
          baseRates: QuoteRates(welderRate: 177.5, fitterRate: 122)));
    });
    await say(t,
        'Mam zlecenie na nierdzewke, TIG i MMA w warsztacie, chce oferte nazwana Kolektor AI');
    expect(calls, 1);
    expect(await t.runAsync(() => dao.listAll()), isEmpty);
    expect(find.byKey(const Key('assistant-local-save')), findsOneWidget);
    await say(t, 'tak');
    expect(find.byType(QuoteEditPage), findsOneWidget);
    final saved = (await t.runAsync(() => dao.listAll()))!.single;
    expect(saved.title, 'Kolektor AI');
    expect(saved.rates.welderRate, 177.5);
    expect(saved.rates.fitterRate, 122);
    expect(saved.status, QuoteStatus.draft);
    expect(saved.joints, isEmpty);
    await appNavigatorKey.currentState!.maybePop();
    await settle(t);
    await say(t, 'cofnij zapis');
    expect(await t.runAsync(() => dao.listAll()), isEmpty);
    expect((await t.runAsync(() => dao.byId(saved.id)))!.isDeleted, isTrue);
  });
}

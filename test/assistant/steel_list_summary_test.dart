import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_tables/steel_list_summary_skill.dart';
import 'package:cut_list_app/domain/steel_weight/steel_weight.dart';
import 'package:cut_list_app/domain/steel_weight/steel_sections.dart';
import 'package:cut_list_app/domain/steel_weight/steel_order_text.dart';
import 'package:cut_list_app/domain/quotes/quote_calculator.dart'
    show formatPln;
import 'package:cut_list_app/features/steel_weight/steel_weight_page.dart';
import 'package:cut_list_app/features/steel_weight/steel_weight_store.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import '../support/test_database.dart';
import '../support/test_account.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command = 'Podsumuj zapisana liste stali';
const order = SteelOrder(items: [
  SteelItem(
      shape: SteelShape.ipe,
      section: 'IPE 100',
      lengthMm: 2500,
      count: 3,
      unitPrice: 6.25,
      priceUnit: PriceUnit.perM),
  SteelItem(
      shape: SteelShape.heb, section: 'HEB 200', lengthMm: 1000, count: 2),
], wastePct: 12.5);

class ReadGate extends InMemorySharedPreferencesStore {
  ReadGate(super.data) : super.withData();
  bool hold = false;
  late final entered = Completer<void>();
  late final release = Completer<void>();
  @override
  Future<Map<String, Object>> getAll() async {
    final snapshot = await super.getAll();
    if (hold) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return snapshot;
  }
}

void main() {
  useTestDatabase();
  useGuestAccount();
  Future<T> finish<T>(WidgetTester t, Future<T> operation) async {
    var done = false;
    late T value;
    Object? error;
    operation.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 40 && !done; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(done, true);
    if (error != null) throw error!;
    return value;
  }

  Future<void> reload(WidgetTester t) async {
    Navigator.of(t.element(find.byType(SteelWeightPage))).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SteelWeightPage()));
    await settle(t);
  }

  test('summary uses native cents, mixed price bases and missing-price warning',
      () {
    final native = summarizeOrder(order);
    final text = steelOrderSummaryText(order);
    expect(text, contains('2 poz., 5 szt.'));
    expect(text, contains(formatPln(native.netGrosze!)));
    expect(text, contains(formatPln(native.orderGrosze!)));
    expect(text, contains('Pozycje bez ceny: 1'));
    expect(text, contains(fmtKg(native.orderKg)));
    final priced = order.copyWith(pricePerKg: 4.15);
    expect(steelOrderSummaryText(priced),
        contains(formatPln(summarizeOrder(priced).orderGrosze!)));
    expect(steelOrderSummaryText(priced), isNot(contains('Pozycje bez ceny')));
    expect(steelOrderSummaryText(const SteelOrder()), contains('pusta'));
    final noPrice = SteelOrder(items: [order.items.last]);
    expect(
        steelOrderSummaryText(noPrice, english: true), contains('No prices'));
    expect(steelOrderSummaryText(noPrice, english: true),
        contains('excluded from cost'));
    expect(steelOrderSummaryText(order.copyWith(pricePerKg: 0)),
        isNot(contains('Pozycje bez ceny')));
  });
  test(
      'AI source guard separates whole-list reads from writes and filtered questions',
      () {
    final s = SteelListSummarySkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'steel_weight'));
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    expect(
        s.acceptsProposal(
            u('Mozesz mi powiedziec ile wazy cala moja lista materialowa'),
            u(command),
            ctx),
        true);
    for (final text in [
      'Nie podsumowuj zapisanej listy stali',
      'Usun cala liste stali',
      'Ile wazy biezaca pozycja stali',
      'Ile kosztuje lista klienta Jana',
      'Ile wazy tylko IPE na liscie',
      'How much would my material list cost at five per kg',
      'Podsumuj liste stali z zapasem 20 procent',
      'Do not summarize my material list',
      'Przetlumacz summarize saved steel list'
    ]) {
      expect(s.acceptsProposal(u(text), u(command), ctx), false, reason: text);
    }
  });
  testWidgets(
      'actual native list summary reads durable list, not draft, without a write',
      (t) async {
    await mount(t,
        home: const SteelWeightPage(),
        interpret: (_) async => throw StateError('Literal read is local'));
    await const SteelOrderStore().save(order);
    await reload(t);
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await say(t, command);
    expect(find.textContaining(steelOrderSummaryText(order)), findsWidgets);
    expect(find.byKey(const Key('assistant-local-save')), findsNothing);
    await prefs.reload();
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, before);
    // An external save is read freshly, rather than the older screen snapshot.
    final newer = order.copyWith(wastePct: 20);
    await const SteelOrderStore().save(newer);
    final result = await finish(
        t,
        ToolBridge.instance
            .performModuleAction('steel_weight', 'summarize_list'));
    expect(result.completed, true);
    expect(result.message.pl, steelOrderSummaryText(newer));
    expect(result.message.en, steelOrderSummaryText(newer, english: true));
    await t.tap(find.text('Lista (2)'));
    await settle(t);
    final listTab = await finish(
        t,
        ToolBridge.instance
            .performModuleAction('steel_weight', 'summarize_list'));
    expect(listTab.completed, true);
    expect(listTab.message.pl, steelOrderSummaryText(newer));
  });
  testWidgets(
      'natural AI list question executes native summary and leaves stored record intact',
      (t) async {
    var calls = 0;
    final speech = FixtureSpeech();
    await mount(t, speech: speech, home: const SteelWeightPage(),
        interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute', [AiCommandStep('steel.list.summary', command)], '');
    });
    await const SteelOrderStore().save(order);
    await reload(t);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('Mozesz mi powiedziec ile wazy cala moja lista materialowa');
    await settle(t);
    expect(calls, 1);
    expect(find.textContaining(steelOrderSummaryText(order)), findsWidgets);
    expect(jsonEncode((await const SteelOrderStore().load()).toJson()),
        jsonEncode(order.toJson()));
  });
  testWidgets('popup and corrupt disk never return a plausible list total',
      (t) async {
    await mount(t,
        home: const SteelWeightPage(),
        interpret: (_) async => throw StateError('Local read only'));
    final context = t.element(find.byType(SteelWeightPage));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Dialog')));
    await settle(t);
    final blocked = await ToolBridge.instance
        .performModuleAction('steel_weight', 'summarize_list');
    expect(blocked.completed, false);
    Navigator.of(context).pop();
    await settle(t);
    final prefs = await SharedPreferences.getInstance();
    final key = 'steel_weight_order_v1';
    await prefs.setString(key, '{bad');
    final corrupt = await finish(
        t,
        ToolBridge.instance
            .performModuleAction('steel_weight', 'summarize_list'));
    expect(corrupt.completed, false);
    expect(corrupt.message.pl, contains('Nie udało się odczytać'));
    expect(prefs.getString(key), '{bad');
  });
  for (final revoke in [false, true]) {
    testWidgets(
        'late saved-list read is rejected after ${revoke ? 'session revision' : 'route change'}',
        (t) async {
      await mount(t,
          home: const SteelWeightPage(),
          interpret: (_) async => throw StateError('Local read'));
      await const SteelOrderStore().save(order);
      await reload(t);
      final prefs = await SharedPreferences.getInstance();
      final gate = ReadGate(
          {for (final k in prefs.getKeys()) 'flutter.$k': prefs.get(k)!});
      SharedPreferencesStorePlatform.instance = gate;
      gate.hold = true;
      final pending = ToolBridge.instance
          .performModuleAction('steel_weight', 'summarize_list');
      await finish(t, gate.entered.future);
      if (revoke) {
        await finish(t, AccountService.instance.invalidateSession());
      } else {
        Navigator.of(t.element(find.byType(SteelWeightPage))).push(
            MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Another route'))));
        await t.pump();
      }
      gate.hold = false;
      gate.release.complete();
      final result = await finish(t, pending);
      expect(result.completed, false);
      expect(result.message.pl, isNot(contains('Masa netto')));
      await settle(t);
    });
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/core/calculator_action_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'fitter_tools_handles_test.dart' as native show cases;
import 'fitter_native_actions_test.dart' show copy, clear, weightInputs;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const copyRequest = 'Wrzuć mi te wyniki do schowka';
const clearRequest = 'Możesz wyczyścić wszystkie pola tego kalkulatora?';
void main() {
  useTestDatabase();
  useGuestAccount();
  final skill = CalculatorActionSkill();
  final ctx = AssistantContext(
      lang: AppLanguage.pl,
      modules: const FixedModuleContext(activeToolId: 'pipe_weight'));
  Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
  test(
      'source-backed calculator action needs an actual whole-form or result request',
      () {
    for (final source in [
      'Jak interpretować te wyniki',
      'Mam problem z wynikiem',
      'Możesz nie czyścić formularza',
      'Nie wrzucaj wyników do schowka',
      'Copy only the temperature',
      'Wyczyść tylko średnicę',
      'Wyczyść formularz nieistniejącego kalkulatora XYZ',
      'Przetłumacz clear the form',
      'How do I clear this form',
      'Nie chcę skopiować wyników',
      'I do not want to copy these results',
      'Czy mogę wyczyścić formularz',
      'Can I clear the form',
      'Wyczyść formularz i zapisy',
      'W moim profilu clear the form',
      'Skopiuj wyniki z historii',
      'Proszę, jak wyczyścić formularz',
      'Could you explain how to clear the form',
      'Please can I clear the form',
      'Czy możesz wyjaśnić jak skopiować wyniki',
    ]) {
      expect(skill.acceptsProposal(u(source), u(clear.command), ctx), false,
          reason: source);
      expect(skill.acceptsProposal(u(source), u(copy.command), ctx), false,
          reason: source);
    }
  });
  test('natural whole-form requests produce one source-bound native probe', () {
    for (final pair in [
      (copyRequest, copy),
      (clearRequest, clear),
      ('Could you put these results in the clipboard', copy),
      ('Can you clear all the inputs', clear),
      ('Żebym nie musiał przepisywać, wrzuć te wyniki do schowka', copy),
    ]) {
      expect(skill.canInterruptPendingWithAi, true);
      expect(skill.aiTaskSwitchCommands(u(pair.$1), ctx), hasLength(1),
          reason: pair.$1);
      expect(skill.acceptsProposal(u(pair.$1), u(pair.$2.command), ctx), true,
          reason: pair.$1);
      expect(
          skill.acceptsProposal(u(pair.$1),
              u(pair.$2 == copy ? clear.command : copy.command), ctx),
          false);
    }
    final other = AssistantContext(
        lang: AppLanguage.pl,
        modules: const FixedModuleContext(activeToolId: 'iso_notebook'));
    expect(skill.aiTaskSwitchCommands(u(copyRequest), other), isEmpty);
    expect(
        skill.aiTaskSwitchCommands(u('Wyczyść pola heat input'), ctx), isEmpty);
  });
  late List<String> copied;
  setUp(() {
    copied = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  });
  Future<void> prepare(WidgetTester t,
      Future<AiCommandPlan> Function(Map<String, Object?>) interpret,
      {FixtureSpeech? speech, bool consent = true}) async {
    await mount(t,
        home: const FitterToolsScreen(initialTab: 5),
        speech: speech,
        consent: consent,
        interpret: interpret);
    await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
    await settle(t);
    await say(t, 'Oblicz heat input 24 V 230 A 150 mm/min');
    expect(find.textContaining('Jaki proces'), findsWidgets);
    expect(ToolBridge.instance.activeToolId, 'pipe_weight');
  }

  for (final action in [copy, clear]) {
    for (final voice in [false, true]) {
      testWidgets(
          'natural action switches the native pending process question action=${action == copy ? "copy" : "clear"} voice=$voice',
          (t) async {
        var calls = 0;
        final speech = FixtureSpeech();
        await prepare(t, (request) async {
          calls++;
          final caps = request['capabilities'] as List;
          expect(caps, hasLength(1));
          expect((caps.single as Map)['id'], 'calculator.action');
          expect((request['context'] as Map)['pending_reply'], isNull);
          if (action == clear && !voice) {
            File('build/assistant-calculator-action-switch-wire.json')
                .writeAsStringSync(jsonEncode(request));
          }
          return AiCommandPlan('execute', [action], '');
        }, speech: speech);
        final before = weightInputs();
        final text = action == copy ? copyRequest : clearRequest;
        if (voice) {
          await t.tap(find.byKey(const Key('assistant-mic')));
          await settle(t);
          speech.emit(text);
          await settle(t);
        } else {
          await say(t, text);
        }
        expect(calls, 1);
        expect(find.textContaining('Jaki proces'), findsNothing);
        expect(ToolBridge.instance.activeToolId, 'pipe_weight');
        if (action == copy) {
          expect(copied.single, contains('5.541 kg/m'));
          expect(weightInputs(), before);
        } else {
          expect(copied, isEmpty);
          expect(weightInputs()['od_mm'], isNull);
          expect(weightInputs()['wall_mm'], isNull);
        }
        expect(t.takeException(), isNull);
      });
    }
  }
  for (final mode in ['wrong-action', 'outage']) {
    testWidgets(
        'failed natural switch preserves actual pending process mode=$mode',
        (t) async {
      var calls = 0;
      await prepare(t, (_) async {
        calls++;
        if (mode == 'outage') throw const AssistantAiUnavailable(503);
        return const AiCommandPlan('execute', [clear], '');
      });
      final before = weightInputs();
      await say(t, copyRequest);
      expect(calls, 1);
      expect(weightInputs(), before);
      expect(copied, isEmpty);
      expect(find.textContaining('Jaki proces'), findsWidgets);
      await say(t, 'TIG');
      expect(calls, 1);
      expect(find.textContaining('Jaki proces'), findsNothing);
      expect(find.textContaining('ASME'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  for (final source in ['Mam problem z wynikiem', 'Can I clear the form']) {
    testWidgets(
        'an informational request cannot authorize a hallucinated clear: $source',
        (t) async {
      var calls = 0;
      await mount(t, home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async {
        calls++;
        return const AiCommandPlan('execute', [clear], '');
      });
      await ToolBridge.instance.current!.apply(native.cases['pipe_weight']!);
      await settle(t);
      final before = weightInputs();
      await say(t, source);
      expect(calls, 1);
      expect(weightInputs(), before);
      expect(copied, isEmpty);
      expect(find.textContaining('Propozycja AI zmienia'), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'natural switch without AI consent preserves the pending action and inputs',
      (t) async {
    var calls = 0;
    await prepare(t, (_) async {
      calls++;
      return const AiCommandPlan('execute', [clear], '');
    }, consent: false);
    final before = weightInputs();
    await say(t, clearRequest);
    expect(calls, 0);
    expect(weightInputs(), before);
    expect(copied, isEmpty);
    expect(find.textContaining('Jaki proces'), findsWidgets);
    await t.scrollUntilVisible(find.textContaining('Włącz AI'), 100,
        scrollable: find
            .descendant(
                of: find.byType(AiChatScreen).last,
                matching: find.byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down))
            .first);
    expect(find.textContaining('Włącz AI'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}

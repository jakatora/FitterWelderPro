import 'dart:convert';
import 'dart:io';
import 'package:cut_list_app/screens/fitter_tools_screen.dart';
import 'package:cut_list_app/assistant/navigation_plan_guard.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/core/open_tool_skill.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'ai_pending_task_switch_test.dart' show newDrawing, pendingPlan;

const request = 'Przejdźmy teraz do kalkulatora heat input';
const heat = AiCommandPlan(
    'execute', [AiCommandStep('tool.open', 'Otwórz heat input')], '');
void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  test('registry target is retained across native and natural AI navigation',
      () {
    final s = OpenToolSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    for (final pair in [
      (request, 'Otworz heat input'),
      ('Przejdzmy teraz do zeszytu ISO', 'Otworz zeszyt ISO'),
      ('Could you please open steel weight', 'Open steel weight'),
      ('Chce teraz otworzyc dziennik spoin', 'Otworz dziennik spoin'),
    ]) {
      expect(s.acceptsProposal(u(pair.$1), u(pair.$2), ctx), true,
          reason: pair.$1);
      expect(s.aiTaskSwitchCommands(u(pair.$1), ctx), hasLength(1));
    }
    for (final source in [
      'Nie otwieraj heat input',
      'Przetlumacz open heat input',
      'Jak obliczyc heat input',
      'Przejdzmy do heat input i ustaw prad 90 A',
      'Przejdzmy do nieistniejacego modulu XYZ',
      'Chce usunac heat input'
    ]) {
      expect(s.acceptsProposal(u(source), u('Otworz heat input'), ctx), false,
          reason: source);
    }
    expect(s.acceptsProposal(u(request), u('Otworz ciezar stali'), ctx), false);
    expect(
        s.acceptsProposal(
            u('Open heat input'), u('Open heat input and delete records'), ctx),
        false);
  });
  Future<IsoNotebookController> prepare(WidgetTester t,
      Future<AiCommandPlan> Function(Map<String, Object?>) interpret,
      {FixtureSpeech? speech}) async {
    await mount(t, interpret: interpret, speech: speech);
    await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
    final c = IsoNotebookController.active!;
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await say(t, newDrawing);
    expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
    return c;
  }

  for (final voice in [false, true]) {
    testWidgets(
        'natural navigation switches a pending task to the requested actual module voice=$voice',
        (t) async {
      var calls = 0;
      final speech = FixtureSpeech();
      final c = await prepare(t, (r) async {
        if (++calls == 1) return pendingPlan;
        final caps = r['capabilities'] as List;
        expect(caps, hasLength(1));
        expect((caps.single as Map)['id'], 'tool.open');
        File('build/assistant-navigation-wire.json')
            .writeAsStringSync(jsonEncode(r));
        expect((r['context'] as Map)['pending_reply'], isNull);
        return heat;
      }, speech: speech);
      final revision = c.revision;
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(request);
        await settle(t);
      } else {
        await say(t, request);
      }
      expect(calls, 2);
      expect(ToolBridge.instance.activeToolId, 'heat_input');
      expect(ToolBridge.instance.current, isNotNull);
      expect(c.revision, revision);
      expect(c.summary!.pipeCount, 2);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsNothing);
    });
  }
  for (final failure in [false, true]) {
    testWidgets(
        'wrong module or outage keeps the old question and both queued drawing steps outage=$failure',
        (t) async {
      var calls = 0;
      final c = await prepare(t, (_) async {
        if (++calls == 1) return pendingPlan;
        if (failure) throw const AssistantAiUnavailable(503);
        return const AiCommandPlan(
            'execute', [AiCommandStep('tool.open', 'Otworz ciezar stali')], '');
      });
      final revision = c.revision;
      await say(t, request);
      expect(calls, 2);
      expect(ToolBridge.instance.activeToolId, 'iso_notebook');
      expect(c.revision, revision);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      await say(t, 'Dorysuj');
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      expect(c.summary!.pipeCount, 4);
      expect(calls, 2);
    });
  }
  testWidgets(
      'literal open bypasses the pending question without an extra AI call',
      (t) async {
    var calls = 0;
    await prepare(t, (_) async {
      calls++;
      return pendingPlan;
    });
    await say(t, 'Otworz heat input');
    expect(calls, 1);
    expect(ToolBridge.instance.activeToolId, 'heat_input');
  });
  testWidgets('natural navigation also works with no pending dialogue',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute', [AiCommandStep('tool.open', 'Otworz zeszyt ISO')], '');
    });
    await say(t, 'Przejdzmy teraz do zeszytu ISO');
    expect(calls, 1);
    expect(ToolBridge.instance.activeToolId, 'iso_notebook');
    expect(IsoNotebookController.active, isNotNull);
  });
  test(
      'natural title navigation has a grounded probe for every available registry module in PL and EN',
      () {
    final skill = OpenToolSkill();
    for (final tool in availableTools) {
      for (final lang in AppLanguage.values) {
        final ctx =
            AssistantContext(lang: lang, modules: const FixedModuleContext());
        final title = lang == AppLanguage.en ? tool.titleEn : tool.titlePl;
        final source = Utterance(
            lang == AppLanguage.en
                ? 'Could you please open $title'
                : 'Przejdzmy teraz do $title',
            lang: lang);
        final command = Utterance(
            lang == AppLanguage.en ? 'open $title' : 'otworz $title',
            lang: lang);
        expect(skill.acceptsProposal(source, command, ctx), true,
            reason: '${tool.id} ${lang.name}');
        expect(skill.aiTaskSwitchCommands(source, ctx), hasLength(1),
            reason: tool.id);
      }
    }
  });
  for (final outage in [false, true]) {
    testWidgets(
        'failed natural navigation without a question never falls back to a calculator action outage=$outage',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        if (outage) throw const AssistantAiUnavailable(503);
        return const AiCommandPlan(
            'execute', [AiCommandStep('tool.open', 'Otworz ciezar stali')], '');
      });
      final bridge = ToolBridge.instance;
      final before =
          Map<String, Object?>.of(bridge.inputFields('rolling_offset')!);
      await say(t, request);
      expect(calls, 1);
      expect(bridge.activeToolId, 'rolling_offset');
      expect(bridge.inputFields('rolling_offset'), before);
      expect(find.textContaining('Nie udało się zinterpretować polecenia'),
          findsWidgets);
    });
  }
  for (final correct in [false, true]) {
    testWidgets(
        'pending module choice keeps the user target instead of accepting a different AI reply correct=$correct',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (r) async {
        calls++;
        expect(((r['context'] as Map)['pending_reply'] as Map)['skill_id'],
            'tool.open');
        return AiCommandPlan(
            'reply',
            [
              AiCommandStep(
                  'tool.open', correct ? 'Zeszyt ISO' : 'Ciężar stali')
            ],
            '');
      });
      await say(t, 'Otworz');
      expect(find.text('Które narzędzie otworzyć?'), findsWidgets);
      await say(t, 'Chce teraz otworzyc zeszyt ISO');
      expect(calls, 1);
      if (!correct) {
        expect(ToolBridge.instance.activeToolId, 'rolling_offset');
        expect(find.text('Które narzędzie otworzyć?'), findsWidgets);
        await say(t, 'Zeszyt ISO');
      }
      expect(ToolBridge.instance.activeToolId, 'iso_notebook');
      expect(calls, 1);
    });
  }
  testWidgets(
      'an exact where-is lookup stays local even while another skill asks a question',
      (t) async {
    var calls = 0;
    await prepare(t, (_) async {
      calls++;
      return pendingPlan;
    });
    await say(t, 'Gdzie jest kalkulator heat input');
    expect(calls, 1);
    expect(ToolBridge.instance.activeToolId, 'heat_input');
  });
  test('implicit navigation must retain the named native clear operation', () {
    const source = 'Wyczysc formularz redukcji';
    const open = AiCommandStep('tool.open', 'Otworz redukcje');
    const clear = AiCommandStep(
        'calculator.action', 'Wyczysc pola biezacego kalkulatora');
    const copy = AiCommandStep(
        'calculator.action', 'Skopiuj wyniki biezacego kalkulatora');
    expect(validNavigationPrerequisites(source, [open, clear], AppLanguage.pl),
        true);
    expect(validNavigationPrerequisites(source, [open], AppLanguage.pl), false);
    expect(validNavigationPrerequisites(source, [open, copy], AppLanguage.pl),
        false);
    expect(
        validNavigationPrerequisites(
            source,
            [const AiCommandStep('tool.open', 'Otworz ciezar stali'), clear],
            AppLanguage.pl),
        false);
    expect(
        validNavigationPrerequisites('Otworz redukcje', [open], AppLanguage.pl),
        true);
  });
  for (final wrongFollowup in [false, true]) {
    testWidgets(
        'incomplete implicit navigation plan changes no native route or inputs followup=$wrongFollowup',
        (t) async {
      var calls = 0;
      await mount(t, home: const FitterToolsScreen(initialTab: 5),
          interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              const AiCommandStep('tool.open', 'Otworz redukcje'),
              if (wrongFollowup)
                const AiCommandStep('calculator.action',
                    'Skopiuj wyniki biezacego kalkulatora'),
            ],
            '');
      });
      final bridge = ToolBridge.instance;
      final before =
          Map<String, Object?>.of(bridge.inputFields('pipe_weight')!);
      await say(t, 'Wyczysc formularz redukcji');
      expect(calls, 1);
      expect(bridge.activeToolId, 'pipe_weight');
      expect(bridge.inputFields('pipe_weight'), before);
    });
  }
}

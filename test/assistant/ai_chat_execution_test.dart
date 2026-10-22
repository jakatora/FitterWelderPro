import 'package:cut_list_app/feedback/feedback_store.dart';
import 'package:cut_list_app/assistant/assistant_history.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import 'package:cut_list_app/assistant/speech_io.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/assistant_panel_controller.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/ui/assistant_overlay.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/ai_chat_screen.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';
import 'package:cut_list_app/services/legal_consent.dart';
import '../support/test_database.dart';
import '../test_prefs.dart';
import 'global_pipe_slope_flow_test.dart' show settle, say;
import 'rolling_offset_current_test.dart' show input, cutFields;

class FixtureSpeech implements SpeechInput {
  SpeechResultCallback? result;
  void Function(String?)? done;
  @override
  bool get isSupported => true;
  @override
  Future<bool> initialize() async => true;
  @override
  Future<void> listen(
      {required AppLanguage language,
      required SpeechResultCallback onResult,
      required void Function(String?) onDone}) async {
    result = onResult;
    done = onDone;
  }

  void emit(String text) {
    result!(text, true);
    done?.call(null);
  }

  @override
  Future<void> stop() async {
    done?.call(null);
  }

  @override
  Future<void> cancel() => stop();
}

class FixtureSkill extends AssistantSkill {
  FixtureSkill(this.id, this.command, this.execute);
  @override
  final String id;
  final String command;
  final Future<SkillResult> Function(SkillMatch) execute;
  @override
  String? get toolId => null;
  @override
  AssistantTier get tier => AssistantTier.c;
  @override
  bool get readOnly => false;
  @override
  List<SkillExample> get examples => [SkillExample(command, command)];
  @override
  SkillMatch? match(Utterance u, AssistantContext c) =>
      u.raw == command ? SkillMatch(this, .99, utterance: u) : null;
  @override
  Map<String, Object?>? fillSlot(
          String slot, Utterance u, AssistantContext c) =>
      int.tryParse(u.raw) != null ? {'value': int.parse(u.raw)} : null;
  @override
  Future<SkillResult> run(SkillMatch m, AssistantContext c) => execute(m);
}

Future<void> mount(WidgetTester t,
    {required Future<AiCommandPlan> Function(Map<String, Object?>) interpret,
    List<AssistantSkill>? skills,
    SpeechInput? speech,
    SpeechOutput? voice,
    AssistantChatSender? chatSender,
    AssistantContextChatSender? contextChatSender,
    DateTime Function()? now,
    Future<String> Function()? welderStamp,
    Widget? home,
    bool consent = true}) async {
  seedFreshInstall();
  ToolBridge.reset();
  if (consent) await LegalConsent.instance.accept();
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 2.5;
  addTearDown(t.view.reset);
  AssistantPanelController.instance.setExpanded(true);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
  });
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          builder: (context, child) => AssistantOverlay(
              assistant: AiChatScreen(
                  embedded: true,
                  aiInterpreter: interpret,
                  skills: skills,
                  speechInput: speech,
                  speechOutput: voice,
                  now: now,
                  welderStamp: welderStamp,
                  chatSender: chatSender, contextChatSender: contextChatSender),
              child: child!),
          home: home ?? const RollingOffsetScreen())));
  await settle(t);
}

class SourceBoundFixtureSkill extends FixtureSkill {
  SourceBoundFixtureSkill(super.id, super.command, super.execute);
  @override
  bool acceptsProposal(Utterance original, Utterance command, AssistantContext context) =>
      original.raw.contains('ogarnij zamówiony wariant') &&
      original.raw.contains('drugi wariant') &&
      !original.raw.contains('wolno wykonać wszystko');
}

void main() {
  for (final voice in [false, true]) {
    testWidgets('exact native command supersedes AI clarification without another model call voice=$voice', (t) async {
      final speech = FixtureSpeech();
      final requests = <Map<String, Object?>>[];
      await mount(t, speech: speech, interpret: (request) async {
        requests.add(request);
        return const AiCommandPlan('clarify', [], 'Jaki wariant poprzedniej sprawy?');
      });
      await say(t, 'ogarnij poprzednią sprawę proszę');
      expect(requests, hasLength(1));
      const command = 'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm';
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(command);
        await settle(t);
      } else {
        await say(t, command);
      }
      expect(requests, hasLength(1));
      expect(find.text('573.1'), findsOneWidget);
      await say(t, 'ogarnij całkiem nową sprawę proszę');
      expect(requests, hasLength(2));
      expect((requests.last['context'] as Map)['pending_question'], isNull);
    });
  }

  for (final cancel in [false, true]) {
  testWidgets('clarification execution source respects cancellation=$cancel', (t) async {
    var runs = 0;
    var calls = 0;
    final skill = SourceBoundFixtureSkill('fixture.bound', 'fixture bound', (_) async {
      runs++;
      return const AnswerResult(AssistantAnswer(text: AssistantText.same('Wykonano wariant')));
    });
    await mount(t, skills: [skill], interpret: (_) async {
      calls++;
      if (calls == 1) return const AiCommandPlan('clarify', [], 'Wybierz wariant; wolno wykonać wszystko');
      return const AiCommandPlan('execute', [AiCommandStep('fixture.bound', 'fixture bound')], '');
    });
    await say(t, 'ogarnij zamówiony wariant');
    expect(runs, 0);
    if (cancel) await say(t, 'anuluj');
    await say(t, 'drugi wariant');
    expect(runs, cancel ? 0 : 1);
    expect(find.text('Wykonano wariant'), cancel ? findsNothing : findsOneWidget);
  });

  }
  for (final failure in ['unavailable', 'malformed']) {
    testWidgets('AI clarification survives $failure without a second chat call', (t) async {
      final requests = <Map<String, Object?>>[];
      var chats = 0;
      await mount(t, interpret: (request) async {
        requests.add(request);
        if (requests.length == 2) {
          if (failure == 'malformed') throw const FormatException('invalid plan');
          throw const AssistantAiUnavailable(503);
        }
        return const AiCommandPlan('clarify', [], 'Który wariant mam wybrać?');
      }, chatSender: (text, history) async {
        chats++;
        return ChatMessage(role: ChatRole.assistant, text: 'Nieoczekiwane zapytanie');
      });
      await say(t, 'pomóż mi dobrać wariant do mojego zadania');
      expect(requests, hasLength(1));
      await say(t, 'ten drugi wariant');
      expect(requests, hasLength(2));
      expect(chats, 0);
      expect(find.textContaining('Nie udało się zinterpretować polecenia'), findsOneWidget);
      await say(t, 'spróbujmy drugi wariant');
      expect(requests, hasLength(3));
      expect((requests.last['context'] as Map)['pending_question'], 'Który wariant mam wybrać?');
      expect(chats, 0);
    });
  }

  useTestDatabase();
  testWidgets(
      'main embedded chat executes captured real model output using actual visible inputs',
      (t) async {
    final fixture = jsonDecode(
        File('test/fixtures/assistant_ai_actual_haiku_offset.json')
            .readAsStringSync()) as Map;
    final calls = <Map<String, Object?>>[];
    await mount(t, interpret: (r) async {
      calls.add(r);
      expect((r['context'] as Map)['inputs'], fixture['actual_inputs']);
      return AiCommandPlan.fromJson(fixture['proposal'], {'rolling.offset'});
    });
    final b = ToolBridge.instance;
    await b.current!.apply({...cutFields, 'dn': 50});
    await settle(t);
    AssistantPanelController.instance.setExpanded(false);
    await settle(t);
    await t.enterText(input('Rise'), '600');
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    await say(t, fixture['text'] as String);
    expect(calls, hasLength(1));
    expect(b.inputFields('rolling_offset'), {
      'rise_mm': 600,
      'spread_mm': 400,
      'angle_deg': 45,
      'dn': 50,
      'gap_mm': 2
    });
    expect(find.text('945.8'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('late AI response cannot overwrite a newer manual edit',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await mount(t, interpret: (_) {
      calls++;
      return pending.future;
    });
    await ToolBridge.instance.current!.apply(cutFields);
    await settle(t);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'ogarnij mi obejscie tej przeszkody');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    AssistantPanelController.instance.setExpanded(false);
    await t.pump(const Duration(milliseconds: 200));
    await t.enterText(input('Rise'), '600');
    await t.pump(const Duration(milliseconds: 200));
    pending.complete(const AiCommandPlan(
        'execute',
        [
          AiCommandStep('rolling.offset',
              'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni')
        ],
        ''));
    await settle(t);
    AssistantPanelController.instance.setExpanded(true);
    await settle(t);
    expect(ToolBridge.instance.inputFields('rolling_offset')!['rise_mm'], 600);
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
  testWidgets(
      'plan pauses on native question and resumes next action after the answer',
      (t) async {
    var finished = 0;
    late FixtureSkill ask;
    ask = FixtureSkill(
        'fixture.ask',
        'fixture question',
        (m) async => m.slots.containsKey('value')
            ? const AnswerResult(
                AssistantAnswer(text: AssistantText.same('Wartość przyjęta.')))
            : AskResult('value', const AssistantText.same('Podaj wartość'),
                partial: m));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      finished++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Następny krok wykonany.')));
    });
    await mount(t,
        skills: [ask, next],
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('fixture.ask', 'fixture question'),
              AiCommandStep('fixture.next', 'fixture next')
            ],
            ''));
    await say(t, 'zajmij sie prosze tymi dwoma sprawami');
    expect(find.text('Podaj wartość'), findsOneWidget);
    expect(finished, 0);
    await say(t, '120');
    expect(finished, 1);
    expect(find.text('Następny krok wykonany.'), findsOneWidget);
  });
  testWidgets(
      'plan waits for actual touch-only save then resumes without duplicate write',
      (t) async {
    var writes = 0, finished = 0;
    final save = FixtureSkill(
        'fixture.save',
        'fixture save',
        (_) async => ConfirmResult(
                const AssistantAnswer(
                    text: AssistantText.same('Podsumowanie zapisu')), () async {
              writes++;
              return null;
            }, touchOnly: true));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      finished++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Następny krok wykonany.')));
    });
    await mount(t,
        skills: [save, next],
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('fixture.save', 'fixture save'),
              AiCommandStep('fixture.next', 'fixture next')
            ],
            ''));
    await say(t, 'ogarnij te sprawy dla mnie');
    expect(writes, 0);
    expect(finished, 0);
    await say(t, 'tak');
    expect(writes, 0);
    expect(finished, 0);
    await t.ensureVisible(find.byKey(const Key('assistant-local-save')));
    await t.tap(find.byKey(const Key('assistant-local-save')));
    await settle(t);
    expect(writes, 1);
    expect(finished, 1);
    expect(find.text('Następny krok wykonany.'), findsOneWidget);
  });
  testWidgets('without server consent no AI call is made', (t) async {
    var calls = 0;
    await mount(t, consent: false, interpret: (_) async {
      calls++;
      return const AiCommandPlan('clarify', [], 'Które narzędzie?');
    });
    await say(t, 'ogarnij mi te rurki prosze');
    expect(calls, 0);
  });
  testWidgets('cancelled AI response never executes when it arrives later',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    var calls = 0;
    await mount(t, interpret: (_) {
      calls++;
      return pending.future;
    });
    await ToolBridge.instance.current!.apply(cutFields);
    await settle(t);
    final before = Map.of(ToolBridge.instance.inputFields('rolling_offset')!);
    await t.enterText(find.byKey(const Key('assistant-command')),
        'ogarnij mi obejscie przeszkody');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(calls, 1);
    await t.tap(find.byTooltip('Anuluj AI'));
    await t.pump(const Duration(milliseconds: 200));
    pending.complete(const AiCommandPlan(
        'execute',
        [
          AiCommandStep('rolling.offset',
              'Rolling offset wznios 600 mm odsunięcie 400 mm kąt 45 stopni')
        ],
        ''));
    await settle(t);
    expect(ToolBridge.instance.inputFields('rolling_offset'), before);
    expect(find.text('Anulowano interpretację AI.'), findsOneWidget);
  });
  testWidgets(
      'AI clarification keeps conversational context for the next answer',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      if (calls == 1) {
        return const AiCommandPlan('clarify', [], 'Jakie kolana masz?');
      }
      final ctx = r['context'] as Map;
      expect(ctx['pending_question'], 'Jakie kolana masz?');
      expect((ctx['history'] as List).last,
          {'role': 'assistant', 'text': 'Jakie kolana masz?'});
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('rolling.offset',
                'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm')
          ],
          '');
    });
    await say(t, 'ogarnij te obejscie prosze');
    expect(find.text('Jakie kolana masz?'), findsOneWidget);
    await say(t, 'czterdziesci piec dlugie');
    expect(calls, 2);
    expect(find.text('573.1'), findsOneWidget);
  });
  testWidgets(
      'final phone speech transcript automatically reaches AI and actual native calculator',
      (t) async {
    final speech = FixtureSpeech();
    var calls = 0;
    await mount(t, speech: speech, interpret: (r) async {
      calls++;
      expect(r['text'], 'ogarnij obejscie prosze');
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('rolling.offset',
                'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm')
          ],
          '');
    });
    expect(calls, 0);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit('ogarnij obejscie prosze');
    await settle(t);
    expect(calls, 1);
    expect(find.text('573.1'), findsOneWidget);
  });
  testWidgets(
      'knowledge answer receives verified native action context instead of losing the conversation',
      (t) async {
    var answerCalls = 0;
    await mount(t,
        interpret: (_) async => const AiCommandPlan('answer', [], ''),
        chatSender: (text, history) async {
          answerCalls++;
          expect(text, 'a dlaczego tyle wyszlo');
          expect(
              history.any((m) =>
                  m.kind == AiReplyKind.nativeAction &&
                  m.text.contains('573,11')),
              isTrue);
          return ChatMessage(
              role: ChatRole.assistant,
              text: 'To wynik geometrii i odjęcia kształtek.',
              kind: AiReplyKind.live);
        });
    await say(t,
        'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni DN100 LR szczelina 3 mm');
    await say(t, 'a dlaczego tyle wyszlo');
    expect(answerCalls, 1);
    expect(
        find.text('To wynik geometrii i odjęcia kształtek.'), findsOneWidget);
  });
  testWidgets(
      'AI ordered plan opens actual ISO, draws two parts and native undo does not call AI',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (_) async {
      calls++;
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('iso.draw', 'Narysuj rura 300 mm w prawo'),
            AiCommandStep('iso.draw', 'Dorysuj rura 200 mm w górę')
          ],
          '');
    });
    await say(t, 'ogarnij mi ten uklad na kartce');
    for (var i = 0;
        i < 10 && (IsoNotebookController.active?.isBusy ?? false);
        i++) {
      await settle(t);
    }
    final c = IsoNotebookController.active!;
    expect(c.hasContent, isTrue);
    expect(c.debugPipeAxisTags, hasLength(2));
    expect(calls, 1);
    await say(t, 'cofnij');
    expect(c.debugPipeAxisTags, hasLength(1));
    expect(calls, 1);
  });
  testWidgets('new native command discards the remainder of a paused AI plan',
      (t) async {
    var nextRuns = 0, otherRuns = 0;
    late FixtureSkill question;
    question = FixtureSkill(
        'fixture.question',
        'fixture question',
        (m) async => AskResult(
            'value', const AssistantText.same('Podaj wartość'),
            partial: m));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      nextRuns++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Następny')));
    });
    final other = FixtureSkill('fixture.other', 'fixture other', (_) async {
      otherRuns++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Inne zadanie')));
    });
    await mount(t,
        skills: [question, next, other],
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('fixture.question', 'fixture question'),
              AiCommandStep('fixture.next', 'fixture next')
            ],
            ''));
    await say(t, 'ogarnij te sprawy');
    await say(t, 'fixture other');
    expect(otherRuns, 1);
    expect(nextRuns, 0);
  });
  testWidgets(
      'AI unavailability is visible while native fallback leaves data untouched',
      (t) async {
    await mount(t,
        interpret: (_) async => throw const AssistantAiUnavailable(503));
    expect(await FeedbackStore.instance.list(), isEmpty);
    final before = Map.of(ToolBridge.instance.inputFields('rolling_offset')!);
    await say(t, 'ogarnij mi obejscie przeszkody');
    expect(
        find.textContaining(
            'Interpretacja poleceń AI jest chwilowo niedostępna'),
        findsOneWidget);
    expect(ToolBridge.instance.inputFields('rolling_offset'), before);
    expect(await FeedbackStore.instance.list(), isEmpty,
        reason: 'AI outage is not a missing app feature');
  });
  for(final (status,code,message) in [
    (404,null,'AI nie jest jeszcze uruchomione'),
    (503,'AI_BUDGET_EXCEEDED','miesięczny limit kosztów AI'),
    (401,'INSTALL_SECRET_INVALID','uwierzytelnić połączenia z AI'),
  ]) {
    testWidgets('AI diagnostic $status/$code does not blame a missing feature',(t) async {
      await mount(t,interpret:(_) async=>throw AssistantAiUnavailable(status,code:code));
      final before=Map.of(ToolBridge.instance.inputFields('rolling_offset')!);
      await say(t,'ogarnij mi obejscie przeszkody');
      expect(find.textContaining(message),findsOneWidget);
      expect(ToolBridge.instance.inputFields('rolling_offset'),before);
      expect(await FeedbackStore.instance.list(),isEmpty);
    });
  }
  testWidgets('revoked consent prevents a pending AI answer from executing',
      (t) async {
    final pending = Completer<AiCommandPlan>();
    await mount(t, interpret: (_) => pending.future);
    await t.enterText(
        find.byKey(const Key('assistant-command')), 'ogarnij te rurki');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    await LegalConsent.instance.clear();
    pending.complete(const AiCommandPlan(
        'execute',
        [
          AiCommandStep('rolling.offset',
              'Rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni')
        ],
        ''));
    await settle(t);
    expect(
        ToolBridge.instance.inputFields('rolling_offset')!['rise_mm'], isNull);
    expect(find.textContaining('Zgoda na AI zmieniła się'), findsOneWidget);
  });
  testWidgets('summary speech must finish before a plan save can be confirmed',
      (t) async {
    final voice = FixtureVoice();
    var writes = 0, nextRuns = 0;
    final save = FixtureSkill(
        'fixture.save',
        'fixture save',
        (_) async => ConfirmResult(
                const AssistantAnswer(text: AssistantText.same('Podsumowanie')),
                () async {
              writes++;
              return null;
            }));
    final next = FixtureSkill('fixture.next', 'fixture next', (_) async {
      nextRuns++;
      return const AnswerResult(
          AssistantAnswer(text: AssistantText.same('Dalszy krok')));
    });
    await mount(t,
        voice: voice,
        skills: [save, next],
        interpret: (_) async => const AiCommandPlan(
            'execute',
            [
              AiCommandStep('fixture.save', 'fixture save'),
              AiCommandStep('fixture.next', 'fixture next')
            ],
            ''));
    await AssistantHistoryStore.instance.setSpeakReplies(true);
    await t.enterText(
        find.byKey(const Key('assistant-command')), 'ogarnij te sprawy');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(
        t
            .widget<FilledButton>(find.byKey(const Key('assistant-local-save')))
            .onPressed,
        isNull);
    expect(writes, 0);
    voice.release.complete();
    await settle(t);
    await t.ensureVisible(find.byKey(const Key('assistant-local-save')));
    await t.tap(find.byKey(const Key('assistant-local-save')));
    await settle(t);
    expect(writes, 1);
    expect(nextRuns, 1);
  });
}

class FixtureVoice implements SpeechOutput {
  final release = Completer<void>();
  @override
  Future<void> speak(String text, AppLanguage language) => release.future;
  @override
  Future<void> stop() async {
    if (!release.isCompleted) release.complete();
  }
}

import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cut_list_app/services/account_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/services/ai_chat_service.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'ai_pending_task_switch_test.dart' show newDrawing, pendingPlan;

const question = 'Czy możesz mi wyjaśnić, jak czytać ten wynik?';
const answer = 'Fixture explanation of the current result';
void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  for (final voice in [false, true]) {
    testWidgets(
        'knowledge answer retains native drawing question and both queued steps voice=$voice',
        (t) async {
      var interpretations = 0, answers = 0;
      final speech = FixtureSpeech();
      await mount(t, speech: speech, interpret: (r) async {
        if (++interpretations == 1) return pendingPlan;
        expect((r['context'] as Map)['pending_reply'], isNotNull);
        File('build/assistant-pending-knowledge-wire.json')
            .writeAsStringSync(jsonEncode(r));
        return const AiCommandPlan('answer', [], '');
      }, contextChatSender: (text, history, summary) async {
        answers++;
        expect(text, question);
        expect(summary!.pipeCount, 2);
        return ChatMessage(
            role: ChatRole.assistant, text: answer, kind: AiReplyKind.live);
      });
      await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await say(t, newDrawing);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      final revision = c.revision;
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(question);
        await settle(t);
      } else {
        await say(t, question);
      }
      expect(interpretations, 2);
      expect(answers, 1);
      expect(c.revision, revision);
      expect(c.summary!.pipeCount, 2);
      expect(find.textContaining(answer), findsWidgets);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      await say(t, 'Dorysuj');
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      expect(c.summary!.pipeCount, 4);
      expect(interpretations, 2);
      expect(answers, 1);
      expect(t.takeException(), isNull);
    });
  }
  for (final scenario in ['unavailable', 'throw', 'edited', 'revoked']) {
    testWidgets(
        'pending question survives a side answer failure without stale content: $scenario',
        (t) async {
      var interpretations = 0, answers = 0;
      final deferred = Completer<ChatMessage>();
      await mount(t, interpret: (_) async {
        if (++interpretations == 1) return pendingPlan;
        return const AiCommandPlan('answer', [], '');
      }, contextChatSender: (_, __, summary) {
        answers++;
        expect(summary!.pipeCount, 2);
        return deferred.future;
      });
      await say(t, 'Narysuj rura metr w prawo kolano DN50 w gore rura metr');
      final c = IsoNotebookController.active!;
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await say(t, newDrawing);
      await t.enterText(find.byKey(const Key('assistant-command')), question);
      await t.tap(find.byKey(const Key('assistant-go')));
      for (var i = 0; i < 12 && answers == 0; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(answers, 1);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      if (scenario == 'edited') {
        await t.runAsync(() =>
            c.renameSketch('Updated sheet', expectedRevision: c.revision));
      } else if (scenario == 'revoked') {
        await t.runAsync(AccountService.instance.invalidateSession);
      }
      if (scenario == 'throw') {
        deferred.completeError(StateError('Fixture offline'));
      } else {
        deferred.complete(ChatMessage(
            role: ChatRole.assistant,
            text: scenario == 'unavailable' ? 'Fixture unavailable' : answer,
            kind: scenario == 'unavailable'
                ? AiReplyKind.unavailable
                : AiReplyKind.live));
      }
      await settle(t);
      if (scenario == 'revoked') {
        expect(find.textContaining(answer), findsNothing);
        expect(
            find.textContaining('Na arkuszu jest już rysunek'), findsNothing);
      } else {
        expect(
            find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
        expect(c.summary!.pipeCount, 2);
        if (scenario == 'edited') {
          expect(find.textContaining(answer), findsNothing);
          expect(
              find.textContaining('Rysunek zmienił się podczas'), findsWidgets);
        } else {
          expect(
              find.textContaining(scenario == 'throw'
                  ? 'Nie udało się pobrać odpowiedzi'
                  : 'Fixture unavailable'),
              findsWidgets);
          await say(t, 'Dorysuj');
          for (var i = 0; i < 12 && c.isBusy; i++) {
            await settle(t);
          }
          await settle(t);
          expect(c.summary!.pipeCount, 4);
        }
      }
      expect(interpretations, 2);
      expect(answers, 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'side explanation retains calculator process question and validated numeric inputs',
      (t) async {
    var interpretations = 0, answers = 0;
    await mount(t, interpret: (r) async {
      interpretations++;
      expect(((r['context'] as Map)['pending_reply'] as Map)['skill_id'],
          'heat.input');
      return const AiCommandPlan('answer', [], '');
    }, chatSender: (_, __) async {
      answers++;
      return ChatMessage(
          role: ChatRole.assistant, text: answer, kind: AiReplyKind.live);
    });
    await say(t, 'Oblicz heat input 24 V 230 A 150 mm/min');
    expect(find.textContaining('Jaki proces spawania?'), findsWidgets);
    expect(interpretations, 0);
    await say(t, question);
    expect(interpretations, 1);
    expect(answers, 1);
    expect(find.textContaining(answer), findsWidgets);
    expect(find.textContaining('Jaki proces spawania?'), findsWidgets);
    expect(interpretations, 1);
    expect(answers, 1);
    await say(t, 'TIG');
    expect(find.textContaining('Liczyć wg EN 1011-1'), findsWidgets);
    await say(t, 'EN 1011-1');
    expect(ToolBridge.instance.activeToolId, 'heat_input');
    final fields = ToolBridge.instance.inputFields('heat_input')!;
    expect(fields['volts'], 24);
    expect(fields['amps'], 230);
    expect(fields['travel_mm_min'], 150);
    expect(fields['process'], 'GTAW');
    expect(interpretations, 1);
    expect(answers, 1);
    expect(t.takeException(), isNull);
  });
}

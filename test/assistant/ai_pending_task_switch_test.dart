import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import '../support/test_account.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const newDrawing =
    'Narysuj rura 500 mm w prawo. Następnie dorysuj rura 300 mm w górę';
const pendingPlan = AiCommandPlan(
    'execute',
    [
      AiCommandStep('iso.draw', 'Narysuj rura 500 mm w prawo'),
      AiCommandStep('iso.draw', 'Dorysuj rura 300 mm w górę')
    ],
    '');
const copyPlan = AiCommandPlan('execute',
    [AiCommandStep('iso.summary.copy', 'Skopiuj zestawienie rysunku ISO')], '');
const switchRequest = 'Wrzuć mi zestawienie tego rysunku do schowka';
void main() {
  useTestDatabase();
  useGuestAccount();
  setUp(() async => (await AppDatabase.get()).delete('iso_drawings'));
  final copied = <String>[];
  setUp(() {
    copied.clear();
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
    expect(c.summary!.pipeCount, 2);
    return c;
  }

  void inspectSwitch(Map<String, Object?> request) {
    final context = request['context'] as Map;
    expect(context['pending_reply'], isNull);
    expect(context['pending_question'], isNull);
    final caps = request['capabilities'] as List;
    expect(caps, hasLength(1));
    expect((caps.single as Map)['id'], 'iso.summary.copy');
    File('build/assistant-task-switch-wire.json')
        .writeAsStringSync(jsonEncode(request));
  }

  for (final voice in [false, true]) {
    testWidgets(
        'natural new task supersedes pending drawing without executing old remainder: voice=$voice',
        (t) async {
      var calls = 0;
      final speech = FixtureSpeech();
      final c = await prepare(t, (request) async {
        if (++calls == 1) return pendingPlan;
        inspectSwitch(request);
        return copyPlan;
      }, speech: speech);
      final revision = c.revision;
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await settle(t);
        speech.emit(switchRequest);
        await settle(t);
      } else {
        await say(t, switchRequest);
      }
      expect(calls, 2);
      expect(copied, hasLength(1));
      expect(c.summary!.pipeCount, 2);
      expect(c.revision, revision);
      expect(
          find.textContaining('Skopiowano zestawienie bieżącego rysunku ISO'),
          findsWidgets);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsNothing);
      await settle(t);
      expect(c.summary!.pipeCount, 2);
    });
  }
  for (final mode in [
    'outage',
    'wrong-target',
    'reply',
    'clarify',
    'multi-step',
    'wrong-command'
  ]) {
    testWidgets(
        'invalid new-task interpretation preserves question and queued drawing: $mode',
        (t) async {
      var calls = 0;
      final c = await prepare(t, (request) async {
        if (++calls == 1) return pendingPlan;
        inspectSwitch(request);
        switch (mode) {
          case 'outage':
            throw const AssistantAiUnavailable(503);
          case 'wrong-target':
            return const AiCommandPlan('execute',
                [AiCommandStep('iso.gap', 'Ustaw szczeline ISO na 9 mm')], '');
          case 'reply':
            return const AiCommandPlan(
                'reply', [AiCommandStep('iso.draw', 'new')], '');
          case 'clarify':
            return const AiCommandPlan('clarify', [], 'Which clipboard?');
          case 'multi-step':
            return const AiCommandPlan(
                'execute',
                [
                  AiCommandStep(
                      'iso.summary.copy', 'Skopiuj zestawienie rysunku ISO'),
                  AiCommandStep(
                      'iso.summary.copy', 'Skopiuj zestawienie rysunku ISO')
                ],
                '');
          default:
            return const AiCommandPlan('execute',
                [AiCommandStep('iso.summary.copy', 'Usun rysunek ISO')], '');
        }
      });
      final revision = c.revision;
      await say(t, switchRequest);
      expect(calls, 2);
      expect(copied, isEmpty);
      expect(c.revision, revision);
      expect(find.textContaining('Na arkuszu jest już rysunek'), findsWidgets);
      await say(t, 'Dorysuj');
      for (var i = 0; i < 12 && c.isBusy; i++) {
        await settle(t);
      }
      await settle(t);
      expect(calls, 2);
      expect(c.summary!.pipeCount, 4);
      expect(copied, isEmpty);
    });
  }
  testWidgets(
      'literal pending choice remains local and keeps its queued remainder',
      (t) async {
    var calls = 0;
    final c = await prepare(t, (_) async {
      calls++;
      return pendingPlan;
    });
    await say(t, 'Dorysuj');
    for (var i = 0; i < 12 && c.isBusy; i++) {
      await settle(t);
    }
    await settle(t);
    expect(calls, 1);
    expect(c.summary!.pipeCount, 4);
    expect(copied, isEmpty);
  });
}

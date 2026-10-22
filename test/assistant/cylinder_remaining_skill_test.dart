import 'package:flutter/material.dart' show Key;
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/welding/shielding_gas.dart';
import 'support/assistant_test_support.dart';

void main() {
  useTestDatabase();
  for (final text in [
    'Ile gazu zostało w butli? Butla 50 L manometr 60 bar palnik 10 L/min rezerwa 10 bar',
    'Calculate gas remaining cylinder 50 L gauge 60 bar torch 10 L/min reserve 10 bar',
  ]) {
    test('standalone cylinder: $text', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final r = await h.say(text);
      expect(r.match?.skill.id, 'gas.remaining');
      final a = r.result as AnswerResult;
      final native = cylinderRemaining(
          waterCapacityL: 50,
          currentPressureBar: 60,
          torchLpm: 10,
          reserveBar: 10)!;
      expect(
          a.answer.lines.map((l) => l.value),
          containsAll([
            native.gasL.toStringAsFixed(0),
            native.flowMinutes.toStringAsFixed(0)
          ]));
    });
  }
  test('missing inputs are clarified without production defaults', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = await h.say('Ile gazu zostało w butli?');
    expect(r.match?.skill.id, 'gas.remaining');
    expect(r.result, isA<AskResult>());
    for (final reply in ['50 L', '60 bar', '10 L/min']) {
      expect((await h.say(reply)).result, isA<AskResult>());
    }
    expect((await h.say('10 bar')).result, isA<AnswerResult>());
  });
  for (final suffix in [
    'butla -50 L manometr 60 bar palnik 10 L/min rezerwa 10 bar',
    'butla 50 L manometr 60 bar albo 80 bar palnik 10 L/min rezerwa 10 bar',
    'butla 50 L manometr 60 bar palnik 0 L/min rezerwa 10 bar',
    'butla 50 L manometr 60 bar palnik 10 L/min rezerwa 60 bar',
  ]) {
    test('invalid or ambiguous request never produces a result: $suffix',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final r = await h.say('Oblicz zapas gazu $suffix');
      expect(r.result, isNot(isA<AnswerResult>()));
    });
  }
  test('alternate flow units use the same arithmetic', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = await h.say(
        'Oblicz zapas gazu butla 50 L manometr 60 bar przepływ 600 litrów na godzinę rezerwa 10 bar');
    expect((r.result as AnswerResult).answer.lines.last.value, '250');
  });
  for (final voice in [false, true]) {
    testWidgets('real chat answer from ${voice ? "voice transcript" : "text"}',
        (t) async {
      final speech = FixtureSpeech();
      await mount(t,
          speech: speech,
          interpret: (_) async =>
              throw StateError('Native calculation needs no paid API'));
      const command =
          'Ile gazu zostało w butli? Butla 50 L manometr 60 bar palnik 10 L/min rezerwa 10 bar';
      if (voice) {
        await t.tap(find.byKey(const Key('assistant-mic')));
        await t.pump();
        speech.emit(command);
        await settle(t);
      } else {
        await say(t, command);
      }
      expect(find.text('2500'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
    });
  }
  testWidgets('AI can select the new capability for natural phrasing',
      (t) async {
    var calls = 0;
    await mount(t, interpret: (r) async {
      calls++;
      expect((r['capabilities'] as List).any((c) => c['id'] == 'gas.remaining'),
          isTrue);
      return const AiCommandPlan(
          'execute',
          [
            AiCommandStep('gas.remaining',
                'Oblicz zapas gazu butla 50 L manometr 60 bar palnik 10 L/min rezerwa 10 bar')
          ],
          '');
    });
    await say(t,
        'Mam pięćdziesięciolitrową butlę, na zegarze sześćdziesiąt barów, palnik bierze dziesięć litrów na minutę. Chcę zostawić dziesięć barów. Ile jeszcze popracuję?');
    expect(calls, 1);
    expect(find.text('250'), findsOneWidget);
  });
  for (final command in [
    'Co to zapas gazu?',
    'Nie obliczaj zapasu gazu',
    'Explain remaining cylinder gas'
  ]) {
    test('description or negation is not a calculation: $command', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say(command)).match?.skill.id, isNot('gas.remaining'));
    });
  }
}

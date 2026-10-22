import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/cone_layout_skill.dart';
import 'package:cut_list_app/domain/fitter/cone_assistant_input.dart';
import 'package:cut_list_app/domain/fitter/cone_development.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/utils/decimal_parse.dart';
import 'package:cut_list_app/widgets/readout.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command =
    'Oblicz stożek współosiowy duża 800 mm mała 300 mm wysokość 500 mm grubość 5 mm zewnętrzne';
const payload = <String, Object?>{
  'shape': 'concentric',
  'mode': 'height',
  'large_dia_mm': 800,
  'small_dia_mm': 300,
  'height_mm': 500,
  'thickness_mm': 5,
  'reference': 'outside',
  'parts': 1,
  'allowance_mm': 0,
};
void main() {
  useTestDatabase();
  for (final mode in ConeSizeMode.values) {
    for (final ref in DiameterRef.values) {
      test('complete native contract shares cone engine: $mode $ref', () {
        final p = {...payload, 'mode': mode.name, 'reference': ref.name}
          ..remove('height_mm');
        p[switch (mode) {
          ConeSizeMode.height => 'height_mm',
          ConeSizeMode.halfAngle => 'half_angle_deg',
          ConeSizeMode.slant => 'slant_mm'
        }] = mode == ConeSizeMode.halfAngle ? 30 : 500;
        final parsed = ConeAssistantInput.fromFields(p);
        expect(parsed.result.outerRadiusMm,
            computeCone(parsed.input)!.outerRadiusMm);
        expect(parsed.input.ref, ref);
      });
    }
  }
  test('contract rejects unknown, incomplete, mixed and invalid geometry', () {
    for (final p in [
      {...payload, 'shape': 'eccentric'},
      {...payload, 'password': 'hidden'},
      {...payload}..remove('reference'),
      {...payload}..remove('thickness_mm'),
      {...payload, 'half_angle_deg': 30},
      {...payload, 'large_dia_mm': '800'},
      {...payload, 'small_dia_mm': 900},
      {...payload, 'height_mm': double.nan},
      {...payload, 'thickness_mm': -1},
      {...payload, 'parts': 5},
      {...payload, 'parts': 2.0},
      {...payload, 'allowance_mm': 201},
    ]) {
      expect(() => ConeAssistantInput.fromFields(p), throwsFormatException);
    }
  });
  test('catalog PL/EN examples route to cone and emit valid native payloads',
      () async {
    for (final e in ConeLayoutSkill().examples.take(3)) {
      for (final text in [e.pl, e.en]) {
        final h = BrainHarness();
        addTearDown(h.timer.dispose);
        final r = await h.say(text);
        expect(r.match?.skill.id, 'cone.layout', reason: text);
        expect(r.result, isA<AnswerResult>(), reason: text);
        final result = r.result as AnswerResult;
        expect(
            ConeAssistantInput.fromFields(result.show!.fields)
                .result
                .outerRadiusMm,
            isPositive);
      }
    }
  });
  test('dialogue asks every missing geometry convention instead of defaulting',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final text in [
      'Oblicz rozwinięcie stożka',
      'współosiowy',
      '800 mm',
      '300 mm',
      '5 mm',
      'zewnętrzne'
    ]) {
      expect((await h.say(text)).result, isA<AskResult>(), reason: text);
    }
    final r = (await h.say('wysokość 500 mm')).result as AnswerResult;
    expect(r.show!.fields, payload);
  });
  test(
      'diameter wording is not a mean reference and unsupported shapes do not compute',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(
            'Stożek współosiowy średnica duża 800 mm średnica mała 300 mm wysokość 500 mm grubość 5 mm'))
        .result as AskResult;
    expect(r.slot, 'reference');
    final s = ConeLayoutSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final u = Utterance('Oblicz stożek przejście', lang: AppLanguage.pl);
    expect(await s.run(s.match(u, ctx)!, ctx), isA<FailedResult>());
  });
  test(
      'AI cannot rewrite numeric dimensions, invent conventions or infer half angle',
      () {
    final s = ConeLayoutSkill();
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    expect(
        s.acceptsProposal(u('Czy możesz $command'), u(command), ctx), isTrue);
    for (final original in [
      command.replaceFirst('800', '900'),
      command.replaceFirst('zewnętrzne', ''),
      command.replaceFirst('grubość 5 mm', ''),
      'Przetłumacz $command',
      'Nie oblicz $command'
    ]) {
      expect(s.acceptsProposal(u(original), u(command), ctx), isFalse,
          reason: original);
    }
  });
  for (final text in [
    command.replaceFirst('500 mm', '-500 mm'),
    command.replaceFirst('500 mm', '500 cali'),
    '$command naddatek 5',
    '$command części pięć',
    command.replaceFirst('wysokość 500 mm', 'kąt 30 stopni'),
    command.replaceFirst('800 mm', '200 mm'),
  ]) {
    test('ambiguous/invalid request asks before native change: $text',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'native command opens and computes cone; bad payload is atomic and popup hides inputs',
      (t) async {
    await mount(t,
        interpret: (_) async => throw StateError('Exact cone is local'));
    await say(t, command);
    final bridge = ToolBridge.instance;
    expect(bridge.current?.toolId, 'cone_layout');
    expect(bridge.inputFields('cone_layout'), payload);
    final result = ConeAssistantInput.fromFields(payload).result;
    await t.scrollUntilVisible(find.byKey(const ValueKey('cone-R')), 350,
        scrollable: find
            .descendant(
                of: find.byType(ConeLayoutPage),
                matching: find.byType(Scrollable))
            .first);
    final readout = t.widget<Readout>(find.byKey(const ValueKey('cone-R')));
    expect(parseDecimal(readout.value), closeTo(result.outerRadiusMm, .06));
    final handle = bridge.current!;
    expect(await handle.apply({...payload, 'half_angle_deg': 30}), isNotEmpty);
    expect(bridge.inputFields('cone_layout'), payload);
    final context = t.element(find.byType(ConeLayoutPage));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect(bridge.inputFields('cone_layout'), isNull);
    expect(await handle.apply({...payload, 'large_dia_mm': 900}), isNotEmpty);
    Navigator.of(context).pop();
    await dialog;
    await settle(t);
    expect(bridge.inputFields('cone_layout'), payload);
    expect(t.takeException(), isNull);
  });
  testWidgets('speech and millimetre payload preserve selected inch display',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        home: const ConeLayoutPage(),
        speech: speech,
        interpret: (_) async => throw StateError('Exact cone is local'));
    await t.ensureVisible(find.byKey(const ValueKey('cone-unit-in')));
    await t.tap(find.byKey(const ValueKey('cone-unit-in')));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit(command);
    await settle(t);
    expect(ToolBridge.instance.inputFields('cone_layout')!['large_dia_mm'],
        closeTo(800, 1e-9));
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('cone-unit-in')))
            .selected,
        isTrue);
    final field = t.widget<TextField>(find.byKey(const ValueKey('cone-D')));
    expect(parseDecimal(field.controller!.text), closeTo(800 / 25.4, 1e-9));
    expect(t.takeException(), isNull);
  });
  for (final wrongNumber in [false, true]) {
    testWidgets(
        'AI paraphrase reaches native cone only with unchanged values: wrong=$wrongNumber',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('cone.layout',
                  wrongNumber ? command.replaceFirst('800', '900') : command)
            ],
            '');
      });
      await say(t,
          'Przygotuj rozwinięcie leja współosiowego duża 800 mm mała 300 mm wysokość 500 mm grubość 5 mm zewnętrzne');
      expect(calls, 1);
      if (wrongNumber) {
        expect(ToolBridge.instance.current?.toolId, isNot('cone_layout'));
      } else {
        expect(ToolBridge.instance.inputFields('cone_layout'), payload);
      }
      expect(t.takeException(), isNull);
    });
  }
}

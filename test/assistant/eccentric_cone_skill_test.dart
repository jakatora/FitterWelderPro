import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/cone_layout_skill.dart';
import 'package:cut_list_app/domain/fitter/cone_development.dart';
import 'package:cut_list_app/domain/fitter/eccentric_cone_assistant_input.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/widgets/readout.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command =
    'Stożek mimośrodowy duża 600 mm mała 200 mm wysokość 400 mm grubość 4 mm zewnętrzne przesunięcie 100 mm';
const fields = <String, Object?>{
  'shape': 'eccentric',
  'mode': 'height',
  'large_dia_mm': 600,
  'small_dia_mm': 200,
  'height_mm': 400,
  'thickness_mm': 4,
  'reference': 'outside',
  'parts': 1,
  'divisions': 16,
  'vertical_side': false,
  'offset_mm': 100,
  'seam_on_short_side': true
};
void main() {
  useTestDatabase();
  for (final vertical in [false, true]) {
    for (final ref in DiameterRef.values) {
      for (final parts in [1, 2, 4]) {
        test('native eccentric contract: vertical=$vertical $ref parts=$parts',
            () {
          final p = {
            ...fields,
            'reference': ref.name,
            'vertical_side': vertical,
            'parts': parts
          };
          if (vertical) p.remove('offset_mm');
          final parsed = EccentricConeAssistantInput.fromFields(p);
          final actual = computeEccentricCone(parsed.input)!;
          expect(parsed.result.shortestGeneratorMm, actual.shortestGeneratorMm);
          expect(parsed.result.offsetMm, actual.offsetMm);
          expect(actual.parts, hasLength(parts));
        });
      }
    }
  }
  test('invalid complete payloads reject unsupported and ignored fields', () {
    for (final p in [
      {...fields, 'vertical_side': true},
      {...fields}..remove('offset_mm'),
      {...fields, 'vertical_side': 'false'},
      {...fields, 'divisions': 17},
      {...fields, 'parts': 3},
      {...fields, 'mode': 'slant'},
      {...fields, 'slant_mm': 500},
      {...fields, 'allowance_mm': 0},
      {...fields, 'offset_mm': -1},
      {...fields, 'offset_mm': double.infinity},
      {...fields, 'seam_on_short_side': 'long'},
      {...fields, 'small_dia_mm': 700},
    ]) {
      expect(() => EccentricConeAssistantInput.fromFields(p),
          throwsFormatException);
    }
  });
  test('bilingual examples use eccentric skill and valid native geometry',
      () async {
    for (final e in EccentricConeSkill().examples) {
      for (final text in [e.pl, e.en]) {
        final h = BrainHarness();
        addTearDown(h.timer.dispose);
        final r = await h.say(text);
        expect(r.match?.skill.id, 'cone.eccentric', reason: text);
        if (r.result is AnswerResult) {
          final p = (r.result as AnswerResult).show!.fields;
          expect(EccentricConeAssistantInput.fromFields(p).result.parts,
              isNotEmpty);
        } else {
          expect(r.result, isA<AskResult>(), reason: text);
        }
      }
    }
  });
  for (final variant in [
    command.replaceFirst('przesunięcie 100 mm', ''),
    '$command ścianka pionowa',
    command.replaceFirst('100 mm', '-100 mm'),
    '$command 3 części',
    '$command 17 podziałów',
    '$command szew',
    '$command naddatek 10 mm',
    command.replaceFirst('wysokość 400 mm', 'tworząca 450 mm')
  ]) {
    test('ambiguous variant asks before applying: $variant', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say(variant)).result, isA<AskResult>());
    });
  }
  test('missing or conflicting offset can be resolved in conversation',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final first = (await h.say(command.replaceFirst('przesunięcie 100 mm', '')))
        .result as AskResult;
    expect(first.slot, 'eccentric_offset');
    final answer = (await h.say('100 mm')).result as AnswerResult;
    expect(answer.show!.fields, fields);
    final conflict =
        (await h.say('$command ścianka pionowa')).result as AskResult;
    expect(conflict.slot, 'eccentric_offset');
    final vertical = (await h.say('ścianka pionowa')).result as AnswerResult;
    expect(
        EccentricConeAssistantInput.fromFields(vertical.show!.fields)
            .input
            .verticalSide,
        true);
    expect(vertical.show!.fields['offset_mm'], isNull);
  });
  testWidgets(
      'actual eccentric screen, atomic invalid application and dialog guard',
      (t) async {
    await mount(t,
        interpret: (_) async => throw StateError('Exact eccentric is native'));
    await say(t, command);
    final b = ToolBridge.instance;
    expect(b.inputFields('cone_layout'), fields);
    final native = EccentricConeAssistantInput.fromFields(fields).result;
    await t.scrollUntilVisible(find.byKey(const ValueKey('cone-ecc-rect')), 400,
        scrollable: find
            .descendant(
                of: find.byType(ConeLayoutPage),
                matching: find.byType(Scrollable))
            .first);
    final displayed =
        t.widget<Readout>(find.byKey(const ValueKey('cone-ecc-rect')));
    String num(double n) => n
        .toStringAsFixed(1)
        .replaceAll('.', ',')
        .replaceFirst(RegExp(r',0$'), '');
    expect(displayed.value,
        '${num(native.parts.first.widthMm)} × ${num(native.parts.first.heightMm)}');
    final handle = b.current!;
    expect(await handle.apply({...fields, 'allowance_mm': 10}), isNotEmpty);
    expect(b.inputFields('cone_layout'), fields);
    final context = t.element(find.byType(ConeLayoutPage));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect(await handle.apply({...fields, 'offset_mm': 200}), isNotEmpty);
    Navigator.of(context).pop();
    await dialog;
    await settle(t);
    expect(b.inputFields('cone_layout'), fields);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'mock speech selects vertical-side geometry and keeps inch display',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        home: const ConeLayoutPage(),
        speech: speech,
        interpret: (_) async => throw StateError('Exact eccentric is native'));
    await t.tap(find.byKey(const ValueKey('cone-unit-in')));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit(command.replaceFirst('przesunięcie 100 mm', 'ścianka pionowa'));
    await settle(t);
    final p = ToolBridge.instance.inputFields('cone_layout')!;
    expect(p['vertical_side'], true);
    expect(p.containsKey('offset_mm'), false);
    expect(p['large_dia_mm'], closeTo(600, 1e-9));
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('cone-unit-in')))
            .selected,
        true);
    expect(EccentricConeAssistantInput.fromFields(p).result.offsetMm,
        closeTo(200, 1e-9));
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets('AI paraphrase keeps offset: wrong=$wrong', (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('cone.eccentric',
                  wrong ? command.replaceFirst('100 mm', '150 mm') : command)
            ],
            '');
      });
      await say(
          t,
          command.replaceFirst('Stożek mimośrodowy',
              'Przygotuj rozwinięcie leja mimośrodowego'));
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          wrong ? isNull : fields);
      expect(t.takeException(), isNull);
    });
  }
}

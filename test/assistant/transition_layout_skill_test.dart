import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/skills/fitter_routes/transition_layout_skill.dart';
import 'package:cut_list_app/domain/fitter/cone_development.dart';
import 'package:cut_list_app/domain/fitter/transition_development.dart';
import 'package:cut_list_app/domain/fitter/transition_assistant_input.dart';
import 'package:cut_list_app/features/cone_layout/cone_layout_page.dart';
import 'package:cut_list_app/widgets/readout.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;

const command =
    'Oblicz przejście prostokąt koło bok A 600 mm bok B 400 mm średnica 300 mm wysokość 400 mm grubość 4 mm zewnętrzne przesunięcie X -50 mm przesunięcie Y 20 mm';
const fields = <String, Object?>{
  'shape': 'transition',
  'side_a_mm': 600,
  'side_b_mm': 400,
  'diameter_mm': 300,
  'height_mm': 400,
  'thickness_mm': 4,
  'reference': 'outside',
  'offset_x_mm': -50,
  'offset_y_mm': 20,
  'parts': 1,
  'divisions': 16,
  'seam': 'sideB'
};
void main() {
  useTestDatabase();
  for (final ref in DiameterRef.values) {
    for (final seam in TransitionSeam.values) {
      for (final parts in [1, 2, 4]) {
        test('transition native geometry: $ref $seam parts=$parts', () {
          final p = {
            ...fields,
            'reference': ref.name,
            'seam': seam.name,
            'parts': parts
          };
          final r = TransitionAssistantInput.fromFields(p);
          final native = computeTransition(r.input)!;
          expect(r.result.topEdgeMm, native.topEdgeMm);
          expect(r.result.parts, hasLength(parts));
          expect(r.input.offsetXMm, -50);
        });
      }
    }
  }
  test('strict native payload rejects incomplete, invalid and foreign fields',
      () {
    for (final p in [
      {...fields}..remove('offset_y_mm'),
      {...fields, 'offset_x_mm': double.nan},
      {...fields, 'side_a_mm': -600},
      {...fields, 'seam': 'short'},
      {...fields, 'parts': 3},
      {...fields, 'divisions': 20},
      {...fields, 'allowance_mm': 0},
      {...fields, 'large_dia_mm': 600},
      {...fields, 'vertical_side': false},
      {...fields, 'thickness_mm': 200},
      {...fields, 'shape': 'eccentric'}
    ]) {
      expect(
          () => TransitionAssistantInput.fromFields(p), throwsFormatException);
    }
  });
  test('bilingual transition examples preserve signed offsets and native shape',
      () async {
    for (final entry in TransitionLayoutSkill().examples.asMap().entries) {
      final e = entry.value;
      for (final text in [e.pl, e.en]) {
        final h = BrainHarness();
        addTearDown(h.timer.dispose);
        final r = await h.say(text);
        expect(r.match?.skill.id, 'transition.layout', reason: text);
        if (const [0, 1, 2, 4].contains(entry.key)) {
          expect(r.result, isA<AnswerResult>(), reason: text);
        }
        if (r.result is AnswerResult) {
          expect(
              TransitionAssistantInput.fromFields(
                      (r.result as AnswerResult).show!.fields)
                  .result
                  .parts,
              isNotEmpty);
        } else {
          expect(r.result, isA<AskResult>(), reason: text);
        }
      }
    }
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(command)).result as AnswerResult;
    expect(r.show!.fields, fields);
  });
  test('conversation asks missing dimensions, convention and positioning',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final text in [
      'Oblicz przejście prostokąt koło',
      '600 mm',
      '400 mm',
      '300 mm',
      '400 mm',
      '4 mm',
      'zewnętrzne'
    ]) {
      expect((await h.say(text)).result, isA<AskResult>(), reason: text);
    }
    final r = (await h.say('centryczne')).result as AnswerResult;
    expect(r.show!.fields, {...fields, 'offset_x_mm': 0, 'offset_y_mm': 0});
  });
  for (final bad in [
    command.replaceFirst('600 mm', '-600 mm'),
    command.replaceFirst('przesunięcie Y 20 mm', ''),
    '$command centryczne',
    '$command naddatek 10 mm',
    '$command 3 części',
    '$command 20 podziałów',
    '$command szew',
    command.replaceFirst('600 mm', '600 cali')
  ]) {
    test('invalid/ambiguous geometry asks before applying: $bad', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say(bad)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'transition command opens actual native development with atomic and dialog guards',
      (t) async {
    await mount(t,
        interpret: (_) async => throw StateError('Exact transition is native'));
    await say(t, command);
    final b = ToolBridge.instance;
    expect(b.inputFields('cone_layout'), fields);
    final native = TransitionAssistantInput.fromFields(fields).result;
    await t.scrollUntilVisible(find.byKey(const ValueKey('tr-rect')), 400,
        scrollable: find
            .descendant(
                of: find.byType(ConeLayoutPage),
                matching: find.byType(Scrollable))
            .first);
    String num(double n) => n
        .toStringAsFixed(1)
        .replaceAll('.', ',')
        .replaceFirst(RegExp(r',0$'), '');
    final displayed = t.widget<Readout>(find.byKey(const ValueKey('tr-rect')));
    expect(displayed.value,
        '${num(native.parts.first.pattern.widthMm)} × ${num(native.parts.first.pattern.heightMm)}');
    final handle = b.current!;
    expect(await handle.apply({...fields, 'large_dia_mm': 600}), isNotEmpty);
    expect(b.inputFields('cone_layout'), fields);
    final context = t.element(find.byType(ConeLayoutPage));
    final dialog = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Hold')));
    await t.pumpAndSettle();
    expect(await handle.apply({...fields, 'offset_x_mm': 50}), isNotEmpty);
    Navigator.of(context).pop();
    await dialog;
    await settle(t);
    expect(b.inputFields('cone_layout'), fields);
    expect(t.takeException(), isNull);
  });
  testWidgets('spoken negative offset remains negative in inch display',
      (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        home: const ConeLayoutPage(),
        speech: speech,
        interpret: (_) async => throw StateError('Exact transition is native'));
    await t.tap(find.byKey(const ValueKey('cone-unit-in')));
    await settle(t);
    await t.tap(find.byKey(const Key('assistant-mic')));
    await settle(t);
    speech.emit(command.replaceFirst('-50', 'minus 50'));
    await settle(t);
    expect(ToolBridge.instance.inputFields('cone_layout')!['offset_x_mm'],
        closeTo(-50, 1e-9));
    expect(
        t
            .widget<ChoiceChip>(find.byKey(const ValueKey('cone-unit-in')))
            .selected,
        true);
    expect(t.takeException(), isNull);
  });
  for (final wrong in [false, true]) {
    testWidgets('AI paraphrase cannot reverse offset direction: wrong=$wrong',
        (t) async {
      var calls = 0;
      await mount(t, interpret: (_) async {
        calls++;
        return AiCommandPlan(
            'execute',
            [
              AiCommandStep('transition.layout',
                  wrong ? command.replaceFirst('-50', '50') : command)
            ],
            '');
      });
      await say(
          t,
          command.replaceFirst('Oblicz przejście prostokąt koło',
              'Przygotuj rozwinięcie prostokąta do koła'));
      expect(calls, 1);
      expect(ToolBridge.instance.inputFields('cone_layout'),
          wrong ? isNull : fields);
      expect(t.takeException(), isNull);
    });
  }
}

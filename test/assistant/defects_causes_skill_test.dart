import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/defects/defect_advice.dart';
import 'package:cut_list_app/features/weld_defects/weld_defects_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test(
      'causes, checks, repair and disclaimer come from the same domain as the screen',
      () async {
    final r =
        (await BrainHarness().say('Przyczyny porowatości MAG stal węglowa'))
            .result as AnswerResult;
    final a = defectAdvice(weldDefectById('porosity')!, DefectProcess.mag135,
        material: DefectMaterial.carbon)!;
    expect(r.answer.text.pl, buildDefectShareText(a, en: false));
    expect(r.answer.text.en, buildDefectShareText(a, en: true));
    expect(r.answer.source!.pl, contains('ISO 6520-1'));
    expect(r.answer.lines.any((v) => v.value.contains('https://')), isTrue);
    expect(r.show!.fields, {
      'defect_id': 'porosity',
      'process': 'mag135',
      'material': 'carbon',
      'position': null
    });
  });
  test(
      'missing process and material are collected, without guessing from current',
      () async {
    final h = BrainHarness();
    expect((await h.say('Dlaczego pojawia się porowatość przy 141 A')).result,
        isA<AskResult>());
    expect(h.brain.pending!.slot, 'process');
    await h.say('MAG');
    expect(h.brain.pending!.slot, 'material');
    final r = (await h.say('stal węglowa')).result as AnswerResult;
    expect(r.show!.fields['process'], 'mag135');
    expect(r.show!.fields['material'], 'carbon');
  });
  test('crack types require choosing the actual defect before advice',
      () async {
    final h = BrainHarness();
    final r =
        (await h.say('Przyczyny pęknięć MAG stal węglowa')).result as AskResult;
    expect(r.slot, 'query');
    expect(r.choices.length, greaterThan(1));
    final second = (await h.say('pęknięcie zimne')).result as AnswerResult;
    expect(second.show!.fields['defect_id'], 'crack_cold');
  });
  test('3041 remains an ISO imperfection number, never a material grade',
      () async {
    final r = (await BrainHarness().say('Przyczyny 3041 TIG stal nierdzewna'))
        .result as AnswerResult;
    expect(r.show!.fields['defect_id'], 'tungsten');
  });
  test(
      'unsupported laser process records a capability gap, not invented causes',
      () async {
    final r =
        (await BrainHarness().say('Przyczyny porowatości laser stal węglowa'))
            .result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test('uncovered material is reported rather than silently changed', () async {
    final h = BrainHarness();
    final r = (await h.say('Przyczyny porowatości MIG stal nierdzewna')).result
        as FailedResult;
    expect(r.reportMissingCapability, isTrue);
    final answer = (await h.say('Przyczyny porowatości MIG aluminium')).result
        as AnswerResult;
    expect(answer.show!.fields['material'], 'aluminium');
    expect(answer.show!.fields['process'], 'mig131');
  });
  test('FCAW asks gas-shielded or self-shielded instead of choosing 136',
      () async {
    final r =
        (await BrainHarness().say('Przyczyny porowatości FCAW stal węglowa'))
            .result as AskResult;
    expect(r.slot, 'process');
  });
  test(
      'unsupported explicit process code is reported without losing the defect',
      () async {
    final r = (await BrainHarness()
            .say('Przyczyny porowatości proces 137 stal węglowa'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test('lettered H-L045 maps to the same pipe-up position as the screen',
      () async {
    final r = (await BrainHarness().say(
            'Przyczyny porowatości MAG stal węglowa pozycja ha el zero czterdzieści pięć',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['position'], 'pipeUp');
  });
  test('position filters come from the domain and can be corrected', () async {
    final h = BrainHarness();
    final r = (await h.say('Przyczyny podtopienia MMA stal węglowa PF')).result
        as AnswerResult;
    expect(r.show!.fields['position'], 'pf');
    expect(
        r.answer.text.pl,
        buildDefectShareText(
            defectAdvice(
                weldDefectById(r.show!.fields['defect_id']! as String)!,
                DefectProcess.mma111,
                material: DefectMaterial.carbon,
                position: DefectPosition.pf)!,
            en: false));
  });
  test(
      'explaining causes still answers locally; unrelated why question is not hijacked',
      () async {
    final r = await BrainHarness()
        .say('Wyjaśnij przyczyny porowatości MAG stal węglowa');
    expect(r.match?.skill.id, 'defects.causes');
    expect(r.result, isA<AnswerResult>());
    expect(
        (await BrainHarness().say('Dlaczego nie działa logowanie'))
            .match
            ?.skill
            .id,
        isNot('defects.causes'));
  });
  test('each crack choice resolves its type even when ISO numbers are shared',
      () async {
    final initial =
        (await BrainHarness().say('Przyczyny pęknięć MAG stal węglowa')).result
            as AskResult;
    for (final choice in initial.choices) {
      final h = BrainHarness();
      await h.say('Przyczyny pęknięć MAG stal węglowa');
      final r = (await h.say(choice.utterance)).result;
      expect(r, isA<AnswerResult>(), reason: choice.utterance);
      expect((r as AnswerResult).answer.text.pl, contains(choice.label.pl));
    }
  });
  test('spoken current and lettered position share the common speech tokenizer',
      () async {
    final r = (await BrainHarness().say(
            'Przyczyny porowatości MAG stal węglowa przy sto czterdzieści jeden amperów pozycja pe ef',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['process'], 'mag135');
    expect(r.show!.fields['position'], 'pf');
  });
  test(
      'a bare defect plus process/current asks for advice instead of saving parameters',
      () async {
    final h = BrainHarness();
    final r = await h.say('porowatość TIG 60 A');
    expect(r.match?.skill.id, 'defects.causes');
    expect(r.result, isA<AskResult>());
    expect(
        h.brain.recognizesCalculation(
            Utterance('porowatość TIG 60 A', lang: AppLanguage.pl), h.ctx),
        isTrue);
    expect(h.actions.savedParams, isEmpty);
  });
  testWidgets(
      'tool handle applies the exact diagnosis filters atomically without ticking checklist',
      (tester) async {
    ToolBridge.reset();
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: WeldDefectsPage())));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    final fields = {
      'defect_id': 'porosity',
      'process': 'mag135',
      'material': 'carbon',
      'position': 'pf'
    };
    expect(await handle.apply(fields), isEmpty);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('defects-selected')), findsOneWidget);
    expect(find.textContaining('Porowatość'), findsWidgets);
    expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((v) => !v.value!),
        isTrue);
    expect(await handle.apply({...fields, 'material': 'aluminium'}),
        fields.keys.toSet());
    await tester.pumpAndSettle();
    expect(find.textContaining('Porowatość'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

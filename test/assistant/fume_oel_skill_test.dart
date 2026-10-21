import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/fume/fume_hazards.dart';
import 'package:cut_list_app/domain/fume/fume_reference.dart';
import 'package:cut_list_app/domain/fume/fume_inputs.dart';
import 'package:cut_list_app/domain/fume/fume_assessment.dart';
import 'package:cut_list_app/features/fume/fume_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final agent in FumeAgent.values) {
    test(
        'table choice ${agent.name} uses shared source without measuring exposure',
        () async {
      final h = BrainHarness();
      final q = (await h.say('NDS')).result as AskResult;
      expect(q.slot, 'agent');
      final result = (await h.say(q.choices
              .firstWhere((c) => c.label.pl == agent.namePl)
              .utterance))
          .result;
      if (agent.nds == null) {
        final missing = result as FailedResult;
        expect(missing.reportMissingCapability, isTrue);
        expect(missing.message.en, contains('check the current NDS list'));
      } else {
        final a = result as AnswerResult;
        expect(a.answer.text.pl, fumeOelReference(agent, en: false));
        expect(a.show!.fields, {'reference_agent': agent.name});
      }
    });
  }
  test('inflected Polish names identify the exact agent without prompting',
      () async {
    for (final e in {
      'NDS tlenku cynku': 'znO',
      'NDS tlenków żelaza': 'feOx',
      'NDS tlenku węgla': 'co',
      'NDS ditlenku azotu': 'nox',
      'NDS chromu VI': 'crVI',
      'NDSCh tlenku cynku': 'znO'
    }.entries) {
      final a = (await BrainHarness().say(e.key)).result as AnswerResult;
      expect(a.show!.fields['reference_agent'], e.value);
    }
  });
  test('cadmium keeps the transitional provision and lead its dated change',
      () async {
    final c = (await BrainHarness().say('NDS kadmu')).result as AnswerResult;
    expect(c.answer.text.pl, contains('0,004'));
    expect(c.answer.text.pl, contains('11.07.2027'));
    final p = (await BrainHarness().say('NDS ołowiu')).result as AnswerResult;
    expect(p.answer.text.pl, contains('9.04.2026'));
  });
  test('chromium without valence asks instead of assuming hexavalent',
      () async {
    final h = BrainHarness();
    expect((await h.say('NDS chromu')).result, isA<AskResult>());
    final a =
        (await h.say('chromu sześć', byVoice: true)).result as AnswerResult;
    expect(a.show!.fields['reference_agent'], 'crVI');
  });
  test(
      'body metal and outside jurisdictions never inherit fume-compound limits',
      () async {
    for (final q in [
      'NDS nikiel metaliczny',
      'NDS Cr(III)',
      'NDS cynku',
      'NDS żelaza',
      'OSHA PEL manganese',
      'NDS manganu w 2025',
      'NDS berylu',
      'NDS tlenku azotu w górnictwie'
    ]) {
      final r = (await BrainHarness().say(q)).result;
      expect(r is AskResult || r is FailedResult, isTrue, reason: q);
    }
    final h = BrainHarness();
    await h.say('NDS');
    expect(
        ((await h.say('nikiel metaliczny')).result as FailedResult)
            .reportMissingCapability,
        isTrue);
  });
  test('inflected metallic nickel is not replaced by nickel compounds',
      () async {
    expect(
        ((await BrainHarness().say('NDS niklu metalicznego')).result
                as FailedResult)
            .reportMissingCapability,
        isTrue);
  });
  test('CO chemical and Polish what are distinguished; CO2 is not CO',
      () async {
    expect(
        ((await BrainHarness().say('co oznacza NDS manganu')).result
                as AnswerResult)
            .show!
            .fields['reference_agent'],
        'mn');
    expect(
        ((await BrainHarness().say('NDS CO')).result as AnswerResult)
            .show!
            .fields['reference_agent'],
        'co');
    expect((await BrainHarness().say('NDS dwutlenku węgla')).result,
        isA<AskResult>());
  });
  test('a confused Polish follow-up co does not select carbon monoxide',
      () async {
    final h = BrainHarness();
    await h.say('NDS');
    expect((await h.say('co?')).result, isA<AskResult>());
  });
  test('two agents ask for selection and absent STEL is not zero', () async {
    final h = BrainHarness();
    expect((await h.say('NDS manganu i kadmu')).result, isA<AskResult>());
    final a = (await h.say('mangan')).result as AnswerResult;
    expect(a.answer.text.pl, contains('nie podaje NDSCh'));
    expect(a.answer.text.pl, contains('frakcja respirabilna'));
  });
  test('an exposure measurement requires its own workflow', () async {
    expect(
        ((await BrainHarness().say('porównaj pomiar manganu 0,1 mg/m3 z NDS'))
                .result as FailedResult)
            .reportMissingCapability,
        isTrue);
  });
  testWidgets('reference preserves entered flow, material and saved input',
      (t) async {
    ToolBridge.reset();
    final saved = encodeFumeInputs(const FumeInputs(
        material: FumeMaterial.carbonSteel,
        process: FumeProcess.mma,
        lev: FumeLevStatus.present,
        flow: 1234,
        diameter: 300));
    SharedPreferences.setMockInitialValues({kFumeInputsPrefsKey: saved});
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: FumePage())));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(kFumeInputsPrefsKey);
    expect(before, saved);
    final flow = find.byKey(const ValueKey('fume-flow'));
    await t.ensureVisible(flow);
    await t.enterText(flow, '1357');
    await t.pumpAndSettle();
    final typed = prefs.getString(kFumeInputsPrefsKey);
    final flowController = t
        .widget<EditableText>(
            find.descendant(of: flow, matching: find.byType(EditableText)))
        .controller;
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({'reference_agent': 'mn'}), isEmpty);
    await t.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('fume-assistant-reference')), findsOneWidget);
    expect(prefs.getString(kFumeInputsPrefsKey), typed);
    expect(flowController.text, '1357');
    expect(find.byKey(const ValueKey('fume-hazards-prompt')), findsNothing);
    expect(
        await handle.apply({'reference_agent': 'cd', 'material': 'stainless'}),
        isNotEmpty);
    await t.pumpAndSettle();
    expect(find.textContaining('Mangan (Mn)'), findsWidgets);
    expect(find.textContaining('Kadm (Cd)'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    ToolBridge.reset();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/command_words.dart';
import 'package:cut_list_app/domain/welding/power_source.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  const sizing =
      'dobierz przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V';
  test('check and size are explicit calculations, including their negations',
      () {
    for (final text in [
      'Sprawdź przewody',
      'Check welding cables',
      'Size welding cables'
    ]) {
      expect(
          requestsCalculation(Utterance(text, lang: AppLanguage.pl)), isTrue);
    }
    for (final text in [
      'nie sprawdzaj przewodów',
      'do not check welding cables',
      "don't size welding cables"
    ]) {
      expect(isNegatedCommand(Utterance(text, lang: AppLanguage.pl)), isTrue);
      expect(
          requestsCalculation(Utterance(text, lang: AppLanguage.pl)), isFalse);
    }
  });
  test('cable duty cycle is not a power source plate calculation', () async {
    final result =
        await BrainHarness(activeToolId: 'power_source', onHome: false).say(
            'Sprawdź przewody spawalniczy 25 m masowy 25 m 200 A cykl pracy 60% otoczenie 30 C próg 4 V przekrój 35 mm²');
    expect(result.match!.skill.id, 'power.cable');
    expect(result.result, isA<AnswerResult>());
  });
  test('check uses the exact domain values and both voltage/heat verdicts',
      () async {
    final r = (await BrainHarness().say(
            'sprawdź przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V przekrój 35 mm²'))
        .result as AnswerResult;
    final check = checkCable(const CableInput(
        currentA: 200,
        weldLeadM: 25,
        returnLeadM: 25,
        sectionMm2: 35,
        dutyPct: 60,
        ambientC: 30,
        dropLimitV: 4))!;
    expect(r.answer.text.pl,
        contains(powerSourceShareText(en: false, cable: check)));
    expect(r.show!.fields['section_mm2'], 35);
    expect(r.show!.fields['cable_mode'], 'check');
  });
  test('size selects from full loop and never assumes a return length',
      () async {
    final r = (await BrainHarness().say(sizing)).result as AnswerResult;
    expect(r.show!.fields['cable_mode'], 'size');
    expect(r.show!.fields.containsKey('section_mm2'), isFalse);
    expect(r.answer.text.pl, contains('70 mm²'));
    expect(r.answer.text.pl, contains('25 + 25 = 50 m'));
  });
  test('dialogue collects every parameter with units', () async {
    final h = BrainHarness();
    expect(
        (await h.say('dobierz przewody spawalnicze')).result, isA<AskResult>());
    expect((await h.say('200 A')).result, isA<AskResult>());
    expect((await h.say('25 m')).result, isA<AskResult>());
    expect((await h.say('25 m')).result, isA<AskResult>());
    expect((await h.say('60 procent')).result, isA<AskResult>());
    expect((await h.say('30 C')).result, isA<AskResult>());
    final r = (await h.say('4 V')).result as AnswerResult;
    expect(r.show!.fields['return_lead_m'], 25);
  });
  test('a loop length is not divided into guessed individual leads', () async {
    final r = (await BrainHarness().say(
            'dobierz przewody spawalnicze pętla 50 m 200 A 60% otoczenie 30 C próg 4 V'))
        .result as AskResult;
    expect(r.slot, 'weld_lead_m');
  });
  test('ambient is conservatively rounded to a named upper band', () async {
    final r = (await BrainHarness().say(sizing.replaceFirst('30 C', '33 C')))
        .result as AnswerResult;
    expect(r.show!.fields['ambient_c'], 35);
    expect(r.answer.text.pl, contains('przedział temperatury do 35°C'));
  });
  test('spoken inputs include squared millimetres', () async {
    final r = (await BrainHarness().say(
            'sprawdź przewody spawalniczy dziesięć metrów masowy dziesięć metrów sto amperów sto procent otoczenie dwadzieścia pięć stopni Celsjusza próg dwa wolty przekrój dwadzieścia pięć milimetrów kwadratowych',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['section_mm2'], 25);
    expect(r.show!.fields['weld_lead_m'], 10);
  });
  test('no feasible size is a result, not an invented cable recommendation',
      () async {
    final r = (await BrainHarness().say(
            'dobierz przewody spawalniczy 500 m masowy 500 m 1500 A 100% otoczenie 50 C próg 0,5 V'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('95 mm²'));
    expect(r.answer.text.pl, contains('żaden do 95 mm²'));
  });
  for (final material in ['aluminium', 'AC']) {
    test('unsupported model is a capability report: $material', () async {
      final r = (await BrainHarness().say('$sizing $material')).result
          as FailedResult;
      expect(r.reportMissingCapability, isTrue);
    });
  }
  test('aluminium workpiece does not turn copper leads into aluminium leads',
      () async {
    expect((await BrainHarness().say('$sizing spawam aluminium MIG DC')).result,
        isA<AnswerResult>());
    expect(
        (await BrainHarness()
                .say('$sizing spawam aluminium ale przewody aluminiowe'))
            .result,
        isA<FailedResult>());
  });
  for (final text in [
    sizing.replaceFirst('200 A', 'minus 200 A'),
    sizing.replaceFirst('25 m', 'minus 25 m'),
    sizing.replaceFirst('60%', '101%'),
    sizing.replaceFirst('30 C', '51 C'),
    sizing.replaceFirst('4 V', '0,1 V'),
    '$sizing 300 A',
    '$sizing 100%',
    'sprawdź przewody spawalniczy 25 m masowy 25 m 200 A 60% otoczenie 30 C próg 4 V przekrój 40 mm²',
  ]) {
    test('invalid inputs ask without applying: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'page selects sized section and removes a stale section on no solution',
      (tester) async {
    final saved = encodePlate(const [PlatePoint(200, 60)]);
    SharedPreferences.setMockInitialValues({kPowerSourcePlatePrefsKey: saved});
    await tester.binding.setSurfaceSize(const Size(1000, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(sizing, byVoice: true)).result
        as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'power_source');
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('ps-section-70')))
            .selected,
        isTrue);
    expect(await handle.apply({...r.show!.fields, 'plate': []}), isNotEmpty);
    expect(await handle.apply({...r.show!.fields, 'return_lead_m': -1}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('ps-section-70')))
            .selected,
        isTrue);
    expect(
        await handle.apply({
          ...r.show!.fields,
          'weld_current_a': 1500,
          'weld_lead_m': 500,
          'return_lead_m': 500,
          'duty_pct': 100,
          'ambient_c': 50,
          'drop_limit_v': .5
        }),
        isEmpty);
    await tester.pumpAndSettle();
    for (final s in kCableSectionsMm2) {
      expect(
          tester
              .widget<ChoiceChip>(find.byKey(ValueKey('ps-section-$s')))
              .selected,
          isFalse);
    }
    expect(
        (await SharedPreferences.getInstance())
            .getString(kPowerSourcePlatePrefsKey),
        saved);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

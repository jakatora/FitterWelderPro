import 'dart:async';
import 'package:flutter/material.dart' show Key, TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/pressure_conversion.dart';
import 'package:cut_list_app/screens/welder_tools_screen.dart';
import '../support/test_database.dart';
import 'ai_chat_execution_test.dart' show mount, FixtureSpeech;
import 'global_pipe_slope_flow_test.dart' show say, settle;
import 'support/assistant_test_support.dart';

const screen = WelderToolsScreen(initialTab: WelderToolsScreen.tabPressure);
void main() {
  useTestDatabase();
  testWidgets(
      'extended conversion opens and fills the lazy pressure tab from another tool',
      (t) async {
    await mount(t,
        interpret: (_) async => throw StateError('Exact conversion is local'));
    await say(t, 'Przelicz 10 mbar na Pa');
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {'tab': 'pressure', 'value': 10, 'from': 'mbar'});
    expect(find.text('1000'), findsOneWidget);
  });
  test('pressure domain uses conventional Pa and water-column factors', () {
    expect(convertWelderPressure(1, 'bar')!['Pa'], closeTo(100000, 1e-9));
    expect(convertWelderPressure(1, 'inH₂O')!['mmH₂O'], closeTo(25.4, 1e-10));
    expect(convertWelderPressure(1, 'kgf/cm²')!['Pa'], closeTo(98066.5, 1e-8));
    expect(convertWelderPressure(10, 'mbar')!['mmH₂O'],
        closeTo(1000 / 9.80665, 1e-10));
    expect(convertWelderPressure(0, 'bar')!.values, everyElement(0));
    for (final bad in [
      {'value': -1},
      {'value': double.nan},
      {'value': 1e308},
      {'from': 'barg'},
      {'from': 'unrecognized'},
      {'action': 'start'},
      {'value': null},
    ]) {
      expect(
          () => PressureCalculatorInput.fromFields(
              {'tab': 'pressure', 'value': 1, 'from': 'bar', ...bad}),
          throwsFormatException);
    }
  });
  for (final command in [
    'Przelicz 10 mbar na mmH₂O',
    'Convert 1 inH2O to Pa',
    'Przelicz 1 kgf/cm² na Pa',
    'Przelicz 1000 Pa na bar',
    'Przelicz 10 mbar na mm słupa wody',
    'Przelicz 10 milibarów na milimetry słupa wody',
    'Przelicz 1 cal słupa wody na paskale',
    'Convert 1 inch of water to Pa',
  ]) {
    test(
        'routes extended pressure units to the real welding converter: $command',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final r = (await h.say(command)).result as AnswerResult;
      expect(r.show!.toolId, 'welder_calculators');
      expect(r.show!.fields['tab'], 'pressure');
      expect(PressureCalculatorInput.fromFields(r.show!.fields).results,
          isNotEmpty);
    });
  }
  test(
      'negative literal and relational conversion cannot silently use a positive literal',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect((await h.say('Przelicz -5 bar na Pa')).result,
        isNot(isA<AnswerResult>()));
    final u = Utterance('Przelicz połowę 10 bar na Pa', lang: h.lang);
    expect(h.brain.recognizesLocalRequest(u, h.ctx), isFalse);
    expect((await h.brain.handle(u, h.ctx)).result, isNot(isA<AnswerResult>()));
  });
  testWidgets(
      'common pressure command fills native value and unit; invalid payload is atomic',
      (t) async {
    await mount(t,
        home: screen,
        interpret: (_) async => throw StateError('Exact command is local'));
    await say(t, 'Przelicz 100 kPa na bar');
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {'tab': 'pressure', 'value': 100, 'from': 'kPa'});
    expect(find.text('1.0000'), findsOneWidget);
    final old = ToolBridge.instance.inputFields('welder_calculators');
    expect(
        await ToolBridge.instance.current!
            .apply({'tab': 'pressure', 'value': -1, 'from': 'bar'}),
        isNotEmpty);
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators'), old);
    await say(t, 'Przelicz 10 mbar na mmH₂O');
    expect(
        ToolBridge.instance.inputFields('welder_calculators')!['from'], 'mbar');
    expect(find.text('101.9716'), findsOneWidget);
  });
  testWidgets('AI edits use manually updated pressure inputs', (t) async {
    var calls = 0;
    await mount(t, home: screen, interpret: (r) async {
      calls++;
      expect((r['context'] as Map)['inputs'],
          {'tab': 'pressure', 'value': 40, 'from': 'mbar'});
      return const AiCommandPlan('execute',
          [AiCommandStep('units.convert', 'Przelicz 20 mbar na Pa')], '');
    });
    await say(t, 'Przelicz 10 mbar na Pa');
    await t.enterText(find.byType(TextField).hitTestable().first, '40');
    await settle(t);
    await say(t, 'Przelicz połowę aktualnej wartości na Pa');
    expect(calls, 1);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {'tab': 'pressure', 'value': 20, 'from': 'mbar'});
    expect(find.text('2000'), findsOneWidget);
  });
  testWidgets('late AI cannot overwrite a manual pressure change', (t) async {
    final pending = Completer<AiCommandPlan>();
    await mount(t, home: screen, interpret: (_) => pending.future);
    await say(t, 'Przelicz 10 mbar na Pa');
    await t.enterText(find.byKey(const Key('assistant-command')),
        'Przelicz połowę aktualnej wartości na Pa');
    await t.tap(find.byKey(const Key('assistant-go')));
    await t.pump(const Duration(milliseconds: 200));
    expect(
        await ToolBridge.instance.current!
            .apply({'tab': 'pressure', 'value': 30, 'from': 'bar'}),
        isEmpty);
    pending.complete(const AiCommandPlan('execute',
        [AiCommandStep('units.convert', 'Przelicz 5 mbar na Pa')], ''));
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {'tab': 'pressure', 'value': 30, 'from': 'bar'});
    expect(find.textContaining('dane zmieniły się'), findsOneWidget);
  });
  testWidgets('mock speech converts pressure through the real form', (t) async {
    final speech = FixtureSpeech();
    await mount(t,
        home: screen,
        speech: speech,
        interpret: (_) async => throw StateError('Exact speech is local'));
    await t.tap(find.byKey(const Key('assistant-mic')));
    await t.pump();
    speech.emit('Przelicz tysiąc paskali na bar');
    await settle(t);
    expect(ToolBridge.instance.inputFields('welder_calculators'),
        {'tab': 'pressure', 'value': 1000, 'from': 'Pa'});
    expect(find.text('0.0100'), findsWidgets);
  });
}

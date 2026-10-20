import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/shade_number.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final current in [15, 81, 83, 111, 141, 160, 2000]) {
    test('TIG current $current never becomes a process code', () async {
      final r = (await BrainHarness().say('dobierz filtr TIG $current A'))
          .result as AnswerResult;
      final advice = computeShade(
          ShadeInput(process: ShadeProcess.tig, currentA: current.toDouble()))!;
      expect(r.answer.text.pl, shadeShareText(advice, en: false));
      expect(r.answer.text.en, shadeShareText(advice, en: true));
      expect(
          r.show!.fields, {'process': 'tig', 'current_a': current.toDouble()});
    });
  }
  test('MIG dialogue explicitly asks the metal family', () async {
    final h = BrainHarness();
    expect((await h.say('filtr MIG 200 A')).result, isA<AskResult>());
    final r = (await h.say('aluminium')).result as AnswerResult;
    expect(r.show!.fields['process'], 'migLight');
  });
  test('explicit process code is supported without interpreting current',
      () async {
    final r = (await BrainHarness().say('filtr proces 141 100 A')).result
        as AnswerResult;
    expect(r.show!.fields['process'], 'tig');
  });
  test('gas flow converts minutes to hours and uses both tables', () async {
    final r = (await BrainHarness()
            .say('filtr cięcie tlenowe przepływ 25 l/min grubość 20 mm'))
        .result as AnswerResult;
    expect(r.show!.fields,
        {'process': 'oxyCutting', 'flow_lh': 1500.0, 'thickness_mm': 20.0});
    expect(r.answer.text.pl, contains('EN 169:'));
    expect(r.answer.text.pl, contains('minimum OSHA'));
  });
  test('gas flow alone never invents a thickness or OSHA minimum', () async {
    final r =
        (await BrainHarness().say('filtr spawanie gazowe przepływ 100 l/h'))
            .result as AnswerResult;
    expect(r.show!.fields.containsKey('thickness_mm'), isFalse);
    expect(r.answer.text.pl, isNot(contains('minimum OSHA')));
  });
  test('spoken numbers and flow time units work together', () async {
    final r = (await BrainHarness().say(
            'filtr spawanie gazowe przepływ sto litrów na godzinę',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['flow_lh'], 100);
  });
  for (final text in [
    'filtr TIG 100',
    'filtr TIG minus 100 A',
    'filtr TIG 2001 A',
    'filtr TIG 100 A 200 A',
    'filtr TIG MAG 100 A',
    'filtr cięcie tlenowe przepływ 100 litrów',
    'filtr cięcie tlenowe przepływ minus 100 l/h',
    'filtr cięcie tlenowe przepływ 100 l/h grubość minus 5 mm',
    'filtr cięcie tlenowe przepływ 100 l/h przepływ 200 l/h',
  ]) {
    test('invalid input never applies: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets('actual shade page applies atomically and clears old gas inputs',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(
            'filtr cięcie tlenowe przepływ 1500 l/h grubość 20 mm',
            byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'shade');
    expect(await handle.apply({'process': 'tig', 'current_a': -5}), isNotEmpty);
    await tester.pumpAndSettle();
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller!.text)
        .toList();
    expect(values, contains('1500.0'));
    expect(values, contains('20.0'));
    expect(await handle.apply({'process': 'tig', 'current_a': 100}), isEmpty);
    await tester.pumpAndSettle();
    final nextValues = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller!.text)
        .toList();
    expect(nextValues, contains('100'));
    expect(nextValues, isNot(contains('1500.0')));
    expect(nextValues, isNot(contains('20.0')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

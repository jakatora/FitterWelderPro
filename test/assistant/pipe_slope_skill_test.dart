import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  testWidgets(
      'spoken result actually fills the visible slope screen; invalid fields are atomic',
      (tester) async {
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final reply = await BrainHarness().say('spadek 1% na 6 metrów');
    final showing =
        showInModule((reply.result as AnswerResult).show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(find.byType(PipeSlopeScreen), findsOneWidget);
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(values, contains('6000.0'));
    expect(values, contains('60.0'));
    final handle = ToolBridge.instance.current!;
    expect(
        await handle
            .apply({'mode': 'length_to_rise', 'length_mm': -1, 'slope_pct': 2}),
        isNotEmpty);
    await tester.pump();
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((f) => f.controller!.text)
            .toList(),
        values);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  test(
      'one percent on six meters uses the same domain and fills the calculator',
      () async {
    final h = BrainHarness();
    final r = (await h.say('spadek 1% na 6 metrów')).result as AnswerResult;
    expect(r.show?.toolId, 'pipe_slope');
    expect(r.show?.fields['length_mm'], 6000);
    expect(r.show?.fields['rise_mm'], 60);
    expect(r.show?.fields['slope_pct'], 1);
    expect(h.actions.savedJournal, isEmpty);
  });
  test('asks for missing values and accepts an explicitly labelled alternative',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz spadek rury')).result, isA<AskResult>());
    expect((await h.say('6 metrów')).result, isA<AskResult>());
    final r = (await h.say('wznios 60 mm')).result as AnswerResult;
    expect(r.show?.fields['mode'], 'slope_from_lr');
    expect(r.show?.fields['slope_pct'], 1);
  });
  test('different units and inverse calculation', () async {
    final h = BrainHarness();
    final r =
        (await h.say('spadek rury wznios 6 cm i 1%')).result as AnswerResult;
    expect(r.show?.fields['mode'], 'rise_to_length');
    expect(r.show?.fields['length_mm'], 6000);
  });
  for (final text in [
    'spadek 1% na minus 6 metrów',
    'spadek minus 1 procent na 6 metrów',
    'spadek 1% długość 6 metrów długość 7 metrów'
  ]) {
    test('invalid or conflicting input never produces an answer: $text',
        () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  test('three contradictory dimensions never set the screen', () async {
    expect(
        (await BrainHarness().say('spadek długość 6000 mm wznios 60 mm i 2%'))
            .result,
        isA<FailedResult>());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'support/assistant_test_support.dart';

void main() {
  test(
      'a bare tool name answers the open-tool question even in the active calculator',
      () async {
    final h = BrainHarness(activeToolId: 'rolling_offset', onHome: false);
    expect((await h.say('otwórz')).result, isA<AskResult>());
    final result = (await h.say('rolling offset')).result as AnswerResult;
    expect(result.show?.toolId, 'rolling_offset');
  });
  test('300/400/45 uses domain geometry and never calls travel a cut length',
      () async {
    final r = (await BrainHarness().say(
            'rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni'))
        .result as AnswerResult;
    expect(r.show?.fields, {'rise_mm': 300, 'spread_mm': 400, 'angle_deg': 45});
    expect(textOf(r), contains('500'));
    expect(textOf(r), contains('nie jest długość rury do cięcia'));
  });
  test('asks each missing quantity, never assumes the default elbow angle',
      () async {
    final h = BrainHarness();
    expect(((await h.say('oblicz rolling offset')).result as AskResult).slot,
        'rise_mm');
    expect(((await h.say('30 cm')).result as AskResult).slot, 'spread_mm');
    expect(((await h.say('400 mm')).result as AskResult).slot, 'angle_deg');
    final result = (await h.say('45 stopni')).result as AnswerResult;
    expect(result.show?.fields['rise_mm'], 300);
  });
  for (final text in [
    'rolling offset rise spread 400 mm angle 45 degrees',
    'rolling offset rise minus 300 mm spread 400 mm angle 45 degrees',
    'rolling offset rise 300 mm spread 400 mm angle 5 degrees',
    'rolling offset rise 300 mm spread 400 mm angle 45 degrees angle 60 degrees'
  ]) {
    test('incomplete/invalid/ambiguous: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'bridge updates the actual screen and rejects invalid updates atomically',
      (tester) async {
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness()
            .say('rolling offset rise 300 mm spread 400 mm angle 45 degrees'))
        .result as AnswerResult;
    final pending = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await pending, ShowOutcome.opened);
    final values = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.controller!.text)
        .toList();
    expect(values, contains('707.1'));
    expect(
        await ToolBridge.instance.current!
            .apply({'rise_mm': 300, 'spread_mm': 400, 'angle_deg': 0}),
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
}

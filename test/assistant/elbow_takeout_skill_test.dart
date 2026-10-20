import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('LR 45 uses actual B from the table, not a circular-arc estimate',
      () async {
    final r = (await BrainHarness().say('wymiar kolana DN50 LR kąt 45 stopni'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('35 mm'));
    expect(r.answer.source!.pl, contains('6.1-1'));
    expect(r.show!.toolId, 'elbow_takeouts');
  });
  test('DN125 metric column remains 190 instead of rounding 7.5 inches',
      () async {
    final r = (await BrainHarness().say('wymiar kolana DN125 LR kąt 90 stopni'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('190 mm'));
  });
  test('SR 45 is explicitly a segment, not a standard 45 degree SR elbow',
      () async {
    final r = (await BrainHarness().say('wymiar kolana DN50 SR kąt 45 stopni'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('segmentu kolana 90°'));
    expect(r.answer.source!.pl, contains('6.2.4'));
  });
  test('NPS, family and angle are collected without assuming LR or 90 degrees',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz wymiar kolana')).result, isA<AskResult>());
    expect((await h.say('2 cale')).result, isA<AskResult>());
    expect((await h.say('LR')).result, isA<AskResult>());
    final r = (await h.say('45 stopni')).result as AnswerResult;
    expect(r.answer.text.pl, contains('35 mm'));
    expect(r.show!.fields['dn'], 50);
  });
  for (final text in [
    'wymiar kolana DN15 SR kąt 90 stopni',
    'wymiar kolana DN15 3D kąt 90 stopni',
    'wymiar kolana DN50 3 cale LR kąt 90 stopni',
    'wymiar kolana DN50 LR kąt minus 45°',
    'wymiar kolana DN50 LR kąt 45 stopni i 90 stopni',
    'wymiar kolana DN50 LR SR kąt 90 stopni',
  ]) {
    test('invalid or conflicting elbow input cannot answer: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  testWidgets(
      'command filters actual table and rejects unknown size atomically',
      (tester) async {
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness()
            .say('wymiar kolana DN50 LR kąt 45 stopni', byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'DN50');
    expect(find.text('35'), findsOneWidget);
    expect(find.textContaining('DN100', findRichText: true), findsNothing);
    expect(await ToolBridge.instance.current!.apply({'dn': 999}), isNotEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'DN50');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

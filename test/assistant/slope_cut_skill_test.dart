import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('cuts and line slopes route to different calculators', () async {
    final h = BrainHarness();
    expect((await h.say('spadek 2% na 6 m')).match!.skill.id, 'pipe.slope');
    final cut = await h.say('cięcie pod spadek 2% OD 100 mm');
    expect(cut.match!.skill.id, 'slope.cut');
    final result = cut.result as AnswerResult;
    expect(result.show!.fields, {'od_mm': 100.0, 'slope_pct': 2.0});
    expect(result.answer.text.pl, contains('2 mm'));
    expect(result.answer.text.pl, contains('skala 0°'));
    expect(result.answer.text.pl, contains('90°'));
  });
  test('DN uses domain OD, never nominal diameter as millimeters', () async {
    final r = (await BrainHarness().say('cięcie pod spadek 2% DN50')).result
        as AnswerResult;
    expect(r.show!.fields['od_mm'], 60.3);
    expect(r.answer.source, isNotNull);
  });
  test('missing diameter and percentage are collected with units', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz cięcie pod spadek')).result, isA<AskResult>());
    expect((await h.say('100 mm')).result, isA<AskResult>());
    final r = (await h.say('2 procent')).result as AnswerResult;
    expect(r.show!.fields['od_mm'], 100);
    expect(r.show!.fields['slope_pct'], 2);
  });
  for (final text in [
    'cięcie pod spadek minus 2% OD 100 mm',
    'cięcie pod spadek 2% OD minus 100 mm',
    'cięcie pod spadek 2% OD 100 mm OD 200 mm',
    'cięcie pod spadek 2% i 3% OD 100 mm',
    'cięcie pod spadek 2% DN999',
    'cięcie pod spadek 2% DN50 OD 100 mm',
  ]) {
    test('invalid data cannot fill calculator: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  testWidgets('voice command fills saw setting and axial mark on the screen',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness()
            .say('cięcie pod spadek 2% OD 100 mm', byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(find.text('2.00 mm'), findsOneWidget);
    expect(find.text('1.146°'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

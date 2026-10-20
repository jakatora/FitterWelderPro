import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('circumference percentage uses real calculator payload', () async {
    final r = (await BrainHarness()
            .say('obrót kolana obwód 400 mm 25%', byVoice: true))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('100 mm'));
    expect(r.show!.toolId, 'elbow_rotation');
    expect(r.show!.fields, {'circumference_mm': 400.0, 'percent': 25.0});
  });
  test('dialogue collects explicit dimensions and rotation units', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz obrót kolanka')).result, isA<AskResult>());
    expect((await h.say('OD 100 mm')).result, isA<AskResult>());
    final r = (await h.say('90 stopni')).result as AnswerResult;
    expect(r.answer.text.pl, contains('78,54 mm'));
  });
  test('ambiguous alternatives can be corrected', () async {
    final h = BrainHarness();
    expect((await h.say('obrót kolana OD 100 mm obwód 400 mm 25%')).result,
        isA<AskResult>());
    final r = (await h.say('obwód 400 mm')).result as AnswerResult;
    expect(r.show!.fields.containsKey('od_mm'), isFalse);
  });
  test('rotation correction removes the competing percentage', () async {
    final h = BrainHarness();
    expect((await h.say('obrót kolana obwód 400 mm 25% kąt 90 stopni')).result,
        isA<AskResult>());
    expect((await h.say('90')).result, isA<AskResult>());
    final r = (await h.say('90 stopni')).result as AnswerResult;
    expect(r.show!.fields.containsKey('percent'), isFalse);
    expect(r.show!.fields['degrees'], 90);
  });
  for (final text in [
    'obrót kolana OD minus 100 mm 25%',
    'obrót kolana obwód 400 mm 101%',
    'obrót kolana obwód 400 mm kąt 361 stopni',
    'obrót kolana obwód 400 mm 25% kąt 90 stopni',
    'obrót kolana obwód 400 mm kąt minus 30 stopni',
  ]) {
    test('invalid input asks without applying: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets('command fills actual rotation tab and displays arc',
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
    final r = (await BrainHarness()
            .say('obrót kolanka obwód 400 mm 25%', byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(ToolBridge.instance.activeToolId, 'elbow_rotation');
    expect(find.textContaining('100.0'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/fitter/fitter_calcs.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('manual radius deducts both elbows and both weld gaps', () async {
    final r = (await BrainHarness().say(
            'oblicz wstawkę offset 300 mm kąt 90 stopni promień 100 mm szczelina 2 mm'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('Wstawka do cięcia: 96 mm'));
    expect(r.show!.fields, {
      'mode': 'manual',
      'angle_deg': 90.0,
      'offset_mm': 300.0,
      'gap_mm': 2.0,
      'radius_mm': 100.0
    });
  });
  test('standard 45 degree LR uses tabulated B, not A tan half angle',
      () async {
    final r = (await BrainHarness().say(
            'wstawka między kolanami DN50 LR offset 300 mm kąt 45 stopni szczelina 2 mm'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('odjęcie każdego 35 mm'));
    expect(r.show!.fields['od_mm'], 60.3);
    expect(r.show!.fields['mode'], '1.5D');
    expect(r.answer.text.pl, contains('350,26 mm'));
  });
  test('dialogue requires explicit family, angle, offset and each weld gap',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz długość wstawki')).result, isA<AskResult>());
    expect((await h.say('promień 100 mm')).result, isA<AskResult>());
    expect((await h.say('90 stopni')).result, isA<AskResult>());
    expect((await h.say('300 mm')).result, isA<AskResult>());
    final r = (await h.say('2 mm')).result as AnswerResult;
    expect(r.answer.text.pl, contains('96 mm'));
  });
  test('conflicting DN and OD can be corrected using one size', () async {
    final h = BrainHarness();
    expect(
        (await h.say(
                'wstawka DN50 OD 114,3 mm LR offset 300 mm kąt 45 stopni szczelina 2 mm'))
            .result,
        isA<AskResult>());
    final r = (await h.say('DN50')).result as AnswerResult;
    expect(r.show!.fields['od_mm'], 60.3);
  });
  test('impossible negative cut is not applied or reported as missing',
      () async {
    final r = (await BrainHarness().say(
            'wstawka promień 100 mm offset 100 mm kąt 90 stopni szczelina 0 mm'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
  });
  test('missing table family reports the capability gap', () async {
    final r = (await BrainHarness()
            .say('wstawka DN15 SR offset 300 mm kąt 45 stopni szczelina 2 mm'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  for (final text in [
    'wstawka promień minus 100 mm offset 300 mm kąt 45 stopni szczelina 2 mm',
    'wstawka promień 100 mm offset 300 mm kąt 180 stopni szczelina 2 mm',
    'wstawka DN50 LR offset 300 mm kąt 120 stopni szczelina 2 mm',
    'wstawka DN50 LR offset minus 300 mm kąt 45 stopni szczelina 2 mm',
    'wstawka DN50 LR offset 300 mm kąt 45 stopni szczelina minus 2 mm',
    'wstawka DN50 LR SR offset 300 mm kąt 45 stopni szczelina 2 mm',
    'wstawka promień 100 mm offset 300 mm offset 400 mm kąt 45 stopni szczelina 2 mm',
  ]) {
    test('invalid values ask and never apply: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  test('pure domain result still matches screen calculation convention', () {
    final r = insertBetweenElbows(
        offsetMm: 300, angleDeg: 90, takeoutMm: 100, weldGapMm: 2);
    expect(r.travelMm, closeTo(300, .00001));
    expect(r.insertMm, closeTo(100, .00001));
    expect(r.cutMm, closeTo(96, .00001));
  });
  testWidgets('voice command fills actual insert tab and cut result',
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
            'oblicz wstawkę promień 100 mm offset 300 mm kąt 90 stopni szczelina 2 mm',
            byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(ToolBridge.instance.activeToolId, 'insert');
    expect(find.text('96.0 mm'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

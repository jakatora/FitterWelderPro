import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('mass per m never assumes a length or piece count', () async {
    final r =
        (await BrainHarness().say('masa rury OD 60,3 mm ścianka 3,91 mm 316L'))
            .result as AnswerResult;
    expect(r.show!.fields.containsKey('length_mm'), isFalse);
    expect(r.show!.fields.containsKey('quantity'), isFalse);
    expect(r.answer.text.pl, contains('5,54 kg/m'));
    expect(r.answer.text.pl, isNot(contains('Łącznie')));
  });
  test('material and wall dialogue retain DN instead of guessing', () async {
    final h = BrainHarness();
    expect((await h.say('ile waży rura DN50')).result, isA<AskResult>());
    expect((await h.say('3,91 mm')).result, isA<AskResult>());
    final r = (await h.say('316L')).result as AnswerResult;
    expect(r.show!.fields['od_mm'], 60.3);
    expect(r.show!.fields['wall_mm'], 3.91);
    expect(r.show!.fields['material'], 'ss316');
  });
  test('piece count requires an explicit length', () async {
    final h = BrainHarness();
    expect((await h.say('masa rury DN50 ścianka 3,91 mm 316L ilość 2')).result,
        isA<AskResult>());
    final r = (await h.say('1 metr')).result as AnswerResult;
    expect(r.show!.fields['length_mm'], 1000);
    expect(r.show!.fields['quantity'], 2);
    expect(r.answer.text.pl, contains('11,08 kg'));
  });
  for (final text in [
    'masa rury OD 10 mm ścianka 5 mm 316L',
    'masa rury OD 10 mm ścianka minus 1 mm 316L',
    'masa rury OD 60 mm ścianka 3 mm stal nierdzewna',
    'masa rury OD 60 mm ścianka 3 mm 316L 304L',
    'masa rury OD 60 mm ścianka 3 mm długość minus 6 m 316L',
    'masa rury OD 60 mm ścianka 3 mm długość 1 m 316L ilość minus 2',
    'masa rury OD 60 mm ścianka 3 mm długość 1 m 316L ilość 1,5',
    'masa rury DN50 OD 100 mm ścianka 3 mm 316L',
  ]) {
    test('invalid or ambiguous mass input cannot fill screen: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  testWidgets(
      'mass command calculates on screen then per-m command clears stale length and quantity',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final h = BrainHarness();
    final r = (await h.say(
            'oblicz masę rury OD 60,3 mm ścianka 3,91 mm długość 1 m 316L ilość 2',
            byVoice: true))
        .result as AnswerResult;
    var showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(find.text('5.541 kg/m'), findsOneWidget);
    expect(find.text('11.08 kg'), findsOneWidget);
    final next =
        (await h.say('oblicz masę rury OD 60,3 mm ścianka 3,91 mm 316L')).result
            as AnswerResult;
    showing = showInModule(next.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.appliedInPlace);
    expect(find.text('11.08 kg'), findsNothing);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.controller!.text)
        .toList();
    expect(fields.where((v) => v.isEmpty).length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

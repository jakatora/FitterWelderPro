import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('BPE inch OD and DIN DN are different nominal systems', () async {
    final a = (await BrainHarness().say('rura sanitarna BPE 2 cale')).result
        as AnswerResult;
    final b = (await BrainHarness().say('rura sanitarna DIN 11850 DN50')).result
        as AnswerResult;
    expect(a.show!.fields, {'standard': 'bpe', 'size': '2"'});
    expect(b.show!.fields, {'standard': 'din11850_ii', 'size': 'DN50'});
    expect(a.answer.text.pl, contains('OD 50,8 mm'));
    expect(b.answer.text.pl, contains('OD 53 mm'));
  });
  test('missing standard asks before choosing a size table', () async {
    final h = BrainHarness();
    expect((await h.say('rura sanitarna DN50')).result, isA<AskResult>());
    final r = (await h.say('DIN 11850')).result as AnswerResult;
    expect(r.show!.fields['size'], 'DN50');
  });
  test('correcting pipe DN to BPE inch OD clears obsolete size slots',
      () async {
    final h = BrainHarness();
    expect((await h.say('rura sanitarna BPE DN50')).result, isA<AskResult>());
    final r = (await h.say('2 cale')).result as AnswerResult;
    expect(r.show!.fields['size'], '2"');
  });
  for (final text in [
    'rura sanitarna BPE OD 51 mm',
    'rura sanitarna DIN 11850 DN50 OD 50,8 mm',
    'rura sanitarna BPE 2 cale OD 53 mm',
    'rura sanitarna BPE DIN 11850 DN50',
    'rura sanitarna DIN 11850 seria I DN50',
    'rura sanitarna DIN 11850 seria III DN50',
    'rura sanitarna BPE OD minus 50,8 mm',
  ]) {
    test('ambiguous or missing sanitary data never selects nearest row: $text',
        () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  testWidgets(
      'selects exact BPE row, applies DIN in place and allows manual search afterwards',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(950, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r =
        (await BrainHarness().say('rura sanitarna BPE 2 cale', byVoice: true))
            .result as AnswerResult;
    var showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(find.byWidgetPredicate((w) => w is Text && w.data == '2"'), findsOneWidget);
    expect(find.text('1/2"'), findsNothing);
    expect(find.text('2 1/2"'), findsNothing);
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({'standard': 'din11850_ii', 'size': '2"'}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('50.80'), findsOneWidget);
    final next = (await BrainHarness().say('rura sanitarna DIN 11850 DN50'))
        .result as AnswerResult;
    showing = showInModule(next.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.appliedInPlace);
    expect(find.text('53.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'DN40');
    await tester.pumpAndSettle();
    expect(find.text('41.00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

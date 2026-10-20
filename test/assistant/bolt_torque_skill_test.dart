import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  const input =
      'oblicz moment dokręcania 5/8 cala B7 smar miedziany preload 50%';
  test('reference 5/8 UNC B7 Cu 50 percent is 134.07 Nm per bolt', () async {
    final r = (await BrainHarness().say(input)).result as AnswerResult;
    expect(r.answer.text.pl, contains('134,07 N·m'));
    expect(r.answer.text.pl, contains('na jedną śrubę'));
    expect(r.show!.fields, {
      'bolt_size': '5/8',
      'grade': 'B7',
      'lube': 'cu_anti_seize',
      'preload_fraction': .5
    });
  });
  test('flange preset selects exact bolt and count, not torque times count',
      () async {
    final r = (await BrainHarness()
            .say('moment śrub DN100 Class 150 B7 smar miedziany preload 50%'))
        .result as AnswerResult;
    expect(r.show!.fields['bolt_size'], '5/8');
    expect(r.show!.fields['flange_dn'], 100);
    expect(r.answer.text.pl, contains('8 śrub'));
    expect(r.answer.text.pl, contains('134,07 N·m'));
  });
  test('dialogue requires size, grade, lube and preload without defaults',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz moment dokręcania')).result, isA<AskResult>());
    expect((await h.say('5/8 cala')).result, isA<AskResult>());
    expect((await h.say('B7')).result, isA<AskResult>());
    expect((await h.say('smar miedziany')).result, isA<AskResult>());
    final r = (await h.say('50 procent')).result as AnswerResult;
    expect(r.show!.fields['preload_fraction'], .5);
  });
  test('B8M requires Class 1 confirmation', () async {
    final h = BrainHarness();
    expect(
        (await h.say('moment śruby 5/8 cala B8M smar miedziany preload 50%'))
            .result,
        isA<AskResult>());
    final r = (await h.say('1')).result as AnswerResult;
    expect(r.answer.text.pl, contains('38,33 N·m'));
    expect(r.answer.text.pl, contains('207 MPa'));
  });
  test('conflicting preset/size can be corrected with manual size', () async {
    final h = BrainHarness();
    expect(
        (await h.say(
                'moment śruby DN100 Class 150 3/4 cala B7 sucho preload 50%'))
            .result,
        isA<AskResult>());
    final r = (await h.say('3/4 cala')).result as AnswerResult;
    expect(r.show!.fields.containsKey('flange_dn'), isFalse);
  });
  test('ASME B16.5 is a standard designation, not a second bolt grade',
      () async {
    final r = (await BrainHarness().say(
            'oblicz moment dokręcania ASME B16.5 DN100 Class 150 B7 smar miedziany preload 50%'))
        .result as AnswerResult;
    expect(r.show!.fields['grade'], 'B7');
  });
  for (final text in [
    'moment śruby 5/8 cala B7 B16 sucho preload 50%',
    'moment śruby minus 5/8 cala B7 sucho preload 50%',
    'moment śruby 5/8 cala B7 olej sucho preload 50%',
    'moment śruby 5/8 cala B7 sucho preload 29%',
    'moment śruby 5/8 cala B7 sucho preload 76%',
    'moment śruby DN100 Class 150 5/8 cala 3/4 cala B7 sucho preload 50%',
  ]) {
    test('invalid or conflicting input never applies: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  for (final text in [
    'moment śruby M16 B7 sucho preload 50%',
    'moment śruby 5/8 cala B8 sucho preload 50%',
    'moment śruby 3 cale B7 sucho preload 50%',
    'moment śruby DN400 Class 150 B7 sucho preload 50%',
    'moment śruby 5/8 cala B8M klasa 2 sucho preload 50%',
    'moment śruby 5/8 cala B7 K 0,17 preload 50%',
  ]) {
    test('missing model reports capability gap: $text', () async {
      final r = (await BrainHarness().say(text)).result as FailedResult;
      expect(r.reportMissingCapability, isTrue);
    });
  }
  test('explicit K cannot silently override a named lubricant preset',
      () async {
    final r =
        (await BrainHarness().say('$input K 0,17')).result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
  });
  testWidgets('page fills real result, clears stale flange and preserves prefs',
      (tester) async {
    final seed = <String, Object>{
      'bolt_torque.bolt_size': '1/2',
      'bolt_torque.grade': 'B16',
      'bolt_torque.lube': 'dry',
      'bolt_torque.preload_fraction': .75,
      'bolt_torque.flange_dn': 15,
      'bolt_torque.flange_class': 150
    };
    SharedPreferences.setMockInitialValues(seed);
    await tester.binding.setSurfaceSize(const Size(1200, 3500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r =
        (await BrainHarness().say(input, byVoice: true)).result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(ToolBridge.instance.activeToolId, 'bolt_torque');
    expect(find.text('134'), findsOneWidget);
    expect(find.textContaining('4 ×'), findsNothing);
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({...r.show!.fields, 'preload_fraction': .9}),
        isNotEmpty);
    expect(
        await handle
            .apply({...r.show!.fields, 'flange_dn': 100, 'flange_class': 600}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.text('134'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    for (final e in seed.entries) {
      expect(prefs.get(e.key), e.value);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/pipe_slope_screen.dart';
import 'support/assistant_test_support.dart';

Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);
String value(WidgetTester t, String label) =>
    t.widget<TextField>(field(label)).controller!.text;
Future<void> mount(WidgetTester t) async {
  ToolBridge.reset();
  t.view.physicalSize = const Size(1000, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          home: const PipeSlopeScreen())));
  await t.pumpAndSettle();
}

void main() {
  for (final mode in ['length_to_rise', 'rise_to_length', 'slope_from_lr']) {
    testWidgets(
        'current independent inputs for $mode recalculate, invert and clear atomically',
        (t) async {
      await mount(t);
      final handle = ToolBridge.instance.current!;
      expect(
          await handle.apply(
              {'mode': mode, 'length_mm': 6000, 'rise_mm': 60, 'slope_pct': 1}),
          isEmpty);
      await t.pumpAndSettle();
      final snapshot = ToolBridge.instance.inputFields('pipe_slope')!;
      expect(snapshot['mode'], mode);
      final derived = mode == 'length_to_rise'
          ? 'rise_mm'
          : mode == 'rise_to_length'
              ? 'length_mm'
              : 'slope_pct';
      expect(snapshot.containsKey(derived), false);
      expect(() => snapshot['mode'] = 'other', throwsUnsupportedError);
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final ctx =
          AssistantContext(lang: AppLanguage.pl, modules: ToolBridge.instance);
      Future<SkillResult> say(String s) async => (await h.brain
              .handle(Utterance(s, lang: AppLanguage.pl, byVoice: true), ctx))
          .result;
      // A manual edit after the previous chat result must be authoritative.
      final manual =
          mode == 'rise_to_length' ? 'Wznios (Rise)' : 'Długość rury';
      await t.enterText(
          field(manual), mode == 'rise_to_length' ? '120' : '12000');
      await t.pumpAndSettle();
      final a = await say('oblicz aktualny spadek') as AnswerResult;
      expect(
          a.show!.fields[mode == 'rise_to_length'
              ? 'length_mm'
              : mode == 'length_to_rise'
                  ? 'rise_mm'
                  : 'slope_pct'],
          mode == 'rise_to_length'
              ? 12000
              : mode == 'length_to_rise'
                  ? 120
                  : 0.5);
      expect(await handle.apply(a.show!.fields), isEmpty);
      await t.pumpAndSettle();
      final edit = mode == 'slope_from_lr'
          ? 'zmień nachylenie na 2%'
          : mode == 'length_to_rise'
              ? 'zmień wznios na 240 mm'
              : 'zmień długość na 6000 mm';
      final inverse = await say(edit) as AnswerResult;
      expect(inverse.show!.fields['mode'],
          mode == 'slope_from_lr' ? 'length_to_rise' : 'slope_from_lr');
      expect(inverse.show!.fields['slope_pct'], 2);
      expect(await handle.apply(inverse.show!.fields), isEmpty);
      await t.pumpAndSettle();
      final before = Map.of(ToolBridge.instance.inputFields('pipe_slope')!);
      for (final fields in <Map<String, Object?>>[
        {
          'mode': 'length_to_rise',
          'length_mm': 100,
          'slope_pct': 2,
          'rise_mm': 99
        },
        {
          'mode': 'length_to_rise',
          'length_mm': 100,
          'slope_pct': 2,
          'action': 1
        },
        {'action': 'clear', 'mode': 'length_to_rise'},
        {
          'mode': 'length_to_rise',
          'length_mm': double.infinity,
          'slope_pct': 2
        },
      ]) {
        expect(await handle.apply(fields), isNotEmpty);
        expect(ToolBridge.instance.inputFields('pipe_slope'), before);
      }
      final clear = await say('wyczyść spadek rury') as AnswerResult;
      expect(await handle.apply(clear.show!.fields), isEmpty);
      await t.pumpAndSettle();
      for (final w in t.widgetList<TextField>(find.byType(TextField))) {
        expect(w.controller!.text, isEmpty);
      }
      expect(await say('oblicz'), isA<AskResult>());
      // An alternative input can change the pair after an incomplete current form.
      await say('długość 6 m');
      final recovered = await say('wznios 60 mm') as AnswerResult;
      expect(recovered.show!.fields['slope_pct'], 1);
      expect(t.takeException(), isNull);
    });
  }
  for (final command in [
    'wyczyść',
    'proszę wyczyść dane',
    'please clear fields'
  ]) {
    test('active-only clear is supported: $command', () async {
      final h = BrainHarness(activeToolId: 'pipe_slope', onHome: false);
      addTearDown(h.timer.dispose);
      final r = (await h.say(command)).result as AnswerResult;
      expect(r.show!.fields, {'action': 'clear'});
    });
  }
  for (final command in ['qwerty asdf', 'a qwerty asdf', 'and qwerty asdf']) {
    test('unrelated utterance after slope is not replayed: $command', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect(
          (await h.say('spadek 1% na 6 metrów')).result, isA<AnswerResult>());
      final r = await h.say(command);
      expect(r.match?.skill.id, isNot('pipe.slope'));
      expect(r.result, isNot(isA<AnswerResult>()));
    });
  }
  test('missing opt-in current fields fail safely without a gap report',
      () async {
    final h = BrainHarness(activeToolId: 'pipe_slope', onHome: false);
    addTearDown(h.timer.dispose);
    final r = (await h.say('oblicz')).result as FailedResult;
    expect(r.reportMissingCapability, false);
  });
  test('active slope does not steal other module commands', () async {
    final h = BrainHarness(activeToolId: 'pipe_slope', onHome: false);
    addTearDown(h.timer.dispose);
    expect(
        (await h.say('oblicz trasę rur H1 2 m')).match?.skill.id, 'pipe.route');
    expect(
        (await h.say(
                'oblicz rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni'))
            .match
            ?.skill
            .id,
        'rolling.offset');
  });
}

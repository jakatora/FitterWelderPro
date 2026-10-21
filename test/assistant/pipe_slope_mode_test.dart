import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';
import 'pipe_slope_current_test.dart' show mount;

List<String> values(WidgetTester t) => t
    .widgetList<TextField>(find.byType(TextField))
    .map((w) => w.controller!.text)
    .toList();
const labels = {
  'length_to_rise': 'Długość → Wznios',
  'rise_to_length': 'Wznios → Długość',
  'slope_from_lr': 'Wyznacz %'
};
void main() {
  for (final from in labels.keys) {
    for (final to in labels.keys) {
      testWidgets(
          'mode action $from to $to equals the actual selector with no invented recalculation',
          (t) async {
        Future<void> initial() async {
          await mount(t);
          expect(
              await ToolBridge.instance.current!.apply({
                'mode': from,
                'length_mm': 6000,
                'rise_mm': 60,
                'slope_pct': 1
              }),
              isEmpty);
          await t.pumpAndSettle();
        }

        await initial();
        await t.tap(find.text(labels[to]!));
        await t.pumpAndSettle();
        final expected = values(t),
            inputs = Map.of(ToolBridge.instance.inputFields('pipe_slope')!);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pumpAndSettle();
        await initial();
        final r = await ToolBridge.instance
            .performModuleAction('pipe_slope', 'mode:$to');
        await t.pumpAndSettle();
        expect(r.completed, true);
        expect(values(t), expected);
        expect(ToolBridge.instance.inputFields('pipe_slope'), inputs);
        final pinned = <String, Map<String, Object?>>{
          'length_to_rise/rise_to_length': {
            'mode': 'rise_to_length',
            'rise_mm': null,
            'slope_pct': 1
          },
          'length_to_rise/slope_from_lr': {
            'mode': 'slope_from_lr',
            'length_mm': 6000,
            'rise_mm': null
          },
          'rise_to_length/length_to_rise': {
            'mode': 'length_to_rise',
            'length_mm': null,
            'slope_pct': 1
          },
          'rise_to_length/slope_from_lr': {
            'mode': 'slope_from_lr',
            'length_mm': null,
            'rise_mm': 60
          },
          'slope_from_lr/length_to_rise': {
            'mode': 'length_to_rise',
            'length_mm': 6000,
            'slope_pct': null
          },
          'slope_from_lr/rise_to_length': {
            'mode': 'rise_to_length',
            'rise_mm': 60,
            'slope_pct': null
          },
        };
        final angle = t
            .widget<TextField>(find.byWidgetPredicate((w) =>
                w is TextField && w.decoration?.labelText == 'Kąt nachylenia'))
            .controller!
            .text;
        if (from != to) {
          expect(ToolBridge.instance.inputFields('pipe_slope'),
              pinned['$from/$to']);
          expect(angle, isEmpty);
          expect(
              (await ToolBridge.instance
                      .performModuleAction('pipe_slope', 'copy'))
                  .completed,
              false);
        } else {
          expect(angle, '0.573');
        }

        if (from == to) {
          expect(values(t).where((s) => s.isNotEmpty), isNotEmpty);
        }
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'mode commands work on incomplete forms and invalid payloads are atomic',
      (t) async {
    await mount(t);
    final bridge = ToolBridge.instance;
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: bridge);
    for (final (command, mode) in [
      ('ustaw tryb obliczanie wzniosu', 'length_to_rise'),
      ('set mode to calculate length', 'rise_to_length'),
      ('zmień tryb na wyznacz procent', 'slope_from_lr'),
    ]) {
      final r = await h.brain
          .handle(Utterance(command, lang: AppLanguage.pl, byVoice: true), ctx);
      expect(r.result, isA<AnswerResult>());
      expect(bridge.inputFields('pipe_slope')!['mode'], mode);
      await t.pumpAndSettle();
      expect(values(t).every((s) => s.isEmpty), true);
    }
    final before = values(t),
        snapshot = Map.of(bridge.inputFields('pipe_slope')!);
    for (final patch in <Map<String, Object?>>[
      {'action': 'mode', 'mode': 'unknown'},
      {'action': 'mode', 'mode': 'length_to_rise', 'length_mm': 100},
      {'action': 'mode', 'mode': 1},
    ]) {
      expect(await bridge.current!.apply(patch), isNotEmpty);
      expect(values(t), before);
      expect(bridge.inputFields('pipe_slope'), snapshot);
    }
    final calc = await h.brain.handle(
        Utterance('spadek długość 6000 mm wznios 60 mm', lang: AppLanguage.pl),
        ctx);
    expect((calc.result as AnswerResult).show!.fields['slope_pct'], 1);
  });
}

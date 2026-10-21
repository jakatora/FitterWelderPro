import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/fitter/pipe_slope.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';
import 'pipe_slope_current_test.dart' show mount, field;

void main() {
  test('ratio domain is exact and refuses invalid/overflow values', () {
    expect(slopePercentFromRatio(1, 150), closeTo(100 / 150, 1e-15));
    expect(slopePercentFromRatio(1e300, 1e300), 100);
    for (final (a, b) in [
      (0.0, 150.0),
      (-1.0, 150.0),
      (1.0, 0.0),
      (1.0, -150.0),
      (double.nan, 150.0),
      (1.0, double.infinity),
      (1e300, 1e-300)
    ]) {
      expect(slopePercentFromRatio(a, b), isNull);
    }
  });
  for (final (ratio, expected) in [
    ('1:150', 40.0),
    ('1:200', 30.0),
    ('2:1000', 12.0),
    ('jeden do stu pięćdziesięciu', 40.0),
    ('one in one hundred fifty', 40.0)
  ]) {
    test('actual brain converts $ratio into exact slope before lengths',
        () async {
      final en = ratio.contains('one');
      final h = BrainHarness(lang: en ? AppLanguage.en : AppLanguage.pl);
      addTearDown(h.timer.dispose);
      final a = (await h.say(
              en
                  ? 'pipe slope $ratio over 6 meters'
                  : 'spadek $ratio na 6 metrów',
              byVoice: true))
          .result as AnswerResult;
      expect(a.show!.fields['rise_mm'], closeTo(expected, 1e-9));
      expect(a.show!.fields['length_mm'], 6000);
      if (expected == 40) {
        expect(
            a.answer.text.of(h.lang), contains(en ? '0.666667' : '0,666667'));
      }
    });
  }
  for (final ratio in [
    '1:0',
    '-1:150',
    '1:-150',
    '1:150:200',
    '1:150 i 1:200',
    '1:150 i 0.67%',
    '1:150 mm',
    '1 do 150 mm',
    '1 do minus 150 i 1%',
    '1 do 150 do 200',
    '1:150 200',
    '1:1000000000000 i 0.0000000002%',
    '1:1000000000000 i 1:500000000000'
  ]) {
    test('ambiguous or invalid ratio is never silently calculated: $ratio',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say('spadek $ratio długość 6 m')).result,
          isNot(isA<AnswerResult>()));
    });
  }
  test('ratio answers complete pending percentage and keep explicit units',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect((await h.say('oblicz spadek długość 6 m')).result, isA<AskResult>());
    final a = (await h.say('1:150')).result as AnswerResult;
    expect(a.show!.fields['rise_mm'], closeTo(40, 1e-9));
  });
  for (final (preset, expected) in [
    ('1:200', '30.0'),
    ('1:150', '40.2'),
    ('1:100', '60.0'),
    ('1:50', '120.0')
  ]) {
    testWidgets(
        'native $preset shortcut preserves actual values and differs from exact ratio when rounded',
        (t) async {
      await mount(t);
      final b = ToolBridge.instance;
      await b.current!
          .apply({'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
      await t.pumpAndSettle();
      if (preset == '1:150') {
        await t.tap(find.text('0.67%  (≈1:150)'));
        await t.pumpAndSettle();
        expect(t.widget<TextField>(field('Wznios (Rise)')).controller!.text,
            '40.2');
        await b.current!.apply(
            {'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
        await t.pumpAndSettle();
      }
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final ctx = AssistantContext(lang: AppLanguage.pl, modules: b);
      Future<SkillResult> say(String s) async => (await h.brain
              .handle(Utterance(s, lang: AppLanguage.pl, byVoice: true), ctx))
          .result;
      final a = await say('wybierz skrót $preset') as AnswerResult;
      await t.pumpAndSettle();
      expect(t.widget<TextField>(field('Wznios (Rise)')).controller!.text,
          expected);
      expect(b.inputFields('pipe_slope')!['length_mm'], 6000);
      if (preset == '1:150') {
        expect(a.answer.text.pl, contains('przybliżenie'));
        expect(b.inputFields('pipe_slope')!['slope_pct'], 0.67);
        final exact = await say('zmień spadek na 1:150') as AnswerResult;
        expect(exact.show!.fields['rise_mm'], closeTo(40, 1e-9));
        expect(await b.current!.apply(exact.show!.fields), isEmpty);
        await t.pumpAndSettle();
        expect(t.widget<TextField>(field('Wznios (Rise)')).controller!.text,
            '40.0');
      }
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'preset action is honest on incomplete data, asks for unknown shortcuts and rejects unavailable modes',
      (t) async {
    await mount(t);
    final b = ToolBridge.instance;
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: b);
    Future<SkillResult> say(String s) async =>
        (await h.brain.handle(Utterance(s, lang: AppLanguage.pl), ctx)).result;
    expect(await say('wybierz skrót 1:300'), isA<AskResult>());
    final a = await say('1:150') as AnswerResult;
    await t.pumpAndSettle();
    expect(a.answer.text.pl, contains('Uzupełnij'));
    expect(b.inputFields('pipe_slope')!['slope_pct'], 0.67);
    await b.current!
        .apply({'mode': 'slope_from_lr', 'length_mm': 6000, 'rise_mm': 60});
    await t.pumpAndSettle();
    final before = Map.of(b.inputFields('pipe_slope')!);
    expect((await say('wybierz skrót 1:150')) is FailedResult, true);
    expect(b.inputFields('pipe_slope'), before);
    for (final p in <Map<String, Object?>>[
      {'action': 'preset', 'preset': '0.67'},
      {'action': 'preset', 'preset': 0.67},
      {'action': 'preset', 'preset': '0.67', 'length_mm': 1}
    ]) {
      expect(await b.current!.apply(p), isNotEmpty);
      expect(b.inputFields('pipe_slope'), before);
    }
    await b.current!
        .apply({'mode': 'length_to_rise', 'length_mm': 6000, 'slope_pct': 1});
    await t.pumpAndSettle();
    expect(await b.current!.apply({'action': 'preset', 'preset': '0.67'}),
        isEmpty);
    await t.pumpAndSettle();
    expect(
        t.widget<TextField>(field('Wznios (Rise)')).controller!.text, '40.2');
    final selected = Map.of(b.inputFields('pipe_slope')!);
    expect(await b.current!.apply({...selected, 'preset': 0.5}), isNotEmpty);
    expect(b.inputFields('pipe_slope'), selected);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cut_list_app/assistant/assistant_validator.dart';
import 'package:cut_list_app/utils/decimal_input_text.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final lang in AppLanguage.values) {
    for (final v in [
      1e21,
      1e30,
      1.25e30,
      -1e30,
      -1.25e100,
      1e300,
      double.maxFinite,
      .001,
      .000001,
      1e-20,
      -.004,
      double.minPositive
    ]) {
      test('display preserves magnitude and sign $v in $lang', () {
        final text = assistantNumber(v, lang);
        expect(double.parse(text.replaceAll(',', '.')), v);
      });
    }
    for (final (value, en) in [
      (0.0, '0'),
      (-0.0, '0'),
      (2.0, '2'),
      (2.5, '2.5'),
      (2.345, '2.35'),
      (100.0, '100'),
      (-1234.56, '-1234.56')
    ]) {
      test('ordinary display remains compact $value in $lang', () {
        expect(assistantNumber(value, lang),
            lang == AppLanguage.pl ? en.replaceAll('.', ',') : en);
      });
    }
  }
  for (final v in [
    0.0,
    -0.0,
    5.0,
    45.0049,
    1e30,
    -1e30,
    1.25e100,
    -1e-20,
    double.minPositive,
    -double.minPositive,
    double.maxFinite
  ]) {
    test('plain input round-trips signed finite $v', () {
      final text = decimalInputText(v);
      expect(text, isNot(contains('e')));
      expect(double.parse(text), v);
    });
  }
  test('ordinary input retains decimal spelling and invalid values refuse', () {
    expect(decimalInputText(5), '5.0');
    expect(decimalInputText(-40), '-40.0');
    for (final v in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(() => decimalInputText(v), throwsArgumentError);
    }
  });
  for (final (command, source, result, native) in [
    ('przelicz 0.001 mm na m', .001, .000001, '1.000000e-6'),
    ('przelicz ${BigInt.from(10).pow(30)} mm na m', 1e30, 1e27, '1.000000e+27'),
  ]) {
    testWidgets(
        'real answer and native conversion keep the same magnitude: $command',
        (t) async {
      ToolBridge.reset();
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 2.5;
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
              home: const Scaffold(body: Text('Start')))));
      await t.pumpAndSettle();
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final reply = await h.say(command, byVoice: true);
      expect(reply.match?.skill.id, 'units.convert');
      final a = reply.result as AnswerResult;
      expect(a.show!.fields['value'], source);
      final parts = a.answer.text.pl.replaceAll(',', '.').split(' = ');
      expect(parts, hasLength(2));
      expect(double.parse(parts.first.split(' ').first), source);
      expect(double.parse(parts.last.split(' ').first),
          closeTo(result, result.abs() * 1e-15));
      final show = showInModule(a.show!, explicit: true);
      await t.pumpAndSettle();
      expect(await show, ShowOutcome.opened);
      expect(find.text(native), findsWidgets);
      expect(t.takeException(), isNull);
    });
  }
}

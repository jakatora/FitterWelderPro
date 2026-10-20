import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/power_source.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/readout.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('uses shared domain result and safe rounding', () async {
    final r = (await BrainHarness()
            .say('oblicz cykl pracy 200 A 60% prąd spawania 150 A'))
        .result as AnswerResult;
    final domain = computeDutyCycle(const DutyCycleInput(
        rows: [PlateRowInput(row: 1, currentA: 200, dutyPct: 60)],
        weldCurrentA: 150))!;
    expect(r.answer.text.pl,
        contains(powerSourceShareText(en: false, duty: domain)));
    expect(r.answer.text.pl, contains('10 min'));
    expect(r.answer.text.pl, contains('40 °C'));
    expect(r.show!.fields['weld_current_a'], 150);
  });
  test('dialogue never uses an example plate or assumes welding current',
      () async {
    final h = BrainHarness();
    expect(
        (await h.say('oblicz cykl pracy spawarki')).result, isA<AskResult>());
    expect((await h.say('200 A 60%')).result, isA<AskResult>());
    final r = (await h.say('150 A')).result as AnswerResult;
    expect((r.show!.fields['plate'] as List), hasLength(1));
  });
  test('spoken rating pairs are read without losing percentage units',
      () async {
    final r = (await BrainHarness().say(
            'oblicz cykl pracy dwieście amperów sześćdziesiąt procent prąd spawania sto pięćdziesiąt amperów',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['plate'], [
      {'current_a': 200.0, 'duty_pct': 60.0}
    ]);
    expect(r.show!.fields['weld_current_a'], 150);
  });
  test('above plate current reports out of range instead of extrapolating',
      () async {
    final r =
        (await BrainHarness().say('cykl pracy 200 A 60% prąd spawania 250 A'))
            .result as AnswerResult;
    expect(r.answer.text.pl, contains('poza zakresem źródła'));
    expect(r.answer.text.pl, isNot(contains('min spawania')));
  });
  test('three rating points remain three distinct pairs', () async {
    final r = (await BrainHarness().say(
            'cykl pracy 200 A 35% 160 A 60% 130 A 100% prąd spawania 150 A'))
        .result as AnswerResult;
    expect(r.show!.fields['plate'], hasLength(3));
  });
  test('an incomplete extra row is not silently dropped and can be corrected',
      () async {
    final h = BrainHarness();
    expect(
        (await h.say('cykl pracy 200 A 60% 160 A prąd spawania 150 A')).result,
        isA<AskResult>());
    final r = (await h.say('200 A 60% 160 A 100%')).result as AnswerResult;
    expect(r.show!.fields['plate'], hasLength(2));
  });
  for (final text in [
    'cykl pracy 200 A 0% prąd spawania 150 A',
    'cykl pracy minus 200 A 60% prąd spawania 150 A',
    'cykl pracy 200 A 101% prąd spawania 150 A',
    'cykl pracy 200 A 60% 200 A 100% prąd spawania 150 A',
    'cykl pracy 200 A 100% 160 A 60% prąd spawania 150 A',
    'cykl pracy 200 A 60% prąd spawania minus 150 A',
    'cykl pracy 200 A 60% prąd spawania 1501 A',
    'cykl pracy 200 A 60% prąd spawania 150 A prąd spawania 160 A',
    'cykl pracy 200 A 60% 80% prąd spawania 150 A',
    'cykl pracy prąd spawania 150 A 60%',
    'cykl pracy 200 A 20% 180 A 40% 160 A 60% 130 A 100% prąd spawania 150 A',
  ]) {
    test('invalid input never applies: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'actual page uses supplied plate, rejects atomically and preserves stored plate',
      (tester) async {
    final saved = encodePlate(const [PlatePoint(120, 70)]);
    SharedPreferences.setMockInitialValues({kPowerSourcePlatePrefsKey: saved});
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(
            'oblicz cykl pracy 200 A 60% prąd spawania 150 A',
            byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    String field(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(field('ps-plate-i-1'), '200');
    expect(field('ps-plate-x-1'), '60');
    expect(field('ps-plate-i-2'), isEmpty);
    expect(field('ps-current'), '150.0');
    final value = tester.widget<Readout>(find.descendant(
        of: find.byKey(const ValueKey('ps-duty')),
        matching: find.byType(Readout)));
    expect(value.value, '100');
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({...r.show!.fields, 'weld_current_a': -1}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(field('ps-current'), '150.0');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kPowerSourcePlatePrefsKey), saved);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/data/tungsten.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final amps in [15, 69, 70, 75, 80, 150, 250, 400]) {
    test('DCEN stainless $amps A uses the shared band lookup', () async {
      final r =
          (await BrainHarness().say('dobierz wolfram DC- nierdzewna $amps A'))
              .result as AnswerResult;
      final size = sizeForCurrent(amps.toDouble())!;
      final diameter = size.diaMm == 1
          ? '1'
          : size.diaMm.toStringAsFixed(1).replaceAll('.', ',');
      expect(r.answer.text.pl, contains('Ø $diameter mm'));
      expect(r.show!.fields, {'amps': amps.toDouble()});
      expect(r.answer.text.pl, contains('nie podpurki'));
    });
  }
  test('dialogue collects polarity, material and current independently',
      () async {
    final h = BrainHarness();
    expect((await h.say('dobierz wolfram')).result, isA<AskResult>());
    expect((await h.say('DC')).result, isA<AskResult>());
    expect((await h.say('minus')).result, isA<AskResult>());
    expect((await h.say('316L')).result, isA<AskResult>());
    final r = (await h.say('75 A')).result as AnswerResult;
    expect(r.answer.text.pl, contains('Ø 1,6 mm'));
  });
  test('spoken command and electrode polarity work together', () async {
    final r = (await BrainHarness().say(
            'dobierz wolfram elektroda ujemna nierdzewka siedemdziesiąt pięć amperów',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['amps'], 75);
  });
  test('explicit thoriated type retains the dust note from the table',
      () async {
    final r = (await BrainHarness().say('wolfram DCEN nierdzewna 200 A WTh20'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('WT20 / WTh20'));
    expect(r.answer.text.pl, contains('pył ze szlifowania'));
  });
  for (final text in [
    'dobierz wolfram DC- 304 A',
    'dobierz wolfram DC- 304,5 A',
    'dobierz wolfram DC- nierdzewna minus 75 A',
    'dobierz wolfram DC- nierdzewna 75',
    'dobierz wolfram DC- nierdzewna 75 A 150 A',
    'dobierz wolfram DC- DC+ nierdzewna 75 A',
    'dobierz wolfram DC- nierdzewna aluminium 75 A',
  ]) {
    test('missing or conflicting data never applies: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  for (final text in [
    'dobierz wolfram AC aluminium 100 A',
    'dobierz wolfram DC+ nierdzewna 100 A',
    'dobierz wolfram DC- stal węglowa 100 A',
    'dobierz wolfram DC- nierdzewna 14 A',
    'dobierz wolfram DC- nierdzewna 401 A',
    'dobierz wolfram DC- nierdzewna 100 A WC20',
  ]) {
    test('missing table queues a capability gap: $text', () async {
      final r = (await BrainHarness().say(text)).result as FailedResult;
      expect(r.reportMissingCapability, isTrue);
    });
  }
  test('incompatible known electrode is not a missing capability', () async {
    final r = (await BrainHarness().say('wolfram DC- nierdzewna 100 A WP'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
  });
  test('an explicit tip colour is not replaced by the default type', () async {
    final red = (await BrainHarness()
            .say('dobierz czerwony wolfram DCEN nierdzewna 100 A'))
        .result as AnswerResult;
    expect(red.answer.text.pl, contains('WT20 / WTh20'));
    final green = (await BrainHarness()
            .say('dobierz zielony wolfram DCEN nierdzewna 100 A'))
        .result as FailedResult;
    expect(green.reportMissingCapability, isFalse);
  });
  test('type ambiguity can be resolved by explicitly omitting the type',
      () async {
    final h = BrainHarness();
    expect(
        (await h.say('dobierz wolfram DCEN nierdzewna 100 A WL20 WT20')).result,
        isA<AskResult>());
    final r = (await h.say('pomiń')).result as AnswerResult;
    expect(r.answer.text.pl, contains('WL20 / WLa20'));
  });
  test('a missing electrode type does not become WL20', () async {
    final r =
        (await BrainHarness().say('dobierz wolfram DCEN nierdzewna 100 A WL10'))
            .result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  test('an incompatible welding process never becomes a TIG recommendation',
      () async {
    final r =
        (await BrainHarness().say('dobierz wolfram MIG DCEN nierdzewna 100 A'))
            .result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
  });
  testWidgets('actual screen fills only current and preserves stock/history',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'prefs_tungsten_in_stock': ['2.4'],
      'prefs_tungsten_overrides': '[]'
    });
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness()
            .say('dobierz wolfram DCEN nierdzewna 75 A', byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final field = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Prąd spawania (A, DC-)');
    expect(tester.widget<TextField>(field).controller!.text, '75.0');
    expect(tester.widget<TextField>(field).decoration!.helperText,
        contains('Ø 1.6 mm'));
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'tungsten');
    expect(await handle.apply({'amps': 500}), isNotEmpty);
    expect(await handle.apply({'amps': 100, 'reason': 'override'}), isNotEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '75.0');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('prefs_tungsten_in_stock'), ['2.4']);
    expect(prefs.getString('prefs_tungsten_overrides'), '[]');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

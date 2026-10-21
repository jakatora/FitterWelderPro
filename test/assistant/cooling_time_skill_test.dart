import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/welding/cooling_time.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/readout.dart';
import 'support/assistant_test_support.dart';

void main() {
  const input = 't8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie';
  test('uses domain result and does not invent a WPS window', () async {
    final r = (await BrainHarness().say(input)).result as AnswerResult;
    expect(r.show!.fields, {
      'q_kj_mm': 1.0,
      'preheat_c': 100.0,
      'thickness_mm': 20.0,
      'shape': 'buttFillRun'
    });
    expect(r.answer.text.pl, contains('Nie podano okna WPS'));
    expect(r.answer.text.pl, contains('5,98 s'));
  });
  test('cooling request wins over heat input even on the heat input page',
      () async {
    final result = await BrainHarness(activeToolId: 'heat_input', onHome: false)
        .say(
            'Oblicz czas stygnięcia t8/5 energia liniowa 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie');
    expect(result.match!.skill.id, 'cooling.t85');
    expect(result.result, isA<AnswerResult>());
  });
  test('dialogue collects every input without defaults', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz t8/5')).result, isA<AskResult>());
    expect((await h.say('1 kJ/mm')).result, isA<AskResult>());
    expect((await h.say('100 C')).result, isA<AskResult>());
    expect((await h.say('20 mm')).result, isA<AskResult>());
    final r = (await h.say('wypełnienie czołowej')).result as AnswerResult;
    expect(r.show!.fields['shape'], 'buttFillRun');
  });
  test('arc parameters use EN process efficiency', () async {
    final r = (await BrainHarness().say(
            'oblicz t8/5 MAG EN 28 V 250 A 350 mm/min temperatura 100 C grubość 20 mm wypełnienie'))
        .result as AnswerResult;
    expect(r.show!.fields['q_kj_mm'], closeTo(.96, .00001));
  });
  test('WPS minimum after thickness is not a travel-speed denominator',
      () async {
    for (final text in [
      't8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm min 5 s max 15 s wypełnienie',
      't8/5 MAG EN 28 V 250 A 350 mm na minutę temperatura 100 C grubość 20 mm wypełnienie min 5 s max 15 s',
    ]) {
      final r = (await BrainHarness().say(text)).result as AnswerResult;
      expect(r.show!.fields['window_min_s'], 5);
      expect(r.show!.fields['window_max_s'], 15);
      expect(r.show!.fields['q_kj_mm'],
          text.contains('MAG') ? closeTo(.96, 1e-12) : 1);
    }
  });
  test('ASME energy is not silently treated as EN Q', () async {
    final h = BrainHarness();
    expect((await h.say('$input ASME')).result, isA<AskResult>());
    expect((await h.say('EN')).result, isA<AnswerResult>());
  });
  test('direct Q and arc parameters require explicit choice', () async {
    final h = BrainHarness();
    expect((await h.say('$input MAG 28 V 250 A 350 mm/min')).result,
        isA<AskResult>());
    final r = (await h.say('użyj parametrów')).result as AnswerResult;
    expect(r.show!.fields['q_kj_mm'], closeTo(.96, .00001));
  });
  test('2D fillet gives the full interval, not its midpoint', () async {
    final r = (await BrainHarness().say(
            't8/5 Q 1 kJ/mm temperatura 100 C grubość 5 mm pachwinowa teowa min 5 s max 15 s'))
        .result as AnswerResult;
    final domain = coolingTime(
        heatInputKjMm: 1,
        preheatC: 100,
        thicknessMm: 5,
        shape: WeldShape.filletTee)!;
    expect(domain.isRange, isTrue);
    expect(r.answer.text.pl, contains('–'));
    expect(r.answer.text.pl, contains('Powyżej podanego okna WPS'));
    expect(r.show!.fields['window_min_s'], 5);
    expect(r.show!.fields['window_max_s'], 15);
  });
  test('one-sided WPS window remains one-sided', () async {
    final r =
        (await BrainHarness().say('$input max 15 s')).result as AnswerResult;
    expect(r.show!.fields.containsKey('window_min_s'), isFalse);
    expect(r.answer.text.pl, contains('Cały wynik w podanym oknie'));
  });
  test('spoken command supplies Q, Celsius temperature and WPS window',
      () async {
    final r = (await BrainHarness().say(
            'oblicz t osiem na pięć jeden kilodżul na milimetr temperatura sto stopni Celsjusza grubość dwadzieścia milimetrów wypełnienie okno od pięć do piętnaście sekund',
            byVoice: true))
        .result as AnswerResult;
    expect(r.show!.fields['q_kj_mm'], 1);
    expect(r.show!.fields['preheat_c'], 100);
    expect(r.show!.fields['window_min_s'], 5);
    expect(r.show!.fields['window_max_s'], 15);
  });
  for (final text in [
    't8/5 Q minus 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie',
    't8/5 Q 1 kJ/mm temperatura 500 C grubość 20 mm wypełnienie',
    't8/5 Q 1 kJ/mm temperatura minus 274 C grubość 20 mm wypełnienie',
    't8/5 Q 1 kJ/mm temperatura 100 C grubość minus 20 mm wypełnienie',
    't8/5 Q 1 kJ/mm temperatura 100 C grubość 20 mm wypełnienie napawanie',
    '$input min 15 s max 5 s',
    '$input min minus 5 s',
    '$input min 5 s min 6 s',
    '$input min 5',
    '$input okno 5 do 15',
    '$input okno 5 do 15 s okno 6 do 20 s',
  ]) {
    test('invalid dimensions or window ask without applying: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets('page gets actual result, clears example WPS, rejects atomically',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
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
    expect(ToolBridge.instance.activeToolId, 'cooling_time');
    String field(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(field('cool-wmin'), isEmpty);
    expect(field('cool-wmax'), isEmpty);
    expect(find.byKey(const ValueKey('cool-verdict-notSet')), findsOneWidget);
    final result =
        tester.widget<Readout>(find.byKey(const ValueKey('cool-result')));
    expect(result.value, contains('6,0'));
    expect(
        await ToolBridge.instance.current!
            .apply({...r.show!.fields, 'preheat_c': 500}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(field('cool-t0'), '100.0');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

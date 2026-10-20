import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  const manual = 'oblicz CE C 0,2 Mn 1 pozostałe zero grubość 15 mm';
  test('explicit remainder zero preserves supplied C and Mn', () async {
    final r = (await BrainHarness().say(manual)).result as AnswerResult;
    expect(r.show!.fields['c_pct'], .2);
    expect(r.show!.fields['mn_pct'], 1);
    expect(r.show!.fields['cr_pct'], 0);
    expect(r.answer.text.pl, contains('CE (IIW) = 0,37%'));
    expect(r.answer.text.pl, contains('szacunki, nie temperatura wymagana'));
  });
  test('dialogue never assumes a missing element is zero', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz równoważnik węgla')).result, isA<AskResult>());
    expect((await h.say('0,2 procent')).result, isA<AskResult>());
    expect((await h.say('Mn 1')).result, isA<AskResult>());
    expect((await h.say('pozostałe zero')).result, isA<AskResult>());
    final r = (await h.say('15 mm')).result as AnswerResult;
    expect(r.show!.fields['c_pct'], .2);
    expect(r.show!.fields['mn_pct'], 1);
  });
  test('catalog chemistry and code minimum are explicitly labelled', () async {
    final r = (await BrainHarness().say('podgrzewanie A106 B grubość 15 mm'))
        .result as AnswerResult;
    expect(r.show!.fields['grade_key'], 'A106 B');
    expect(r.show!.fields['c_pct'], .25);
    expect(r.answer.text.pl, contains('Skład typowy z katalogu'));
    expect(r.answer.text.pl, contains('Minimum kodowe B31.3'));
    expect(r.answer.text.pl, contains('10°C'));
  });
  for (final grade in ['304L', 'P91']) {
    test('unsupported CE method for $grade refers to WPS instead of estimating',
        () async {
      final r = (await BrainHarness().say('podgrzewanie $grade grubość 20 mm'))
          .result as AnswerResult;
      expect(r.answer.text.pl,
          contains('metody CE/Seferiana nie są przeznaczone'));
      expect(r.answer.text.pl, isNot(contains('Seferian:')));
    });
  }
  test('catalog and own chemistry require a source choice', () async {
    final h = BrainHarness();
    expect(
        (await h.say(
                'oblicz CE A106 B C 0,2 Mn 1 pozostałe zero grubość 15 mm'))
            .result,
        isA<AskResult>());
    final r = (await h.say('własny skład')).result as AnswerResult;
    expect(r.show!.fields.containsKey('grade_key'), isFalse);
    expect(r.show!.fields['c_pct'], .2);
  });
  test('choosing catalog discards custom analysis', () async {
    final h = BrainHarness();
    expect(
        (await h.say(
                'oblicz CE A106 B C 0,2 Mn 1 pozostałe zero grubość 15 mm'))
            .result,
        isA<AskResult>());
    final r = (await h.say('katalog')).result as AnswerResult;
    expect(r.show!.fields['c_pct'], .25);
  });
  for (final text in [
    'oblicz CE C minus 0,2 Mn 1 pozostałe zero grubość 15 mm',
    'oblicz CE C 0,2 Mn 1 pozostałe zero grubość minus 15 mm',
    'oblicz CE C 0,2 C 0,3 Mn 1 pozostałe zero grubość 15 mm',
    'oblicz CE C 20 g Mn 1 pozostałe zero grubość 15 mm',
    'podgrzewanie A106 B A53 B grubość 15 mm',
  ]) {
    test('invalid or ambiguous input asks without applying: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  test('total chemistry above 100 percent fails', () async {
    final r = (await BrainHarness()
            .say('oblicz CE C 60 Mn 60 pozostałe zero grubość 15 mm'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isFalse);
  });
  testWidgets(
      'actual page switches to CE, fills all chemistry and rejects mixed payload',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1200, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(manual, byVoice: true)).result
        as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'heat_input');
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(find.text('102 °C'), findsWidgets);
    expect(find.textContaining('Nie podano wodoru HD'), findsOneWidget);
    expect(await handle.apply({...r.show!.fields, 'volts': 24}), isNotEmpty);
    expect(await handle.apply({...r.show!.fields, 'c_pct': -1}), isNotEmpty);
    expect(
        await handle
            .apply({...r.show!.fields, 'thickness_mm': double.infinity}),
        isNotEmpty);
    expect(
        await handle.apply({
          'process': 'GTAW',
          'volts': 12,
          'amps': 100,
          'travel_mm_min': 100
        }),
        isEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

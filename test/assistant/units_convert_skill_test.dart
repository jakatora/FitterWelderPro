import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final entry in {
    'Przelicz 2 cale na mm': ('length', 'in'),
    'Convert 5 bar to psi': ('pressure', 'bar'),
    'Przelicz minus 40 stopni Celsjusza na Fahrenheita': ('temperature', '°C'),
    'Przelicz 10 l/min na cfh': ('flow', 'l/min'),
    'Przelicz 10 litrów na minutę na cfh': ('flow', 'l/min'),
  }.entries) {
    test('converts with source and target: ${entry.key}', () async {
      final reply = await BrainHarness().say(entry.key, byVoice: true);
      expect(reply.match?.skill.id, 'units.convert');
      final r = reply.result as AnswerResult;
      expect(r.show!.fields['kind'], entry.value.$1);
      expect(r.show!.fields['from'], entry.value.$2);
    });
  }
  test('missing target dialogue preserves the original source and value',
      () async {
    final h = BrainHarness();
    expect((await h.say('Przelicz 2 cale')).result, isA<AskResult>());
    final result = (await h.say('na mm')).result as AnswerResult;
    expect(result.show!.fields['from'], 'in');
    expect(result.show!.fields['value'], 2);
    expect(result.answer.text.pl, contains('50,8'));
  });
  for (final text in [
    'Przelicz 1 mm na bar',
    'Przelicz 10 slpm na cfh',
    'Przelicz minus 300 C na F',
    'Przelicz minus 5 bar na psi',
    'Przelicz 2 3 cale na mm',
  ]) {
    test('refuses ambiguous or invalid conversion: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
  testWidgets(
      'fills lazy tab, rejects invalid input atomically and reapplies same command',
      (tester) async {
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say('Przelicz 5 bar na psi')).result
        as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    final visible = find.byType(TextField).hitTestable();
    expect(visible, findsOneWidget);
    expect(tester.widget<TextField>(visible).controller!.text, '5.0');
    final handle = ToolBridge.instance.current!;
    expect(
        await handle
            .apply({'kind': 'temperature', 'value': -300, 'from': '°C'}),
        isNotEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(visible).controller!.text, '5.0');
    await tester.enterText(visible, '7');
    expect(await handle.apply(r.show!.fields), isEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(visible).controller!.text, '5.0');
    expect(
        await handle.apply({'kind': 'temperature', 'value': -40, 'from': '°C'}),
        isEmpty);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(visible).controller!.text, '-40.0');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

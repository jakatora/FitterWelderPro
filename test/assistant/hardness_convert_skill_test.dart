import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/features/hardness/hardness_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  testWidgets(
      'module applies conversion and rejects malformed updates atomically',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    ToolBridge.reset();
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const HardnessPage())));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'hardness');
    expect(ToolBridge.instance.isReady(handle), true);
    expect(
        await handle.apply(
            {'value': 300.0, 'scale': 'hv', 'material': 'carbonLowAlloy'}),
        isEmpty);
    await tester.pump();
    final input =
        tester.widget<TextField>(find.byKey(const ValueKey('hard-conv-value')));
    expect(input.controller!.text, '300.0');
    expect(
        await handle.apply(
            {'value': 99.0, 'scale': 'invalid', 'material': 'carbonLowAlloy'}),
        isNotEmpty);
    expect(input.controller!.text, '300.0');
    expect(
        await handle.apply(
            {'value': -1.0, 'scale': 'hv', 'material': 'carbonLowAlloy'}),
        isNotEmpty);
    expect(input.controller!.text, '300.0');
    final row = find.byKey(const ValueKey('hard-row-0-value'));
    await tester.scrollUntilVisible(row, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(row, '220');
    await tester.pump();
    expect(
        await handle
            .apply({'value': 250.0, 'scale': 'hv', 'material': 'stainless'}),
        isNotEmpty);
    expect(tester.widget<TextField>(row).controller!.text, '220');
    expect(input.controller!.text, '300.0');
    await tester.pumpWidget(const SizedBox());
    ToolBridge.reset();
  });

  test('asks material, preserves value and converts through domain table',
      () async {
    final h = BrainHarness();
    final first = await h.say('Przelicz twardość 250 HV na HB', byVoice: true);
    expect(first.match?.skill.id, 'hardness.convert');
    expect((first.result as AskResult).slot, 'material');
    final result = (await h.say('stal niestopowa')).result as AnswerResult;
    expect(result.answer.lines.last.value, '238.00 HB');
    expect(result.show!.fields,
        {'value': 250.0, 'scale': 'hv', 'material': 'carbonLowAlloy'});
  });
  test('asks missing target then material', () async {
    final h = BrainHarness();
    expect((await h.say('Przelicz twardość 250 HV')).result, isA<AskResult>());
    expect(((await h.say('HRC')).result as AskResult).slot, 'material');
    expect(
        ((await h.say('carbon steel')).result as AnswerResult)
            .answer
            .lines
            .last
            .value,
        '22.20 HRC');
  });
  for (final text in [
    'Przelicz 250 HV na HB stal nierdzewna',
    'Przelicz 10 HRC na HV stal niestopowa',
    'Przelicz -250 HV na HB stal niestopowa',
    'Przelicz minus 250 HV na HB stal niestopowa',
    'Przelicz 250 HV i 300 HV na HB stal niestopowa',
    'Przelicz 250 300 HV na HB stal niestopowa',
    'Przelicz 250 HV na HB na HRC stal niestopowa',
  ]) {
    test('no invented conversion: $text', () async {
      expect(
          (await BrainHarness().say(text)).result, isNot(isA<AnswerResult>()));
    });
  }
}

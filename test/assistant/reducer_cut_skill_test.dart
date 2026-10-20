import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';

void main() {
  test('reducer trim is not interpreted as placing a fitting on ISO', () {
    expect(
        parseIsoCommand(Utterance(
            'skróć redukcję duża 100 mm mała 50 mm długość 200 mm docelowa 75 mm',
            lang: AppLanguage.pl)),
        isNull);
  });

  test('conical trim uses actual diameters and matches the independent fixture',
      () async {
    final r = (await BrainHarness().say(
            'skróć redukcję duża 114,3 mm mała 60,3 mm długość 102 mm docelowa 88,9 mm'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('47,98 mm'));
    expect(r.show!.fields,
        {'d1_mm': 114.3, 'd2_mm': 60.3, 'length_mm': 102.0, 'target_mm': 88.9});
  });
  test('explicit OD qualifiers and mixed units work', () async {
    final r = (await BrainHarness().say(
            'redukcja duże OD 10 cm małe OD 50 mm długość 0,2 m docelowe OD 75 mm'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('100 mm od dużego'));
  });
  test('dialogue collects four measurements, preserving dimensions', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz skrócenie redukcji')).result, isA<AskResult>());
    expect((await h.say('100 mm')).result, isA<AskResult>());
    expect((await h.say('50 mm')).result, isA<AskResult>());
    expect((await h.say('20 cm')).result, isA<AskResult>());
    final r = (await h.say('75 mm')).result as AnswerResult;
    expect(r.show!.fields['length_mm'], 200);
    expect(r.answer.text.pl, contains('100 mm od dużego'));
  });
  test('overall reducer length is not accepted as conical length', () async {
    final h = BrainHarness();
    final r = await h.say(
        'redukcja duża 100 mm mała 50 mm cała długość 200 mm docelowa 75 mm');
    expect((r.result as AskResult).slot, 'length_mm');
    final corrected = (await h.say('100 mm')).result as AnswerResult;
    expect(corrected.show!.fields['length_mm'], 100);
    expect(corrected.answer.text.pl, contains('50 mm od dużego'));
  });
  for (final text in [
    'redukcja duża 100 mm mała 100 mm długość 200 mm docelowa 75 mm',
    'redukcja duża 100 mm mała minus 50 mm długość 200 mm docelowa 75 mm',
    'redukcja duża 100 mm mała 50 mm długość 200 mm docelowa 120 mm',
    'redukcja duża 100 mm mała 50 mm długość 0 mm docelowa 75 mm',
    'redukcja duża 100 mm duża 200 mm mała 50 mm długość 200 mm docelowa 75 mm',
  ]) {
    test('invalid data asks and never fills: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'voice command opens the reducer tab and calculates the visible cut',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(950, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(
            'skróć redukcję duża 114,3 mm mała 60,3 mm długość 102 mm docelowa 88,9 mm',
            byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(ToolBridge.instance.activeToolId, 'reducer');
    expect(find.text('48.0 mm'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

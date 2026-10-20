import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('measured arcs produce proportional cut and correct remainder',
      () async {
    final r = (await BrainHarness().say(
            'cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy 30'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('extrados 60 mm, intrados 30 mm'));
    expect(r.answer.text.pl, contains('Zostaje 60°'));
  });
  test('dialogue collects angles and full arcs without assuming base 90',
      () async {
    final h = BrainHarness();
    expect((await h.say('oblicz cięcie kolanka')).result, isA<AskResult>());
    expect((await h.say('45')).result, isA<AskResult>());
    expect((await h.say('90 mm')).result, isA<AskResult>());
    expect((await h.say('45 mm')).result, isA<AskResult>());
    final r = (await h.say('30 stopni')).result as AnswerResult;
    expect(r.show!.fields['base_angle_deg'], 45);
    expect(r.answer.text.pl, contains('extrados 60 mm, intrados 30 mm'));
  });
  for (final text in [
    'cięcie kolanka baza 90 extrados minus 180 mm intrados 90 mm docelowy 45',
    'cięcie kolanka baza 90 extrados 180 mm intrados 180 mm docelowy 45',
    'cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy 90',
    'cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy minus 45',
    'cięcie kolanka baza 90 extrados 180 mm extrados 200 mm intrados 90 mm docelowy 45',
    'cięcie kolanka baza 90 extrados 180 mm intrados 90 mm docelowy 45 docelowy 30',
  ]) {
    test('invalid or conflicting input never applies: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets('command fills actual elbow-cut tab and displays marks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await tester.pumpAndSettle();
    final r = (await BrainHarness().say(
            'przytnij kolano baza 90 długi bok 180 mm krótki bok 90 mm docelowy 45',
            byVoice: true))
        .result as AnswerResult;
    final showing = showInModule(r.show!, explicit: true);
    await tester.pumpAndSettle();
    expect(await showing, ShowOutcome.opened);
    expect(ToolBridge.instance.activeToolId, 'elbow_cut');
    expect(find.text('90.0 mm'), findsWidgets);
    expect(find.text('45.0 mm'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

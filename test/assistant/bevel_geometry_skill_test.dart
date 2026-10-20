import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('X has half depth on each face and explicit angle convention', () async {
    final r = (await BrainHarness().say(
            'fazowanie X ścianka 20 mm kąt na stronę 30 próg 2 mm szczelina 2 mm'))
        .result as AnswerResult;
    expect(r.show!.fields['joint'], 'x');
    expect(r.show!.fields['convention'], 'perSide');
    expect(r.answer.text.pl, contains('9 mm'));
    expect(r.answer.text.pl, contains('5,2 mm'));
  });
  test('dialogue does not assume joint, convention, land or gap', () async {
    final h = BrainHarness();
    expect((await h.say('oblicz fazowanie')).result, isA<AskResult>());
    expect((await h.say('10 mm')).result, isA<AskResult>());
    expect((await h.say('V')).result, isA<AskResult>());
    expect((await h.say('na stronę')).result, isA<AskResult>());
    expect((await h.say('30 stopni')).result, isA<AskResult>());
    expect((await h.say('1 mm')).result, isA<AskResult>());
    final r = (await h.say('0 mm')).result as AnswerResult;
    expect(r.show!.fields['gap_mm'], 0);
    expect(r.show!.fields['root_face_mm'], 1);
    expect(r.show!.fields['angle_deg'], 30);
  });
  for (final text in [
    'fazowanie V ścianka 10 mm kąt 30 próg 1 mm szczelina 0 mm',
    'fazowanie V ścianka 10 mm kąt na stronę 90 próg 1 mm szczelina 0 mm',
    'fazowanie V ścianka 10 mm kąt na stronę 30 próg 10 mm szczelina 0 mm',
    'fazowanie V ścianka 10 mm kąt na stronę 30 próg 1 mm szczelina minus 1 mm',
    'fazowanie V ścianka minus 10 mm kąt na stronę 30 próg 1 mm szczelina 0 mm',
    'fazowanie V ścianka 10 mm kąt na stronę 30 kąt 40 próg 1 mm szczelina 0 mm',
  ]) {
    test('asks for invalid or ambiguous geometry: $text', () async {
      expect((await BrainHarness().say(text)).result, isA<AskResult>());
    });
  }
  testWidgets(
      'spoken bevel and thermal commands produce visible calculated results',
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
    final h = BrainHarness();
    for (final entry in {
      'fazowanie V ścianka 10 mm kąt rowka 60 próg 1 mm szczelina 0 mm':
          '5.20 mm',
      'oblicz dylatację długość 50 m delta 100 C 304L': '80.0 mm',
    }.entries) {
      final r = (await h.say(entry.key, byVoice: true)).result as AnswerResult;
      final showing = showInModule(r.show!, explicit: true);
      await tester.pumpAndSettle();
      expect(await showing,
          isIn([ShowOutcome.opened, ShowOutcome.appliedInPlace]));
      expect(find.text(entry.value), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

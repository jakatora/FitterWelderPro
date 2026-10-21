import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/rigging/rigging_colors.dart';
import 'package:cut_list_app/domain/rigging/colour_reference.dart';
import 'package:cut_list_app/domain/grinding/grinding_check.dart';
import 'package:cut_list_app/domain/grinding/stripe_reference.dart';
import 'package:cut_list_app/features/rigging/rigging_page.dart';
import 'package:cut_list_app/features/rigging/rigging_store.dart';
import 'package:cut_list_app/features/grinding/grinding_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  for (final c in SlingColour.values.where((c) => c.nominalT != null)) {
    test('sling body ${c.name} uses source enum without assessing a lift',
        () async {
      final a =
          (await BrainHarness().say('${c.labelPl} pas ile ton', byVoice: true))
              .result as AnswerResult;
      expect(a.answer.text.pl, slingColourReference(c, tag: false, en: false));
      expect(a.show!.fields,
          {'reference_colour': c.name, 'reference_part': 'body'});
      if (c.orAbove) expect(a.answer.text.pl, contains('i więcej'));
    });
  }
  for (final c in slingTagMaterials.keys) {
    test('sling label ${c.name} is material, not a lifting capacity', () async {
      final a = (await BrainHarness()
              .say('${c.labelPl} etykieta zawiesia jaki materiał'))
          .result as AnswerResult;
      expect(a.answer.text.pl, slingColourReference(c, tag: true, en: false));
      expect(a.answer.text.pl, contains(slingTagMaterials[c]!));
      expect(a.answer.text.pl, isNot(contains('${c.nominalT!.toInt()} t')));
      expect(a.show!.fields['reference_part'], 'tag');
    });
  }
  test('two objects require a part and a colour selection', () async {
    final h = BrainHarness();
    expect(
        ((await h.say('niebieski pas i zielona etykieta zawiesia')).result
                as AskResult)
            .slot,
        'part');
    await h.say('label');
    expect(h.brain.pending!.slot, 'colour');
    final a = (await h.say('green')).result as AnswerResult;
    expect(a.answer.text.en, contains('polyamide (PA)'));
  });
  test('body colour does not identify label material', () async {
    final h = BrainHarness();
    final q =
        (await h.say('zielony pas z jakiego materiału')).result as AskResult;
    expect(q.slot, 'colour');
    final a = (await h.say('niebieska')).result as AnswerResult;
    expect(a.answer.text.en, contains('polyester (PES)'));
  });
  test('disc body colour does not identify the speed stripe', () async {
    final h = BrainHarness();
    final q = (await h.say('czerwona tarcza jaki pasek')).result as AskResult;
    expect(q.slot, 'stripe');
    final a = (await h.say('żółty')).result as AnswerResult;
    expect(a.show!.fields['reference_stripe'], 'yellow');
  });
  test('missing tag is STOP, never a guessed WLL and not a software-gap report',
      () async {
    final a = (await BrainHarness().say('zielony pas bez etykiety ile ton'))
        .result as FailedResult;
    expect(a.reportMissingCapability, isFalse);
    expect(a.message.pl, contains('STOP'));
  });
  test('a real lift request is not answered as a colour-only permission',
      () async {
    final a = (await BrainHarness().say('czy mogę podnieść 3 t zielonym pasem'))
        .result as FailedResult;
    expect(a.reportMissingCapability, isTrue);
  });
  for (final s in SpeedStripe.values) {
    test('stripe ${s.name} uses the existing source value without setting RPM',
        () async {
      final a = (await BrainHarness()
              .say('${s.colourPl} pasek na tarczy', byVoice: true))
          .result as AnswerResult;
      expect(a.answer.text.en, grindingStripeReference(s, en: true));
      expect(a.show!.fields, {'reference_stripe': s.name});
    });
  }
  test('blue or yellow is not silently treated as a combined stripe', () async {
    final h = BrainHarness();
    final q = (await h.say('niebieski lub żółty pasek na tarczy')).result
        as AskResult;
    expect(q.slot, 'stripe');
    final a = (await h.say('blue + yellow')).result as AnswerResult;
    expect(a.show!.fields['reference_stripe'], 'blueYellow');
  });
  test(
      'RPM or compatibility requests are reported rather than inferred from stripe',
      () async {
    final a = (await BrainHarness()
            .say('czy mogę użyć tarczy czerwony pasek 125 mm 12000 rpm'))
        .result as FailedResult;
    expect(a.reportMissingCapability, isTrue);
  });
  test(
      'flap/diamond wheels and unknown colours do not inherit bonded-abrasive values',
      () async {
    for (final q in [
      'czerwony pasek tarcza diamentowa',
      'biały pasek na tarczy',
      'czarny pas ile ton'
    ]) {
      expect(
          ((await BrainHarness().say(q)).result as FailedResult)
              .reportMissingCapability,
          isTrue);
    }
  });
  Future<void> boot(WidgetTester t, Widget page) async {
    ToolBridge.reset();
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(1000, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(), child: MaterialApp(home: page)));
    await t.pumpAndSettle();
  }

  testWidgets(
      'sling reference preserves entered WLL, chosen body colour and preferences',
      (tester) async {
    await boot(tester, const RiggingPage());
    final wll = find.byKey(const ValueKey('rig-wll'));
    await tester.ensureVisible(wll);
    await tester.enterText(wll, '3');
    await tester.tap(find.byKey(const ValueKey('rig-colour-red')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<EditableText>(
            find.descendant(of: wll, matching: find.byType(EditableText)))
        .controller;
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(RiggingStore.key);
    final handle = ToolBridge.instance.current!;
    expect(
        await handle
            .apply({'reference_colour': 'green', 'reference_part': 'body'}),
        isEmpty);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('rig-assistant-reference')), findsOneWidget);
    expect(controller.text, '3');
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('rig-colour-red')))
            .selected,
        isTrue);
    expect(prefs.getString(RiggingStore.key), before);
    expect(
        await handle.apply({
          'reference_colour': 'green',
          'reference_part': 'body',
          'wll': 2000
        }),
        {'reference_colour', 'reference_part', 'wll'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'stripe reference preserves typed speed and selected actual stripe',
      (tester) async {
    await boot(tester, const GrindingPage());
    final field = find.byKey(const ValueKey('gr-disc-v'));
    await tester.ensureVisible(field);
    final edit =
        find.descendant(of: field, matching: find.byType(EditableText));
    await tester.enterText(edit, '90');
    await tester.tap(find.byKey(const ValueKey('gr-stripe-red')));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    expect(await handle.apply({'reference_stripe': 'blueYellow'}), isEmpty);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('gr-assistant-reference')), findsOneWidget);
    expect(tester.widget<EditableText>(edit).controller.text, startsWith('90'));
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('gr-stripe-red')))
            .selected,
        isTrue);
    expect(await handle.apply({'reference_stripe': 'blue', 'disc_v': 50}),
        {'reference_stripe', 'disc_v'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

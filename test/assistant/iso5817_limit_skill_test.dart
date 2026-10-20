import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_limits.dart';
import 'package:cut_list_app/domain/iso5817/iso5817_table.dart';
import 'package:cut_list_app/features/iso5817/iso5817_page.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test(
      'generic ISO question requires edition confirmation and retains all fields',
      () async {
    final h = BrainHarness();
    final r =
        (await h.say('Limit ISO 5817 5011 poziom B t 10 mm spoina czołowa'))
            .result as AskResult;
    expect(r.slot, 'edition');
    final a = (await h.say('2014')).result as AnswerResult;
    expect(a.answer.source!.pl, contains('2014'));
    expect(a.show!.fields['t'], 10);
    expect(a.show!.fields['limit_only'], isTrue);
  });
  test('2023 never silently uses the 2014 numerical table', () async {
    final r = (await BrainHarness()
            .say('Limit ISO 5817 2023 5011 poziom B t 10 mm spoina czołowa'))
        .result as FailedResult;
    expect(r.reportMissingCapability, isTrue);
  });
  for (final t in [3.0, 3.01, 10.0, 100.0]) {
    test('limits use domain thickness branch and cap: t=$t', () async {
      final a = (await BrainHarness().say(
              'Limit ISO 5817 2014 5011 poziom B t $t mm spoina czołowa krótkie'))
          .result as AnswerResult;
      final limit = iso5817Limit(
          iso5817ItemById('1.7')!, Iso5817Level.b, Iso5817Input(t: t));
      expect(
          a.answer.text.pl, contains(iso5817LimitValueText(limit, en: false)));
      expect(a.show!.fields['item_id'], '1.7');
    });
  }
  test(
      'measurement report is the same domain report and uses a supplied measurement',
      () async {
    final a = (await BrainHarness().say(
            'Sprawdź ISO 5817 2014 5011 poziom B t 10 mm pomiar 0,4 mm spoina czołowa'))
        .result as AnswerResult;
    final input = Iso5817Input(t: 10);
    final result = assessIso5817(
        item: iso5817ItemById('1.7')!,
        required: Iso5817Level.b,
        input: input,
        measured: .4,
        isShort: false);
    expect(
        a.answer.text.pl,
        buildIso5817Report(
            assessment: result,
            kind: Iso5817WeldKind.butt,
            input: input,
            en: false));
    expect(a.show!.fields['limit_only'], isFalse);
  });
  test('missing width asks rather than borrowing old UI width', () async {
    final h = BrainHarness();
    final r = (await h.say(
            'Limit ISO 5817 2014 pozycja 1.9 poziom C t 10 mm spoina czołowa'))
        .result as AskResult;
    expect(r.slot, 'b');
    final a = (await h.say('b 12 mm')).result as AnswerResult;
    expect(a.show!.fields['b'], 12);
    expect(a.show!.fields['measured'], isNull);
  });
  test('undercut kinds require exact choice, never first table row', () async {
    final h = BrainHarness();
    final q = (await h.say(
            'Limit ISO 5817 2014 podtopienie poziom B t 10 mm spoina czołowa'))
        .result as AskResult;
    expect(q.slot, 'items');
    expect(q.choices.length, 2);
    final a = (await h.say('item 1.7')).result as AnswerResult;
    expect(a.show!.fields['item_id'], '1.7');
  });
  test('short-only limit requires the actual short/long classification',
      () async {
    final h = BrainHarness();
    final q = (await h.say(
            'Sprawdź ISO 5817 2014 5011 poziom C t 2 mm pomiar 0,1 mm spoina czołowa'))
        .result as AskResult;
    expect(q.slot, 'short');
    final a = (await h.say('long')).result as AnswerResult;
    expect(a.show!.fields['short'], isFalse);
    expect(a.answer.text.pl, contains('dług'));
  });
  test('spoken values share number tokenizer', () async {
    final a = (await BrainHarness().say(
            'Limit ISO 5817 2014 5011 poziom B t dziesięć milimetrów spoina czołowa',
            byVoice: true))
        .result as AnswerResult;
    expect(a.show!.fields['t'], 10);
  });
  test('numeric input conflicts do not invent a limit', () async {
    final r = (await BrainHarness().say(
            'Limit ISO 5817 2014 5011 poziom B t 10 mm t 12 mm spoina czołowa'))
        .result as AskResult;
    expect(r.slot, 't');
  });
  test('out-of-scope internal imperfection and fatigue create capability gaps',
      () async {
    for (final command in [
      'Limit ISO 5817 2014 2011 poziom B t 10 mm spoina czołowa',
      'Limit ISO 5817 2014 5011 poziom B t 10 mm spoina czołowa fatigue'
    ]) {
      final r = (await BrainHarness().say(command)).result as FailedResult;
      expect(r.reportMissingCapability, isTrue);
    }
  });
  test('spoken level letters and bare dimension answer remain local', () async {
    final h = BrainHarness();
    final q = (await h.say(
            'Limit ISO 5817 2014 item 1.9 poziom ce t 10 mm spoina czołowa',
            byVoice: true))
        .result as AskResult;
    expect(q.slot, 'b');
    final a = (await h.say('dwanaście milimetrów', byVoice: true)).result
        as AnswerResult;
    expect(a.show!.fields['level'], 'c');
    expect(a.show!.fields['b'], 12);
  });
  test(
      'angle measurements require degree units and never accept impossible angles',
      () async {
    final h = BrainHarness();
    final q = (await h.say(
            'Sprawdź ISO 5817 2014 item 1.12 butt poziom B t 10 mm pomiar 120 mm'))
        .result as AskResult;
    expect(q.slot, 'measured');
    final q2 = (await h.say('kąt 200 stopni')).result as AskResult;
    expect(q2.slot, 'measured');
    final a = (await h.say('kąt 120 stopni')).result as AnswerResult;
    expect(a.show!.fields['measured'], 120);
  });
  test(
      'presence assessment requires confirmation; no returns to limit reference',
      () async {
    final h = BrainHarness();
    final q = (await h.say(
            'Sprawdź ISO 5817 2014 item 1.1 poziom B t 10 mm spoina czołowa'))
        .result as AskResult;
    expect(q.slot, 'present');
    final a = (await h.say('nie')).result as AnswerResult;
    expect(a.show!.fields['limit_only'], isTrue);
    expect(a.answer.text.pl, isNot(contains('Stwierdzono: tak')));
  });
  test('explaining a check command never runs its assessment', () async {
    final r = await BrainHarness().say(
        'Wyjaśnij polecenie sprawdź ISO 5817 2014 5011 poziom B t 10 mm pomiar 0,4 mm spoina czołowa');
    expect(r.match?.skill.id, isNot('iso5817.limit'));
  });
  test(
      'all source table names in PL and EN can be selected without an alias list',
      () async {
    for (final item in kIso5817Items) {
      for (final (lang, name) in [
        (AppLanguage.pl, item.namePl),
        (AppLanguage.en, item.nameEn)
      ]) {
        final r =
            await BrainHarness(lang: lang).say('ISO 5817 2014 limit $name');
        expect(r.match?.skill.id, 'iso5817.limit', reason: name);
        expect(r.match!.slots['items'], contains(item.id), reason: name);
      }
    }
  });
  test('the active ISO screen never steals a different calculator command',
      () async {
    final r = await BrainHarness(activeToolId: 'iso5817', onHome: false).say(
        'Sprawdź przewody spawalniczy 25 m masowy 25 m 601 A 60% otoczenie 30 C próg 4 V przekrój 35 mm²');
    expect(r.match?.skill.id, 'power.cable');
  });
  testWidgets(
      'limit reference never asserts the presence of a crack or exports an assessment',
      (tester) async {
    ToolBridge.reset();
    await tester.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(),
        child: const MaterialApp(home: Iso5817Page())));
    await tester.pumpAndSettle();
    final handle = ToolBridge.instance.current!;
    final fields = {
      'item_id': '1.1',
      'kind': 'butt',
      'level': 'b',
      't': 10.0,
      'short': false,
      'limit_only': true
    };
    expect(await handle.apply(fields), isEmpty);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('iso5817-enable-assessment')), 400,
        scrollable: find
            .descendant(
                of: find.byType(Iso5817Page), matching: find.byType(Scrollable))
            .first);
    expect(find.byKey(const ValueKey('iso5817-verdict')), findsNothing);
    expect(find.byKey(const ValueKey('iso5817-share')), findsNothing);
    expect(
        find.textContaining('obecność niezgodności nie została potwierdzona'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('iso5817-enable-assessment')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('iso5817-verdict')), findsOneWidget);
    expect(await handle.apply({...fields, 'kind': 'unknown'}),
        fields.keys.toSet());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

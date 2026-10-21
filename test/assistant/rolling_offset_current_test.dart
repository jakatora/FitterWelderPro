import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/fitter/rolling_offset.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/screens/rolling_offset_screen.dart';
import 'support/assistant_test_support.dart';

const geometry = 'rolling offset wznios 300 mm odsunięcie 400 mm kąt 45 stopni';
const cutCommand = '$geometry DN100 LR szczelina 3 mm';
const cutFields = {
  'rise_mm': 300,
  'spread_mm': 400,
  'angle_deg': 45,
  'dn': 100,
  'gap_mm': 3
};
Finder input(String fragment) => find.byWidgetPredicate((w) =>
    w is TextField &&
    !w.readOnly &&
    (w.decoration?.labelText ?? '').contains(fragment));
Future<void> mountRolling(WidgetTester t) async {
  ToolBridge.reset();
  t.view.physicalSize = const Size(1000, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pumpAndSettle();
  });
  await t.pumpWidget(AppLanguageScope(
      controller: AppLanguageController(AppLanguage.pl),
      child: MaterialApp(
          navigatorKey: appNavigatorKey,
          navigatorObservers: [appRoutes],
          home: const RollingOffsetScreen())));
  await t.pumpAndSettle();
}

void main() {
  test('validated input uses actual B45 table cut and freezes complete fields',
      () {
    final r = RollingOffsetInput.fromFields(cutFields);
    expect(r.cut!.takeout.mm, 64);
    expect(r.cut!.cutMm, closeTo(573.1067811865476, 1e-9));
    expect(() => r.fields['dn'] = 50, throwsUnsupportedError);
    for (final patch in <Map<String, Object?>>[
      {'dn': 110},
      {'dn': 100.5},
      {'gap_mm': null},
      {'gap_mm': -1},
      {'gap_mm': double.infinity},
      {'rise_mm': 0},
      {'angle_deg': 89},
      {'spread_mm': double.nan},
      {'unexpected': 1},
      {'rise_mm': 20, 'spread_mm': 20},
    ]) {
      expect(() => RollingOffsetInput.fromFields({...cutFields, ...patch}),
          throwsFormatException);
    }
  });
  test(
      'fresh cut dialogue asks for the actual gap; geometry remains compatible',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        ((await h.say('$geometry DN100')).result as AskResult).slot, 'gap_mm');
    final a = (await h.say('3 mm', byVoice: true)).result as AnswerResult;
    expect(a.answer.text.pl, contains('573,11'));
    expect(a.answer.source!.pl, contains('B (45°)'));
    expect(a.show!.fields['gap_mm'], 3);
  });
  test('cut request asks DN and accepts a single spoken bare DN', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(((await h.say('$geometry szczelina 0 mm')).result as AskResult).slot,
        'dn');
    final a = (await h.say('sto')).result as AnswerResult;
    expect(a.show!.fields['dn'], 100);
  });
  test('SR/3D cut refuses but radius-independent geometry is still available',
      () async {
    for (final family in ['SR', '3D', 'SR90']) {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final no = (await h.say('$geometry DN100 $family szczelina 3 mm')).result
          as FailedResult;
      expect(no.reportMissingCapability, true);
      final modelGeometry = family == 'SR90'
          ? 'rolling offset wznios 300 mm odsunięcie 400 mm'
          : geometry;
      final yes = (await h.say('$modelGeometry $family tylko geometria')).result
          as AnswerResult;
      expect(yes.answer.source, isNull);
      expect(yes.show!.fields['dn'], isNull);
    }
  });
  test(
      'attached LR angle is explicit and a conflicting target must be resolved',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final q = (await h.say('$geometry DN100 LR90 szczelina 3 mm')).result
        as AskResult;
    expect(q.slot, 'angle_deg');
    final a = (await h.say('45')).result as AnswerResult;
    expect(a.show!.fields['angle_deg'], 45);
    expect(a.answer.source!.pl, contains('B (45°)'));
    final b = (await h.say(
            'rolling offset wznios 300 mm odsunięcie 400 mm DN100 LR90 szczelina 3 mm'))
        .result as AnswerResult;
    expect(b.show!.fields['angle_deg'], 90);
    expect(b.answer.text.pl, contains('190 mm'));
    expect(b.answer.source!.pl, contains('A (90°)'));
  });
  test('custom-radius cut cannot silently use a standard DN takeout', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('$geometry DN100 promień 100 mm szczelina 3 mm'))
        .result as FailedResult;
    expect(r.reportMissingCapability, true);
  });
  testWidgets(
      'real readback preserves manual rise, DN/gap; invalid changes are atomic and fresh geometry clears cut',
      (t) async {
    await mountRolling(t);
    final b = ToolBridge.instance, handle = ToolBridge.instance.current!;
    expect(await handle.apply(cutFields), isEmpty);
    await t.pumpAndSettle();
    expect(find.text('573.1'), findsOneWidget);
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ctx = AssistantContext(lang: AppLanguage.pl, modules: b);
    Future<SkillResult> say(String s) async => (await h.brain
            .handle(Utterance(s, lang: AppLanguage.pl, byVoice: true), ctx))
        .result;
    await t.enterText(input('Rise'), '600');
    await t.pumpAndSettle();
    final edit = await say('zmień kąt na 30 stopni') as AnswerResult;
    expect(edit.show!.fields['rise_mm'], 600);
    expect(edit.show!.fields['dn'], 100);
    expect(edit.show!.fields['gap_mm'], 3);
    expect(await handle.apply(edit.show!.fields), isEmpty);
    await t.pumpAndSettle();
    // A native selection changed after the prior dialogue must win.
    t
        .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>))
        .onChanged!(50);
    await t.pumpAndSettle();
    final next = await say('a szczelina 2 mm') as AnswerResult;
    expect(next.show!.fields['dn'], 50);
    expect(next.show!.fields['rise_mm'], 600);
    expect(await handle.apply(next.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(ctx.recentSlot('dn'), 50);
    final wall = await h.brain
        .handle(Utterance('a ścianka?', lang: AppLanguage.pl), ctx);
    expect(wall.match?.skill.id, 'pipe.wall');
    expect(wall.match?.slots['dn'], 50);
    final before = Map.of(b.inputFields('rolling_offset')!);
    for (final p in <Map<String, Object?>>[
      {'dn': 110},
      {'gap_mm': -1},
      {'action': 'clear', 'dn': 100},
      {'angle_deg': double.infinity}
    ]) {
      expect(await handle.apply({...next.show!.fields, ...p}), isNotEmpty);
      expect(b.inputFields('rolling_offset'), before);
    }
    final q = await say('zmień DN na 110');
    expect(q, isA<AskResult>());
    expect(b.inputFields('rolling_offset'), before);
    final correction = await say('DN100') as AnswerResult;
    expect(correction.show!.fields['rise_mm'], 600);
    expect(await handle.apply(correction.show!.fields), isEmpty);
    await t.pumpAndSettle();
    final fresh =
        (await h.brain.handle(Utterance(geometry, lang: AppLanguage.pl), ctx))
            .result as AnswerResult;
    expect(fresh.show!.fields.keys, hasLength(3));
    expect(await handle.apply(fresh.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(b.inputFields('rolling_offset')!['dn'], isNull);
    final clear = await say('wyczyść rolling offset') as AnswerResult;
    expect(await handle.apply(clear.show!.fields), isEmpty);
    await t.pumpAndSettle();
    expect(b.inputFields('rolling_offset')!['rise_mm'], isNull);
    expect(b.inputFields('rolling_offset')!['angle_deg'], 45);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'manual invalid nonblank gap never silently becomes zero for a cut',
      (t) async {
    await mountRolling(t);
    await ToolBridge.instance.current!.apply(cutFields);
    await t.pumpAndSettle();
    await t.enterText(input('Szczelina'), '.');
    await t.pumpAndSettle();
    await t.tap(find.text('OBLICZ'));
    await t.pumpAndSettle();
    expect(find.text('573.1'), findsNothing);
    expect(
        find.text('Podaj szczelinę spoiny co najmniej 0 mm.'), findsOneWidget);
  });
}

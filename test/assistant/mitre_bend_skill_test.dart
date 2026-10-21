import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/app_navigator.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/core/tool_bridge.dart';
import 'package:cut_list_app/domain/fitter/mitre_bend.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/widgets/readout.dart';
import 'support/assistant_test_support.dart';

const fullCommand =
    'Oblicz kolano segmentowe OD 168,3 mm kąt 90 stopni 3 spoiny promień 252,45 mm prosty 0 mm';

void main() {
  test('whole brain uses native geometry and actual values', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(fullCommand, byVoice: true);
    expect(reply.match?.skill.id, 'mitre.bend');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('kąt cięcia 15°'));
    expect(r.answer.lines[0].value, '135,29 mm');
    expect(r.show!.fields, containsPair('welds', 3));
    expect(r.show!.fields, containsPair('radius_mm', 252.45));
    expect(r.show!.toolId, 'mitre_bend');
  });
  test('dialogue asks all geometric inputs without remembered defaults',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('oblicz kolano segmentowe'), 'od_mm');
    expect(await ask('DN100'), 'angle_deg');
    expect(await ask('90'), 'welds');
    expect(await ask('3'), 'radius_mm');
    expect(await ask('20 cm'), 'tangent_mm');
    final r = (await h.say('0 mm')).result as AnswerResult;
    expect(r.show!.fields, {
      'od_mm': 114.3,
      'angle_deg': 90.0,
      'welds': 3,
      'radius_mm': 200.0,
      'tangent_mm': 0.0
    });
  });
  test(
      'DN conversion cites the table and manual OD correction drops that source',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final good = (await h.say(
            'kolano segmentowe DN100 kąt 90 stopni 3 spoiny promień 200 mm prosty 0 mm'))
        .result as AnswerResult;
    expect(good.answer.source?.pl, contains('B36.10M'));
    await h.say(
        'kolano segmentowe DN9999 kąt 90 stopni 3 spoiny promień 200 mm prosty 0 mm');
    final corrected = (await h.say('100 mm')).result as AnswerResult;
    expect(corrected.show!.fields['od_mm'], 100);
    expect(corrected.answer.source, isNull);
  });
  test('an unrelated correction cannot resolve an ambiguous angle', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final first = (await h.say(
            'kolano segmentowe OD 100 mm kąt 90 albo 60 stopni 3 spoiny promień 200 mm prosty 0 mm'))
        .result as AskResult;
    expect(first.slot, 'angle_deg');
    final other = (await h.say('spoiny 4')).result as AskResult;
    expect(other.slot, 'angle_deg');
    final r = (await h.say('60')).result as AnswerResult;
    expect(r.show!.fields['angle_deg'], 60);
    expect(r.show!.fields['welds'], 4);
  });
  test('explicit DN carries to another tool; manual OD clears it', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say(
        'kolano segmentowe DN100 kąt 90 stopni 3 spoiny promień 200 mm prosty 0 mm');
    final wall = await h.say('a ścianka sch 40');
    expect(wall.match?.skill.id, 'pipe.wall');
    expect(wall.result, isA<AnswerResult>());
    expect(wall.match?.slots['dn'], 100);
    await h.say(fullCommand);
    final unknown = await h.say('a ścianka sch 40');
    expect(unknown.result, isA<AskResult>());
    expect((unknown.result as AskResult).slot, 'dn');
  });
  test('natural count label and conjunction before a named count remain valid',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h
            .say(fullCommand.replaceFirst('3 spoiny', 'liczba spoin wynosi 3')))
        .result as AnswerResult;
    expect(r.show!.fields['welds'], 3);
    final second = (await h.say(
            'kolano segmentowe OD 100 mm kąt 90 stopni i 3 spoiny promień 200 mm prosty 0 mm'))
        .result as AnswerResult;
    expect(second.show!.fields['angle_deg'], 90);
    expect(second.show!.fields['welds'], 3);
  });
  test('single weld ignores radius and asks for enough tangent', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final a = (await h.say(
            'kolano segmentowe OD 100 mm kąt 90 stopni 1 spoina prosty 0 mm'))
        .result as AskResult;
    expect(a.slot, 'tangent_mm');
    final r = (await h.say('100 mm')).result as AnswerResult;
    expect(r.show!.fields['radius_mm'], 0);
    expect(r.answer.text.pl, contains('0 pełnych segmentów i 2 końcowe'));
    expect(r.answer.lines[0].value, '100 mm');
  });
  for (final (change, slot) in <(String, String)>[
    ('OD 0 mm', 'od_mm'),
    ('OD minus 100 mm', 'od_mm'),
    ('DN9999', 'od_mm'),
    ('DN50 OD 168,3 mm', 'od_mm'),
    ('OD 4000 mm', 'od_mm'),
    ('kąt 0 stopni', 'angle_deg'),
    ('kąt 181 stopni', 'angle_deg'),
    ('3,5 spoiny', 'welds'),
    ('0 spoin', 'welds'),
    ('13 spoin', 'welds'),
    ('spoiny 3 mm', 'welds'),
    ('spoiny 3 kg', 'welds'),
    ('promień 80 mm', 'radius_mm'),
    ('promień minus 200 mm', 'radius_mm'),
    ('prosty minus 10 mm', 'tangent_mm'),
    ('OD 100 mm albo 200 mm', 'od_mm'),
    ('OD 100 mm 200 mm', 'od_mm'),
    ('kąt 90 60', 'angle_deg'),
    ('3 albo 4 spoiny', 'welds'),
  ]) {
    test('invalid or ambiguous continuation asks: $change', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      expect((await h.say(fullCommand)).result, isA<AnswerResult>());
      final r = (await h.say(change.startsWith('DN50 OD')
              ? 'kolano segmentowe $change kąt 90 stopni 3 spoiny promień 252,45 mm prosty 0 mm'
              : 'a $change'))
          .result;
      expect(r, isA<AskResult>());
      expect((r as AskResult).slot, slot);
      expect(h.actions.savedParams, isEmpty);
      expect(h.actions.savedJournal, isEmpty);
    });
  }
  test('ambiguous count can be corrected without losing dimensions', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say(
                'kolano segmentowe OD 168,3 mm kąt 90 stopni 3 albo 4 spoiny promień 252,45 mm prosty 0 mm'))
            .result,
        isA<AskResult>());
    final r = (await h.say('spoiny 4')).result as AnswerResult;
    expect(r.show!.fields['welds'], 4);
    expect(r.show!.fields['od_mm'], 168.3);
  });
  test('new independent command interrupts pending question', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    await h.say('oblicz kolano segmentowe');
    final r = await h
        .say('ile waży rura DN50 ścianka 3 mm stal węglowa długość 2 metry');
    expect(r.match?.skill.id, 'pipe.weight');
    expect(r.result, isA<AnswerResult>());
  });
  testWidgets('native bridge applies values atomically and shows actual cut',
      (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.5;
    addTearDown(t.view.reset);
    ToolBridge.reset();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
    await t.pumpWidget(AppLanguageScope(
        controller: AppLanguageController(AppLanguage.pl),
        child: MaterialApp(
            navigatorKey: appNavigatorKey,
            navigatorObservers: [appRoutes],
            home: const Scaffold(body: Text('Start')))));
    await t.pumpAndSettle();
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(fullCommand)).result as AnswerResult;
    final opening = showInModule(r.show!, explicit: true);
    await t.pumpAndSettle();
    expect(await opening, ShowOutcome.opened);
    final handle = ToolBridge.instance.current!;
    expect(handle.toolId, 'mitre_bend');
    String field(String key) =>
        t.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    expect(field('mitre-od'), '168.3');
    expect(field('mitre-radius'), '252.45');
    expect(find.descendant(of: find.byType(Readout), matching: find.text('15')),
        findsOneWidget);
    for (final patch in <Map<String, Object?>>[
      {'od_mm': 0},
      {'welds': 2.5},
      {'radius_mm': double.infinity},
      {'radius_mm': 80},
      {'tangent_mm': -1},
      {'unexpected': 1},
    ]) {
      expect(await handle.apply({...r.show!.fields, ...patch}), isNotEmpty);
      await t.pump();
      expect(field('mitre-od'), '168.3');
      expect(field('mitre-radius'), '252.45');
      expect(
          find.descendant(of: find.byType(Readout), matching: find.text('15')),
          findsOneWidget);
    }
    expect(await handle.apply({'od_mm': 100}), isNotEmpty);
    expect(field('mitre-od'), '168.3');
    expect(t.takeException(), isNull);
  });
  for (final radius in [double.infinity, double.nan, double.maxFinite]) {
    test('nonfinite or overflowing native geometry refuses $radius', () {
      expect(
          computeMitreBend(MitreBendInput(
              odMm: 100, bendAngleDeg: 180, welds: 2, radiusMm: radius)),
          isNull);
    });
  }
}

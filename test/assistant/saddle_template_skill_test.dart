import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('angled branch: strip length π·d and template fields', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(
        'Szablon siodła rura główna 168,3 mm odgałęzienie 114,3 mm kąt 45 stopni',
        byVoice: true);
    expect(reply.match?.skill.id, 'saddle.template');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl,
        contains('π·d = ${(math.pi * 114.3).toStringAsFixed(2).replaceAll('.', ',')} mm'));
    expect(r.show!.toolId, 'saddle_template');
    expect(r.show!.fields,
        {'header_od_mm': 168.3, 'branch_od_mm': 114.3, 'angle_deg': 45.0});
  });

  test('90° without printing stays with the 90° table; angles go here',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say('siodło 90 stopni rura główna 100 mm odgałęzienie 60 mm'))
            .match
            ?.skill
            .id,
        'saddle.cut');
    expect((await h.say('siodło 60 mm na 100 mm kąt 45 stopni')).match?.skill.id,
        'saddle.template');
    expect((await h.say('szablon siodła 60 mm na 100 mm kąt 90 stopni'))
            .match
            ?.skill
            .id,
        'saddle.template');
  });

  test('dialogue asks the angle; angles outside 15–90° are refused', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ask = (await h.say('szablon siodła DN50 na DN100')).result as AskResult;
    expect(ask.slot, 'angle_deg');
    final r = (await h.say('60')).result as AnswerResult;
    expect(r.show!.fields['angle_deg'], 60.0);
    expect((await h.say('szablon siodła DN50 na DN100 kąt 10 stopni')).result,
        isA<FailedResult>());
  });
}

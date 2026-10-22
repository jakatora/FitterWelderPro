import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/pwht/pwht_plan.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('B31.3 P-No 1 25 mm: same plan as the module tables', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Czy potrzebne PWHT B31.3 P-No 1 grubość 25 mm',
        byVoice: true);
    expect(reply.match?.skill.id, 'pwht.plan');
    final r = reply.result as AnswerResult;
    final plan = planPwht(const PwhtInput(
        code: PwhtCode.asmeB313, material: PwhtMaterial.p1, thicknessMm: 25))!;
    final range = plan.entry.holdRange!;
    expect(r.answer.text.pl,
        contains('Wytrzymanie ${range.minC}–${range.maxC} °C, min. ${plan.holdMinutes} min'));
    expect(r.answer.text.pl, contains('Wiążą WPS'));
    expect(r.show!.toolId, 'pwht_planner');
    expect(r.show!.fields,
        {'code': 'asmeB313', 'material': 'p1', 'thickness_mm': 25.0});
  });

  test('grade names map to P-No groups; austenitic needs no PWHT by table',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final p91 = (await h.say('Plan PWHT B31.1 P91 grubość 30 mm')).result
        as AnswerResult;
    expect(p91.show!.fields['material'], 'p15e');
    expect(p91.answer.text.pl, contains('PWHT wymagane'));
    final crmo = (await h.say(
            'Wyżarzanie odprężające B31.3 13CrMo4-5 grubość 15 mm OD 168,3 mm'))
        .result as AnswerResult;
    expect(crmo.show!.fields['material'], 'p4');
    expect(crmo.show!.fields['od_mm'], 168.3);
    final ss = (await h.say('PWHT B31.3 nierdzewna 304L grubość 12 mm')).result
        as AnswerResult;
    expect(ss.answer.text.pl, contains('tabela nie wymaga PWHT'));
  });

  test('dialogue asks code, group and thickness; preheat is not PWHT',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('zaplanuj obróbkę cieplną PWHT'), 'code');
    expect(await ask('B31.3'), 'material');
    expect(await ask('P22'), 'thickness_mm');
    final r = (await h.say('40 mm')).result as AnswerResult;
    expect(r.show!.fields['material'], 'p5a');
    expect((await h.say('jakie podgrzewanie wstępne dla P91')).match?.skill.id,
        isNot('pwht.plan'));
  });
}

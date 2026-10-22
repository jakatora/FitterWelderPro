import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('V groove reference: A_w = t·d + (t−c)²·tan(α/2)', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // A_w = 10·2 + 8,5²·tan 30° = 61,71 mm²; S = 0,2·6,171 + 0,05·2 = 1,334
    // → w górę do 0,1 mm: 1,4 mm.
    final reply = await h.say(
        'Skurcz spoiny czołowej blacha 10 mm rowek V kąt 60 stopni szczelina 2 mm próg 1,5 mm',
        byVoice: true);
    expect(reply.match?.skill.id, 'distortion.shrinkage');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('jednej spoiny czołowej: 1,4 mm'));
    expect(r.show!.toolId, 'distortion');
    expect(r.show!.fields, {
      'groove': 'v',
      'thickness_mm': 10.0,
      'gap_mm': 2.0,
      'root_face_mm': 1.5,
      'angle_deg': 60.0,
    });
  });

  test('pre-weld length: final + n × S, rounded up to 0.5 mm', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // 1000 + 2 × 1,4 = 1002,8 → 1003.
    final r = (await h.say(
            'Wymiar przed spawaniem wymiar końcowy 1000 mm 2 spoiny czołowe blacha 10 mm rowek V kąt 60 stopni szczelina 2 mm próg 1,5 mm'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('przed spawaniem: 1003 mm'));
    expect(r.show!.fields['butt_welds'], 2);
    expect(r.show!.fields['fillet_welds'], 0);
  });

  test('groove kinds and the half-V bevel angle', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final half = (await h.say(
            'Ile się skurczy spoina pół V blacha 12 mm kąt 45 stopni szczelina 2 mm próg 1 mm'))
        .result as AnswerResult;
    expect(half.show!.fields['groove'], 'halfV');
    final x = (await h.say(
            'Skurcz poprzeczny rowek X blacha 20 mm kąt 60 stopni szczelina 3 mm próg 2 mm'))
        .result as AnswerResult;
    expect(x.show!.fields['groove'], 'x');
  });

  test('dialogue asks for every groove input', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('oblicz skurcz spawalniczy'), 'thickness_mm');
    expect(await ask('10 mm'), 'groove');
    expect(await ask('rowek V'), 'angle_deg');
    expect(await ask('60'), 'gap_mm');
    expect(await ask('2 mm'), 'root_face_mm');
    final r = (await h.say('1,5 mm')).result as AnswerResult;
    expect(r.show!.fields['root_face_mm'], 1.5);
  });

  test('thermal expansion is not weld shrinkage', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('jaki skurcz rury przy dylatacji 80 stopni');
    expect(reply.match?.skill.id, isNot('distortion.shrinkage'));
  });

  test('the full module title with "i" is explained, not calculated',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply =
        await h.say('do czego służą odkształcenia i skurcz spawalniczy');
    expect(reply.match?.skill.id, 'tool.explain');
  });
}

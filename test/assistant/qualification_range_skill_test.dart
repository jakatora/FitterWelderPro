import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('ISO 9606-1 tab. 6: BW 8 mm → 3–16 mm; tab. 7: D 60,3 → ≥ 30,15',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(
        'Zakres uprawnień próbka spoina czołowa grubość 8 mm rura 60,3 mm',
        byVoice: true);
    expect(reply.match?.skill.id, 'qualification.range');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('grubość 3–16 mm'));
    expect(r.answer.text.pl, contains('średnice ≥ 30,15 mm'));
    expect(r.show!.toolId, 'qualification_range');
    expect(r.show!.fields,
        {'weld_type': 'bw', 'thickness_mm': 8.0, 'diameter_mm': 60.3});
  });

  test('thin plate, s ≥ 12 layers note, fillet table 8, oxyacetylene', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final thin = (await h.say('co obejmuje egzamin na blasze 2 mm spoina czołowa'))
        .result as AnswerResult;
    expect(thin.answer.text.pl, contains('grubość 2–4 mm'));
    final thick = (await h.say(
            'jaki zakres grubości daje próbka spoina czołowa 14 mm'))
        .result as AnswerResult;
    expect(thick.answer.text.pl, contains('≥ 3 mm'));
    expect(thick.answer.text.pl, contains('co najmniej 3 warstwy'));
    final fw = (await h.say('zakres grubości spoina pachwinowa próbka 5 mm'))
        .result as AnswerResult;
    expect(fw.answer.text.pl, contains('(tab. 8)'));
    final gas = (await h.say('zakres grubości próbka 311 spoina czołowa 4 mm'))
        .result as AnswerResult;
    expect(gas.answer.text.pl, contains('grubość 3–6 mm'));
  });

  test('certificate expiry is a different question', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect((await h.say('kiedy mi wygasa uprawnienie na 141')).match?.skill.id,
        isNot('qualification.range'));
  });
}

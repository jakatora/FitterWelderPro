import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('ASME B16.5: DN100 Class 300 RF → 8 × 3/4" × 4-1/2"', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply =
        await h.say('Długość szpilek DN100 klasa 300 RF', byVoice: true);
    expect(reply.match?.skill.id, 'bolt.kit');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('8 szpilek 3/4" × 4-1/2" (≈ 114,3 mm)'));
    expect(r.answer.text.pl, contains('16 nakrętek'));
    expect(r.show!.toolId, 'bolt_kit');
    expect(r.show!.fields, {'dn': 100, 'class': 300, 'facing': 'rf'});
  });

  test('kit for several joints, RTJ length', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('Komplet śrub na 4 połączenia DN80 klasa 600 RTJ'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('32 szpilek'));
    expect(r.answer.text.pl, contains('64 nakrętek'));
    expect(r.show!.fields['joints'], 4);
  });

  test('torque stays with the torque calculator; facing is asked', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say('jaki moment dokręcenia śruby 3/4 cala B7 na smarze'))
            .match
            ?.skill
            .id,
        isNot('bolt.kit'));
    final ask =
        (await h.say('jakie szpilki do kołnierza DN150 klasa 150')).result;
    expect((ask as AskResult).slot, 'facing');
    final r = (await h.say('RF')).result as AnswerResult;
    expect(r.answer.text.pl, contains('8 szpilek 3/4" × 4"'));
  });
}

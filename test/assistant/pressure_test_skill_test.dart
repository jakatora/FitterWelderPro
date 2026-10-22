import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('B31.3 hydro: 1,5·P·ST/S, hold 10 min, ST/S assumption said aloud',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(
        'Ciśnienie próby B31.3 hydro ciśnienie projektowe 16 bar',
        byVoice: true);
    expect(reply.match?.skill.id, 'pressure.test');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('minimalne ciśnienie próby 24 bar'));
    expect(r.answer.text.pl, contains('Przyjąłem ST/S = 1'));
    expect(r.answer.text.pl, contains('min. 10 min'));
    expect(r.show!.toolId, 'hydrotest');
    expect(r.show!.fields, {'preset': 'b31_3_hydro', 'design_bar': 16.0});
  });

  test('pneumatic 1,1·P with the 1,33·P ceiling; MPa converted', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final pn = (await h.say('Próba pneumatyczna B31.3 projektowe 10 bar'))
        .result as AnswerResult;
    expect(pn.answer.text.pl, contains('11 bar'));
    expect(pn.answer.text.pl, contains('Nie przekraczaj 13,3 bar'));
    final b311 = (await h.say('Ciśnienie próby B31.1 projektowe 1,6 MPa'))
        .result as AnswerResult;
    expect(b311.answer.text.pl, contains('24 bar'));
  });

  test('water volume from OD, wall and length', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // ID = 114,3 − 2·6,02 = 102,26 mm; V = π·102,26²/4·120 000 mm → 985,6 l.
    final r = (await h.say(
            'Próba wodna B31.3 projektowe 40 bar OD 114,3 mm ścianka 6,02 mm długość 120 m'))
        .result as AnswerResult;
    expect(r.answer.text.pl, contains('ok. 986 l'));
    expect(r.show!.fields['length_m'], 120.0);
  });

  test('a test piece is not a pressure test; unit conversion is not a test',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say('zakres uprawnień z próbki grubość 10 mm')).match?.skill.id,
        isNot('pressure.test'));
    expect((await h.say('przelicz 16 bar na psi')).match?.skill.id,
        isNot('pressure.test'));
  });
}

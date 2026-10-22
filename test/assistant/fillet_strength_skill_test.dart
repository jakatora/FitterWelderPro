import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('S355 a4 2×100 mm: independent EN 1993-1-8 reference', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // fvw,d = 490/√3/(0,9·1,25) = 251,47 MPa; l_eff = 2·(100 − 2·4) = 184 mm;
    // F_Rd = 251,47 · 4 · 184 / 1000 = 185,08 kN → w dół do 0,1: 185.
    final reply = await h.say(
        'Nośność spoiny pachwinowej a4 długość 100 mm 2 spoiny S355 blacha 10 mm',
        byVoice: true);
    expect(reply.match?.skill.id, 'fillet.strength');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('F_Rd = 185 kN'));
    expect(r.show!.toolId, 'fillet_strength');
    expect(r.show!.fields, {
      'steel': 's355',
      'throat_mm': 4.0,
      'part_thickness_mm': 10.0,
      'length_mm': 100.0,
      'welds': 2,
    });
  });

  test('force verdict: green only when F_Ed ≤ F_Rd', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ok = (await h.say(
            'Czy spoina a4 długość 100 mm 2 spoiny S355 blacha 10 mm przeniesie 185 kN'))
        .result as AnswerResult;
    expect(ok.answer.text.pl, contains('wystarczy'));
    expect(ok.answer.text.pl, isNot(contains('NIE wystarczy')));
    final bad = (await h.say(
            'Czy spoina a4 długość 100 mm 2 spoiny S355 blacha 10 mm przeniesie 186 kN'))
        .result as AnswerResult;
    expect(bad.answer.text.pl, contains('NIE wystarczy'));
    expect(bad.show!.fields['force_kn'], 186.0);
  });

  test('leg z is converted to throat a = z/√2', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(
            'Nośność spoiny pachwinowej bok z6 długość 80 mm 1 spoina S275 blacha 8 mm'))
        .result as AnswerResult;
    expect(r.show!.fields['throat_mm'], closeTo(4.2426, 1e-4));
    expect(r.answer.text.pl, contains('a = z/√2'));
  });

  test('dialogue asks every input; no remembered page defaults', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('policz nośność spoiny pachwinowej'), 'steel');
    expect(await ask('S235'), 'throat_mm');
    expect(await ask('a5'), 'part_thickness_mm');
    expect(await ask('12 mm'), 'length_mm');
    expect(await ask('150 mm'), 'welds');
    final r = (await h.say('2 spoiny')).result as AnswerResult;
    expect(r.show!.fields['welds'], 2);
    expect(r.show!.fields['steel'], 's235');
  });

  test('module limits are reported instead of a number', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say(
            'Nośność spoiny pachwinowej a4 długość 30 mm 2 spoiny S355 blacha 10 mm'))
        .result;
    expect(r, isA<FailedResult>(),
        reason: 'l_eff 22 mm < max(30 mm; 6a)');
  });

  test('a conjunction before a weld count is not a throat', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say(
        'nośność spoiny pachwinowej S355 długość 100 mm a 4 spoiny blacha 10 mm');
    expect(reply.match?.skill.id, 'fillet.strength');
    expect((reply.result as AskResult).slot, 'throat_mm');
  });
}

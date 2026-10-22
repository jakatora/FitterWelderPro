import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import '../support/test_database.dart';
import 'support/assistant_test_support.dart';

void main() {
  useTestDatabase();

  test('seeded starting point: horizontal 3/3 butt → 140/72 A', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Parametry tandem TIG blacha 3 mm poziom na styk',
        byVoice: true);
    expect(reply.match?.skill.id, 'tandem.tig');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('zewnętrzny z drutem 140 A'));
    expect(r.answer.text.pl, contains('wewnętrzny bez drutu 72 A'));
    expect(r.show!.toolId, 'welder_tanks');
    expect(r.show!.fields, {
      't1_mm': 3.0,
      't2_mm': 3.0,
      'position': 'HORIZONTAL',
      'joint_type': 'BUTT',
    });
  });

  test('interpolation between 3 and 4 mm, none outside the data', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // 3,5 mm: (140 + 190)/2 = 165 A, (72 + 100)/2 = 86 A.
    final mid = (await h.say('tandem TIG poziom 3,5 mm na styk')).result
        as AnswerResult;
    expect(mid.answer.text.pl, contains('165 A'));
    expect(mid.answer.text.pl, contains('86 A'));
    final out = (await h.say('tandem TIG poziom 12 mm na styk')).result
        as AnswerResult;
    expect(out.answer.text.pl, contains('nie ekstrapoluje'));
  });

  test('dialogue: thickness, position, joint', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('policz prąd tandem TIG'), 't1_mm');
    expect(await ask('4 mm'), 'position');
    expect(await ask('poziom'), 'joint_type');
    final r = (await h.say('na styk')).result as AnswerResult;
    expect(r.answer.text.pl, contains('190 A'));
  });
}

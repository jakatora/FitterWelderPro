import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan.dart';
import 'package:cut_list_app/domain/pass_plan/pass_plan_form.dart';
import 'support/assistant_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('DN150 Sch 40, 8 joints: same plan as the module form', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final reply = await h.say('Ile ściegów i elektrod na 8 złączy DN150 Sch 40',
        byVoice: true);
    expect(reply.match?.skill.id, 'pass.plan');
    final r = reply.result as AnswerResult;
    final plan = planPasses(passPlanInputFromForm({
      ...passPlanDefaultForm(),
      PassPlanField.count: '8',
    }))!;
    expect(r.answer.text.pl,
        contains('${plan.passesPerJoint} ściegów na złącze'));
    expect(r.answer.text.pl, contains('z zapisanego planu modułu'));
    expect(r.show!.toolId, 'pass_plan');
    expect(r.show!.fields, {'dn': 150, 'sch': '40', 'count': 8});
  });

  test('dialogue asks schedule and joint count', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final first = (await h.say('plan ściegów DN100')).result as AskResult;
    expect(first.slot, 'sch');
    final second = (await h.say('80')).result as AskResult;
    expect(second.slot, 'count');
    final r = (await h.say('4')).result as AnswerResult;
    expect(r.show!.fields, {'dn': 100, 'sch': '80', 'count': 4});
  });

  test('electrode exposure questions stay with exposure', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    expect(
        (await h.say('jak długo elektroda zasadowa może leżeć poza piecykiem'))
            .match
            ?.skill
            .id,
        isNot('pass.plan'));
  });
}

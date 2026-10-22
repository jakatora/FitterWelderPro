import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite.dart';
import 'package:cut_list_app/domain/ferrite_pmi/ferrite_pmi_sources.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('duplex and austenitic presets come from the module table', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final duplex = (await h.say('Jaki zakres ferrytu dla duplex')).result
        as AnswerResult;
    for (final p in kFerritePresets
        .where((p) => p.group == FerritePresetGroup.duplex)) {
      expect(duplex.answer.text.pl, contains(p.requirement.text(en: false)));
    }
    expect(duplex.show!.toolId, 'ferrite_pmi');
    final ss = (await h.say('Ile ferrytu w spoinie 316L')).result as AnswerResult;
    expect(ss.answer.text.pl, contains('Decyduje specyfikacja projektu'));
  });

  test('material is asked when missing', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final ask = (await h.say('wymagany ferryt')).result as AskResult;
    expect(ask.slot, 'group');
    final r = (await h.say('duplex')).result as AnswerResult;
    expect(r.answer.text.pl, contains('Typowe wymagania'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/assistant_coverage.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/widgets/tool_registry.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

void main() {
  test('every registered module has coverage, including unavailable modules',
      () {
    final coverage = assistantCoverage();
    expect(coverage.keys.toSet(), kToolRegistry.map((t) => t.id).toSet());
    expect(coverage.values, everyElement(isA<AssistantTier>()));
    expect(() => coverage.clear(), throwsUnsupportedError);
  });

  test('session writes require an attached actions port', () {
    final readOnly = assistantCoverage();
    final session = assistantCoverage(
      skills: buildSkillCatalog(actions: FakeActionsPort()),
    );
    expect(readOnly['weld_journal'], AssistantTier.b);
    expect(session['weld_journal'], AssistantTier.c);
    expect(session['welder_pipes'], AssistantTier.c);
    expect(readOnly['dn_mm'], AssistantTier.b);
  });

  test('removing specialized skills downgrades coverage immediately', () {
    final all = buildSkillCatalog(actions: FakeActionsPort());
    final withoutPipe = all.where((s) => s.toolId != 'dn_mm');
    expect(assistantCoverage(skills: withoutPipe)['dn_mm'], AssistantTier.a);
    expect(assistantCoverage(skills: const []).values,
        everyElement(AssistantTier.a));
    // Do not falsely claim full drawing coverage while ISO bypasses catalog.
    expect(assistantCoverage().values, isNot(contains(AssistantTier.d)));
  });

  test('every available module has a nonempty contextual explanation in PL/EN',
      () async {
    for (final tool in availableTools) {
      for (final lang in AppLanguage.values) {
        final harness = BrainHarness(
          lang: lang,
          activeToolId: tool.id,
          onHome: false,
        );
        final response = await harness.say(
          lang == AppLanguage.en ? 'what is this tool for?' : 'do czego służy?',
        );
        expect(response.match?.skill.id, 'tool.explain', reason: tool.id);
        expect(response.result, isA<AnswerResult>(), reason: tool.id);
        final answer = response.result as AnswerResult;
        final text = lang == AppLanguage.en
            ? answer.answer.text.en
            : answer.answer.text.pl;
        expect(text,
            contains(lang == AppLanguage.en ? tool.titleEn : tool.titlePl),
            reason: tool.id);
        expect(text.trim(), isNotEmpty);
        expect(answer.show, isNull, reason: 'description must not navigate');
      }
    }
  });

  test('contextual explanations do not use a stale module on home', () async {
    for (final active in [null, 'dn_mm', 'unknown_tool']) {
      final response =
          await BrainHarness(activeToolId: active).say('do czego służy?');
      expect(response.match?.skill.id, isNot('tool.explain'));
    }
    final explicit = await BrainHarness(activeToolId: 'dn_mm', onHome: false)
        .say('do czego służy rolling offset?');
    expect((explicit.result as AnswerResult).answer.text.pl,
        contains('Rolling offset'));
  });
}

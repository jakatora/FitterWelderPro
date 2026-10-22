import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_draw_skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_summary_skill.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_summary.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  test(
      'summary reads only the foreground native snapshot, including unknown CUT',
      () async {
    var foreground = true;
    SketchSummary? snapshot = const SketchSummary(
        pipeCount: 3, computedCutCount: 2, computedCutTotalMm: 1988, gapMm: 3);
    final port = CallbackIsoDrawingPort(
        isForeground: () => foreground,
        hasPendingQuestion: () => false,
        summary: () => snapshot,
        execute: (_) async => throw StateError('read-only must not execute'));
    final skill = IsoSummarySkill(port);
    final ctx = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    final match = skill.match(u('Podsumuj rysunek ISO'), ctx)!;
    final answer = await skill.run(match, ctx) as AnswerResult;
    expect(skill.readOnly, isTrue);
    expect(answer.answer.text.pl, contains('Odcinki rur: 3'));
    expect(answer.answer.text.pl, contains('1988.0 mm'));
    expect(answer.answer.text.pl, contains('bez obliczalnego CUT: 1'));
    expect(skill.match(u('Summarize the ISO drawing'), ctx), isNotNull);
    expect(skill.match(u('Jaka jest suma długości CUT w tym rysunku'), ctx),
        isNotNull);
    expect(skill.match(u('Ile waży rura DN50'), ctx), isNull);
    expect(skill.acceptsProposal(u('Usuń rysunek'), match.utterance!, ctx),
        isFalse);
    expect(
        skill.acceptsProposal(u('Czy możesz podsumować aktualny rysunek ISO?'),
            match.utterance!, ctx),
        isTrue);
    expect(
        skill.acceptsProposal(u('Powiedz mi ile rur jest w aktualnym szkicu'),
            match.utterance!, ctx),
        isTrue);
    expect(
        skill.acceptsProposal(
            u('Podsumuj historię rozmowy'), match.utterance!, ctx),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Ile waży rura DN50 w tym rysunku'), match.utterance!, ctx),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Nie podsumowuj rysunku ISO'), match.utterance!, ctx),
        isFalse);
    foreground = false;
    expect(await skill.run(match, ctx), isA<FailedResult>());
    foreground = true;
    snapshot = null;
    expect(await skill.run(match, ctx), isA<FailedResult>());
  });
}

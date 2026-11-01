import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:cut_list_app/assistant/assistant_ai_client.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_draw_skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_gap_skill.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_settings.dart';
import 'package:cut_list_app/i18n/app_language.dart';

class VisibleGap extends FixedModuleContext implements FieldModuleContext {
  const VisibleGap(this.gap) : super(activeToolId: 'iso_notebook');
  final double gap;
  @override
  Map<String, Object?> inputFields(String toolId) => {'gap_mm': gap};
}

void main() {
  Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
  test(
      'pronoun requires fresh committed sheet reference and never leaks its private identity',
      () {
    var time = DateTime(2026, 10, 22, 12);
    var reference = const IsoDrawingReference('sheet-private-A', 7);
    var foreground = true;
    final port = CallbackIsoDrawingPort(
        isForeground: () => foreground,
        hasPendingQuestion: () => false,
        reference: () => reference,
        execute: (_) async => throw StateError('no mutation'));
    final skill = IsoGapSkill(port);
    final context = AssistantContext(
        lang: AppLanguage.pl, modules: const VisibleGap(3), now: () => time);
    void commit() => context.remember(SkillMatch(skill, .99, slots: {
          'iso_gap_sheet_id': 'sheet-private-A',
          'iso_gap_sheet_revision': 7,
          'iso_gap_reference_generation': context.actionReferenceGeneration,
          'gap_mm': 3.0
        }));
    final source = u('Zmniejsz ją o 1 mm'),
        proposal = u('Ustaw szczelinę ISO na 2 mm');
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
    commit();
    expect(skill.acceptsProposal(source, proposal, context), isTrue);
    expect(
        skill.acceptsProposal(
            u('Czy możesz zmniejszyć ją o 1 mm'), proposal, context),
        isTrue);
    expect(skill.acceptsProposal(u('Decrease it by 1 mm'), proposal, context),
        isTrue);
    expect(
        skill.acceptsProposal(
            source, u('Ustaw szczelinę ISO na 1 mm'), context),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Zmniejsz ją w rolling offset o 1 mm'), proposal, context),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Zmniejsz ją o 1 mm i usuń rysunek'), proposal, context),
        isFalse);
    final wire = jsonEncode(assistantAiRequest(
        text: source.raw, context: context, skills: [skill]));
    expect(wire, isNot(contains('sheet-private-A')));
    expect(wire, isNot(contains('iso_gap_sheet_id')));
    reference = const IsoDrawingReference('sheet-private-B', 7);
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
    reference = const IsoDrawingReference('sheet-private-A', 8);
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
    reference = const IsoDrawingReference('sheet-private-A', 7);
    context.invalidateActionReference();
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
    commit();
    time = time.add(const Duration(minutes: 3));
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
    commit();
    foreground = false;
    expect(skill.acceptsProposal(source, proposal, context), isFalse);
  });
  test('AI may normalize requests addressed to it, never advice or permission',
      () {
    final port = CallbackIsoDrawingPort(
        isForeground: () => true,
        hasPendingQuestion: () => false,
        execute: (_) async => throw StateError('validation only'));
    final skill = IsoGapSkill(port);
    final context =
        AssistantContext(lang: AppLanguage.pl, modules: const VisibleGap(3));
    final proposed = u('Ustaw szczelinę ISO na 2 mm');
    for (final text in [
      'Czy możesz zmniejszyć szczelinę w ISO o 1 mm',
      'A zmniejsz szczelinę w ISO o 1 mm',
      'And decrease the ISO gap by 1 mm',
      'Możesz proszę ustawić szczelinę w szkicu na 2 mm',
      'Czy mógłbyś zmienić szczelinę ISO na 2 mm',
      'Czy mogłabyś zmniejszyć szczelinę w ISO o 1 mm',
      'Could you please decrease the gap in ISO by 1 mm',
      'Would you set root gap in this drawing to 2 mm',
      'Can you change the gap in ISO to 2 mm',
    ]) {
      expect(skill.acceptsProposal(u(text), proposed, context), isTrue,
          reason: text);
      expect(
          skill.acceptsProposal(
              u(text), u('Ustaw szczelinę ISO na 4 mm'), context),
          isFalse,
          reason: 'model changed amount: $text');
    }
    for (final text in [
      'Czy mogę zmniejszyć szczelinę w ISO o 1 mm',
      'A nie zmniejsz szczeliny w ISO o 1 mm',
      'And decrease the ISO gap by minus 1 mm',
      'Jak mogę ustawić szczelinę ISO na 2 mm',
      'Czy możesz wyjaśnić jak ustawić szczelinę ISO na 2 mm',
      'Could you explain how to set the gap in ISO to 2 mm',
      'Can I set the gap in ISO to 2 mm',
      'Czy możesz ustawić szczelinę ISO na −2 mm',
      'Czy możesz ustawić szczelinę ISO na -2 mm',
      'Czy możesz ustawić szczelinę w kalkulatorze na 2 mm',
      'Czy możesz ustawić szczelinę według ISO 5817 na 2 mm',
      'Czy możesz ustawić szczelinę ISO na 2 mm albo 4 mm',
      'Czy możesz ustawić szczelinę ISO na 2',
    ]) {
      expect(skill.acceptsProposal(u(text), proposed, context), isFalse,
          reason: text);
    }
  });
  for (final (text, gap) in [
    ('Ustaw szczelinę w tym rysunku na 3 mm', 3.0),
    ('Ustaw szczelinę ISO na 0 mm', 0.0),
    ('Zmień szczelinę spoiny w szkicu na 0,3 cm', 3.0),
    ('Set weld gap in this drawing to 2.5 mm', 2.5),
    ('Change root gap in the sketch to 0.01 m', 10.0),
  ]) {
    test(text, () {
      final command = parseIsoCommand(u(text))!;
      expect(command.kind, IsoCommandKind.setRootGap);
      expect(command.gapMm, gap);
      expect(command.copyWith().gapMm, gap);
      expect(command.steps, isEmpty);
    });
  }
  for (final text in [
    'Ustaw szczelinę ISO na -3 mm',
    'Ustaw szczelinę ISO na −3 mm',
    'Ustaw szczelinę ISO na 11 mm',
    'Ustaw szczelinę ISO na 3',
    'Ustaw szczelinę ISO na 3 mm albo 4 mm',
    'Ustaw szczelinę w kalkulatorze na 3 mm',
    'Nie ustawiaj szczeliny ISO na 3 mm',
    'Jak ustawić szczelinę ISO na 3 mm?'
  ]) {
    test('reject without drawing: $text',
        () => expect(parseIsoCommand(u(text)), isNull));
  }
  test('same input bounds as native editor including nonfinite values', () {
    for (final value in [0, 2.5, kSketchMaxGapMm]) {
      expect(isValidSketchGapMm(value), isTrue);
    }
    for (final value in [-1, 10.1, double.nan, double.infinity]) {
      expect(isValidSketchGapMm(value), isFalse);
    }
  });
  test('proposal respects actual ISO form, relative amount and target module',
      () {
    final port = CallbackIsoDrawingPort(
        isForeground: () => true,
        hasPendingQuestion: () => false,
        execute: (_) async => throw StateError('no mutation in match'));
    final skill = IsoGapSkill(port);
    final ctx =
        AssistantContext(lang: AppLanguage.pl, modules: const VisibleGap(3));
    final relative = u('Zmniejsz szczelinę w ISO o 1 mm');
    final correct = u('Ustaw szczelinę ISO na 2 mm');
    expect(skill.acceptsProposal(relative, correct, ctx), isTrue);
    expect(
        skill.acceptsProposal(relative, u('Ustaw szczelinę ISO na 1 mm'), ctx),
        isFalse);
    expect(
        skill.acceptsProposal(u('Ustaw w ISO szczelinę 0,2 cm'), correct, ctx),
        isTrue);
    expect(
        skill.acceptsProposal(
            u('Ustaw szczelinę w rolling offset na 2 mm'), correct, ctx),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Ustaw szczelinę według ISO 5817 na 2 mm'), correct, ctx),
        isFalse);
    expect(skill.acceptsProposal(u('Ustaw w ISO szczelinę 2'), correct, ctx),
        isFalse);
    expect(
        skill.acceptsProposal(
            relative,
            correct,
            AssistantContext(
                lang: AppLanguage.pl, modules: const FixedModuleContext())),
        isFalse);
    expect(IsoDrawSkill(port).match(correct, ctx), isNull);
  });
}

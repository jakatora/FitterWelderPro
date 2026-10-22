import 'package:flutter_test/flutter_test.dart';
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

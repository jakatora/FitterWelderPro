import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_name_skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_draw_skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
  for (final (text, name) in [
    ('Nazwij rysunek Linia CW-123', 'Linia CW-123'),
    ('Nazwij tę izometrię „Rurociąg chłodzący”', 'Rurociąg chłodzący'),
    ('Zmień nazwę rysunku na 6"-CWS-1234', '6"-CWS-1234'),
    ('Rename drawing to Cooling loop', 'Cooling loop'),
    ('Name this drawing “Łódź / ISO-02”', 'Łódź / ISO-02'),
    ('Nazwij rysunek Narysuj rura dwa metry', 'Narysuj rura dwa metry'),
  ]) {
    test('name remains literal: $text', () {
      final command = parseIsoCommand(u(text))!;
      expect(command.kind, IsoCommandKind.renameSketch);
      expect(command.sketchName, name);
      expect(command.copyWith().sketchName, name);
      expect(command.steps, isEmpty);
    });
  }
  for (final text in [
    'Nazwij rysunek',
    'Nazwij rysunek ""',
    'Nie nazywaj rysunku Linia CW-123',
    'Przetłumacz: nazwa rysunku Linia CW-123',
    'Nazwij rysunek ${'x' * 201}',
    'Nazwij rysunek x\ny'
  ]) {
    test('invalid/negated/reference name is not a drawing: $text', () {
      expect(parseIsoCommand(u(text)), isNull);
    });
  }
  test('AI cannot rewrite a literal name or invent an unprovided title', () {
    final port = CallbackIsoDrawingPort(
        isForeground: () => false,
        hasPendingQuestion: () => false,
        execute: (_) async => throw StateError('match does not execute'));
    final skill = IsoNameSkill(port);
    final context = AssistantContext(
        lang: AppLanguage.pl, modules: const FixedModuleContext());
    final command = u('Nazwij rysunek Łódź CW-123');
    expect(skill.acceptsProposal(command, command, context), isTrue);
    expect(
        skill.acceptsProposal(
            u('Nazwij rysunek Lodz CW-123'), command, context),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Chciałbym nazwać ten rysunek „Łódź CW-123”'), command, context),
        isTrue);
    expect(
        skill.acceptsProposal(u('Chciałbym nazwać ten rysunek jakoś sensownie'),
            command, context),
        isFalse);
    expect(
        skill.acceptsProposal(
            u('Chciałbym wiedzieć jak nazwać rysunek „Łódź CW-123”'),
            command,
            context),
        isFalse);
    expect(IsoDrawSkill(port).match(command, context), isNull);
  });
}

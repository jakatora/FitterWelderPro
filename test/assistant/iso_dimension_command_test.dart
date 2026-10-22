import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_dimension_skill.dart';

void main() {
  test('model normalization preserves explicit ordinal, units and value', () {
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    final command = u('Zmień wymiar ISO rury numer 2 na 500 mm');
    expect(
        acceptsIsoDimensionProposal(
            u('Ten drugi odcinek powinien mieć pół metra'), command),
        isTrue);
    expect(
        acceptsIsoDimensionProposal(u('Zmień drugi odcinek na 50 cm'), command),
        isTrue);
    for (final original in [
      'Zmień trzeci odcinek na 500 mm',
      'Zmień drugi odcinek na 600 mm',
      'Zmień drugi odcinek na -500 mm',
      'Zmień drugi odcinek na 500',
      'Zmień odcinek na 500 mm',
      'Zmień ostatni odcinek na 500 mm',
      'Zmień drugi odcinek na 500 mm albo 600 mm'
    ]) {
      expect(acceptsIsoDimensionProposal(u(original), command), isFalse,
          reason: original);
    }
    expect(
        acceptsIsoDimensionProposal(
            u('Change the last pipe ISO to half a meter'),
            u('Set ISO dimension of last pipe to 500 mm')),
        isTrue);
  });
  test('AI dimension proposals distinguish a request from advice or negation',
      () {
    Utterance u(String text) => Utterance(text, lang: AppLanguage.pl);
    final command = u('Zmień wymiar ISO rury numer 2 na 500 mm');
    for (final text in [
      'Czy możesz zmienić drugi odcinek na 500 mm?',
      'Could you please set the second pipe to 500 mm?',
      'Chciałbym żeby drugi odcinek miał 500 mm',
      'Ten drugi odcinek powinien mieć pół metra',
    ]) {
      expect(acceptsIsoDimensionProposal(u(text), command), isTrue,
          reason: text);
    }
    for (final text in [
      'Nie zmieniaj drugiego odcinka na 500 mm',
      'Proszę nie zmieniaj drugiego odcinka na 500 mm',
      'Jak zmienić drugi odcinek na 500 mm?',
      'Czy mogę zmienić drugi odcinek na 500 mm?',
      'Czy drugi odcinek powinien mieć 500 mm?',
      'Czy możesz wyjaśnić jak zmienić drugi odcinek na 500 mm?',
      'How do I set the second pipe to 500 mm?',
      'Can I set the second pipe to 500 mm?',
      'Should the second pipe be 500 mm?',
      'Could you explain setting the second pipe to 500 mm?',
      'Please do not set the second pipe to 500 mm',
      "Don't change the second pipe to 500 mm",
      'Please don’t change the second pipe to 500 mm',
    ]) {
      expect(acceptsIsoDimensionProposal(u(text), command), isFalse,
          reason: text);
    }
  });
  for (final (text, index, mm, lang) in [
    ('Zmień wymiar ISO ostatniej rury na 500 mm', null, 500.0, AppLanguage.pl),
    ('Ustaw wymiar ISO rury numer 2 na 1,5 m', 2, 1500.0, AppLanguage.pl),
    ('Set ISO dimension of last pipe to 50 cm', null, 500.0, AppLanguage.en),
    (
      'Change the ISO dimension of pipe number 3 to 1234.5 mm',
      3,
      1234.5,
      AppLanguage.en
    ),
  ]) {
    test('explicit dimension: $text', () {
      final result = parseIsoCommand(Utterance(text, lang: lang))!;
      expect(result.kind, IsoCommandKind.setPipeDimension);
      expect(result.pipeOrdinal, index);
      expect(result.dimensionMm, mm);
      expect(result.copyWith().dimensionMm, mm);
      expect(result.copyWith().pipeOrdinal, index);
      expect(result.steps, isEmpty);
    });
  }
  for (final text in [
    'Nie zmieniaj wymiaru ISO ostatniej rury na 500 mm',
    'Jak zmienić wymiar ISO ostatniej rury na 500 mm?',
    'Zmień wymiar ISO ostatniej rury na -500 mm',
    'Zmień wymiar ISO ostatniej rury na −500 mm',
    'Zmień wymiar ISO rury numer -1 na 500 mm',
    'Zmień wymiar ISO ostatniej rury na 0 mm',
    'Zmień wymiar ISO ostatniej rury na 500',
    'Zmień wymiar ISO rury numer 0 na 500 mm',
    'Zmień wymiar ISO rury numer 1 na 500 mm albo 600 mm',
    'Set ISO dimension of pipe number 2 to 500 mm and delete all pipes',
  ]) {
    test('unsafe or ambiguous edit never becomes a drawing: $text', () {
      expect(parseIsoCommand(Utterance(text, lang: AppLanguage.pl)), isNull);
    });
  }
}

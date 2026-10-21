import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  test('an ordinary pipe segment does not become a mitred bend request', () {
    final parsed = parseIsoCommand(Utterance(
        'draw pipe one meter segment elbow up pipe one meter',
        lang: AppLanguage.en));
    expect(parsed, isNotNull);
    expect(parsed!.has(IsoParseWarningKind.unsupportedSegmentedBend), isFalse);
  });
  for (final (lang, text) in [
    (AppLanguage.pl, 'narysuj kolano segmentowe w górę'),
    (AppLanguage.pl, 'narysuj segmentowe kolano w górę'),
    (AppLanguage.en, 'draw pipe one meter right mitred bend up pipe one meter'),
    (
      AppLanguage.pl,
      'narysuj rura metr w prawo kolano segmentowe w górę rura metr'
    ),
    (AppLanguage.en, 'draw segmented elbow up'),
    (AppLanguage.en, 'draw mitered bend right'),
    (AppLanguage.en, 'draw mitred bend up'),
    (AppLanguage.en, 'draw gored elbow up'),
    (AppLanguage.en, 'draw lobster back elbow up'),
  ]) {
    test('does not substitute ordinary elbow: $text', () {
      final parsed = parseIsoCommand(Utterance(text, lang: lang));
      expect(parsed, isNotNull);
      expect(parsed!.has(IsoParseWarningKind.unsupportedSegmentedBend), isTrue);
    });
  }
}

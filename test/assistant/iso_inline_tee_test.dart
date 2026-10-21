import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  test(
      'a tee can form part of the run without being converted to a symbol request',
      () {
    final c = parseIsoCommand(Utterance(
        'narysuj rura metr w prawo trójnik DN80 na DN50 rura metr w prawo',
        lang: AppLanguage.pl))!;
    expect(c.warnings, isEmpty);
    expect(c.steps, [
      const IsoPipe(dir: IsoDir.right, lengthMm: 1000),
      const IsoFitting('tee', dn: 80, dnOut: 50),
      const IsoPipe(dir: IsoDir.right, lengthMm: 1000)
    ]);
  });
  test('a branch-only size can inherit an explicit run pipe size', () {
    final c = parseIsoCommand(Utterance(
        'narysuj rura DN80 metr trójnik na DN50 rura metr',
        lang: AppLanguage.pl))!;
    expect(c.steps[1], const IsoFitting('tee', dn: 80, dnOut: 50));
  });
  test('an inline branch direction is not silently ignored', () {
    final c = parseIsoCommand(Utterance(
        'narysuj rura metr trójnik w górę rura metr',
        lang: AppLanguage.pl))!;
    expect(c.has(IsoParseWarningKind.unsupportedTee), isTrue);
  });
  test('ambiguous and negative tee sizes reject the complete command', () {
    for (final text in [
      'narysuj rura metr trójnik DN80 na DN50 na DN25 rura metr',
      'narysuj rura metr trójnik DN minus 50 rura metr'
    ]) {
      final c = parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!;
      expect(c.has(IsoParseWarningKind.invalidSymbolSize), isTrue);
    }
  });
}

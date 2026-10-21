import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  for (final text in [
    'od trójnika rura metr w górę',
    'narysuj odgałęzienie od ostatniego trójnika rura metr w górę',
    'from the last tee pipe one metre up',
    'please draw branch from the last tee pipe one metre up'
  ]) {
    test(text, () {
      final c = parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!;
      expect(c.fromLastTee, isTrue);
      expect(c.append, isTrue);
      expect(c.explicitLastTee,
          text.contains('ostatniego') || text.contains('last'));
      expect(c.steps.single, const IsoPipe(dir: IsoDir.up, lengthMm: 1000));
      expect(c.copyWith().fromLastTee, isTrue);
    });
  }
}

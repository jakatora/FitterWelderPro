import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';

void main() {
  for (final e in {
    'narysuj symbol kolana 45 DN50': 'elbow45',
    'draw symbol of 45 degree elbow DN50': 'elbow45',
    'narysuj symbol trójnika DN50': 'tee',
    'draw tee symbol DN50': 'tee'
  }.entries) {
    test(e.key, () {
      final c = parseIsoCommand(Utterance(e.key, lang: AppLanguage.pl))!;
      expect(c.warnings, isEmpty);
      expect(c.steps.single, IsoFitting(e.value, dn: 50, symbolOnly: true));
      final roundtrip = parseIsoCommand(Utterance(
          isoStepsToUtterance(c.steps, AppLanguage.pl),
          lang: AppLanguage.pl))!;
      expect(roundtrip.steps, c.steps);
    });
  }
  test(
      'symbol orientation survives parsing, compass resolution and serialization',
      () {
    final c = parseIsoCommand(Utterance(
        'narysuj symbol kolana 45 DN50 na północ',
        lang: AppLanguage.pl))!;
    final resolved = c.resolveCompass((_) => IsoDir.up)!;
    expect(resolved.steps.single,
        const IsoFitting('elbow45', dn: 50, symbolOnly: true, dir: IsoDir.up));
    final text = isoStepsToUtterance(resolved.steps, AppLanguage.pl);
    expect(parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!.steps,
        resolved.steps);
  });
  test(
      'invalid or ambiguous explicit symbol sizes never become blank-DN symbols',
      () {
    for (final text in [
      'narysuj symbol kolana 45 DN0',
      'narysuj symbol trójnika DN minus 50',
      'narysuj symbol kolana 45 DN50 DN80'
    ]) {
      final c = parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!;
      expect(c.has(IsoParseWarningKind.invalidSymbolSize), isTrue,
          reason: text);
    }
  });
  test('explicit symbol placement verbs work without drawing context', () {
    for (final text in [
      'wstaw symbol kolana 45 DN50',
      'umieść symbol trójnika DN50',
      'place tee symbol DN50',
      'add symbol of 45 degree elbow DN50'
    ]) {
      final c = parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!;
      expect(c.explicit, isTrue, reason: text);
      expect((c.steps.single as IsoFitting).symbolOnly, isTrue);
    }
  });
  test('a routing request is not changed into a standalone symbol', () {
    for (final text in [
      'narysuj rura metr kolano 45 rura metr',
      'narysuj symbol kolana 30 DN50',
      'narysuj symbol rura kolano 45 rura'
    ]) {
      final c = parseIsoCommand(Utterance(text, lang: AppLanguage.pl))!;
      expect(c.warnings, isNotEmpty);
    }
  });
  test('a reducing tee preserves both sizes in its description', () {
    final c = parseIsoCommand(Utterance('narysuj symbol trójnika DN80 na DN50',
        lang: AppLanguage.pl))!;
    expect(c.steps.single,
        const IsoFitting('tee', dn: 80, dnOut: 50, symbolOnly: true));
    final text = isoStepsToUtterance(c.steps, AppLanguage.en);
    expect(
        parseIsoCommand(Utterance(text, lang: AppLanguage.en))!.steps, c.steps);
  });
}

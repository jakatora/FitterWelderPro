import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';

IsoCommand parse(String text, [AppLanguage lang = AppLanguage.pl]) =>
    parseIsoCommand(Utterance(text, lang: lang))!;
void main() {
  test(
      'alternative or conflicting directions are not silently reduced to the first one',
      () {
    for (final text in [
      'narysuj symbol zaworu kulowego DN50 w lewo albo w prawo',
      'draw pipe 1 m up or down',
      'narysuj symbol kołnierza DN50 na północ w górę',
    ]) {
      expect(parse(text).has(IsoParseWarningKind.directionAmbiguous), isTrue,
          reason: text);
    }
    expect(isoDirectionOf(Utterance('góra albo dół', lang: AppLanguage.pl)),
        isNull);
    expect(isoCompassOf(Utterance('north or south', lang: AppLanguage.en)),
        isNull);
    expect(
        parse('narysuj symbol zaworu DN50 w górę').chooseValve(
            Utterance('kulowy w lewo albo w prawo', lang: AppLanguage.pl)),
        isNull);
  });

  const nouns = <String, (String, String, String)>{
    'ballValve': ('zaworu kulowego', 'ball valve', 'DN50'),
    'gateValve': ('zasuwy', 'gate valve', 'DN50'),
    'checkValve': ('zaworu zwrotnego', 'check valve', 'DN50'),
    'globeValve': ('zaworu grzybkowego', 'globe valve', 'DN50'),
    'butterflyValve': ('przepustnicy', 'butterfly valve', 'DN50'),
    'flange': ('kołnierza', 'flange', 'DN50'),
    'blindFlange': ('kołnierza zaślepiającego', 'blind flange', 'DN50'),
    'cap': ('zaślepki', 'cap', 'DN50'),
    'reducer': ('redukcji', 'reducer', 'DN100 na DN80'),
    'weld': ('spoiny', 'weld', ''),
    'fieldWeld': ('spoiny montażowej', 'field weld', ''),
    'support': ('podpory', 'support', ''),
  };
  for (final entry in nouns.entries) {
    for (final lang in AppLanguage.values) {
      test(
          '${entry.key} keeps standalone orientation in ${lang.name}, wire and utterance replay',
          () {
        final (pl, en, size) = entry.value;
        final text = lang == AppLanguage.pl
            ? 'narysuj symbol $pl $size w górę'
            : 'draw symbol of $en ${size.replaceAll(' na ', ' to ')} up';
        final command = parse(text, lang);
        expect(command.warnings, isEmpty, reason: text);
        final fitting = command.steps.single as IsoFitting;
        expect(fitting.tool, entry.key);
        expect(fitting.symbolOnly, isTrue);
        expect(fitting.dir, IsoDir.up);
        expect(
            decodeIsoSteps(
                jsonDecode(jsonEncode(encodeIsoSteps(command.steps)))),
            command.steps);
        expect(parse(isoStepsToUtterance(command.steps, lang), lang).steps,
            command.steps);
      });
    }
  }
  test('a standalone direction is meaningful without requiring the word symbol',
      () {
    expect(
        parse('narysuj zawór kulowy DN50 w lewo').steps.single,
        const IsoFitting('ballValve',
            dn: 50, symbolOnly: true, dir: IsoDir.left));
  });
  test(
      'compass survives a missing valve type and is resolved against the actual north arrow',
      () {
    final missing = parse('narysuj symbol zaworu DN50 na północ');
    expect(missing.compassAt[0], IsoCompass.north);
    final chosen =
        missing.chooseValve(Utterance('kulowy', lang: AppLanguage.pl))!;
    expect(chosen.compassAt[0], IsoCompass.north);
    expect(
        chosen.resolveCompass((_) => IsoDir.back)!.steps.single,
        const IsoFitting('ballValve',
            dn: 50, symbolOnly: true, dir: IsoDir.back));
    final changed = missing
        .chooseValve(Utterance('kulowy DN80 w lewo', lang: AppLanguage.pl))!;
    expect(changed.compassAt, isEmpty);
    expect(
        changed.steps.single,
        const IsoFitting('ballValve',
            dn: 80, symbolOnly: true, dir: IsoDir.left));
    expect(missing.chooseValve(Utterance('kulowy DN400', lang: AppLanguage.pl)),
        isNull);
  });
  test(
      'a fitting in a route cannot silently turn flow or accept direction in a valve-type reply',
      () {
    for (final text in [
      'narysuj rura metr w prawo zawór kulowy DN50 w górę rura metr',
      'draw pipe 1 m right flange DN50 north pipe 1 m',
      'narysuj rura metr redukcja DN100 na DN80 w lewo rura metr',
    ]) {
      expect(parse(text).has(IsoParseWarningKind.axialDirectionRequiresPipe),
          isTrue,
          reason: text);
    }
    final missing = parse('narysuj rura metr w prawo zawór DN50 rura metr');
    expect(
        missing.chooseValve(Utterance('kulowy w górę', lang: AppLanguage.pl)),
        isNull);
  });
  for (final text in [
    'narysuj symbol zaworu kulowego DN50 DN80 w górę',
    'narysuj symbol kołnierza DN50 DN80 w górę',
    'narysuj symbol redukcji DN100 na DN80 DN50 w górę',
    'narysuj symbol zaworu kulowego DN50 DN80.5 w górę',
    'narysuj symbol zaworu kulowego DN50 DN w górę',
    'narysuj symbol spoiny DN50 w górę',
  ]) {
    test(
        'ambiguous or ignored size is refused: $text',
        () => expect(
            parse(text).has(IsoParseWarningKind.invalidSymbolSize), isTrue));
  }
}

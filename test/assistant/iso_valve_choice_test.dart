import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';

IsoCommand command(String s) =>
    parseIsoCommand(Utterance(s, lang: AppLanguage.pl))!;
Utterance reply(String s) => Utterance(s, lang: AppLanguage.pl);
void main() {
  for (final e in {
    'kulowy': 'ballValve',
    'ball': 'ballValve',
    'zasuwa': 'gateValve',
    'gate': 'gateValve',
    'zwrotny': 'checkValve',
    'check': 'checkValve',
    'grzybkowy': 'globeValve',
    'globe': 'globeValve',
    'przepustnica': 'butterflyValve',
    'butterfly': 'butterflyValve'
  }.entries) {
    test('${e.key} fills exactly the missing valve and preserves the route',
        () {
      final c = command('narysuj rura metr w prawo zawór DN50');
      final chosen = c.chooseValve(reply(e.key))!;
      expect(chosen.steps.first, c.steps.first);
      expect(chosen.steps.last, IsoFitting(e.value, dn: 50));
      expect(chosen.has(IsoParseWarningKind.valveTypeMissing), isFalse);
      expect(c.has(IsoParseWarningKind.valveTypeMissing), isTrue);
    });
  }
  test('multiple valves are clarified one at a time with separate sizes', () {
    final c = command('narysuj rura metr zawór DN50 rura metr zawór DN80');
    final first = c.chooseValve(reply('ball'))!;
    expect(first.has(IsoParseWarningKind.valveTypeMissing), isTrue);
    final second = first.chooseValve(reply('check'))!;
    expect(second.steps[1], const IsoFitting('ballValve', dn: 50));
    expect(second.steps[3], const IsoFitting('checkValve', dn: 80));
    expect(second.has(IsoParseWarningKind.valveTypeMissing), isFalse);
  });
  test('explicit DN or NPS overrides only the chosen valve size', () {
    final c = command('narysuj zawór DN50');
    expect(c.chooseValve(reply('kulowy DN80'))!.steps.single,
        const IsoFitting('ballValve', dn: 80));
    expect(c.chooseValve(reply('kulowy 2 cale'))!.steps.single,
        const IsoFitting('ballValve', dn: 50));
  });
  test('conflicts, negation and ambiguous sizes do not fill anything', () {
    final c = command('narysuj zawór DN50');
    for (final r in [
      'kulowy albo zwrotny',
      'nie kulowy',
      'ball not gate',
      'kulowy DN999',
      'kulowy DN50 DN80',
      'kulowy 80',
      'kulowy rura DN80',
      'return'
    ]) {
      expect(c.chooseValve(reply(r)), isNull, reason: r);
    }
    expect(c.steps.single, const IsoFitting(kIsoAnyValve, dn: 50));
  });
}

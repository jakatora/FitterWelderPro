import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/iso/iso_command_parser.dart';
import 'package:cut_list_app/screens/iso_notebook_screen.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

void main() {
  test(
      'new-command preflight does not execute a write or clear a pending question',
      () async {
    final h = BrainHarness();
    await h.say('oblicz wagę rury');
    final pending = h.brain.pending;
    expect(pending, isNotNull);
    expect(
        h.brain.recognizesNewCommand(
            Utterance('NDS manganu', lang: AppLanguage.pl), h.ctx),
        isTrue);
    expect(
        h.brain.recognizesNewCommand(
            Utterance('zapisz TIG stal węglowa 2 mm 80 A',
                lang: AppLanguage.pl),
            h.ctx),
        isTrue);
    expect(
        h.brain.recognizesNewCommand(
            Utterance('nie zapisuj TIG 2 mm 80 A', lang: AppLanguage.pl),
            h.ctx),
        isFalse);
    expect(identical(h.brain.pending, pending), isTrue);
    expect(h.actions.savedParams, isEmpty);
  });
  test(
      'compass pipes and turns resolve together and preserve dimensions and DN',
      () {
    final c = parseIsoCommand(Utterance(
        'narysuj rura metr na północ kolano DN50 na wschód rura dwa metry',
        lang: AppLanguage.pl))!;
    final r = c.resolveCompass(
        (v) => v == IsoCompass.north ? IsoDir.back : IsoDir.right)!;
    expect(r.compassAt, isEmpty);
    expect(r.steps.first, const IsoPipe(dir: IsoDir.back, lengthMm: 1000));
    expect(r.steps[1], const IsoTurn(toDir: IsoDir.right, dn: 50));
    expect(c.compassAt, isNotEmpty);
  });
  test('missing north mapping does not resolve part of a command', () {
    final c = parseIsoCommand(Utterance(
        'draw pipe 1 m north elbow east pipe 2 m',
        lang: AppLanguage.en))!;
    final before = c.steps.toList();
    expect(c.resolveCompass((v) => v == IsoCompass.north ? IsoDir.back : null),
        isNull);
    expect(c.steps, before);
    expect(c.compassAt, hasLength(2));
  });
  test('turn corrections resolve the compass and clear its pending reference',
      () {
    final c = parseIsoCommand(
        Utterance('zmień ostatnie kolano na zachód', lang: AppLanguage.pl))!;
    expect(c.kind, IsoCommandKind.changeLastTurn);
    final r = c.resolveCompass((_) => IsoDir.left)!;
    expect(r.turnDir, IsoDir.left);
    expect(r.turnCompass, isNull);
  });
  test('invalid indices or compass attached to a fitting fail without mutation',
      () {
    for (final steps in [
      <IsoStep>[],
      <IsoStep>[const IsoFitting('ballValve')]
    ]) {
      final c = IsoCommand(
          kind: IsoCommandKind.draw,
          steps: steps,
          compassAt: const {0: IsoCompass.north});
      expect(c.resolveCompass((_) => IsoDir.right), isNull);
    }
  });
}

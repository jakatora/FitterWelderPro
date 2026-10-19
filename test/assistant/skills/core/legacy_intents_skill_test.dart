// Stary parser jako umiejętność: zapis parametru spawania i wpis do
// dziennika — ocena według DOWODÓW, nie samego czasownika „dodaj"
// (kradzież zamiaru, Review Focus 2).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../../support/assistant_test_support.dart';

void main() {
  group('kradzież zamiaru: „dodaj…" bez dowodów to NIE zapis', () {
    for (final t in [
      'dodaj zawór kulowy dn50',
      'dodaj rurę 2 metry',
      'dodaj spoinę 12',
      'add a ball valve DN50',
      'dodaj kolano 90',
    ]) {
      test(t, () async {
        final h = BrainHarness();
        final r = await h.say(t);
        expect(r.match?.skill.id, isNot(startsWith('legacy.')), reason: t);
        expect(r.result, isNot(isA<ConfirmResult>()));
        expect(h.actions.savedParams, isEmpty);
        expect(h.actions.savedJournal, isEmpty);
      });
    }
  });

  group('zapis parametru', () {
    test('komplet → podsumowanie, zapis dopiero po perform', () async {
      final h = BrainHarness();
      final r = await h.say('Zapisz MAG czarna ścianka 5 mm 110 amper');
      expect(r.match!.skill.id, 'legacy.save');
      final c = r.result as ConfirmResult;
      expect(c.touchOnly, isFalse);
      expect(h.actions.savedParams, isEmpty);
      await c.perform();
      expect(h.actions.savedParams.single.process, 'MIG_MAG');
      expect(h.actions.savedParams.single.currentA, 110);
    });
    test('bez czasownika, ale z dowodami (proces + prąd)', () async {
      final r = await BrainHarness().say('spawam rurę dn50 141 80 amper');
      expect(r.match!.skill.id, 'legacy.save');
    });
    test('pytania po kolei aż do podsumowania', () async {
      final h = BrainHarness();
      final r = await h.say('zapisz TIG ścianka 2 mm 60 A');
      final ask = r.result as AskResult;
      expect(ask.slot, 'material');
      expect(ask.question.pl, contains('materiał'));
      final r2 = await h.say('nierdzewka');
      expect((r2.result as AskResult).slot, 'filler');
      final r3 = await h.say('bez drutu');
      expect(r3.result, isA<ConfirmResult>());
    });
    test('pytanie wiedzowe to nie zapis', () async {
      final r = await BrainHarness().say('jaki prąd na TIG nierdzewka 2 mm?');
      expect(r.match?.skill.id, isNot('legacy.save'));
    });
    test('EN', () async {
      final r = await BrainHarness(lang: AppLanguage.en)
          .say('Save TIG stainless wall 2 mm 60 A no filler');
      expect(r.match!.skill.id, 'legacy.save');
      expect(r.result, isA<ConfirmResult>());
    });
  });

  group('dziennik spoin', () {
    test('„dopisz do dziennika spoinę 12 projekt Blok 4"', () async {
      final h = BrainHarness();
      final r = await h.say('Dopisz do dziennika spoinę 12 projekt Blok 4');
      expect(r.match!.skill.id, 'legacy.journal');
      final c = r.result as ConfirmResult;
      expect(h.actions.savedJournal, isEmpty);
      final undo = await c.perform();
      expect(h.actions.savedJournal.single.draft.weldNo, '12');
      expect(h.actions.savedJournal.single.draft.project, 'Blok 4');
      await undo!();
      expect(h.actions.savedJournal, isEmpty);
    });
    test('„spoina nr" wystarcza zamiast słowa „dziennik"', () async {
      final r = await BrainHarness().say('dodaj spoina nr 7 projekt Hala B');
      expect(r.match!.skill.id, 'legacy.journal');
    });
    test('numer zajęty → pytanie o inny numer, projekt zostaje', () async {
      final actions = FakeActionsPort()
        ..takenWeldNos['Blok 4'] = {'12'};
      final h = BrainHarness(actions: actions);
      final r = await h.say('dopisz do dziennika spoinę 12 projekt Blok 4');
      final ask = r.result as AskResult;
      expect(ask.slot, 'weld_no');
      expect(ask.question.pl, contains('12'));
      final r2 = await h.say('13');
      final c = r2.result as ConfirmResult;
      await c.perform();
      expect(actions.savedJournal.single.draft.weldNo, '13');
      expect(actions.savedJournal.single.draft.project, 'Blok 4');
    });
    test('brak projektu → pytanie', () async {
      final r = await BrainHarness().say('dopisz do dziennika spoinę 12');
      expect((r.result as AskResult).slot, 'project');
    });
  });

  test('bez portu zapisów katalog nie ma umiejętności legacy', () {
    // Sesja bez AssistantActions (np. przed zadaniem 1.0) nie może przyjąć
    // zapisu — polecenie trafia dalej (do starego silnika w AiChatScreen).
    expect(buildSkillCatalog().map((s) => s.id),
        isNot(anyOf(contains('legacy.save'), contains('legacy.journal'))));
    expect(buildSkillCatalog(actions: FakeActionsPort()).map((s) => s.id),
        containsAll(['legacy.save', 'legacy.journal']));
  });
}

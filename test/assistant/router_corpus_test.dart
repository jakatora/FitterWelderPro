// GLOBALNY test routera (plan 1.3, Review Focus 1–2): każdy przykład i każde
// odrzucenie KAŻDEJ umiejętności z buildSkillCatalog() przez cały mózg.
//
//   • przykład PL i EN trafia w swoją umiejętność, a `run` nie kończy się
//     błędem;
//   • odrzucenie nie trafia w swoją umiejętność ani w `alsoNot`, a jeśli ma
//     `routesTo` — trafia dokładnie tam;
//   • polecenia „dodaj…" bez dowodów nigdy nie dają zapisu.
//
// Koordynator rozszerza katalog po każdym scaleniu grupy — ten test łapie
// kolizje zamiarów między grupami bez dopisywania czegokolwiek tutaj.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/assistant/skills/skill_catalog.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

void main() {
  final catalog = buildSkillCatalog(actions: FakeActionsPort());

  test('katalog: unikalne id, przykłady i odrzucenia', () {
    final ids = catalog.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length, reason: 'zduplikowane id');
    for (final s in catalog) {
      expect(s.examples, isNotEmpty, reason: s.id);
      if (s.tier == AssistantTier.b && s.fallbackOrder == null) {
        expect(s.examples.length, greaterThanOrEqualTo(6), reason: s.id);
        expect(s.rejections.length, greaterThanOrEqualTo(3), reason: s.id);
      }
    }
  });

  for (final skill in catalog) {
    group(skill.id, () {
      for (final ex in skill.examples) {
        for (final (lang, text) in [
          (AppLanguage.pl, ex.pl),
          (AppLanguage.en, ex.en),
        ]) {
          test('trafia: [${lang.name}] $text', () async {
            final h = BrainHarness(lang: lang);
            final r = await h.say(text);
            expect(r.match?.skill.id, skill.id,
                reason: 'wynik: ${textOf(r.result, lang)}');
            expect(r.result, isNot(isA<FailedResult>()),
                reason: textOf(r.result, lang));
            expect(r.notUnderstood, isFalse);
          });
        }
      }
      for (final rej in skill.rejections) {
        test('odrzuca: [${rej.lang.name}] ${rej.text}', () async {
          final h = BrainHarness(lang: rej.lang);
          final r = await h.say(rej.text);
          final got = r.match?.skill.id;
          expect(got, isNot(skill.id), reason: textOf(r.result, rej.lang));
          for (final other in rej.alsoNot) {
            expect(got, isNot(other), reason: textOf(r.result, rej.lang));
          }
          if (rej.routesTo != null) {
            expect(got, rej.routesTo, reason: textOf(r.result, rej.lang));
          }
        });
      }
    });
  }

  group('polecenia „dodaj…" bez dowodów nigdy nie zapisują', () {
    for (final t in [
      'dodaj zawór kulowy dn50',
      'dodaj rurę 2 metry',
      'dodaj spoinę 12',
      'dodaj kołnierz dn100',
      'add a pipe 2 meters',
      'add weld 12',
    ]) {
      test(t, () async {
        final h = BrainHarness(
            lang: t.startsWith('add') ? AppLanguage.en : AppLanguage.pl);
        final r = await h.say(t);
        expect(r.match?.skill.id ?? '', isNot(startsWith('legacy.')));
        expect(r.result, isNot(isA<ConfirmResult>()));
      });
    }
  });
}

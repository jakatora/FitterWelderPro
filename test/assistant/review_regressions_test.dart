// Regresje z przeglądu rdzenia asystenta (koordynator, po 5af8b98).
// Każdy przypadek: wypowiedź → oczekiwany wynik. Zasada: nigdy cichy zły
// wynik — pytanie w toku nie może połknąć nowego polecenia, kontekst nie
// może podsunąć cudzego DN, liczby słowne nie mogą się sklejać po cichu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import 'support/assistant_test_support.dart';

/// Mózg z pytaniem „Jakie DN?" w toku (pipe.od).
Future<BrainHarness> askedForDn() async {
  final h = BrainHarness();
  final r = await h.say('jaka średnica dn');
  expect((r.result as AskResult).slot, 'dn');
  return h;
}

void main() {
  group('1. pytanie w toku nie przechwytuje nowego polecenia', () {
    test('„ile waży rura dn50" po „Jakie DN?" → nie OD', () async {
      final h = await askedForDn();
      final r = await h.say('ile waży rura dn50');
      expect(r.match?.skill.id, isNot('pipe.od'));
      expect(textOf(r.result), isNot(contains('60,3')));
      expect(r.match?.skill.id, 'pipe.weight');
      expect(h.brain.pending?.slot, 'wall_mm');
    });
    test('„zapisz TIG nierdzewka 60 A" → zapis parametru, nie „DN60"',
        () async {
      final h = await askedForDn();
      final r = await h.say('zapisz TIG nierdzewka 60 A');
      expect(r.match?.skill.id, 'legacy.save');
      expect(textOf(r.result), isNot(contains('DN60')));
    });
    test('„dodaj zawór kulowy dn50" → nie OD i nie zapis', () async {
      final h = await askedForDn();
      final r = await h.say('dodaj zawór kulowy dn50');
      expect(r.match?.skill.id, isNot('pipe.od'));
      expect(r.result, isNot(isA<ConfirmResult>()));
      expect(textOf(r.result), isNot(contains('60,3')));
    });
    test('„ścianka dn50 sch 40" przy pytaniu pipe.od → ścianka', () async {
      final h = await askedForDn();
      final r = await h.say('ścianka dn50 sch 40');
      expect(r.match?.skill.id, 'pipe.wall');
      expect(textOf(r.result), startsWith('DN50 Sch 40 — ścianka 3,91 mm'));
    });
    test('zwykła odpowiedź „40" nadal działa', () async {
      final h = await askedForDn();
      final r = await h.say('40');
      expect(r.match?.skill.id, 'pipe.od');
      expect(textOf(r.result), contains('48,3 mm'));
    });
    test('liczba z jednostką to nie DN („60 A")', () async {
      final h = await askedForDn();
      final r = await h.say('60 A');
      expect(textOf(r.result), isNot(contains('DN60')));
    });
  });

  group('2. jedna opisana OD dla DN w obu odpowiedziach', () {
    test('DN300: pipe.od i pipe.wall podają 323,9 i 323,8 z opisem', () async {
      final od = textOf((await BrainHarness().say('średnica dn300')).result);
      final wall =
          textOf((await BrainHarness().say('ścianka dn300 sch 40')).result);
      expect(od, contains('323,9 mm'));
      expect(od, contains('323,8 mm'));
      expect(od, contains('ASME B36.10M'));
      expect(wall, contains('OD 323,8 mm wg ASME'));
      expect(wall, contains('323,9'));
      expect(wall, contains('DN ↔ mm'));
    });
    test('DN600: 609,6 i 610 opisane w obu', () async {
      final od = textOf((await BrainHarness().say('średnica dn600')).result);
      final wall =
          textOf((await BrainHarness().say('ścianka dn600 sch 40')).result);
      expect(od, contains('609,6 mm'));
      expect(od, contains('610 mm'));
      expect(wall, contains('OD 610 mm wg ASME'));
      expect(wall, contains('609,6'));
    });
    test('DN40: bez różnicy — bez dopisku', () async {
      final od = textOf((await BrainHarness().say('średnica dn40')).result);
      final wall =
          textOf((await BrainHarness().say('ścianka dn40 sch 40')).result);
      expect(od, isNot(contains('Tabela ścianek')));
      expect(wall, contains('OD 48,3 mm wg ASME,'));
      expect(wall, isNot(contains('DN ↔ mm')));
    });
    test('lista ścianek też opisuje OD', () async {
      final wall = textOf((await BrainHarness().say('jakie ścianki ma dn300')).result);
      expect(wall, startsWith('DN300 (OD 323,8 mm wg ASME; w tabeli DN ↔ mm: 323,9 mm)'));
    });
  });

  group('3. ułamki po jednostce i „N i <ułamek>"', () {
    test('„dwa cale i pół" → 2,5" = DN65', () async {
      expect(Utterance('dwa cale i pół', lang: AppLanguage.pl).npsInches(), 2.5);
      final r = await BrainHarness().say('średnica dwa cale i pół');
      expect(textOf(r.result), contains('(DN65)'));
    });
    test('„jeden i trzy czwarte cala" → 1,75"', () {
      expect(
          Utterance('jeden i trzy czwarte cala', lang: AppLanguage.pl)
              .npsInches(),
          1.75);
    });
    test('„dwa metry i pół" → 2500 mm', () {
      expect(Utterance('rura dwa metry i pół', lang: AppLanguage.pl).lengthMm(),
          2500);
    });
    test('„metr i ćwierć" → 1250 mm', () {
      expect(Utterance('metr i ćwierć', lang: AppLanguage.pl).lengthMm(), 1250);
    });
  });

  group('5. „dn 4 0" nie dziedziczy DN z kontekstu', () {
    test('„ścianka dn 4 0 sch 80" po „dn 100" → pytanie o DN', () async {
      final h = BrainHarness();
      await h.say('dn 100');
      h.wait(const Duration(minutes: 1));
      final r = await h.say('ścianka dn 4 0 sch 80');
      expect(r.result, isA<AskResult>());
      expect((r.result as AskResult).slot, 'dn');
      expect(textOf(r.result), isNot(contains('DN100')));
    });
  });

  group('6. dziedziczenie DN tylko przy krótkiej kontynuacji', () {
    test('„jaka średnica drutu 1,2?" po DN40 → nie OD rury', () async {
      final h = BrainHarness();
      await h.say('średnica dn40');
      final r = await h.say('jaka średnica drutu 1,2?');
      expect(r.match?.skill.id, isNot('pipe.od'));
      expect(textOf(r.result), isNot(contains('48,3')));
    });
    test('„jaka grubość blachy" po DN40 → nie ścianka rury', () async {
      final h = BrainHarness();
      await h.say('średnica dn40');
      final r = await h.say('jaka grubość blachy');
      expect(r.match?.skill.id, isNot('pipe.wall'));
    });
    test('„jaka grubość spoiny" po DN40 → nie ścianka rury', () async {
      final h = BrainHarness();
      await h.say('średnica dn40');
      final r = await h.say('jaka grubość spoiny');
      expect(r.match?.skill.id, isNot('pipe.wall'));
    });
    test('„a ścianka?" i „a sch 80?" dalej dziedziczą', () async {
      final h = BrainHarness();
      await h.say('średnica dn40');
      expect((await h.say('a ścianka?')).match!.skill.id, 'pipe.wall');
      expect(textOf((await h.say('a sch 80?')).result),
          startsWith('DN40 Sch 80'));
    });
  });

  group('7. dwa różne DN w zdaniu → pytanie', () {
    test('„średnica dn50 i dn80" → pytanie z oboma', () async {
      final r = await BrainHarness().say('średnica dn50 i dn80');
      final ask = r.result as AskResult;
      expect(ask.slot, 'dn');
      expect(ask.choices.map((c) => c.utterance), ['DN50', 'DN80']);
      expect(Utterance('średnica dn50 i dn80', lang: AppLanguage.pl).dn(),
          isNull);
    });
    test('„DN fifty and sixty" → pytanie (EN)', () async {
      final u = Utterance('DN fifty and sixty', lang: AppLanguage.en);
      expect(u.dn(), isNull);
      final r = await BrainHarness(lang: AppLanguage.en).say('DN fifty and sixty');
      expect((r.result as AskResult).slot, 'dn');
    });
    test('ten sam DN dwa razy to nie dwuznaczność', () {
      expect(Utterance('dn50 czyli dn 50', lang: AppLanguage.pl).dn(), 50);
    });
  });

  group('8. wiedza nie zgaduje wpisu Pomocy', () {
    test('„ile mm ma kolano dn50" → nie knowledge', () async {
      final r = await BrainHarness().say('ile mm ma kolano dn50');
      expect(r.match?.skill.id, isNot('knowledge'));
    });
    test('jedno słowo treści → nie knowledge („kolano")', () async {
      final r = await BrainHarness().say('kolano');
      expect(r.match?.skill.id, isNot('knowledge'));
    });
    test('liczba z jednostką → nie knowledge', () async {
      final r = await BrainHarness().say('porowatość przy 120 A');
      expect(r.match?.skill.id, isNot('knowledge'));
    });
    test('pytania z Pomocy dalej działają', () async {
      for (final t in [
        'dlaczego pojawia się porowatość',
        'jaki przepływ gazu osłonowego ustawić',
        'ile czasu powinien trwać back purge',
      ]) {
        expect((await BrainHarness().say(t)).match?.skill.id, 'knowledge',
            reason: t);
      }
    });
  });

  group('niższe', () {
    test('„a ścianka dla DN50 proszę bardzo" po OD → ścianka', () async {
      final h = BrainHarness();
      await h.say('średnica dn40');
      final r = await h.say('a ścianka dla DN50 proszę bardzo');
      expect(r.match!.skill.id, 'pipe.wall');
      expect(textOf(r.result), startsWith('DN50'));
    });
    test('„a średnica dla DN50" po ściance → średnica', () async {
      final h = BrainHarness();
      await h.say('ścianka dn40 sch 40');
      final r = await h.say('a średnica dla DN50');
      expect(r.match!.skill.id, 'pipe.od');
      expect(textOf(r.result), startsWith('DN50 — średnica zewnętrzna 60,3'));
    });
    test('„ten" po polsku to nie 10', () {
      final u = Utterance('ile ma ten dn40', lang: AppLanguage.pl);
      expect(u.tokens, ['ile', 'ma', 'ten', 'dn', '40']);
      expect(u.dn(), 40);
      expect(Utterance('ten', lang: AppLanguage.en).tokens, ['10']);
    });
  });
}

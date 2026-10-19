// `pipe.od`: DN / NPS → średnica zewnętrzna z tabeli „DN ↔ mm". Liczby
// i norma wyłącznie z domeny (pipe_size_lookup.dart), niejasne → pytanie.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/fitter/pipe_size_lookup.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../../support/assistant_test_support.dart';

void main() {
  test('DN40 — odpowiedź PL z normą i drugą serią', () async {
    final h = BrainHarness();
    final r = await h.say('Jaka jest średnica rury DN40?');
    expect(r.match!.skill.id, 'pipe.od');
    final a = r.result as AnswerResult;
    expect(
        a.answer.text.pl,
        'DN40 — średnica zewnętrzna 48,3 mm '
        '(EN 10220 / ISO 4200 seria 1, ASME B36.10M). '
        'W szeregu EN 3: 44,5 mm.');
    expect(a.answer.source!.pl, kDnOdSourcePl);
    expect(a.answer.text.pl.contains('6708'), isFalse);
    expect(a.show!.toolId, 'dn_mm');
    expect(a.show!.fields, {'dn': 40});
    expect(a.followUps.map((f) => f.utterance), ['a ścianka?', 'a DN50?']);
    expect(a.answer.spoken!.pl, contains('48,3 milimetra'));
  });

  test('DN40 — EN', () async {
    final h = BrainHarness(lang: AppLanguage.en);
    final r = await h.say('what is the OD of DN40');
    final a = r.result as AnswerResult;
    expect(
        a.answer.text.en,
        'DN40 — outside diameter 48.3 mm '
        '(EN 10220 / ISO 4200 series 1, ASME B36.10M). '
        'EN series 3: 44.5 mm.');
    expect(a.followUps.map((f) => f.utterance), ['and the wall?', 'and DN50?']);
  });

  test('każda liczba odpowiedzi jest z domeny — wszystkie DN z tabeli',
      () async {
    for (final dn in knownDns) {
      final h = BrainHarness();
      final r = await h.say('średnica DN$dn');
      final a = r.result as AnswerResult;
      final main = odForDn(dn)!;
      expect(a.answer.lines.first.value,
          '${main.toString().replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '')} mm',
          reason: 'DN$dn');
      expect(a.show!.fields['dn'], dn);
    }
  });

  test('cale: „średnica 2 cale" → DN50, 60,3 mm', () async {
    final h = BrainHarness();
    final r = await h.say('średnica 2 cale');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl, startsWith('2" (DN50) — średnica zewnętrzna 60,3 mm'));
    expect(a.show!.fields, {'dn': 50});
  });

  test('„de en czterdzieści" i „dn40 ile mm"', () async {
    for (final t in ['ile ma de en czterdzieści', 'dn40 ile mm', 'DN 40']) {
      final h = BrainHarness();
      final r = await h.say(t);
      expect(r.match!.skill.id, 'pipe.od', reason: t);
      expect(textOf(r.result), contains('48,3 mm'), reason: t);
    }
  });

  test('„dn" bez liczby → pytanie o DN, odpowiedź „40" → wynik', () async {
    final h = BrainHarness();
    final r = await h.say('dn');
    final ask = r.result as AskResult;
    expect(ask.slot, 'dn');
    final r2 = await h.say('40');
    expect(textOf(r2.result), contains('48,3 mm'));
  });

  test('„dn 4 0" → pytanie, nie zgadujemy', () async {
    final h = BrainHarness();
    final r = await h.say('średnica dn 4 0');
    expect((r.result as AskResult).slot, 'dn');
  });

  test('DN spoza tabeli → pytanie z dwoma najbliższymi', () async {
    final h = BrainHarness();
    final r = await h.say('średnica DN45');
    final ask = r.result as AskResult;
    expect(ask.slot, 'dn');
    expect(ask.question.pl, contains('DN45'));
    expect(ask.choices.map((c) => c.utterance), ['DN40', 'DN50']);
    final r2 = await h.say(ask.choices.last.utterance);
    expect(textOf(r2.result), contains('60,3 mm'));
  });

  test('„a dla DN50?" po DN40', () async {
    final h = BrainHarness();
    await h.say('jaka średnica dn40');
    h.wait(const Duration(seconds: 20));
    final r = await h.say('a dla DN50?');
    expect(r.match!.skill.id, 'pipe.od');
    expect(textOf(r.result), startsWith('DN50 — średnica zewnętrzna 60,3 mm'));
  });

  test('dopowiedzenie nie przejmuje poleceń innych modułów', () async {
    for (final t in [
      'dodaj zawór kulowy dn50',
      'ile waży rura dn50',
      'narysuj rurę dn50',
      'wymiar kolana dn50',
    ]) {
      final h = BrainHarness();
      await h.say('jaka średnica dn40');
      h.wait(const Duration(seconds: 3));
      final r = await h.say(t);
      expect(r.match?.skill.id, isNot('pipe.od'), reason: t);
      expect(r.match?.skill.id, isNot('pipe.wall'), reason: t);
    }
  });

  test('„a średnica?" po ściance bierze DN z kontekstu', () async {
    final h = BrainHarness();
    await h.say('ścianka dn50 sch 40');
    final r = await h.say('a średnica?');
    expect(r.match!.skill.id, 'pipe.od');
    expect(textOf(r.result), startsWith('DN50 — średnica zewnętrzna 60,3 mm'));
  });

  test('odrzucenia: ścianka, otwórz, dodaj, ciężar', () async {
    final cases = {
      'ścianka dn40 sch40': 'pipe.wall',
      'otwórz tabelę dn': 'tool.open',
    };
    for (final e in cases.entries) {
      final r = await BrainHarness().say(e.key);
      expect(r.match?.skill.id, e.value, reason: e.key);
    }
    for (final t in ['dodaj zawór kulowy dn50', 'ile waży rura dn50']) {
      final r = await BrainHarness().say(t);
      expect(r.match?.skill.id, isNot('pipe.od'), reason: t);
      expect(r.result, isNot(isA<ConfirmResult>()), reason: t);
    }
  });
}

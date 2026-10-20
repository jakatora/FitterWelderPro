// `pipe.wall`: ścianka rury z tabeli „Grubości ścianek" (ASME B36.10M /
// B36.19M). DN z wypowiedzi albo z kontekstu („a ścianka?" po DN40).

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/data/pipe_schedules.dart';
import 'package:cut_list_app/i18n/app_language.dart';

import '../../support/assistant_test_support.dart';

void main() {
  test('„ścianka dn40 sch40" → 3,68 mm z normą', () async {
    final h = BrainHarness();
    final r = await h.say('ścianka dn40 sch40');
    expect(r.match!.skill.id, 'pipe.wall');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl,
        startsWith('DN40 Sch 40 — ścianka 3,68 mm (ASME B36.10M)'));
    expect(a.answer.text.pl, contains('średnica wewnętrzna 40,94 mm'));
    expect(a.answer.source!.pl, 'ASME B36.10M');
    expect(a.show!.toolId, 'wall_thickness');
    expect(a.show!.fields, {'dn': 40, 'schedule': '40'});
  });

  test('Sch 10S → B36.19M', () async {
    final r = await BrainHarness().say('DN100 sch 10S ile ścianki');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl, startsWith('DN100 Sch 10S — ścianka 3,05 mm'));
    expect(a.answer.source!.pl, 'ASME B36.19M');
  });

  test('STD, XS i cale', () async {
    expect(textOf((await BrainHarness().say('ścianka DN 25 STD')).result),
        startsWith('DN25 Sch STD — ścianka 3,38 mm'));
    expect(
        textOf((await BrainHarness()
                .say('grubość ścianki rury 2 cale schedule 80'))
            .result),
        startsWith('DN50 Sch 80 — ścianka 5,54 mm'));
  });

  test('wszystkie ścianki z tabeli zgadzają się z domeną', () async {
    for (final row in kPipeWalls) {
      for (final e in row.walls.entries) {
        if (e.value == null) continue;
        final r = await BrainHarness().say('ścianka dn${row.dn} sch ${e.key}');
        final a = r.result as AnswerResult;
        expect(a.answer.lines.first.value,
            '${e.value!.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '').replaceAll('.', ',')} mm',
            reason: 'DN${row.dn} ${e.key}');
      }
    }
  });

  test('bez harmonogramu → lista ścianek i chipy', () async {
    final r = await BrainHarness().say('jakie ścianki ma DN80');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl, contains('Sch 40 5,49 mm'));
    expect(a.answer.lines.length, greaterThan(5));
    expect(a.show!.fields, {'dn': 80});
    expect(a.followUps.map((f) => f.utterance), contains('a sch 80?'));
  });

  test('„a ścianka?" po DN40 → pipe.wall z DN z kontekstu', () async {
    final h = BrainHarness();
    await h.say('jaka jest średnica rury dn40');
    h.wait(const Duration(seconds: 10));
    final r = await h.say('a ścianka?');
    expect(r.match!.skill.id, 'pipe.wall');
    expect(textOf(r.result), startsWith('DN40 (OD 48,3 mm wg ASME)'));
    final r2 = await h.say('a sch 80?');
    expect(r2.match!.skill.id, 'pipe.wall');
    expect(textOf(r2.result), startsWith('DN40 Sch 80 — ścianka 5,08 mm'));
    final r3 = await h.say('a dla DN50?');
    expect(r3.match!.skill.id, 'pipe.wall');
    expect(textOf(r3.result), startsWith('DN50 Sch 80 — ścianka 5,54 mm'));
  });

  test('„ścianka" bez DN i bez kontekstu → pytanie o DN', () async {
    final h = BrainHarness();
    final r = await h.say('jaka ścianka sch 40');
    expect((r.result as AskResult).slot, 'dn');
    final r2 = await h.say('DN50');
    expect(textOf(r2.result), startsWith('DN50 Sch 40 — ścianka 3,91 mm'));
  });

  test('harmonogram spoza tabeli → pytanie z wyborem', () async {
    final h = BrainHarness();
    final r = await h.say('ścianka dn50 sch 10');
    final ask = r.result as AskResult;
    expect(ask.slot, 'schedule');
    expect(ask.choices.map((c) => c.utterance), contains('sch 10S'));
    final r2 = await h.say('sch 10S');
    expect(textOf(r2.result), startsWith('DN50 Sch 10S — ścianka 2,77 mm'));
  });

  test('EN', () async {
    final r = await BrainHarness(lang: AppLanguage.en)
        .say('wall thickness DN50 sch 80');
    final a = r.result as AnswerResult;
    expect(a.answer.text.en, startsWith('DN50 Sch 80 — wall 5.54 mm'));
  });

  test('odrzucenia: średnica, zapis parametru, ciężar', () async {
    expect((await BrainHarness().say('jaka jest średnica rury dn40')).match!.skill.id,
        'pipe.od');
    expect(
        (await BrainHarness()
                .say('zapisz TIG nierdzewka ścianka 2 mm 60 A bez drutu'))
            .match!
            .skill
            .id,
        'legacy.save');
    final w = await BrainHarness().say('ile waży rura dn50 sch 40');
    expect(w.match?.skill.id, isNot('pipe.wall'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('labelled diameters give the independent reference depth', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    // R = 50, r = 30 → h_max = 50 − √(50² − 30²) = 10 mm.
    final reply =
        await h.say('Siodło rura główna 100 mm odgałęzienie 60 mm', byVoice: true);
    expect(reply.match?.skill.id, 'saddle.cut');
    final r = reply.result as AnswerResult;
    expect(r.answer.text.pl, contains('Największa głębokość wycięcia 10 mm'));
    expect(r.show!.toolId, 'saddle_cut');
    expect(r.show!.fields, {'header_od_mm': 100.0, 'branch_od_mm': 60.0});
  });

  test('two unlabelled DN sizes: the smaller one is the branch', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final text in [
      'Wycięcie siodłowe DN50 na DN100',
      'siodło DN100 i DN50',
    ]) {
      final r = (await h.say(text)).result as AnswerResult;
      expect(r.show!.fields, {'header_od_mm': 114.3, 'branch_od_mm': 60.3},
          reason: text);
    }
  });

  test('equal tee from two equal DN markers', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('siodło DN100 na DN100')).result as AnswerResult;
    expect(r.show!.fields, {'header_od_mm': 114.3, 'branch_od_mm': 114.3});
  });

  test('dialogue asks both diameters and accepts DN or mm answers', () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    Future<String> ask(String text) async =>
        ((await h.say(text)).result as AskResult).slot;
    expect(await ask('oblicz siodło'), 'header_od_mm');
    expect(await ask('DN100'), 'branch_od_mm');
    final r = (await h.say('60,3 mm')).result as AnswerResult;
    expect(r.show!.fields, {'header_od_mm': 114.3, 'branch_od_mm': 60.3});
  });

  test('a branch larger than the labelled header is refused, not swapped',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final r = (await h.say('siodło rura główna 60 mm odgałęzienie 100 mm'))
        .result;
    expect(r, isA<FailedResult>());
  });

  test('angles and printing belong to the saddle template, not the table',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    for (final text in [
      'szablon siodła 114,3 mm na 168,3 mm',
      'siodło 60 mm na 100 mm kąt 45 stopni',
    ]) {
      expect((await h.say(text)).match?.skill.id, isNot('saddle.cut'),
          reason: text);
    }
  });

  test('unitless pair: OD in mm, but DN-like integers are not guessed',
      () async {
    final h = BrainHarness();
    addTearDown(h.timer.dispose);
    final mm = (await h.say('siodło 60,3 na 114,3')).result as AnswerResult;
    expect(mm.show!.fields, {'header_od_mm': 114.3, 'branch_od_mm': 60.3});
    final ask = (await h.say('siodło 50 na 100')).result;
    expect(ask, isA<AskResult>(),
        reason: '50 na 100 może znaczyć DN50 na DN100 albo milimetry');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/fitter/pipe_route.dart';
import 'support/assistant_test_support.dart';

const command =
    'Oblicz trasę rur H1 2000 mm H2 500 mm X 1000 mm Y 800 mm DN100 szczelina 3 mm bez spoin końcowych';
BrainHarness h() {
  final h = BrainHarness();
  addTearDown(h.timer.dispose);
  return h;
}

void main() {
  test('native route dimensions and normative DN resolve to actual cut lengths',
      () async {
    final r = await h().say(command, byVoice: true);
    expect(r.match?.skill.id, 'pipe.route');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl, contains('845 mm, 1190 mm, 645 mm'));
    expect(a.answer.text.pl, contains('2680 mm'));
    expect(a.answer.source?.pl, contains('B16.9'));
    final p = PipeRouteInput.fromFields(a.show!.fields);
    expect(p.result.total, 2680);
    expect(p.result.weldCount, 4);
    expect(p.fields['end_welds'], false);
    expect(p.fields['dn'], 100);
  });
  for (final (kind, r, total) in [
    ('SR', 102, 2880),
    ('SR90', 102, 2880),
    ('3D', 305, 2068),
    ('3D90', 305, 2068),
    ('LR', 152, 2680)
  ]) {
    test('explicit $kind uses its actual standard takeout', () async {
      final a = (await h().say(command.replaceFirst('DN100', 'DN100 $kind')))
          .result as AnswerResult;
      expect(a.show!.fields['r_mm'], r);
      expect(PipeRouteInput.fromFields(a.show!.fields).result.total, total);
      expect(
          a.answer.source?.pl,
          contains(kind.startsWith('SR')
              ? 'SR'
              : kind.startsWith('3D')
                  ? '3D'
                  : 'LR'));
      if (kind != 'LR') {
        expect(a.show!.fields['dn'], isNull,
            reason: 'native DN picker represents LR only');
      }
    });
  }
  test('missing SR row retains type when asking and accepts an actual R',
      () async {
    final b = h();
    expect(
        ((await b.say(command.replaceFirst('DN100', 'DN15 SR'))).result
                as AskResult)
            .slot,
        'r_mm');
    final a = (await b.say('20 mm')).result as AnswerResult;
    expect(a.show!.fields['r_mm'], 20);
    expect(a.show!.fields['dn'], isNull);
    expect(a.answer.source, isNull);
  });
  test('conflicting radius types require a choice, not the LR default',
      () async {
    final b = h();
    expect(
        ((await b.say(command.replaceFirst('DN100', 'DN100 LR SR'))).result
                as AskResult)
            .slot,
        'r_mm');
    final a = (await b.say('SR')).result as AnswerResult;
    expect(a.show!.fields['r_mm'], 102);
  });
  test('radius type before DN does not corrupt the preceding length', () async {
    final a =
        (await h().say(command.replaceFirst('DN100', 'short radius DN100')))
            .result as AnswerResult;
    expect(a.show!.fields['y_mm'], 800);
    expect(a.show!.fields['r_mm'], 102);
  });
  test('typed dialogue requires both gap and end-measurement choice', () async {
    final b = h();
    Future<String> ask(String t) async =>
        ((await b.say(t)).result as AskResult).slot;
    expect(await ask('oblicz trasę rur'), 'h1_mm');
    expect(await ask('2 m'), 'h2_mm');
    expect(await ask('50 cm'), 'x_mm');
    expect(await ask('1 m'), 'y_mm');
    expect(await ask('80 cm'), 'r_mm');
    expect(await ask('DN100'), 'gap_mm');
    expect(await ask('3 mm'), 'end_welds');
    final a = (await b.say('nie')).result as AnswerResult;
    expect(PipeRouteInput.fromFields(a.show!.fields).result.total, 2680);
  });
  test('end welds use six actual gaps and different total', () async {
    final a = (await h().say(command.replaceFirst(
            'bez spoin końcowych', 'ze spoinami końcowymi')))
        .result as AnswerResult;
    final p = PipeRouteInput.fromFields(a.show!.fields);
    expect(p.result.total, 2674);
    expect(p.result.weldCount, 6);
    expect(p.result.developedMm, closeTo(3169.522083, 1e-6));
  });
  test('signed datum heights and spoken H labels retain actual levels',
      () async {
    final a = (await h().say(
            'trasa rur ha jeden wynosi minus 500 mm ha dwa wynosi minus 2000 mm X 1000 mm Y 800 mm R 152 mm szczelina 3 mm bez spoin końcowych'))
        .result as AnswerResult;
    expect(a.show!.fields['h1_mm'], -500);
    expect(a.show!.fields['h2_mm'], -2000);
    expect(PipeRouteInput.fromFields(a.show!.fields).result.total, 2680);
  });
  test('explicit zero is clearly C-C and never labelled ready to cut',
      () async {
    final a = (await h().say(command.replaceFirst('DN100', 'R 0 mm'))).result
        as AnswerResult;
    expect(a.answer.text.pl, contains('wynik C-C'));
    expect(a.answer.text.pl, isNot(contains('Rury do cięcia')));
  });
  for (final (text, key) in <(String, String)>[
    ('H1 500 mm', 'heights'),
    ('X 0 mm', 'x_mm'),
    ('Y minus 100 mm', 'y_mm'),
    ('R minus 1 mm', 'r_mm'),
    ('R 45 stopni', 'r_mm'),
    ('R 999 mm', 'geometry'),
    ('DN9999', 'r_mm'),
    ('szczelina minus 3 mm', 'gap_mm'),
    ('spoiny końcowe może', 'end_welds'),
    ('X 100 mm albo 200 mm', 'x_mm'),
  ]) {
    test('invalid continuation asks: $text', () async {
      final b = h();
      await b.say(command);
      final q = (await b.say('a $text')).result as AskResult;
      expect(q.slot, key);
    });
  }
  test(
      'typed R clears old nominal DN instead of labelling a custom fitting ASME',
      () async {
    final b = h();
    await b.say(command);
    final a = (await b.say('a R 100 mm')).result as AnswerResult;
    expect(a.show!.fields['dn'], isNull);
    expect(a.answer.source, isNull);
    expect(PipeRouteInput.fromFields(a.show!.fields).result.total, 2888);
  });
  for (final text in [
    'trasa rur trzy kolana 90 stopni H1 2000 mm',
    'trasa rur dwa kolana 45 stopni H1 2000 mm',
    'trasa rur kolana segmentowe H1 2000 mm',
    'trasa rur DN100 SR45 H1 2000 mm',
  ]) {
    test('different physical route model is reported, never substituted: $text',
        () async {
      final a = (await h().say(text)).result as FailedResult;
      expect(a.reportMissingCapability, isTrue);
    });
  }
  test(
      'ambiguous angle must be resolved even if another parameter is corrected',
      () async {
    final b = h();
    final q =
        (await b.say('$command kąt 90 albo 45 stopni')).result as AskResult;
    expect(q.slot, 'shape');
    expect((await b.say('R 152 mm')).result, isA<AskResult>());
    final a = (await b.say('90')).result as AnswerResult;
    expect(a.show!.toolId, 'pipe_route');
  });
}

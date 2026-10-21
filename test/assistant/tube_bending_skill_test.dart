import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/fitter/tube_bending_command.dart';
import 'package:cut_list_app/i18n/app_language.dart';
import 'support/assistant_test_support.dart';

const singleCommand =
    'Oblicz gięcie rurki jedno gięcie CLR 38 mm kąt 90 stopni ramię A 200 mm ramię B 150 mm';
const multiCommand =
    'Gięcie rurki wiele gięć CLR 38 mm odcinki 150 mm 200 mm 250 mm kąty 90 45';
BrainHarness harness({AppLanguage lang = AppLanguage.pl}) {
  final h = BrainHarness(lang: lang);
  addTearDown(h.timer.dispose);
  return h;
}

void main() {
  test('PL voice command uses native single geometry without bender guesses',
      () async {
    final r = await harness().say(singleCommand, byVoice: true);
    expect(r.match?.skill.id, 'tube.bending');
    final a = r.result as AnswerResult;
    expect(a.answer.text.pl, contains('Utnij 334 mm'));
    expect(a.answer.lines.first.value, '162 mm / 90°');
    expect(a.show!.fields, containsPair('mode', 'single'));
    expect(a.show!.fields, containsPair('min_straight_mm', 0.0));
  });
  for (final (text, id) in [
    ('zmień spadek rury długość 6000 mm wznios 60 mm', 'pipe.slope'),
    (
      'zmień ukosowanie ścianka 10 mm próg 1,5 mm szczelina 2 mm kąt 37,5 stopnia na stronę',
      'bevel.geometry'
    ),
  ]) {
    test('visible bender cannot steal another explicit calculator: $text',
        () async {
      final h = BrainHarness(activeToolId: 'tube_bending', onHome: false);
      addTearDown(h.timer.dispose);
      final r = await h.say(text);
      expect(r.match?.skill.id, id);
      expect(r.result, isNot(isA<FailedResult>()));
    });
  }
  test('full set command can start a new calculation from home', () async {
    final a = (await harness(lang: AppLanguage.en).say(
            'set tube bending single CLR 38 mm angle 90 degrees leg A 200 mm leg B 150 mm'))
        .result as AnswerResult;
    expect(a.answer.text.en, contains('Cut 334 mm'));
  });
  test('typed dialogue collects mode and every required input', () async {
    final h = harness();
    Future<String> slot(String t) async =>
        ((await h.say(t)).result as AskResult).slot;
    expect(await slot('oblicz gięcie rurek'), 'mode');
    expect(await slot('jedno'), 'clr_mm');
    expect(await slot('38 mm'), 'angle_deg');
    expect(await slot('90'), 'leg_a_mm');
    expect(await slot('20 cm'), 'leg_b_mm');
    final a = (await h.say('15 cm')).result as AnswerResult;
    expect(a.answer.text.pl, contains('Utnij 334 mm'));
  });
  test('mode answer preserves dimensions supplied before it', () async {
    final h = harness();
    expect(
        (await h.say(
                'gięcie rurki CLR 38 mm kąt 90 stopni ramię A 200 mm ramię B 150 mm'))
            .result,
        isA<AskResult>());
    final a = (await h.say('single')).result as AnswerResult;
    expect(a.answer.text.pl, contains('Utnij 334 mm'));
  });
  test('tube rolling offset never runs the pipe-offset formula', () async {
    final r = await harness(lang: AppLanguage.en).say(
        'Tube bending rolling offset CLR 30 mm rise 100 mm spread 50 mm angle 45 degrees leg A 200 mm leg B 200 mm');
    expect(r.match?.skill.id, 'tube.bending');
    final c =
        TubeBendingCommand.fromFields((r.result as AnswerResult).show!.fields);
    expect(c.offset!.travelMm, closeTo(158.113883, 1e-6));
    expect(c.run.bends, hasLength(2));
  });
  test(
      'multi lists preserve order and explicit rotation; corrections retain other arrays',
      () async {
    final h = harness();
    final a =
        (await h.say('$multiCommand obroty 0 180')).result as AnswerResult;
    expect(a.show!.fields['segments_mm'], [150.0, 200.0, 250.0]);
    expect(a.show!.fields['angles_deg'], [90.0, 45.0]);
    expect(a.show!.fields['rotations_deg'], [0.0, 180.0]);
    final corrected =
        (await h.say('a odcinki 160 mm 200 mm 250 mm')).result as AnswerResult;
    expect(corrected.show!.fields['segments_mm'], [160.0, 200.0, 250.0]);
    expect(corrected.show!.fields['angles_deg'], [90.0, 45.0]);
    expect(corrected.show!.fields['rotations_deg'], [0.0, 180.0]);
  });
  test('one final explicit length unit applies to a list', () async {
    final a = (await harness()
            .say('gięcie rurki multi CLR 3 cm odcinki 15 20 25 cm kąty 90 45'))
        .result as AnswerResult;
    expect(a.show!.fields['segments_mm'], [150.0, 200.0, 250.0]);
  });
  test('inches in input are canonical millimetres; output units are explicit',
      () async {
    final a = (await harness(lang: AppLanguage.en).say(
            'tube bending single CLR 1 inch angle 90 degrees leg A 8 inches leg B 6 inches units inch'))
        .result as AnswerResult;
    expect(a.show!.fields['clr_mm'], 25.4);
    expect(a.show!.fields['leg_a_mm'], 203.2);
    expect(a.show!.fields['unit'], 'inch');
    expect(a.answer.text.en, contains('1/32 inch'));
  });
  for (final (change, key) in <(String, String)>[
    ('CLR 0 mm', 'clr_mm'),
    ('CLR minus 38 mm', 'clr_mm'),
    ('kąt 180 stopni', 'angle_deg'),
    ('kąt 90 albo 45', 'angle_deg'),
    ('ramię A 1 mm', 'geometry'),
    ('ramię A 0 mm', 'leg_a_mm'),
    ('minimum straight minus 1 mm', 'min_straight_mm'),
    ('marker offset 1001 mm', 'marker_offset_mm'),
    ('springback 31 degrees', 'springback_deg'),
    ('unit cm', 'unit'),
  ]) {
    test(
        'bad continuation asks without replacing valid calculator values: $change',
        () async {
      final h = harness();
      await h.say(singleCommand);
      final a = (await h.say('a $change')).result as AskResult;
      expect(a.slot, key);
    });
  }
  test('inconsistent arrays ask; correction retains CLR and geometry',
      () async {
    final h = harness();
    final bad = (await h.say(
            'gięcie rurki multi CLR 38 mm odcinki 150 mm 200 mm kąty 90 45'))
        .result as AskResult;
    expect(bad.slot, 'segments_mm');
    final good =
        (await h.say('odcinki 150 mm 200 mm 250 mm')).result as AnswerResult;
    expect(good.show!.fields['clr_mm'], 38);
    expect(good.show!.fields['angles_deg'], [90.0, 45.0]);
  });
  test('explicit rotations cannot be padded, ignored or dropped', () async {
    final h = harness();
    expect(
        ((await h.say('$multiCommand obroty 90 180')).result as AskResult).slot,
        'rotations_deg');
    final good = (await h.say('bez obrotów')).result as AnswerResult;
    expect(good.show!.fields['rotations_deg'], [0.0, 0.0]);
  });
  test('mode switch requires fresh geometry and keeps the known bender',
      () async {
    final h = harness();
    await h.say(singleCommand);
    final q = (await h.say('a odsadzka')).result as AskResult;
    expect(q.partial.slots['clr_mm'], 38);
    expect(q.partial.slots['leg_a_mm'], isNull);
    expect(q.partial.slots['angle_deg'], isNull);
  });
  test('warning lines show actual minimum grip and marker limits', () async {
    final a = (await harness().say(
            '$singleCommand minimum straight 200 mm marker offset 1000 mm'))
        .result as AnswerResult;
    expect(a.answer.lines.where((l) => l.label.pl == 'Uwaga'), hasLength(3));
    expect(
        a.answer.lines.map((l) => l.value).join(' '), contains('poza rurką'));
  });
  test('independent supported question interrupts typed pending input',
      () async {
    final h = harness();
    await h.say('oblicz gięcie rurek');
    await h.say('single');
    final r = await h.say('jaka jest średnica rury DN40');
    expect(r.match?.skill.id, 'pipe.od');
    expect(r.result, isA<AnswerResult>());
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'package:cut_list_app/domain/welding/heat_input.dart';
import 'support/assistant_test_support.dart';

void main() {
  test('parametry z jednostkami odpowiadają domenie i wypełniają moduł',
      () async {
    final h = BrainHarness();
    final reply =
        await h.say('oblicz energię liniową TIG EN 24 V 230 A 150 mm/min');
    expect(reply.match?.skill.id, 'heat.input');
    final result = reply.result as AnswerResult;
    expect(result.show!.fields, {
      'process': 'GTAW',
      'standard': 'en1011',
      'volts': 24.0,
      'amps': 230.0,
      'travel_mm_min': 150.0
    });
    final expected = heatInputKJPerMm(
        volts: 24,
        amps: 230,
        travelMmPerMin: 150,
        standard: HeatInputStandard.en1011,
        efficiency: WeldingProcess.gtaw.thermalEfficiency)!;
    expect(expected, closeTo(1.3248, 1e-9));
    expect(
        textOf(result),
        contains(
            '${HeatInputUnit.kjPerMm.format(expected).replaceAll('.', ',')} kJ/mm'));
  });
  test('sprawność z WPS jest uwzględniana, także w procentach', () async {
    for (final suffix in ['sprawność 0,8', 'sprawność 80%']) {
      final reply = await BrainHarness()
          .say('oblicz heat input TIG EN 24 V 230 A 150 mm/min $suffix');
      final result = reply.result as AnswerResult;
      expect(result.show!.fields['efficiency'], 0.8);
      expect(textOf(result), contains('1,77 kJ/mm'));
    }
    final invalid = await BrainHarness()
        .say('oblicz heat input TIG EN 24 V 230 A 150 mm/min sprawność 2');
    expect(invalid.result, isA<AskResult>());
  });

  test('dopytuje o proces i konwencję, zamiast zgadywać sprawność', () async {
    final h = BrainHarness();
    expect(
        ((await h.say('heat input 12 V 100 A 90 mm/min')).result as AskResult)
            .slot,
        'process');
    expect(((await h.say('TIG')).result as AskResult).slot, 'standard');
    final reply = await h.say('ASME');
    expect(textOf(reply.result), contains('0,8 kJ/mm'));
    expect((reply.result as AnswerResult).show!.fields['standard'], 'asmeIx');
  });
  test('każdy proponowany proces daje się wybrać odpowiedzią na pytanie', () async {
    for (final process in WeldingProcess.values) {
      final h = BrainHarness();
      await h.say('heat input 24 V 230 A 150 mm/min');
      final reply = await h.say(process.code);
      expect((reply.result as AskResult).slot,'standard',reason:process.code);
      final result = (await h.say('EN')).result as AnswerResult;
      expect(result.show!.fields['process'],process.code);
    }
  });

  test('krótka odpowiedź liczbowa uzupełnia tylko wskazane pole', () async {
    final h = BrainHarness();
    expect(
        ((await h.say('oblicz heat input TIG EN 24 V 150 mm/min')).result
                as AskResult)
            .slot,
        'amps');
    final reply = await h.say('230');
    expect(textOf(reply.result), contains('1,32 kJ/mm'));
    expect((reply.result as AnswerResult).show!.fields['amps'], 230.0);
  });

  test('ustawienie pojedynczego pola działa tylko w kontekście kalkulatora',
      () async {
    final h = BrainHarness(activeToolId: 'heat_input', onHome: false);
    final reply = await h.say('ustaw 250 A');
    expect(reply.match?.skill.id, 'heat.input');
    expect((reply.result as AnswerResult).show!.fields, {'amps': 250.0});
    expect(textOf(reply.result), contains('250 A'));
    expect((await BrainHarness().say('ustaw 250 A')).match?.skill.id,
        isNot('heat.input'));
  });
  test('sprzeczne lub niepoprawne liczby nie ustawiają części danych',
      () async {
    for (final text in [
      'ustaw heat input 100 A 120 A 24 V',
      'ustaw heat input minus 100 A 24 V',
      'ustaw heat input 0 A 24 V'
    ]) {
      final reply = await BrainHarness().say(text);
      expect(reply.result, isA<AskResult>(), reason: text);
    }
  });
}

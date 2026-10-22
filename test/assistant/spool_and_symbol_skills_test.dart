import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/assistant/core/skill.dart';
import 'support/assistant_test_support.dart';

void main() {
  group('spool.tolerance (PFI ES-3)', () {
    test('DN bands: ±3 / ±4,76 mm (sharper of inch and metric)',
        () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final small = (await h.say('Jaka tolerancja wymiaru spoola DN200'))
          .result as AnswerResult;
      expect(small.answer.text.pl, contains('±3 mm'));
      expect(small.show!.toolId, 'spool_check');
      final mid = (await h.say('Ile wolno odchyłki na spoolu DN400')).result
          as AnswerResult;
      // 3/16″ = 4,7625 → w dół do siatki 0,01 mm = 4,76 < 5,0 metryczne.
      expect(mid.answer.text.pl, contains('±4,76 mm'));
    });

    test('drawing vs measured gives a verdict', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final ok = (await h.say(
              'Tolerancja spoola DN100 rysunek 1500 mm zmierzone 1503 mm'))
          .result as AnswerResult;
      expect(ok.answer.text.pl, contains('+3 mm — w tolerancji'));
      final out = (await h.say(
              'Tolerancja spoola DN100 rysunek 1500 mm zmierzone 1504 mm'))
          .result as AnswerResult;
      expect(out.answer.text.pl, contains('POZA tolerancją'));
    });

    test('rotation and face tilt', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final rot = (await h.say('Tolerancja obrotu otworów kołnierza na spoolu'))
          .result as AnswerResult;
      expect(rot.answer.text.pl, contains('1/16″'));
      final tilt = (await h.say(
              'Tolerancja nachylenia czoła kołnierza na spoolu średnica 219,1 mm'))
          .result as AnswerResult;
      expect(tilt.answer.text.pl, contains('najwyżej'));
    });
  });

  group('weld.symbol', () {
    test('basic symbols from the module cheat sheet', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final fillet = (await h.say('Jaka spoina ma symbol trójkąta'))
          .result as AnswerResult;
      expect(fillet.answer.text.pl, contains('Trójkąt prostokątny'));
      expect(fillet.show!.toolId, 'weld_symbols');
      final half = (await h.say('Symbol spoiny pół V')).result as AnswerResult;
      expect(half.answer.text.pl, contains('Ukosowany tylko jeden brzeg'));
    });

    test('field weld flag and all-around circle', () async {
      final h = BrainHarness();
      addTearDown(h.timer.dispose);
      final flag = (await h.say('Chorągiewka na symbolu spoiny'))
          .result as AnswerResult;
      expect(flag.answer.text.pl, contains('spoina montażowa'));
      final circle = (await h.say('Kółko na linii odniesienia symbolu spoiny'))
          .result as AnswerResult;
      expect(circle.answer.text.pl, contains('dookoła'));
    });
  });
}

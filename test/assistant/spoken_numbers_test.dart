// Wspólny tokenizer mowy (wyciągnięty ze starego parsera): zwijanie tekstu,
// liczby słownie na cyfry i pierwsza liczba w zdaniu.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/spoken_numbers.dart';

void main() {
  group('foldSpeech', () {
    test('małe litery, bez polskich znaków, przecinek dziesiętny', () {
      expect(foldSpeech('Ścianka 2,77 MM'), 'scianka 2.77 mm');
    });
    test('cale cudzysłowem i ułamki calowe', () {
      expect(foldSpeech('rura 2"'), 'rura 2 cal');
      expect(foldSpeech('3/4"'), 'frac0.75 cal');
    });
    test('żargon „rura setka" = DN100', () {
      expect(foldSpeech('rura setka'), 'rura dn 100');
    });
  });

  group('spokenTokens', () {
    test('„dn czterdzieści" → [dn, 40]', () {
      expect(spokenTokens('dn czterdzieści'), ['dn', '40']);
    });
    test('„dn40" → [dn, 40]', () {
      expect(spokenTokens('dn40'), ['dn', '40']);
    });
    test('„czterdzieści pięć" → 45', () {
      expect(spokenTokens('czterdzieści pięć'), ['45']);
    });
    test('dwie liczby słowne obok siebie zostają osobno', () {
      expect(spokenTokens('ścianka dwa sześćdziesiąt'), ['scianka', '2', '60']);
    });
    test('„metr dwadzieścia" zostaje jako metr + 20', () {
      expect(spokenTokens('metr dwadzieścia'), ['metr', '20']);
    });
    test('liczby cyframi zachowują zapis (kody 141, 1.4404)', () {
      expect(spokenTokens('TIG 141 stal 1.4404'), ['tig', '141', 'stal', '1.4404']);
    });
    test('ułamki i „półtora" jako liczby dziesiętne', () {
      expect(spokenTokens('półtora cala'), ['1.5', 'cala']);
      expect(spokenTokens('trzy czwarte cala'), ['0.75', 'cala']);
      expect(spokenTokens('dwa i pół metra'), ['2.5', 'metra']);
    });
    test('EN', () {
      expect(spokenTokens('DN forty'), ['dn', '40']);
      expect(spokenTokens('one hundred and ten amps'), ['110', 'amps']);
    });
    test('pusty tekst → pusta lista', () => expect(spokenTokens('  '), isEmpty));
  });

  group('spokenItems', () {
    test('flagi: cyframi / słownie / ułamek', () {
      final items = spokenItems(foldSpeech('141 dwa 3/4'));
      expect(items.map((i) => i.value).toList(), [141, 2, 0.75]);
      expect(items[0].raw, '141');
      expect(items[1].isSpoken, isTrue);
      expect(items[2].fraction, isTrue);
    });
  });

  group('parseSpokenNumber', () {
    test('„półtora" → 1,5', () => expect(parseSpokenNumber('półtora'), 1.5));
    test('„sto dwadzieścia pięć" → 125',
        () => expect(parseSpokenNumber('sto dwadzieścia pięć'), 125));
    test('bez liczby → null', () => expect(parseSpokenNumber('stal'), isNull));
  });

  test('isInchUnit', () {
    for (final w in ['cal', 'cala', 'cale', 'cali', 'calowa', 'inch', 'inches']) {
      expect(isInchUnit(w), isTrue, reason: w);
    }
    expect(isInchUnit('calkiem'), isFalse);
  });
}

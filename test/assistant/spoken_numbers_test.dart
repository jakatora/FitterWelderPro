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

  group('przecinek dziesiętny: cyfry kolejno, z zerami wiodącymi', () {
    test('„dwa przecinek zero pięć" → 2,05',
        () => expect(parseSpokenNumber('dwa przecinek zero pięć'), 2.05));
    test('„zero przecinek zero zero pięć" → 0,005',
        () => expect(parseSpokenNumber('zero przecinek zero zero pięć'), 0.005));
    test('„przecinek zero zero pięć" (bez całości) → 0,005',
        () => expect(parseSpokenNumber('przecinek zero zero pięć'), 0.005));
    test('„dwa przecinek siedem siedem" → 2,77', () {
      expect(spokenTokens('dwa przecinek siedem siedem'), ['2.77']);
    });
    test('„dwa przecinek siedemdziesiąt pięć" → 2,75',
        () => expect(parseSpokenNumber('dwa przecinek siedemdziesiąt pięć'), 2.75));
    test('„dwa przecinek pięć sześćdziesiąt amper" → 2,5 i 60', () {
      expect(spokenTokens('dwa przecinek pięć sześćdziesiąt amper'),
          ['2.5', '60', 'amper']);
    });
    test('„2 przecinek 77 60 A" → 2,77 i 60', () {
      expect(spokenTokens('2 przecinek 77 60 A'), ['2.77', '60', 'a']);
    });
    test('„2 przecinek 0 5" → 2,05',
        () => expect(spokenTokens('2 przecinek 0 5'), ['2.05']));
    test('„zero zero pięć" bez przecinka to trzy liczby, nie 5', () {
      expect(spokenTokens('zero zero pięć'), ['0', '0', '5']);
    });
  });

  group('„N i <ułamek>"', () {
    test('„jeden i trzy czwarte" → 1,75',
        () => expect(spokenTokens('jeden i trzy czwarte'), ['1.75']));
    test('„dwa i jedna czwarta cala" → 2,25',
        () => expect(spokenTokens('dwa i jedna czwarta cala'), ['2.25', 'cala']));
    test('EN „one and three quarters" → 1,75',
        () => expect(spokenTokens('one and three quarters'), ['1.75']));
  });

  test('„and" nie znika przy przerwanym ciągu („fifty and sixty")', () {
    expect(spokenTokens('DN fifty and sixty'), ['dn', '50', 'and', '60']);
    expect(spokenTokens('one hundred and ten'), ['110']);
  });

  test('słowa wyłączone z liczb („ten" po polsku)', () {
    expect(
        spokenItems(foldSpeech('ten dn40'), notNumbers: const {'ten'})
            .map((i) => i.text)
            .toList(),
        ['ten', 'dn', '40']);
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

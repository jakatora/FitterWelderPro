// Wypowiedź asystenta: zwinięcie tekstu i wyciąganie wielkości (DN, NPS,
// długość, kąt, liczba przy słowie-kluczu). Zasada: niejasne → null
// (umiejętność dopyta), nigdy cichy zły wynik.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/assistant/core/utterance.dart';
import 'package:cut_list_app/i18n/app_language.dart';

Utterance pl(String s) => Utterance(s, lang: AppLanguage.pl);
Utterance en(String s) => Utterance(s, lang: AppLanguage.en);

void main() {
  group('zwinięcie i tokeny', () {
    test('folded bez polskich znaków', () {
      expect(pl('Jaka ŚREDNICA rury?').folded, 'jaka srednica rury');
    });
    test('tokens z liczbami słownie', () {
      expect(pl('dn czterdzieści').tokens, ['dn', '40']);
    });
    test('hasAny — całe słowa i frazy, wejście zwijane', () {
      final u = pl('Jaka jest średnica zewnętrzna rury');
      expect(u.hasAny(['średnica zewnętrzna']), isTrue);
      expect(u.hasAny(['srednica']), isTrue);
      expect(u.hasAny(['sredni']), isFalse); // nie fragment słowa
      expect(u.hasAny(['scianka', 'wall']), isFalse);
    });
    test('hasStem — kolano/kolanko/kolana', () {
      expect(pl('kolanko').hasStem(['kolan']), isTrue);
      expect(pl('dwa kolana').hasStem(['kolan']), isTrue);
      expect(pl('trójnik').hasStem(['kolan']), isFalse);
      expect(pl('trójnik').hasStem(['trojnik']), isTrue);
    });
  });

  group('dn()', () {
    // dn40 — sklejone
    test('dn40', () => expect(pl('jaka średnica dn40').dn(), 40));
    // dn 40 — ze spacją
    test('dn 40', () => expect(pl('średnica DN 40').dn(), 40));
    // de en 40 — literowane przez rozpoznawanie mowy
    test('de en 40', () => expect(pl('ile ma de en 40').dn(), 40));
    // d n 40
    test('d n 40', () => expect(pl('d n 40 ile mm').dn(), 40));
    // dn czterdzieści — słownie
    test('dn czterdzieści', () => expect(pl('dn czterdzieści').dn(), 40));
    // de en czterdzieści
    test('de en czterdzieści',
        () => expect(pl('ile ma de en czterdzieści').dn(), 40));
    // „rura setka" — żargon = DN100
    test('rura setka', () => expect(pl('rura setka').dn(), 100));
    // EN
    test('EN: what is the OD of DN40',
        () => expect(en('what is the OD of DN40').dn(), 40));
    test('EN: dee en forty', () => expect(en('d n forty').dn(), 40));
    // „dn 4 0" — cyfry osobno: 40 czy 4? → null (pytanie)
    test('dn 4 0 → null', () {
      final u = pl('dn 4 0');
      expect(u.dn(), isNull);
      expect(u.mentionsDn, isTrue);
    });
    // DN i dalsze liczby z jednostką nie są dwuznaczne
    test('dn 40 2 metry → 40', () => expect(pl('dn 40 2 metry').dn(), 40));
    test('dn 50 141 80 amper → 50',
        () => expect(pl('spawam rurę dn 50 141 80 amper').dn(), 50));
    // samo „dn" bez liczby
    test('dn bez liczby → null, ale mentionsDn', () {
      final u = pl('jaka średnica dn');
      expect(u.dn(), isNull);
      expect(u.mentionsDn, isTrue);
    });
    // „ten en 40" — źle rozpoznane, to nie DN
    test('ten en 40 → null', () {
      final u = pl('ten en 40');
      expect(u.dn(), isNull);
      expect(u.mentionsDn, isFalse);
    });
    test('ułamkowe DN → null', () => expect(pl('dn 40,5').dn(), isNull));
    test('brak DN', () => expect(pl('średnica 2 cale').dn(), isNull));
  });

  group('npsInches()', () {
    // 2"
    test('2"', () => expect(pl('rura 2"').npsInches(), 2));
    // 2 cale
    test('2 cale', () => expect(pl('średnica 2 cale').npsInches(), 2));
    // dwa cale
    test('dwa cale', () => expect(pl('dwa cale').npsInches(), 2));
    // półtora cala
    test('półtora cala', () => expect(pl('półtora cala').npsInches(), 1.5));
    // trzy czwarte cala
    test('trzy czwarte cala',
        () => expect(pl('trzy czwarte cala').npsInches(), 0.75));
    // trzy czwarte (bez „cala")
    test('trzy czwarte', () => expect(pl('rura trzy czwarte').npsInches(), 0.75));
    // 1 1/4"
    test('1 1/4"', () => expect(pl('1 1/4"').npsInches(), 1.25));
    // pół cala
    test('pół cala', () => expect(pl('pół cala').npsInches(), 0.5));
    // NPS 2
    test('NPS 2', () => expect(en('NPS 2 OD').npsInches(), 2));
    // EN
    test('two inch', () => expect(en('two inch pipe').npsInches(), 2));
    test('brak cali → null', () => expect(pl('dn40').npsInches(), isNull));
  });

  group('lengthMm()', () {
    // „2 m"
    test('2 m', () {
      final u = pl('rura 2 m');
      expect(u.lengthMm(), 2000);
      expect(u.lengthAssumedMeters, isFalse);
    });
    // „2m" sklejone
    test('2m', () => expect(pl('rura 2m').lengthMm(), 2000));
    // „dwa metry"
    test('dwa metry', () => expect(pl('rura dwa metry').lengthMm(), 2000));
    // „1500"
    test('1500 bez jednostki = mm', () {
      final u = pl('rura 1500');
      expect(u.lengthMm(), 1500);
      expect(u.lengthAssumedMeters, isFalse);
    });
    // „1500 mm"
    test('1500 mm', () => expect(pl('1500 mm').lengthMm(), 1500));
    // „150 cm"
    test('150 cm', () => expect(pl('150 cm').lengthMm(), 1500));
    // „metr dwadzieścia" = 1,2 m
    test('metr dwadzieścia → 1200',
        () => expect(pl('rura metr dwadzieścia').lengthMm(), 1200));
    // „dwa metry dwadzieścia" = 2,2 m
    test('dwa metry dwadzieścia → 2200',
        () => expect(pl('dwa metry dwadzieścia').lengthMm(), 2200));
    // „metr"
    test('metr → 1000', () => expect(pl('rura metr').lengthMm(), 1000));
    // „półtora metra"
    test('półtora metra → 1500',
        () => expect(pl('półtora metra').lengthMm(), 1500));
    // „pół metra"
    test('pół metra → 500', () => expect(pl('pół metra').lengthMm(), 500));
    // „rura 2" → 2000 z założeniem metrów
    test('rura 2 → 2000, założone metry', () {
      final u = pl('rura 2');
      expect(u.lengthMm(), 2000);
      expect(u.lengthAssumedMeters, isTrue);
    });
    // próg założenia metrów
    test('assumeMetersBelow', () {
      expect(pl('rura 30').lengthMm(assumeMetersBelow: 10), 30);
    });
    // DN i kąt nie są długością
    test('dn50 kolano 90 → brak długości',
        () => expect(pl('dn50 kolano 90').lengthMm(), isNull));
    test('EN: 2 meters', () => expect(en('pipe 2 meters').lengthMm(), 2000));
    test('brak liczby → null', () => expect(pl('rura').lengthMm(), isNull));
  });

  group('numberNear()', () {
    test('sch 40', () => expect(pl('ścianka dn40 sch 40').numberNear(['sch']), 40));
    test('liczba przed słowem (60 amper)',
        () => expect(pl('60 amper').numberNear(['amper']), 60));
    test('przez słowo-most (prąd na 90)',
        () => expect(pl('prąd na 90').numberNear(['prad']), 90));
    test('brak klucza → null', () => expect(pl('dn40').numberNear(['sch']), isNull));
  });

  group('angleDeg()', () {
    test('45°', () => expect(pl('kolano 45°').angleDeg(), 45));
    test('45 stopni', () => expect(pl('cięcie 45 stopni').angleDeg(), 45));
    test('kolano 90', () => expect(pl('kolano 90').angleDeg(), 90));
    test('kąt 37,5', () => expect(pl('kąt 37,5').angleDeg(), 37.5));
    test('EN: 30 degrees', () => expect(en('30 degrees').angleDeg(), 30));
    test('kolano bez kąta → null', () => expect(pl('kolano').angleDeg(), isNull));
    test('kolano dn50 → null (to nie kąt)',
        () => expect(pl('kolano dn50').angleDeg(), isNull));
  });

  group('kontynuacja i alternatywy', () {
    test('„a dla DN50?" to kontynuacja', () {
      expect(pl('a dla DN50?').isContinuation, isTrue);
      expect(pl('a ścianka?').isContinuation, isTrue);
      expect(en('and DN50?').isContinuation, isTrue);
      expect(en('what about DN50').isContinuation, isTrue);
      expect(pl('jaka średnica dn50').isContinuation, isFalse);
    });
    test('withRaw zachowuje język i głos, bez alternatyw', () {
      final u = Utterance('ten en 40',
          lang: AppLanguage.pl, byVoice: true, alternatives: ['de en 40']);
      final alt = u.withRaw(u.alternatives.single);
      expect(alt.raw, 'de en 40');
      expect(alt.lang, AppLanguage.pl);
      expect(alt.byVoice, isTrue);
      expect(alt.alternatives, isEmpty);
      expect(alt.dn(), 40);
    });
  });
}

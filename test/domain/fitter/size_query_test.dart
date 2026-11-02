// Wyszukiwarki rozmiarów (take-outy kolan, schedule): podpowiedź w polu mówi
// „Szukaj: DN50, 2", 100…”, a przed poprawką `2"` nie znajdowało nic, bo
// porównanie szło z NPS zapisanym bez znaku cala ('2').

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/data/elbow_takeouts.dart';
import 'package:cut_list_app/domain/fitter/size_query.dart';

List<int> _hits(String q) => kElbowTakeouts
    .where((e) => sizeQueryMatches(q, dn: e.dn, nps: e.nps))
    .map((e) => e.dn)
    .toList();

void main() {
  test('parseNpsInches', () {
    expect(parseNpsInches('2'), 2);
    expect(parseNpsInches('1 1/2'), 1.5);
    expect(parseNpsInches('1-1/2'), 1.5);
    expect(parseNpsInches('3/4'), 0.75);
    expect(parseNpsInches('1,5'), 1.5);
    expect(parseNpsInches('2"'), 2);
    expect(parseNpsInches('abc'), isNull);
    expect(parseNpsInches('1/0'), isNull);
  });
  test('oversized and non-finite inch inputs are safely rejected', () {
    final digits = '9' * 400;
    for (final q in ['$digits/2', '1/$digits', '$digits 1/2', digits,
      '99999999999999999999/2', '1/99999999999999999999', '1/0']) {
      expect(parseNpsInches(q), isNull, reason: q);
      expect(sizeQueryMatches('$q"', dn: 50, nps: '2"'), isFalse, reason: q);
    }
    expect(parseNpsInches('1 1/2'), 1.5);
  });
  test('embedded or repeated inch marks cannot turn a typo into another size', () {
    for (final q in ['1"2"', '1″2"', '1”2"', '1" 1/2"', '2""',
      '1"2', '1″2', '1”2', '"2']) {
      expect(_hits(q), isEmpty, reason: q);
      expect(parseNpsInches(q), isNull, reason: q);
    }
    expect(_hits('12"'), [300]);
    expect(_hits('1 1/2"'), [40]);
  });

  test('2" / 2 cale / 2 cali / 2 in → tylko NPS 2 (DN50)', () {
    for (final q in ['2"', '2 "', '2 cale', '2 cali', '2 cala', '2cal', '2 in',
        '2in', '2 inch', "2''", '2″', '2”']) {
      expect(_hits(q), [50], reason: q);
    }
  });

  test('1 1/2" / 1-1/2" / 1,5" → DN40', () {
    for (final q in ['1 1/2"', '1-1/2"', '1,5"', '1.5 cala']) {
      expect(_hits(q), [40], reason: q);
    }
  });

  test('1/2" → DN15, nie 1 1/2', () {
    expect(_hits('1/2"'), [15]);
  });

  test('DN 50 ze spacją i dn50', () {
    expect(_hits('DN 50'), containsAll([50, 500]));
    expect(_hits('dn50'), isNot(contains(150)));
    expect(_hits('DN15'), [15, 150]);
  });

  test('zwykła liczba działa jak dotąd (podciąg DN)', () {
    expect(_hits('100'), [100]);
    expect(_hits(''), kElbowTakeouts.map((e) => e.dn).toList());
  });

  test('NPS zapisany ze znakiem cala w danych też pasuje', () {
    expect(sizeQueryMatches('2"', dn: 50, nps: '2"'), isTrue);
    expect(sizeQueryMatches('3"', dn: 50, nps: '2"'), isFalse);
  });
}

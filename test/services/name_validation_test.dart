// Wspólny walidator imienia i nazwiska (onboarding + profil).
//
// Stary regex `^[\p{L} '\-]{2,}$` przepuszczał nazwy bez liter („--",
// „' -"), choć komunikat mówił „min. 2 litery", i nie miał limitu długości —
// a podpis na czacie jest przycinany do 32 znaków.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/user_profile.dart';

void main() {
  test('poprawne imiona i nazwiska', () {
    for (final ok in [
      'Jo',
      'Jan',
      'Anna-Maria',
      "O'Brien",
      'Łukasz',
      'Żółkiewski',
      'van der Berg',
    ]) {
      expect(checkNamePart(ok), isNull, reason: ok);
    }
  });

  test('puste pole', () {
    expect(checkNamePart('   '), NameProblem.empty);
  });

  test('bez co najmniej 2 liter — odrzucone', () {
    for (final bad in ['--', "' -", 'J', "J'", '- -']) {
      expect(checkNamePart(bad), NameProblem.invalid, reason: bad);
    }
  });

  test('cyfry i znaki specjalne — odrzucone', () {
    for (final bad in ['Jan2', 'Jan!', 'J@n', 'Jan_K']) {
      expect(checkNamePart(bad), NameProblem.invalid, reason: bad);
    }
  });

  test('limit długości pola', () {
    expect(checkNamePart('A' * kNamePartMaxLength), isNull);
    expect(checkNamePart('A' * (kNamePartMaxLength + 1)), NameProblem.tooLong);
  });

  test('imię i nazwisko razem mieszczą się w podpisie czatu (32 znaki)', () {
    expect(fullNameTooLong('Jan', 'Kowalski'), isFalse);
    expect(fullNameTooLong('A' * 16, 'B' * 15), isFalse); // 16 + 1 + 15 = 32
    expect(fullNameTooLong('A' * 16, 'B' * 16), isTrue); // 33
  });
}

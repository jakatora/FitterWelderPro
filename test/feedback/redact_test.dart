// Maskowanie danych kontaktowych w tekście zgłoszenia.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/feedback/redact.dart';

void main() {
  group('telefony', () {
    const cases = {
      '+48 600 100 200': '***',
      'mój numer +48 600 100 200, dzwoń': 'mój numer ***, dzwoń',
      '+48600100200': '***',
      '(+48) 600-100-200': '***',
      '0048 600 100 200': '***',
      '600-100-200': '***',
      '600.100.200': '***',
      '600100200': '***',
      'zadzwoń 600 100 200 jutro': 'zadzwoń *** jutro',
      '22 123 45 67': '***',
      'biuro (22) 123-45-67': 'biuro ***',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(redactPersonalData(input), expected));
    });
  });

  group('e-maile', () {
    const cases = {
      'jan@x.pl': '***',
      'pisz na Jan.Kowalski+fwp@firma.com.pl dzięki': 'pisz na *** dzięki',
      'jan małpa wp kropka pl': '***',
      'mail: jan at gmail.com': 'mail: ***',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(redactPersonalData(input), expected));
    });
  });

  group('ciągi ≥ 9 cyfr i konta', () {
    const cases = {
      'PESEL 85010112345': 'PESEL ***',
      '123456789': '***',
      'nip 123-456-78-90': 'nip ***',
      'konto PL61 1090 1014 0000 0712 1981 2874': 'konto ***',
      'konto 61109010140000071219812874': 'konto ***',
    };
    cases.forEach((input, expected) {
      test(input, () => expect(redactPersonalData(input), expected));
    });
  });

  group('treść techniczna zostaje', () {
    const keep = [
      '12345678',
      'dodaj odcinki 1200 1500 800',
      'DN 50 100 200',
      'rura 2 cale sch 40',
      'spadek 1.5% na 12 m',
      'data 2026-10-19 i 19.10.2026',
      'kolano 90 stopni DN150',
      'ile waży 6000 mm rury 168,3 x 7,1',
      'it fails at startup. Please fix it',
      'look at this dot',
    ];
    for (final k in keep) {
      test(k, () => expect(redactPersonalData(k), k));
    }
  });

  group('prepareFeedbackText', () {
    test('przycina do 500 jednostek UTF-16', () {
      expect(prepareFeedbackText('a' * 800).length, 500);
      expect(prepareFeedbackText('  krótki  '), 'krótki');
    });

    test('maskuje PRZED przycięciem — numer na granicy nie zostaje w połowie',
        () {
      final text = '${'a' * 495} 600100200';
      final out = prepareFeedbackText(text);
      expect(out.length, lessThanOrEqualTo(500));
      expect(out, endsWith('***'));
      expect(out, isNot(contains('600')));
    });

    test('nie rozcina emoji (pary zastępczej) na granicy', () {
      final text = '${'a' * 499}🔥 dalej';
      final out = prepareFeedbackText(text);
      expect(out.length, 499);
      expect(out.codeUnitAt(out.length - 1), 'a'.codeUnitAt(0));
    });

    test('truncateUtf16 nie zmienia krótszych tekstów', () {
      expect(truncateUtf16('abc', 5), 'abc');
    });
  });
}

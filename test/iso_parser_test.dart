import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/iso_parser.dart';

void main() {
  group('parseIsoExpression — basic', () {
    test('plain integer', () {
      expect(parseIsoExpression('3000'), 3000);
    });

    test('decimal with dot', () {
      expect(parseIsoExpression('1020.5'), 1020.5);
    });

    test('comma is treated as decimal point', () {
      expect(parseIsoExpression('1020,5'), 1020.5);
    });

    test('whitespace ignored', () {
      expect(parseIsoExpression('  3000  '), 3000);
      expect(parseIsoExpression(' 1020,5 + 20 '), 1040.5);
    });
  });

  group('parseIsoExpression — addition / subtraction', () {
    test('add/sub chain', () {
      expect(parseIsoExpression('3000+525-80'), 3445);
    });

    test('leading minus', () {
      expect(parseIsoExpression('-150'), -150);
    });

    test('leading plus', () {
      expect(parseIsoExpression('+150'), 150);
    });
  });

  group('parseIsoExpression — multiplication', () {
    test('asterisk', () {
      expect(parseIsoExpression('5*200'), 1000);
    });

    test('lowercase x', () {
      expect(parseIsoExpression('5x200'), 1000);
    });

    test('uppercase X', () {
      expect(parseIsoExpression('5X200'), 1000);
    });

    test('unicode multiplication sign', () {
      expect(parseIsoExpression('5×200'), 1000);
    });

    test('middle dot', () {
      expect(parseIsoExpression('5·200'), 1000);
    });

    test('multiplication binds tighter than addition', () {
      expect(parseIsoExpression('5*200+150'), 1150);
      expect(parseIsoExpression('150+5*200'), 1150);
    });
  });

  group('parseIsoExpression — parentheses', () {
    test('simple group', () {
      expect(parseIsoExpression('(3000)'), 3000);
    });

    test('group + multiplication', () {
      expect(parseIsoExpression('(1500+200)*2'), 3400);
    });

    test('complex expression from the README', () {
      expect(parseIsoExpression('(1500+200)*2+100'), 3500);
    });

    test('nested parentheses', () {
      expect(parseIsoExpression('((1500+200)*2)+100'), 3500);
      expect(parseIsoExpression('2*(3*(4+1))'), 30);
    });
  });

  // P1-03: normaliseInput pre-pass — welders paste from PDFs / WhatsApp where
  // dashes, minuses, fractions, NBSPs and unit suffixes leak through. The
  // parser was previously throwing "bad chars" on perfectly sensible inputs.
  group('parseIsoExpression — P1-03 unicode normalisation', () {
    test('U+2212 minus sign treated as ASCII minus', () {
      expect(parseIsoExpression('3000−525'), 2475);
      expect(parseIsoExpression('−150'), -150);
    });

    test('U+2010 hyphen treated as ASCII minus', () {
      expect(parseIsoExpression('3000‐525'), 2475);
    });

    test('U+2011 non-breaking hyphen treated as ASCII minus', () {
      expect(parseIsoExpression('3000‑525'), 2475);
    });

    test('U+2012 figure dash treated as ASCII minus', () {
      expect(parseIsoExpression('3000‒525'), 2475);
    });

    test('U+2013 en dash treated as ASCII minus', () {
      expect(parseIsoExpression('3000–525'), 2475);
    });

    test('U+2014 em dash treated as ASCII minus', () {
      expect(parseIsoExpression('3000—525'), 2475);
    });

    test('U+2015 horizontal bar treated as ASCII minus', () {
      expect(parseIsoExpression('3000―525'), 2475);
    });

    test('vulgar fraction ½ -> 0.5', () {
      expect(parseIsoExpression('½'), 0.5);
      expect(parseIsoExpression('100+½'), 100.5);
    });

    test('vulgar fraction ¼ -> 0.25', () {
      expect(parseIsoExpression('¼'), 0.25);
      expect(parseIsoExpression('100+¼'), 100.25);
    });

    test('vulgar fraction ¾ -> 0.75', () {
      expect(parseIsoExpression('¾'), 0.75);
      expect(parseIsoExpression('100+¾'), 100.75);
    });

    test('zero-width space U+200B stripped', () {
      expect(parseIsoExpression('30​00'), 3000);
    });

    test('zero-width non-joiner U+200C stripped', () {
      expect(parseIsoExpression('30‌00'), 3000);
    });

    test('left-to-right mark U+200E stripped', () {
      expect(parseIsoExpression('30‎00'), 3000);
    });

    test('right-to-left mark U+200F stripped', () {
      expect(parseIsoExpression('30‏00'), 3000);
    });

    test('narrow no-break space U+202F stripped as thousands sep', () {
      expect(parseIsoExpression('1 234'), 1234);
    });

    test('BOM U+FEFF stripped', () {
      expect(parseIsoExpression('﻿3000'), 3000);
    });

    test('trailing mm unit dropped', () {
      expect(parseIsoExpression('3000mm'), 3000);
      expect(parseIsoExpression('3000 mm'), 3000);
      expect(parseIsoExpression('3000MM'), 3000);
    });

    test('trailing in unit dropped', () {
      expect(parseIsoExpression('76in'), 76);
      expect(parseIsoExpression('76 in'), 76);
    });

    test('trailing inch quote dropped', () {
      expect(parseIsoExpression('76"'), 76);
      expect(parseIsoExpression('76 "'), 76);
    });

    test('NBSP thousands separator stripped', () {
      expect(parseIsoExpression('1 234'), 1234);
      expect(parseIsoExpression('12 345'), 12345);
    });

    test('apostrophe thousands separator stripped', () {
      expect(parseIsoExpression("1'234"), 1234);
    });

    test('combined real-world paste: NBSP thousands + en-dash + mm suffix', () {
      // U+00A0 thousands sep + U+2013 en-dash + 'mm' trailing unit.
      // "3 000–2 525 mm" -> "3000-2525" -> 475.
      expect(
        parseIsoExpression('3 000–2 525 mm'),
        475,
      );
    });

  });

  group('parseIsoExpression — errors', () {
    test('empty', () {
      expect(() => parseIsoExpression(''), throwsFormatException);
    });

    test('bad character', () {
      expect(() => parseIsoExpression('3000/2'), throwsFormatException);
      expect(() => parseIsoExpression('abc'), throwsFormatException);
    });

    test('missing closing paren', () {
      expect(() => parseIsoExpression('(3000'), throwsFormatException);
    });

    test('trailing operator', () {
      expect(() => parseIsoExpression('3000+'), throwsFormatException);
    });
  });
}

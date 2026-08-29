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

    // WHY these two tests changed: the previous version asserted
    // `parseIsoExpression('76in') == 76` and `parseIsoExpression('76"') == 76`,
    // i.e. they *guarded the bug* — the normaliser deleted the inch suffix
    // instead of converting it, so every imperial dimension came out 25.4x too
    // small and a 1930 mm spool would have been cut to 76 mm. Inches are now
    // converted to the app's internal base unit (mm), so these tests assert the
    // conversion instead of the deletion.
    test('trailing in unit converts inches to millimetres', () {
      expect(parseIsoExpression('76in'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('76 in'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('76IN'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('76inch'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('76 inches'), closeTo(1930.4, 1e-9));
    });

    test('trailing inch quote converts inches to millimetres', () {
      expect(parseIsoExpression('76"'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('76 "'), closeTo(1930.4, 1e-9));
      // ASCII double apostrophe — what an all-ASCII drawing export produces.
      expect(parseIsoExpression("76''"), closeTo(1930.4, 1e-9));
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

  // Imperial isometrics are a real, shipped use case (the app is on Google
  // Play worldwide, the saddle template has an inch preview and the material
  // list is dual-unit), so the parser must UNDERSTAND inches rather than throw
  // them away. The suffix declares the unit of the whole expression; the
  // returned value is always millimetres, like everywhere else in the app.
  group('parseIsoExpression — units', () {
    test('no suffix means millimetres (unchanged behaviour)', () {
      expect(parseIsoExpression('3000'), 3000);
      expect(parseIsoExpression('3000+525-80'), 3445);
    });

    test('mm suffix is a no-op, not a conversion', () {
      expect(parseIsoExpression('3000mm'), 3000);
      expect(parseIsoExpression('3000 mm'), 3000);
      expect(parseIsoExpression('3000MM'), 3000);
    });

    test('inch suffix applies to the whole expression', () {
      // 70 + 6 = 76 in -> 1930.4 mm. If the suffix only bound to the last
      // number the result would be 70 + 152.4 = 222.4 mm.
      expect(parseIsoExpression('70+6"'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('(70+6) in'), closeTo(1930.4, 1e-9));
      expect(parseIsoExpression('4*19"'), closeTo(1930.4, 1e-9));
    });

    test('mm suffix survives arithmetic', () {
      expect(parseIsoExpression('3000+525-80 mm'), 3445);
    });

    test('inch suffix keeps the sign of a negative expression', () {
      expect(parseIsoExpression('-5"'), closeTo(-127.0, 1e-9));
    });

    test('decimal inches', () {
      expect(parseIsoExpression('2.5"'), closeTo(63.5, 1e-9));
      expect(parseIsoExpression('2,5"'), closeTo(63.5, 1e-9));
    });

    test('a lone unit with no number is still an error', () {
      expect(() => parseIsoExpression('mm'), throwsFormatException);
      expect(() => parseIsoExpression('"'), throwsFormatException);
    });
  });

  // WHY this group exists: the normaliser used to rewrite '½' to the bare
  // string '0.5', so '4½' concatenated into '40.5' — a fitter typing a
  // perfectly normal 4½" got 40.5 instead of 4.5. A vulgar fraction after a
  // number is an implicit ADDITION and is now expanded as one, in brackets so
  // it cannot be broken apart by surrounding * or -.
  group('parseIsoExpression — mixed fractions', () {
    test('vulgar fraction after a whole number adds to it', () {
      expect(parseIsoExpression('4½'), 4.5);
      expect(parseIsoExpression('4¼'), 4.25);
      expect(parseIsoExpression('4¾'), 4.75);
    });

    test('multi-digit whole part is kept intact', () {
      // The old bug would have produced '10' + '(4+0.5)' here if only the
      // last digit had been captured.
      expect(parseIsoExpression('104½'), 104.5);
    });

    test('optional space between whole number and fraction', () {
      expect(parseIsoExpression('4 ½'), 4.5);
    });

    test('bare fraction with no whole part still works', () {
      expect(parseIsoExpression('½'), 0.5);
      expect(parseIsoExpression('100+½'), 100.5);
    });

    test('mixed number is bracketed, so precedence is preserved', () {
      // '4½*2' must be (4+0.5)*2 = 9, never 4+(0.5*2) = 5.
      expect(parseIsoExpression('4½*2'), 9);
      expect(parseIsoExpression('100-4½'), 95.5);
    });

    test('mixed number with inch suffix', () {
      expect(parseIsoExpression('4½"'), closeTo(114.3, 1e-9));
      expect(parseIsoExpression('4½ in'), closeTo(114.3, 1e-9));
    });

    test('ASCII mixed fraction "4 1/2" adds to the whole number', () {
      expect(parseIsoExpression('4 1/2'), 4.5);
      expect(parseIsoExpression('4 3/4"'), closeTo(120.65, 1e-9));
    });

    test('a bare n/d fraction is still rejected — it is division', () {
      // Deliberate: a standalone '3/4' is numerically identical to the
      // division '3/4', and this parser rejects division on purpose (see the
      // file header). Only the mixed form '4 1/2', which cannot be read as
      // arithmetic, is accepted. Rejecting here keeps '3000/2' an error too.
      expect(() => parseIsoExpression('3/4"'), throwsFormatException);
      expect(() => parseIsoExpression('3/4'), throwsFormatException);
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

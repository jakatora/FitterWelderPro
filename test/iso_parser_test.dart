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

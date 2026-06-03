import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/unit_parser.dart';

void main() {
  group('mm', () {
    test('plain integer string parses as millimetres', () {
      expect(UnitParser.parseToMm('1500'), 1500.0);
    });

    test('decimal millimetres preserve fraction', () {
      expect(UnitParser.parseToMm('1500.5'), 1500.5);
    });

    test('explicit mm suffix with space', () {
      expect(UnitParser.parseToMm('1500 mm'), 1500.0);
    });

    test('explicit mm suffix without space', () {
      expect(UnitParser.parseToMm('1500mm'), 1500.0);
    });
  });

  group('inches', () {
    test('inch with double-quote suffix', () {
      expect(UnitParser.parseToMm('59"'), closeTo(1498.6, 0.01));
    });

    test('inch with " in" suffix', () {
      expect(UnitParser.parseToMm('59 in'), closeTo(1498.6, 0.01));
    });

    test('inch with "in" suffix no space', () {
      expect(UnitParser.parseToMm('59in'), closeTo(1498.6, 0.01));
    });

    test('inch case-insensitive INCH', () {
      expect(UnitParser.parseToMm('59 INCH'), closeTo(1498.6, 0.01));
    });

    test('fractional inches', () {
      expect(UnitParser.parseToMm('2.5"'), closeTo(63.5, 0.001));
    });
  });

  group('feet-inch', () {
    test("4' 11\" notation", () {
      expect(UnitParser.parseToMm('4\' 11"'), closeTo(1498.6, 0.01));
    });

    test('feet and inches with space between', () {
      expect(UnitParser.parseToMm('4\' 11"'), closeTo(1498.6, 0.01));
    });

    test("just feet 5'", () {
      expect(UnitParser.parseToMm('5\''), closeTo(1524.0, 0.01));
    });
  });

  group('invalid', () {
    test('empty string returns null', () {
      expect(UnitParser.parseToMm(''), isNull);
    });

    test('abc returns null', () {
      expect(UnitParser.parseToMm('abc'), isNull);
    });

    test("double-apostrophe nonsense returns null", () {
      expect(UnitParser.parseToMm("''"), isNull);
    });
  });

  group('validate', () {
    test('valid millimetres returns null', () {
      expect(UnitParser.validate('1500'), isNull);
    });

    test('invalid input returns non-null reason', () {
      expect(UnitParser.validate('abc'), isNotNull);
    });
  });
}

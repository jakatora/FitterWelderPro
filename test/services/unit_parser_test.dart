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

    // ASME isometrics write feet and inches with a hyphen, inches often with
    // a fraction — the AI hands these over as rawDimension when it does not
    // convert them itself (golden set 08).
    test("drawing notation 4'-6\" (hyphen)", () {
      expect(UnitParser.parseToMm('4\'-6"'), closeTo(1371.6, 1e-9));
      expect(UnitParser.parseToMm('4\' - 6"'), closeTo(1371.6, 1e-9));
      expect(UnitParser.parseToMm('3\'-0"'), closeTo(914.4, 1e-9));
    });

    test("fractional inches after feet: 2'-1 1/2\" and 1'-0 3/4\"", () {
      // 2 ft 1.5 in = 25.5 in = 647.7 mm; 1 ft 0.75 in = 12.75 in = 323.85 mm
      expect(UnitParser.parseToMm('2\'-1 1/2"'), closeTo(647.7, 1e-9));
      expect(UnitParser.parseToMm('1\'-0 3/4"'), closeTo(323.85, 1e-9));
      expect(UnitParser.parseToMm('1\' 1/2"'), closeTo(317.5, 1e-9));
    });

    test('a zero denominator is not a length', () {
      expect(UnitParser.parseToMm('2\'-1 1/0"'), isNull);
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

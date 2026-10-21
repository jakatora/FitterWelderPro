import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/domain/iso_notebook/iso_length_text.dart';
import 'package:cut_list_app/services/iso_parser.dart';

void main() {
  for (final value in [
    1.25,
    1234.56789,
    1000.0,
    1e-7,
    1.23456789e-20,
    1e21,
    1.23456789e30,
    double.minPositive,
    double.maxFinite
  ]) {
    test(
        'ISO literal preserves $value without display rounding or exponent syntax',
        () {
      final text = isoLengthExpression(value);
      expect(text, isNot(contains('e')));
      expect(parseIsoExpression(text), value);
    });
  }
  test('integer formatting stays compatible and invalid lengths are refused',
      () {
    expect(isoLengthExpression(1000), '1000');
    expect(isoLengthExpression(1.25), '1.25');
    for (final value in [
      0.0,
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      expect(() => isoLengthExpression(value), throwsArgumentError);
    }
  });
}

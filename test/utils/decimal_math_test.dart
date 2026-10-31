import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/utils/decimal_math.dart';

void main() {
  test('decimal cancellation retains exact boundaries', () {
    expect(compareDecimalSum([16.8, -0.3], 16.5), 0);
    expect(compareDecimalSum([0.1, 0.2], 0.3), 0);
    expect(compareDecimalSum([16.7999999996, -0.3], 16.5), -1);
    expect(compareDecimalSum([18.5000000004], 18.5), 1);
  });
  test('uncertainty below one binary ULP is not lost in comparisons', () {
    expect(compareDecimalSum([16.5, -1e-16], 16.5), -1);
    expect(compareDecimalSum([16.5, 1e-16], 16.5), 1);
    expect(compareDecimalSum([100, 1e-16], 100), 1);
  });
  test(
      'cancellation is independent of summation order and intermediate overflow',
      () {
    expect(decimalSum([1e308, 0.1, -1e308]), 0.1);
    expect(decimalSum([-1e308, 1e308, 0.1]), 0.1);
    expect(compareDecimalSum([1e308, 1e308], 1e308), 1);
  });
  test('products keep their canonical decimal value', () {
    expect(decimalProduct(5, 0.08), 0.4);
    expect(decimalProduct(5, 0.08000000004), 0.4000000002);
    expect(decimalProduct(-0.1, 0.2), -0.02);
  });
  test('empty and signed values have consistent sums', () {
    expect(decimalSum([]), 0);
    expect(compareDecimalSum([], 0), 0);
    expect(decimalSum([-0.1, -0.2]), -0.3);
  });
  test('non-finite values cannot enter exact comparisons', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      expect(() => decimalComponents(value), throwsArgumentError);
      expect(() => compareDecimalSum([value], 0), throwsArgumentError);
    }
  });
}

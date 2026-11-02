import 'package:flutter_test/flutter_test.dart';
import 'package:cut_list_app/services/bar_nesting.dart';

void main() {
  test('joining gaps cannot leave negative cut pieces on very short stock', () {
    expect(() => splitCutLengths(845, stockLengthMm: 0.001, joinGapMm: 3), throwsStateError);
  });

  test('mistyped tiny stock is rejected before expanding millions of parts',
      () {
    expect(() => splitCutLengths(6000, stockLengthMm: 0.001), throwsStateError);
  });
  test('the split boundary retains all parts and respects joining gaps', () {
    expect(splitCutLengths(10000, stockLengthMm: 1), hasLength(10000));
    final parts = splitCutLengths(19999, stockLengthMm: 1, joinGapMm: 1);
    expect(parts, hasLength(10000));
    expect(parts.every((p) => p == 1), isTrue);
    expect(() => splitCutLengths(20000, stockLengthMm: 1, joinGapMm: 1),
        throwsStateError);
  });
  test('combined expansions reject an oversized plan rather than dropping cuts',
      () {
    expect(
        () => nestPiecesToBars(
            cuts: const [CutRequest(6000), CutRequest(6000)],
            stockLengthMm: 1,
            sawKerfMm: 0),
        throwsStateError);
    expect(
        () => nestPiecesToBars(
            cuts: const [CutRequest(500), CutRequest(500)],
            stockLengthMm: 6000,
            sawKerfMm: 1,
            pieceLimit: 1),
        throwsStateError);
  });
  test('split metadata is immutable and shared instead of quadratic copies',
      () {
    final plans = nestPiecesToBars(
        cuts: const [CutRequest(7000)], stockLengthMm: 6000, sawKerfMm: 0);
    final pieces = plans.expand((p) => p.pieces).toList();
    expect(pieces.map((p) => p.lengthMm), [6000, 1000]);
    expect(identical(pieces[0].partLengthsMm, pieces[1].partLengthsMm), isTrue);
    expect(() => pieces[0].partLengthsMm[0] = 3, throwsUnsupportedError);
  });
}

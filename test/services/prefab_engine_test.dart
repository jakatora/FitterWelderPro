import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';

void main() {
  group('DimRef.centreToCentre (default)', () {
    test('elbow <-> elbow: iso=500, leftCte=55, rightCte=55 -> 390', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToCentre,
        leftCteMm: 55,
        rightCteMm: 55,
      );
      expect(result, 390);
    });

    test('one elbow: iso=500, leftCte=55, rightCte=null -> 445', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToCentre,
        leftCteMm: 55,
        rightCteMm: null,
      );
      expect(result, 445);
    });

    test('no elbow: iso=500, leftCte=null, rightCte=null -> 500', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToCentre,
        leftCteMm: null,
        rightCteMm: null,
      );
      expect(result, 500);
    });
  });

  group('DimRef.centreToFace', () {
    test('iso=500, leftCte=55, rightCte=0 -> 445 (rightCte ignored)', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToFace,
        leftCteMm: 55,
        rightCteMm: 0,
      );
      expect(result, 445);
    });
  });

  group('DimRef.faceToFace', () {
    test('iso=500, both null -> 500 (no axial sub)', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.faceToFace,
        leftCteMm: null,
        rightCteMm: null,
      );
      expect(result, 500);
    });
  });

  group('DimRef.faceToEnd', () {
    test('iso=500, leftPhysicalLen=178 -> 322', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.faceToEnd,
        leftPhysicalLenMm: 178,
      );
      expect(result, 322);
    });
  });

  group('DimRef.centreToEnd', () {
    test('iso=500, leftCte=55 -> 445', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToEnd,
        leftCteMm: 55,
      );
      expect(result, 445);
    });

    test(
      'spec example: elbow->pipe->reducer, ISO to reducer end '
      '(leftCte=76, rightPhys=76) -> ISO-152',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 1000,
          ref: DimRef.centreToEnd,
          leftCteMm: 76,
          rightPhysicalLenMm: 76,
        );
        expect(result, 848);
      },
    );

    test(
      'direction-flipped: reducer->pipe->elbow with leftPhys + rightCte '
      'still subtracts both',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 1000,
          ref: DimRef.centreToEnd,
          leftPhysicalLenMm: 76,
          rightCteMm: 76,
        );
        expect(result, 848);
      },
    );
  });

  group('DimRef.centreToFace — spec rule (no body subtracted on face side)', () {
    test(
      'elbow->pipe->reducer, ISO to reducer FACE '
      '(leftCte=76, rightPhys=76) -> reducer length NOT subtracted',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 1000,
          ref: DimRef.centreToFace,
          leftCteMm: 76,
          rightPhysicalLenMm: 76,
        );
        // 1000 - 76 (elbow CTE) - 0 (reducer body NOT subtracted on face side)
        expect(result, 924);
      },
    );
  });

  group('DimRef.faceToEnd — symmetric in side ordering', () {
    test('iso=500, rightPhysicalLen=178 -> 322 (mirror of left case)', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.faceToEnd,
        rightPhysicalLenMm: 178,
      );
      expect(result, 322);
    });
  });

  group('mid-segment physical', () {
    test(
      'centreToCentre iso=2000, leftCte=55, rightCte=55, midPhysicalSum=267 -> 1623',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 2000,
          ref: DimRef.centreToCentre,
          leftCteMm: 55,
          rightCteMm: 55,
          midPhysicalSumMm: 267,
        );
        expect(result, 1623);
      },
    );
  });

  group('NaN propagation', () {
    test('isoValueMm=double.nan -> result isNaN', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: double.nan,
        ref: DimRef.centreToCentre,
        leftCteMm: 55,
        rightCteMm: 55,
      );
      expect(result.isNaN, isTrue);
    });

    // P0-09 regression: infinity from parseIsoExpression('1e500') used to
    // pass the isNaN gate and propagate as a poison value through every
    // downstream sum. Engine now returns NaN for any non-finite ISO.
    test('isoValueMm=infinity -> result isNaN', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: double.infinity,
        ref: DimRef.centreToCentre,
        leftCteMm: 55,
        rightCteMm: 55,
      );
      expect(result.isNaN, isTrue);
    });

    // P0-09 regression: a result <= 0 is meaningless (you cannot cut a
    // negative pipe) — engine now returns NaN so the warning chip fires
    // instead of the BOM showing a plausible-looking small number.
    test('cut <= 0 from over-subtraction -> result isNaN', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 100,
        ref: DimRef.centreToCentre,
        leftCteMm: 60,
        rightCteMm: 60,
      );
      // Legacy: 100 - 120 = -20. New behaviour: NaN.
      expect(result.isNaN, isTrue);
    });
  });

  // P0-09 regression: CTF used to subtract BOTH CTEs even though the
  // spec says only the centre side counts. The new flag pair lets the
  // engine pick the right side; callers that omit the flag fall back to
  // crediting the LARGER CTE (conservative — pipe never over-cut).
  group('DimRef.centreToFace — P0-09 fix (only centre-side CTE)', () {
    test(
      'flag-disambiguated: leftCte=55 + rightCte=55, rightIsPhysical=true '
      '-> credits leftCte only -> 445 (not 390)',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 500,
          ref: DimRef.centreToFace,
          leftCteMm: 55,
          rightCteMm: 55,
          rightIsPhysical: true,
        );
        expect(result, 445);
      },
    );

    test(
      'flag-disambiguated mirror: leftIsPhysical=true credits rightCte',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 500,
          ref: DimRef.centreToFace,
          leftCteMm: 55,
          rightCteMm: 76,
          leftIsPhysical: true,
        );
        expect(result, 500 - 76);
      },
    );

    test(
      'no flags + both CTEs equal: conservative — credits one side only, '
      'NOT both -> 445',
      () {
        final result = PrefabEngine.cutLengthMm(
          isoValueMm: 500,
          ref: DimRef.centreToFace,
          leftCteMm: 55,
          rightCteMm: 55,
        );
        expect(result, 445);
      },
    );

    test('no flags + asymmetric CTEs: credits the larger', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToFace,
        leftCteMm: 55,
        rightCteMm: 76,
      );
      expect(result, 500 - 76);
    });
  });

  group('needsDimRefPicker', () {
    test('both physical-end booleans false -> false', () {
      expect(
        PrefabEngine.needsDimRefPicker(
          leftIsPhysical: false,
          rightIsPhysical: false,
        ),
        isFalse,
      );
    });

    test('left true -> true', () {
      expect(
        PrefabEngine.needsDimRefPicker(
          leftIsPhysical: true,
          rightIsPhysical: false,
        ),
        isTrue,
      );
    });

    test('right true -> true', () {
      expect(
        PrefabEngine.needsDimRefPicker(
          leftIsPhysical: false,
          rightIsPhysical: true,
        ),
        isTrue,
      );
    });

    test('both true -> true', () {
      expect(
        PrefabEngine.needsDimRefPicker(
          leftIsPhysical: true,
          rightIsPhysical: true,
        ),
        isTrue,
      );
    });
  });
}

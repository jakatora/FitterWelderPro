import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/models/prefab/dim_ref.dart';
// The segment builder is imported for one purpose: proving that the cut it
// shows the fitter is the number this engine produced, gap included.
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/prefab_engine.dart';

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
      'spends the same two rules, one per side',
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

  // The engine's own documentation states the contribution rules PER SIDE,
  // and every DimRef spends exactly two of them — one per anchor. FTE and CTE
  // used to spend the body rule on BOTH ends (CTE both CTE rules on top of
  // that). With one axial and one bodied end the extra term was zero and the
  // bug stayed invisible; the moment both ends fell in the SAME category the
  // engine charged twice and the pipe came back short.
  group('DimRef.faceToEnd — one body per side, never both', () {
    test('two DN100 valves, 229 mm body each: subtracts 229, not 458', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.faceToEnd,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 229,
        leftIsPhysical: true,
        rightIsPhysical: true,
      );
      // Legacy: 2000 - 229 - 229 = 1542, i.e. 229 mm of pipe thrown away on
      // a dimension the fitter had read correctly.
      expect(result, 1771);
    });

    test('explicit stops: face on the left, end on the right', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        leftStop: SideStop.face,
        rightStop: SideStop.end,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 229,
      );
      expect(result, 1771);
    });

    test('explicit stops beat the guess: the SHORTER body can be the end', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.faceToEnd,
        leftStop: SideStop.end,
        rightStop: SideStop.face,
        leftPhysicalLenMm: 100,
        rightPhysicalLenMm: 300,
        leftIsPhysical: true,
        rightIsPhysical: true,
      );
      // Left to guess the engine would take the larger body (300); the caller
      // knows the dimension runs through the 100 mm one.
      expect(result, 1900);
    });

    test('mixed ends: the one bodied side is the end side', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.faceToEnd,
        leftPhysicalLenMm: 229,
        leftIsPhysical: true,
      );
      expect(result, 1771);
    });
  });

  group('DimRef.centreToEnd — one stop per side', () {
    test('two elbows, 55 mm CTE each: one centre rule, not two', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 500,
        ref: DimRef.centreToEnd,
        leftCteMm: 55,
        rightCteMm: 55,
      );
      // The far anchor is measured THROUGH to its end and an elbow has no
      // body length to give up, so only the centre side spends its CTE.
      // Legacy: 500 - 55 - 55 = 390.
      expect(result, 445);
    });

    test('two valves, 229 mm body each: 229 once, and no CTE at all', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.centreToEnd,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 229,
        leftIsPhysical: true,
        rightIsPhysical: true,
      );
      expect(result, 1771);
    });

    test('mixed ends: elbow CTE on one side, valve body on the other', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.centreToEnd,
        leftCteMm: 55,
        rightPhysicalLenMm: 229,
        rightIsPhysical: true,
      );
      expect(result, 2000 - 55 - 229);
    });

    test('explicit stops name the sides outright', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        leftStop: SideStop.centre,
        rightStop: SideStop.end,
        leftCteMm: 55,
        rightCteMm: 55,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 229,
      );
      // Left spends only its CTE and right only its body, however many
      // numbers the caller hands over: no side is ever charged twice.
      expect(result, 2000 - 55 - 229);
    });
  });

  group('symmetric refs with the same category on both ends', () {
    test('CTC spends the centre rule on each side — both CTEs', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.centreToCentre,
        leftCteMm: 76,
        rightCteMm: 76,
      );
      expect(result, 1848);
    });

    test('FTF with a valve at BOTH ends subtracts neither body', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.faceToFace,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 229,
        leftIsPhysical: true,
        rightIsPhysical: true,
      );
      expect(result, 2000);
    });
  });

  group('stop types stand on their own', () {
    test('an end stop on BOTH anchors — a shape no DimRef can name', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        leftStop: SideStop.end,
        rightStop: SideStop.end,
        leftPhysicalLenMm: 229,
        rightPhysicalLenMm: 100,
      );
      expect(result, 1671);
    });

    test('one stop given: the other comes from the ref pair', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 2000,
        ref: DimRef.centreToEnd,
        leftStop: SideStop.end,
        leftPhysicalLenMm: 229,
        // Ignored: this side stops at an end, so it spends its body length
        // and nothing else.
        leftCteMm: 999,
        rightCteMm: 55,
      );
      expect(result, 2000 - 229 - 55);
    });

    test('neither stops nor ref -> NaN, never a guessed length', () {
      final result = PrefabEngine.cutLengthMm(isoValueMm: 2000, leftCteMm: 55);
      expect(result.isNaN, isTrue);
    });
  });

  group('weld root gap', () {
    test('omitted: nothing subtracted, so existing callers keep their number',
        () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 1000,
        ref: DimRef.centreToCentre,
        leftCteMm: 76,
        rightCteMm: 76,
      );
      expect(result, 848);
    });

    test('2 mm gap on two joints takes 4 mm off', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 1000,
        ref: DimRef.centreToCentre,
        leftCteMm: 76,
        rightCteMm: 76,
        weldGapMm: 2,
        weldCount: 2,
      );
      expect(result, 844);
    });

    test('a gap with no joint to sit in changes nothing', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 1000,
        ref: DimRef.centreToCentre,
        leftCteMm: 76,
        rightCteMm: 76,
        weldGapMm: 2,
        weldCount: 0,
      );
      expect(result, 848);
    });

    test('a gap that eats the whole run -> NaN, not a negative cut', () {
      final result = PrefabEngine.cutLengthMm(
        isoValueMm: 50,
        ref: DimRef.faceToFace,
        weldGapMm: 100,
        weldCount: 1,
      );
      expect(result.isNaN, isTrue);
    });
  });

  // One run, one number from the builder and from a DimRef-style engine call.
  // The builder used to subtract `welds * gap` in a formula PrefabEngine knew
  // nothing about. NB: the `viaNotebook` calls below pass a gap; the real ISO
  // notebook has no gap setting and passes none, so with a gap above 0 the
  // notebook screen itself still shows the run `welds * gap` longer.
  group('segment builder and PrefabEngine agree on the same run', () {
    test('elbow -> open end, 2 mm gap on one joint', () {
      const isoMm = 1000.0;
      const elbowTakeoutMm = 76.2;

      final viaBuilder = builderCutMm(
        isoMm: isoMm,
        startRef: IsoRefPoint.axis,
        startOffsetMm: elbowTakeoutMm,
        endRef: IsoRefPoint.open,
        endOffsetMm: 0,
        gapMm: 2,
        welds: 1,
      );
      final viaNotebook = PrefabEngine.cutLengthMm(
        isoValueMm: isoMm,
        ref: DimRef.centreToFace,
        leftCteMm: elbowTakeoutMm,
        rightCteMm: 0,
        weldGapMm: 2,
        weldCount: 1,
      );

      expect(viaBuilder, viaNotebook);
      expect(viaBuilder, closeTo(1000 - 76.2 - 2, 1e-9));
    });

    test('valve far face -> elbow axis, 3 mm gap on two joints', () {
      const isoMm = 2000.0;

      final viaBuilder = builderCutMm(
        isoMm: isoMm,
        startRef: IsoRefPoint.faceFar,
        startOffsetMm: 229,
        endRef: IsoRefPoint.axis,
        endOffsetMm: 76.2,
        gapMm: 3,
        welds: 2,
      );
      final viaNotebook = PrefabEngine.cutLengthMm(
        isoValueMm: isoMm,
        ref: DimRef.centreToEnd,
        leftPhysicalLenMm: 229,
        rightCteMm: 76.2,
        leftIsPhysical: true,
        weldGapMm: 3,
        weldCount: 2,
      );

      expect(viaBuilder, viaNotebook);
      expect(viaBuilder, closeTo(2000 - 229 - 76.2 - 6, 1e-9));
    });

    test('a builder segment with no gap set matches the plain engine call',
        () {
      final viaBuilder = builderCutMm(
        isoMm: 3450,
        startRef: IsoRefPoint.open,
        startOffsetMm: 0,
        endRef: IsoRefPoint.open,
        endOffsetMm: 0,
        gapMm: 0,
        // open → open: nothing is welded, so no gap either (this used to pass
        // 1, the builder's old start-only count; with gap 0 it made no
        // difference to the number, but it pinned the wrong rule).
        welds: builderWeldCount(kOpenEndTag, kOpenEndTag),
      );
      final viaNotebook = PrefabEngine.cutLengthMm(
        isoValueMm: 3450,
        ref: DimRef.faceToFace,
      );
      expect(viaBuilder, viaNotebook);
      expect(viaBuilder, 3450);
    });
  });

  group('weldCountForEnds', () {
    test('one weld per anchor the pipe is welded to, none for a free end', () {
      expect(
          PrefabEngine.weldCountForEnds(
              startIsOpenEnd: true, endIsOpenEnd: true),
          0);
      expect(
          PrefabEngine.weldCountForEnds(
              startIsOpenEnd: false, endIsOpenEnd: true),
          1);
      expect(
          PrefabEngine.weldCountForEnds(
              startIsOpenEnd: true, endIsOpenEnd: false),
          1);
      expect(
          PrefabEngine.weldCountForEnds(
              startIsOpenEnd: false, endIsOpenEnd: false),
          2);
    });

    test('gap 3, elbow 152 → open end, ISO 1000: 1000 − 152 − 3 = 845', () {
      final cut = builderCutMm(
        isoMm: 1000,
        startRef: IsoRefPoint.axis,
        startOffsetMm: 152,
        endRef: IsoRefPoint.open,
        endOffsetMm: 0,
        gapMm: 3,
        welds: builderWeldCount('ELB90', kOpenEndTag),
      );
      expect(cut, 845);
    });
  });

  group('IsoRefPoint -> SideStop', () {
    test('near face and open end stop at the face', () {
      expect(stopForRefPoint(IsoRefPoint.faceNear), SideStop.face);
      expect(stopForRefPoint(IsoRefPoint.open), SideStop.face);
    });

    test('axis and centre stop on the centreline', () {
      expect(stopForRefPoint(IsoRefPoint.axis), SideStop.centre);
      expect(stopForRefPoint(IsoRefPoint.center), SideStop.centre);
    });

    test('far face runs through the body to its end', () {
      expect(stopForRefPoint(IsoRefPoint.faceFar), SideStop.end);
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

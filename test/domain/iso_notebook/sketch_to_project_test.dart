// ISO notebook sketch → CUT project.
//
// The promise under test: the CUT a project segment stores (and the CUT the
// segment builder and the gap recompute get back from that row) is exactly the
// CUT the notebook shows for the same pipe — sketchCutMm, the one formula the
// notebook screen itself calls. Checked for elbow–elbow, elbow–WN flange,
// tee and reducer runs, with a weld gap, through a real SQLite database.

import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_cut.dart';
import 'package:cut_list_app/domain/iso_notebook/sketch_to_project.dart';
import 'package:cut_list_app/models/prefab/dim_ref.dart';
import 'package:cut_list_app/models/prefab/end_connection.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/screens/segment_builder_screen.dart';
import 'package:cut_list_app/services/iso_sketch_project_writer.dart';
import 'package:cut_list_app/services/prefab_engine.dart';
import 'package:cut_list_app/services/takeout_catalog.dart';

import '../../support/test_database.dart';

// ── Minimal sketch model (what the notebook's private classes implement) ──

class Comp implements SketchComponent {
  Comp(
    this.pos,
    this.toolName, {
    this.dn,
    this.cteMm,
    this.physicalLengthMm,
    this.dnOut,
    this.endA,
    this.endB,
  });
  @override
  final Offset pos;
  @override
  final String toolName;
  @override
  final int? dn;
  @override
  final int? cteMm;
  @override
  final int? physicalLengthMm;
  @override
  final int? dnOut;
  @override
  final EndConnection? endA;
  @override
  final EndConnection? endB;
}

class Ded implements SketchDeduct {
  Ded(this.name, this.value);
  @override
  final String name;
  @override
  final String value;
}

class Dim implements SketchDimension {
  Dim(this.iso, {this.ref = DimRef.centreToCentre, this.deducts = const []});
  @override
  final String iso;
  @override
  final DimRef ref;
  @override
  final List<SketchDeduct> deducts;
  @override
  bool get isReference {
    final t = iso.trim();
    return t.startsWith('(') && t.endsWith(')');
  }
}

class Pipe implements SketchPipe {
  Pipe(this.a, this.b, [this.dimension]);
  @override
  final Offset a;
  @override
  final Offset b;
  @override
  final SketchDimension? dimension;
}

const _g = 32.0; // grid step
Offset _p(double x, double y) => Offset(x * _g, y * _g);

Comp _elbow(Offset p, {int cte = 152}) =>
    Comp(p, 'elbow90', dn: 100, cteMm: cte);

final int _teeCte = TakeoutCatalog.tee[100]!; // 105, ASME B16.9 DN100

// ── The representative route ─────────────────────────────────────────────
//
//   F0 ─p1(1000 CTC)─ E1
//                      │ p2 (2000 CTC)          kolano–kolano
//                     E2 ─p3(1500 CTC)─ T ─p6(1200 CTE, −3 uszczelka)─ WN flange
//                                       │ p4 (800 CTF)                   trójnik
//                                       R (reducer 100×80, 102)          redukcja
//                                       │ p5 (600 FTF)
//                                     free end
//
// plus an undimensioned pipe and a "(900)" reference dimension elsewhere.
// The notebook's pipe list is deliberately NOT in route order.

final _f0 = _p(0, 0);
final _e1 = _p(8, 0);
final _e2 = _p(8, 8);
final _t = _p(16, 8);
final _r = _p(16, 16);
final _free = _p(16, 24);
final _flange = _p(24, 8);

final _comps = <SketchComponent>[
  _elbow(_e1),
  _elbow(_e2),
  Comp(_t, 'tee', dn: 100), // take-out from the B16.9 table
  Comp(_r, 'reducer',
      dn: 100,
      dnOut: 80,
      physicalLengthMm: 102,
      endA: EndConnection.buttWeld,
      endB: EndConnection.buttWeld),
  Comp(_flange, 'flange',
      dn: 100,
      physicalLengthMm: 76,
      endA: EndConnection.weldNeck,
      endB: EndConnection.none),
  // Weld dots sit half a grid step away from the joints (auto-weld pass) and
  // must not change anything.
  Comp(_e1 + const Offset(-0.55 * _g, 0), 'weld'),
];

final p1 = Pipe(_f0, _e1, Dim('1000'));
final p2 = Pipe(_e1, _e2, Dim('2000'));
final p3 = Pipe(_e2, _t, Dim('1500'));
final p4 = Pipe(_t, _r, Dim('800', ref: DimRef.centreToFace));
final p5 = Pipe(_r, _free, Dim('600', ref: DimRef.faceToFace));
final p6 = Pipe(_t, _flange,
    Dim('1200', ref: DimRef.centreToEnd, deducts: [Ded('Uszczelka', '3')]));
final p7 = Pipe(_p(0, 30), _p(4, 30)); // no dimension
final p8 = Pipe(_p(0, 34), _p(4, 34), Dim('(900)')); // reference

/// Notebook order — the sketch pipe numbers R1..R8.
final _pipes = <SketchPipe>[p3, p1, p2, p5, p4, p6, p7, p8];

const _gap = 3.0;

double _nb(SketchPipe p, {double gap = _gap}) =>
    sketchCutMm(p, _comps, gapMm: gap);

/// CUT the segment builder shows when it reopens [s] ("edit").
double _builderCut(Segment s, double gap) {
  final refs = splitIsoRef(s.isoRef);
  IsoRefPoint point(String kind, double v, String code) =>
      restoredStoredAnchor(kind: kind, valueMm: v, refCode: code) ??
      IsoRefPoint.open;
  String tag(String kind) => kind == 'logical' ? kOpenEndTag : kStoredAnchorTag;
  return builderCutMm(
    isoMm: s.isoMm,
    startRef: point(s.startKind, s.startValueMm, refs.start),
    startOffsetMm: s.startKind == 'logical' ? 0 : s.startValueMm,
    endRef: point(s.endKind, s.endValueMm, refs.end),
    endOffsetMm: s.endKind == 'logical' ? 0 : s.endValueMm,
    gapMm: gap,
    welds: builderWeldCount(tag(s.startKind), tag(s.endKind)),
  );
}

void main() {
  group('sketchCutMm — the notebook formula, with the weld gap', () {
    test('kolano–kolano: 2000 − 2×152 − 2×gap', () {
      expect(_nb(p2, gap: 0), 2000 - 152 - 152);
      expect(_nb(p2), 2000 - 152 - 152 - 2 * _gap);
    });

    test('kolano–kołnierz WN, oś–koniec: − CTE − Y − 2×gap', () {
      final pipe = Pipe(_e1, _flange, Dim('2000', ref: DimRef.centreToEnd));
      final comps = [_elbow(_e1), _comps[4]];
      expect(sketchCutMm(pipe, comps, gapMm: _gap), 2000 - 152 - 76 - 6);
    });

    test('trójnik (B16.9 take-out) – kolano', () {
      expect(_nb(p3), 1500 - 152 - _teeCte - 6);
    });

    test('trójnik – redukcja, oś–czoło: the reducer body stays in the pipe',
        () {
      expect(_nb(p4), 800 - _teeCte - 6);
    });

    test('za redukcją do wolnego końca: one weld, one gap', () {
      expect(sketchWeldCount(p5, _comps, kSketchJointTolerance), 1);
      expect(_nb(p5), 600 - 3);
    });

    test('a free pipe end is not a weld; a weld dot near a joint changes '
        'nothing', () {
      expect(sketchEndIsWelded(_f0, _comps, kSketchJointTolerance), isFalse);
      expect(sketchEndIsWelded(_e1, _comps, kSketchJointTolerance), isTrue);
      expect(_nb(p1), 1000 - 152 - 3);
    });

    test('gap 0 reproduces the notebook numbers from before the gap existed',
        () {
      for (final p in [p1, p2, p3, p4, p5, p6]) {
        final b = sketchCutBreakdown(p, _comps)!;
        expect(b.gapTotalMm, 0);
        expect(
          b.cutMm,
          PrefabEngine.cutLengthMm(
                isoValueMm: b.isoMm,
                ref: b.ref,
                leftCteMm: b.axial.leftMm,
                rightCteMm: b.axial.rightMm,
                leftPhysicalLenMm:
                    b.leftPhysicalMm > 0 ? b.leftPhysicalMm : null,
                rightPhysicalLenMm:
                    b.rightPhysicalMm > 0 ? b.rightPhysicalMm : null,
                midPhysicalSumMm: b.midPhysicalMm,
                leftIsPhysical: b.leftPhysicalMm > 0,
                rightIsPhysical: b.rightPhysicalMm > 0,
              ) -
              b.manualDeductMm,
        );
      }
    });

    test('a threaded valve end is not a weld', () {
      final v = Comp(_e1, 'ballValve',
          dn: 100,
          physicalLengthMm: 229,
          endA: EndConnection.threaded,
          endB: EndConnection.threaded);
      expect(sketchEndIsWelded(_e1, [v], kSketchJointTolerance), isFalse);
    });

    test('a nonsense gap never lengthens the pipe', () {
      expect(_nb(p2, gap: -5), _nb(p2, gap: 0));
      expect(_nb(p2, gap: double.nan), _nb(p2, gap: 0));
    });
  });

  group('planProjectFromSketch', () {
    final plan = planProjectFromSketch(
        pipes: _pipes, components: _comps, gapMm: _gap);

    test('route order, sketch labels and skipped pipes', () {
      expect([for (final s in plan.segments) s.label],
          ['R2', 'R3', 'R1', 'R5', 'R4', 'R6']);
      expect([for (final s in plan.segments) s.seqNo], [1, 2, 3, 4, 5, 6]);
      expect([for (final s in plan.skipped) s.label], ['R7', 'R8']);
      expect(plan.skipped[0].reason.pl, contains('brak wymiaru'));
      expect(plan.skipped[1].reason.pl, contains('odniesienia'));
      expect(plan.gapMm, _gap);
      expect(plan.suggestedDn, 100);
      expect(plan.notes.map((n) => n.pl).join(' '),
          allOf(contains('rozgałęzienie'), contains('DN80')));
    });

    test('every planned CUT is the notebook CUT, and the row explains it', () {
      for (final s in plan.segments) {
        final pipe = _pipes[s.pipeIndex];
        expect(s.cutMm, closeTo(_nb(pipe), 1e-9), reason: s.label);
        expect(
          PrefabEngine.storedSegmentCutMm(
            isoMm: s.isoMm,
            isoRef: s.isoRef,
            startKind: s.start.kind,
            startValueMm: s.start.valueMm,
            endKind: s.end.kind,
            endValueMm: s.end.valueMm,
            gapMm: _gap,
          ),
          closeTo(_nb(pipe), 1e-9),
          reason: s.label,
        );
      }
    });

    test('ends: free end OPEN, elbows AXIS, WN flange through its hub', () {
      final byLabel = {for (final s in plan.segments) s.label: s};
      final first = byLabel['R2']!; // p1: free end → elbow
      expect(first.start.kind, 'logical');
      expect(first.start.refCode, 'OPEN');
      expect(first.end.refCode, 'AXIS');
      expect(first.end.valueMm, 152);
      expect(first.reversed, isFalse);

      final flange = byLabel['R6']!; // p6: tee → WN flange, 3 mm gasket
      expect(flange.start.refCode, 'AXIS');
      expect(flange.start.valueMm, _teeCte + 3);
      expect(flange.end.refCode, 'FACE_FAR');
      expect(flange.end.valueMm, 76);
      expect(flange.notes.single.pl, contains('ręczne 3 mm'));

      final reducer = byLabel['R5']!; // p4: tee → reducer face
      expect(reducer.end.kind, 'nonAxial');
      expect(reducer.end.refCode, 'FACE_NEAR');
      expect(reducer.end.valueMm, 0);

      expect(byLabel['R4']!.dn, 80, reason: 'past the reducer');
    });

    test('a pipe walked against its drawing direction is flipped', () {
      final plan2 = planProjectFromSketch(
        pipes: [Pipe(_e1, _f0, Dim('1000'))],
        components: [_elbow(_e1)],
        gapMm: _gap,
      );
      final s = plan2.segments.single;
      expect(s.reversed, isTrue);
      expect(s.start.kind, 'logical');
      expect(s.end.refCode, 'AXIS');
      expect(s.cutMm, 1000 - 152 - 3);
    });

    test('uncertain deducts are listed, never saved silently', () {
      final noCte = Comp(_e1, 'elbow90', dn: 100); // no CTE on the elbow
      final valveNoLength = Comp(_e1, 'gateValve', dn: 100);
      final plan2 = planProjectFromSketch(
        pipes: [
          Pipe(_f0, _e1, Dim('1000')),
          Pipe(_p(0, 40), _p(8, 40), Dim('900', deducts: [Ded('x', '5')])),
        ],
        components: [noCte],
      );
      expect(plan2.segments, isEmpty);
      expect(plan2.canCreate, isFalse);
      expect(plan2.skipped.map((s) => s.reason.pl).join(' | '),
          allOf(contains('CTE'), contains('odliczenia ręczne')));

      final plan3 = planProjectFromSketch(
        pipes: [Pipe(_f0, _e1, Dim('1000', ref: DimRef.faceToEnd))],
        components: [valveNoLength],
      );
      expect(plan3.skipped.single.reason.pl, contains('długości zabudowy'));
    });

    test('CUT ≤ 0 is skipped', () {
      final plan2 = planProjectFromSketch(
        pipes: [Pipe(_e1, _e2, Dim('300'))],
        components: [_elbow(_e1), _elbow(_e2)],
      );
      expect(plan2.skipped.single.reason.pl, contains('CUT ≤ 0'));
    });
  });

  group('szkic → projekt → baza', () {
    useTestDatabase();

    test('CUT z bazy == CUT zeszytu; builder and gap recompute agree', () async {
      final plan = planProjectFromSketch(
          pipes: _pipes, components: _comps, gapMm: _gap);
      final projectId = await createProjectFromSketch(
        plan,
        const SketchProjectSettings(
          name: '4"-CWS-1001',
          materialGroup: 'CS',
          dn: 100,
          schedule: '40',
          diameterMm: 114.3,
          wallThicknessMm: 6.02,
          stockLengthMm: 6000,
          sawKerfMm: 1,
        ),
      );

      final project = (await ProjectDao().getById(projectId))!;
      expect(project.name, '4"-CWS-1001');
      expect(project.gapMm, _gap, reason: 'the project gets the sketch gap');
      expect(project.diameterMm, 114.3);

      final rows = await SegmentDao().listForProject(projectId);
      expect(rows, hasLength(6));
      for (var i = 0; i < rows.length; i++) {
        final s = rows[i];
        final planned = plan.segments[i];
        final pipe = _pipes[planned.pipeIndex];
        final notebook = _nb(pipe);
        expect(s.seqNo, i + 1);
        expect(s.isoExpr, (pipe.dimension!).iso);
        expect(s.cutMm, closeTo(notebook, 1e-9), reason: planned.label);
        expect(_builderCut(s, project.gapMm), closeTo(notebook, 1e-9),
            reason: 'builder reopen of ${planned.label}');
      }
      // DN80 past the reducer: OD 88.9, Sch 40 wall 5.49.
      final past = rows[4];
      expect(past.diameterMm, 88.9);
      expect(past.wallThicknessMm, 5.49);
      expect(rows[0].diameterMm, 114.3);

      // Change the project's gap: the recompute must land on the notebook's
      // CUT at the new gap — same welds on both sides.
      await ProjectDao().updateSettings(projectId,
          name: project.name,
          stockLengthMm: 6000,
          sawKerfMm: 1,
          gapMm: 5);
      final after = await SegmentDao().listForProject(projectId);
      for (var i = 0; i < after.length; i++) {
        final pipe = _pipes[plan.segments[i].pipeIndex];
        expect(after[i].cutMm, closeTo(_nb(pipe, gap: 5), 1e-9),
            reason: plan.segments[i].label);
      }
    });

    test('a plan with nothing to create is refused', () async {
      final empty = planProjectFromSketch(pipes: [p7], components: _comps);
      expect(
        () => createProjectFromSketch(
          empty,
          const SketchProjectSettings(
            name: 'x',
            materialGroup: 'SS',
            dn: null,
            schedule: null,
            diameterMm: 60.3,
            wallThicknessMm: 3.91,
            stockLengthMm: 6000,
            sawKerfMm: 1,
          ),
        ),
        throwsStateError,
      );
    });
  });
}

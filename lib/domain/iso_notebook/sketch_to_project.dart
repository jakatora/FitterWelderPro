/// Turns an ISO-notebook sketch into CUT-project segments.
///
/// The fitter draws the run, types the dimensions and the notebook shows a
/// CUT for every pipe. Until now the only ways out of the notebook were a PDF
/// and the clipboard — the cut list had to be retyped segment by segment in
/// the segment builder. This layer plans the project instead: one segment per
/// dimensioned pipe, in route order, each carrying
///
///   * its ISO expression and millimetres as typed on the sketch,
///   * both ends in the `segments` vocabulary (`start_kind` / `iso_ref` /
///     `*_value_mm`) chosen so the row EXPLAINS its own cut: the segment
///     builder reopening it, and the recompute run when the project's gap
///     changes ([PrefabEngine.storedSegmentCutMm]), arrive at the same number,
///   * `cut_mm` — equal to the CUT the notebook shows for that pipe
///     ([sketchCutMm]); a pipe for which that cannot be guaranteed is NOT
///     planned but listed in [SketchProjectPlan.skipped] with the reason.
///
/// Rules (same spirit as the ISO scanner's plan):
///   1. Nothing is invented. A pipe with no dimension, a reference dimension,
///      an axial fitting without a take-out, a body without a length the
///      dimension runs through — is skipped and named, never saved silently.
///   2. The CUT is never computed a second way. [sketchCutBreakdown] is the
///      notebook's own formula; the row's columns are derived from it and the
///      result is re-checked through [PrefabEngine.anchoredCutMm].
///
/// Pure: no widgets, no database.
library;

import 'dart:ui' show Offset;

import '../../data/pipe_schedules.dart';
import '../../models/prefab/dim_ref.dart';
import '../../services/prefab_engine.dart';
import 'sketch_cut.dart';

/// A note attached to a planned segment or to the whole plan, in both UI
/// languages.
class SketchPlanNote {
  final String pl;
  final String en;
  const SketchPlanNote(this.pl, this.en);

  String text({required bool polish}) => polish ? pl : en;

  @override
  String toString() => pl;
}

/// Label of the sketch pipe number [n] (1-based, the "n." of the notebook's
/// cut list and PDF): `R3`.
String sketchPipeLabel(int n) => 'R$n';

/// One end of a planned segment, in the `segments` table's vocabulary.
class SketchSegmentEnd {
  /// `logical` (free end, nothing welded — the builder's OPEN_END), `axial`
  /// or `nonAxial`.
  final String kind;

  /// Half of `segments.iso_ref`: `OPEN`, `FACE_NEAR`, `AXIS`, `CENTER`,
  /// `FACE_FAR`.
  final String refCode;

  /// What this end takes off the dimension at [refCode] (mm).
  final double valueMm;

  const SketchSegmentEnd({
    required this.kind,
    required this.refCode,
    required this.valueMm,
  });

  bool get isOpenEnd => kind == 'logical';

  SideStop get stop => sideStopForRefCode(refCode) ?? SideStop.face;
}

/// One pipe of the sketch, ready to become a `segments` row.
class SketchSegmentPlan {
  /// 1-based position along the route — the row's `seq_no`.
  final int seqNo;

  /// The pipe's number on the sketch (1-based, the notebook cut list's "n.").
  final int sketchPipeNo;

  /// Index of the pipe in the list handed to [planProjectFromSketch].
  final int pipeIndex;

  /// The ISO expression exactly as typed on the sketch.
  final String isoExpr;
  final double isoMm;

  /// THE cut — equal to [sketchCutMm] of the pipe.
  final double cutMm;

  final SketchSegmentEnd start;
  final SketchSegmentEnd end;

  /// Nominal size read off the components on the pipe's ends, if any.
  final int? dn;

  /// Things worth telling the fitter about this segment (not blocking).
  final List<SketchPlanNote> notes;

  /// True when the route walks this pipe from its drawn end `b` to `a`.
  final bool reversed;

  const SketchSegmentPlan({
    required this.seqNo,
    required this.sketchPipeNo,
    required this.pipeIndex,
    required this.isoExpr,
    required this.isoMm,
    required this.cutMm,
    required this.start,
    required this.end,
    required this.dn,
    required this.notes,
    required this.reversed,
  });

  /// `R3`.
  String get label => sketchPipeLabel(sketchPipeNo);

  /// Value for `segments.iso_ref`.
  String get isoRef => '${start.refCode}|${end.refCode}';

  int get welds => PrefabEngine.weldCountForEnds(
        startIsOpenEnd: start.isOpenEnd,
        endIsOpenEnd: end.isOpenEnd,
      );
}

/// A pipe that did NOT make it into the plan, and why.
class SketchSkippedPipe {
  final int sketchPipeNo;
  final SketchPlanNote reason;
  const SketchSkippedPipe(this.sketchPipeNo, this.reason);

  String get label => sketchPipeLabel(sketchPipeNo);
}

/// The whole plan.
class SketchProjectPlan {
  /// Segments in route order (seq 1..N).
  final List<SketchSegmentPlan> segments;

  /// Pipes left out — the "to complete" list. Never empty silently: every
  /// pipe of the sketch is either in [segments] or here.
  final List<SketchSkippedPipe> skipped;

  /// Plan-wide notes (several diameters, a branched route…).
  final List<SketchPlanNote> notes;

  /// Gap the CUTs were computed with (mm per weld).
  final double gapMm;

  /// Most frequent nominal size read off the sketch, a proposal for the
  /// project's DN.
  final int? suggestedDn;

  const SketchProjectPlan({
    required this.segments,
    required this.skipped,
    required this.notes,
    required this.gapMm,
    required this.suggestedDn,
  });

  bool get canCreate => segments.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────

/// Plans the project for the sketch's [pipes] (the notebook's pipe lines, in
/// the notebook's own order — their 1-based index is the sketch pipe number)
/// and [components], with the sketch's root gap [gapMm].
SketchProjectPlan planProjectFromSketch({
  required List<SketchPipe> pipes,
  required List<SketchComponent> components,
  double gapMm = 0,
  double tol = kSketchJointTolerance,
}) {
  final gap = sanitizeSketchGap(gapMm);
  final route = _orderRoute(pipes, components, tol);
  final segments = <SketchSegmentPlan>[];
  final skipped = <SketchSkippedPipe>[];
  final notes = <SketchPlanNote>[];
  final dnCounts = <int, int>{};

  for (final step in route.steps) {
    final pipe = pipes[step.index];
    final no = step.index + 1;
    final result = _planOne(
      pipe,
      components,
      pipes: pipes,
      tol: tol,
      gapMm: gap,
      reversed: step.reversed,
    );
    if (result.skip != null) {
      skipped.add(SketchSkippedPipe(no, result.skip!));
      continue;
    }
    final seg = result.plan!;
    final dn = sketchInferredDn(pipe, components, tol, pipes: pipes);
    if (dn != null) dnCounts[dn] = (dnCounts[dn] ?? 0) + 1;
    segments.add(SketchSegmentPlan(
      seqNo: segments.length + 1,
      sketchPipeNo: no,
      pipeIndex: step.index,
      isoExpr: seg.isoExpr,
      isoMm: seg.isoMm,
      cutMm: seg.cutMm,
      start: seg.start,
      end: seg.end,
      dn: dn,
      notes: seg.notes,
      reversed: step.reversed,
    ));
  }
  skipped.sort((x, y) => x.sketchPipeNo.compareTo(y.sketchPipeNo));

  if (route.branched) {
    notes.add(const SketchPlanNote(
      'Trasa ma rozgałęzienie (trójnik) — segmenty idą najpierw jedną '
          'odnogą; sprawdź kolejność na rysunku.',
      'The route branches (tee) — segments follow one leg first; check the '
          'order against the drawing.',
    ));
  }
  if (route.runCount > 1) {
    notes.add(SketchPlanNote(
      'Szkic ma ${route.runCount} niepołączone ciągi rur — kolejność '
          'segmentów między nimi sprawdź na rysunku.',
      'The sketch has ${route.runCount} disconnected runs — check the order '
          'of segments between them against the drawing.',
    ));
  }
  if (dnCounts.length > 1) {
    final list = (dnCounts.keys.toList()..sort()).map((d) => 'DN$d').join(', ');
    notes.add(SketchPlanNote(
      'Na szkicu są różne średnice ($list) — segment dostaje średnicę '
          'odczytaną z kształtek na jego końcach.',
      'The sketch has several sizes ($list) — each segment gets the size '
          'read off the fittings on its ends.',
    ));
  }

  int? suggested;
  var best = 0;
  for (final e in dnCounts.entries) {
    if (e.value > best || (e.value == best && (suggested ?? 0) < e.key)) {
      best = e.value;
      suggested = e.key;
    }
  }

  return SketchProjectPlan(
    segments: segments,
    skipped: skipped,
    notes: notes,
    gapMm: gap,
    suggestedDn: suggested,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Project header and rows
// ─────────────────────────────────────────────────────────────────────────

/// What the fitter confirmed in the "create project" window.
class SketchProjectSettings {
  final String name;

  /// `SS` / `CS`.
  final String materialGroup;

  /// Project nominal size, when known.
  final int? dn;

  /// Schedule key of [kSchedules] the wall came from, when picked.
  final String? schedule;

  /// Outside diameter (mm) — `projects.diameter_mm`.
  final double diameterMm;
  final double wallThicknessMm;
  final double stockLengthMm;
  final double sawKerfMm;

  // No gap here on purpose: the project takes [SketchProjectPlan.gapMm], the
  // gap every planned CUT was computed with. A second, editable copy could
  // only make the project disagree with the sketch.

  const SketchProjectSettings({
    required this.name,
    required this.materialGroup,
    required this.dn,
    required this.schedule,
    required this.diameterMm,
    required this.wallThicknessMm,
    required this.stockLengthMm,
    required this.sawKerfMm,
  });
}

/// Outside diameter and wall of [seg]: the project's, unless the fittings on
/// the segment's ends say it is another nominal size (past a reducer) that
/// the pipe table knows — then that size's OD, with the wall of the same
/// schedule when one was picked (else the project's wall).
({double diameterMm, double wallThicknessMm}) sketchSegmentSize(
  SketchSegmentPlan seg,
  SketchProjectSettings s,
) {
  final dn = seg.dn;
  if (dn == null || dn == s.dn) {
    return (diameterMm: s.diameterMm, wallThicknessMm: s.wallThicknessMm);
  }
  for (final row in kPipeWalls) {
    if (row.dn != dn) continue;
    final wall = s.schedule == null ? null : row.walls[s.schedule];
    return (diameterMm: row.od, wallThicknessMm: wall ?? s.wallThicknessMm);
  }
  return (diameterMm: s.diameterMm, wallThicknessMm: s.wallThicknessMm);
}

/// The `segments` row for [seg] — same shape as the segment builder's and the
/// scan review's rows: no component-library record behind either end (the
/// take-off lives in `*_value_mm`, the point it was measured to in `iso_ref`),
/// which the builder restores as a stored anchor with exactly these numbers.
Map<String, Object?> sketchSegmentRow(
  SketchSegmentPlan seg, {
  required String id,
  required String projectId,
  required double diameterMm,
  required double wallThicknessMm,
  required int nowMs,
}) =>
    {
      'id': id,
      'project_id': projectId,
      'seq_no': seg.seqNo,
      'diameter_mm': diameterMm,
      'wall_thickness_mm': wallThicknessMm,
      'start_kind': seg.start.kind,
      'start_library_id': null,
      'start_value_mm': seg.start.valueMm,
      'end_kind': seg.end.kind,
      'end_library_id': null,
      'end_value_mm': seg.end.valueMm,
      'iso_ref': seg.isoRef,
      'iso_expr': seg.isoExpr,
      'iso_mm': seg.isoMm,
      'cut_mm': seg.cutMm,
      'created_at': nowMs,
      'updated_at': nowMs,
      // v22: the pipe's number on the sketch (`R3`) is its piece mark — the
      // cut list shows it next to `S01` so the piece off the saw can be found
      // on the sketch. No spool_id: the notebook only marks a split, it does
      // not number spools.
      'label': seg.label,
    };

// ─────────────────────────────────────────────────────────────────────────
// One pipe
// ─────────────────────────────────────────────────────────────────────────

class _Planned {
  final String isoExpr;
  final double isoMm;
  final double cutMm;
  final SketchSegmentEnd start;
  final SketchSegmentEnd end;
  final List<SketchPlanNote> notes;
  const _Planned(
      this.isoExpr, this.isoMm, this.cutMm, this.start, this.end, this.notes);
}

class _OneResult {
  final _Planned? plan;
  final SketchPlanNote? skip;
  const _OneResult.plan(this.plan) : skip = null;
  const _OneResult.skip(this.skip) : plan = null;
}

String _mm(double v) {
  final r = v.roundToDouble();
  return (v - r).abs() < 1e-9 ? r.toStringAsFixed(0) : v.toStringAsFixed(1);
}

_OneResult _planOne(
  SketchPipe pipe,
  List<SketchComponent> components, {
  required List<SketchPipe> pipes,
  required double tol,
  required double gapMm,
  required bool reversed,
}) {
  final dim = pipe.dimension;
  if (dim == null || dim.iso.trim().isEmpty) {
    return const _OneResult.skip(SketchPlanNote(
      'brak wymiaru — wpisz go na szkicu',
      'no dimension — enter it on the sketch',
    ));
  }
  if (dim.isReference) {
    return const _OneResult.skip(SketchPlanNote(
      'wymiar odniesienia w nawiasie — nie jest do cięcia',
      'reference dimension in brackets — not a cut',
    ));
  }
  final b = sketchCutBreakdown(pipe, components,
      tol: tol, gapMm: gapMm, pipes: pipes);
  if (b == null) {
    return _OneResult.skip(SketchPlanNote(
      'nieczytelny wymiar „${dim.iso}” — popraw go na szkicu',
      'unreadable dimension “${dim.iso}” — fix it on the sketch',
    ));
  }
  if (b.unreadableDeducts.isNotEmpty) {
    final rows = b.unreadableDeducts
        .map((d) => '${d.name.trim().isEmpty ? '?' : d.name.trim()}: '
            '${d.value.trim()}')
        .join(', ');
    return _OneResult.skip(SketchPlanNote(
      'nieczytelne odliczenie „$rows” — popraw je w oknie wymiaru',
      'unreadable deduct “$rows” — fix it in the dimension window',
    ));
  }
  if (b.refUnconfirmed) {
    return const _OneResult.skip(SketchPlanNote(
      'przy kołnierzu / zaworze nie potwierdzono, dokąd biegnie wymiar — '
          'otwórz wymiar i wybierz punkt odniesienia',
      'at the flange / valve it is not confirmed where the dimension runs '
          'to — open the dimension and pick the reference point',
    ));
  }
  if (b.axial.oletHeaderEnds.isNotEmpty) {
    return const _OneResult.skip(SketchPlanNote(
      'rura główna przy olecie narysowana dwiema liniami — to jedna rura, '
          'narysuj przelot jedną linią',
      'the header at an olet is drawn as two lines — it is one pipe, draw '
          'the run as one line',
    ));
  }
  if (b.axial.teeRoleUnknown.isNotEmpty) {
    return const _OneResult.skip(SketchPlanNote(
      'trójnik redukcyjny: ze szkicu nie wynika, czy ta rura to przelot czy '
          'odgałęzienie (C czy M) — dorysuj przelot jako linię prostą',
      'reducing tee: the sketch does not show whether this pipe is the run '
          'or the branch (C or M) — draw the run as a straight line',
    ));
  }
  if (b.axial.missing.isNotEmpty) {
    return const _OneResult.skip(SketchPlanNote(
      'kształtka na końcu bez wymiaru oś–czoło (CTE) — na szkicu NIE '
          'odjęta; uzupełnij jej specyfikację',
      'a fitting on an end has no centre-to-end (CTE) — NOT deducted on the '
          'sketch; complete its spec',
    ));
  }
  if (sketchMidPhysicalsWithoutLength(pipe, components, tol).isNotEmpty) {
    return const _OneResult.skip(SketchPlanNote(
      'element w środku rury bez długości zabudowy — uzupełnij ją na szkicu',
      'a component inside the run has no length — complete it on the sketch',
    ));
  }
  final throughEnds = b.explicitStops
      ? [
          if (b.stopA == SideStop.end) pipe.a,
          if (b.stopB == SideStop.end) pipe.b,
        ]
      : (dim.ref == DimRef.faceToEnd || dim.ref == DimRef.centreToEnd)
          ? [pipe.a, pipe.b]
          : const <Offset>[];
  if (throughEnds.isNotEmpty) {
    // The dimension runs THROUGH a body — a body whose length is unknown
    // contributes 0 on the sketch, which is a gap, not a number.
    for (final endpoint in throughEnds) {
      for (final c in components) {
        if ((c.pos - endpoint).distance >= tol) continue;
        if (!sketchIsPhysicalTool(c.toolName)) continue;
        final len = c.physicalLengthMm;
        if (len == null || len <= 0) {
          return const _OneResult.skip(SketchPlanNote(
            'wymiar biegnie przez element bez długości zabudowy — uzupełnij ją',
            'the dimension runs through a component with no length — '
                'complete it',
          ));
        }
      }
    }
  }
  final cut = b.cutMm;
  if (!cut.isFinite || cut <= 0) {
    return const _OneResult.skip(SketchPlanNote(
      'CUT ≤ 0 — sprawdź wymiar i odliczenia',
      'CUT ≤ 0 — check the dimension and the deducts',
    ));
  }
  if (b.manualDeductMm < 0) {
    return const _OneResult.skip(SketchPlanNote(
      'ujemne odliczenie ręczne — sprawdź wiersze kalkulatora',
      'negative manual deduct — check the calculator rows',
    ));
  }

  // Which stop each side takes — exactly as the engine resolved it for the
  // sketch's CUT.
  final lc = b.axial.leftMm.toDouble();
  final rc = b.axial.rightMm.toDouble();
  final lp = b.leftPhysicalMm.toDouble();
  final rp = b.rightPhysicalMm.toDouble();
  // The stops the sketch's own CUT used (explicit, or resolved from ref).
  final stopA = b.stopA;
  final stopB = b.stopB;
  final stops =
      (stopA == null || stopB == null) ? null : (left: stopA, right: stopB);
  if (stops == null) {
    return const _OneResult.skip(SketchPlanNote(
      'nie da się ustalić punktu odniesienia wymiaru',
      'the dimension reference cannot be resolved',
    ));
  }

  double deduction(SideStop s, double cte, double phys) => switch (s) {
        SideStop.centre => cte,
        SideStop.end => phys,
        SideStop.face => 0,
      };

  _End side(Offset p, SideStop stop, double cte, double phys) {
    final welded =
        sketchEndIsWelded(p, components, tol, pipe: pipe, pipes: pipes);
    var axial = false;
    for (final c in components) {
      if ((c.pos - p).distance < tol && sketchIsAxialTool(c.toolName)) {
        axial = true;
      }
    }
    return _End(
      welded: welded,
      axial: axial,
      stop: stop,
      valueMm: deduction(stop, cte, phys),
    );
  }

  var left = side(pipe.a, stops.left, lc, lp);
  var right = side(pipe.b, stops.right, rc, rp);

  // Hand-typed rows and bodies planted inside the run have no side of their
  // own. The row can only express take-offs per end, so they are booked on a
  // WELDED end (an open end restores as OPEN_END with nothing to take off):
  // the one whose stop already takes something, else a face end turned into
  // "through the body" with exactly that length.
  final notes = <SketchPlanNote>[];
  final extras = b.manualDeductMm + b.midPhysicalMm;
  if (extras > 0) {
    _End? target;
    var onLeft = true;
    for (final (e, isLeft) in [(left, true), (right, false)]) {
      if (e.welded && e.stop != SideStop.face) {
        target = e;
        onLeft = isLeft;
        break;
      }
    }
    if (target == null) {
      for (final (e, isLeft) in [(left, true), (right, false)]) {
        if (e.welded) {
          target = e;
          onLeft = isLeft;
          break;
        }
      }
    }
    if (target == null) {
      return const _OneResult.skip(SketchPlanNote(
        'odliczenia ręczne / elementy w środku rury, a na końcach nie ma '
            'kształtki, do której można je przypisać — dodaj segment ręcznie',
        'manual deducts / components inside the run, but no fitting on '
            'either end to book them on — add the segment by hand',
      ));
    }
    final moved = target.withExtra(extras);
    if (onLeft) {
      left = moved;
    } else {
      right = moved;
    }
    // Which end is START depends on the route direction.
    final isStart = onLeft != reversed;
    final what = <String>[
      if (b.manualDeductMm > 0) 'ręczne ${_mm(b.manualDeductMm)} mm',
      if (b.midPhysicalMm > 0) 'w środku rury ${b.midPhysicalMm} mm',
    ].join(' + ');
    final whatEn = <String>[
      if (b.manualDeductMm > 0) 'manual ${_mm(b.manualDeductMm)} mm',
      if (b.midPhysicalMm > 0) 'inside the run ${b.midPhysicalMm} mm',
    ].join(' + ');
    notes.add(SketchPlanNote(
      'odliczenia ($what) zapisane na końcu ${isStart ? 'START' : 'END'}',
      'deducts ($whatEn) booked on the ${isStart ? 'START' : 'END'} end',
    ));
  }

  final start = (reversed ? right : left).toEnd();
  final end = (reversed ? left : right).toEnd();

  // Re-check: the row's own columns, through the rule the builder and the
  // gap recompute use, must give the sketch's number.
  final welds = PrefabEngine.weldCountForEnds(
    startIsOpenEnd: start.isOpenEnd,
    endIsOpenEnd: end.isOpenEnd,
  );
  if (welds != b.welds) {
    return const _OneResult.skip(SketchPlanNote(
      'niezgodna liczba spoin — dodaj segment ręcznie',
      'weld count mismatch — add the segment by hand',
    ));
  }
  final check = PrefabEngine.anchoredCutMm(
    isoMm: b.isoMm,
    startStop: start.stop,
    startOffsetMm: start.valueMm,
    endStop: end.stop,
    endOffsetMm: end.valueMm,
    gapMm: gapMm,
    welds: welds,
  );
  if (!check.isFinite || (check - cut).abs() > 1e-6) {
    return const _OneResult.skip(SketchPlanNote(
      'CUT segmentu nie zgadza się z CUT szkicu — dodaj segment ręcznie',
      'the segment CUT does not match the sketch CUT — add it by hand',
    ));
  }

  if (gapMm > 0 && welds < 2) {
    notes.add(SketchPlanNote(
      welds == 0
          ? 'oba końce bez kształtki — szczelina nie odjęta'
          : 'jeden koniec bez kształtki — szczelina odjęta raz',
      welds == 0
          ? 'no fitting on either end — no gap deducted'
          : 'one end without a fitting — gap deducted once',
    ));
  }

  return _OneResult.plan(_Planned(
    dim.iso.trim(),
    b.isoMm,
    check,
    start,
    end,
    notes,
  ));
}

class _End {
  final bool welded;
  final bool axial;
  final SideStop stop;
  final double valueMm;
  const _End({
    required this.welded,
    required this.axial,
    required this.stop,
    required this.valueMm,
  });

  /// [extra] more millimetres off this end. A face stop takes nothing, so it
  /// becomes a stop through the body taking exactly [extra].
  _End withExtra(double extra) => _End(
        welded: welded,
        axial: axial,
        stop: stop == SideStop.face ? SideStop.end : stop,
        valueMm: valueMm + extra,
      );

  SketchSegmentEnd toEnd() {
    if (!welded) {
      // Nothing welded here — the builder's OPEN_END. A free end never takes
      // anything off (no fitting on it), so its value is 0 whatever the stop.
      return const SketchSegmentEnd(
          kind: 'logical', refCode: 'OPEN', valueMm: 0);
    }
    final String code;
    switch (stop) {
      case SideStop.face:
        code = 'FACE_NEAR';
      case SideStop.centre:
        code = axial ? 'AXIS' : 'CENTER';
      case SideStop.end:
        code = 'FACE_FAR';
    }
    return SketchSegmentEnd(
      kind: axial ? 'axial' : 'nonAxial',
      refCode: code,
      valueMm: stop == SideStop.face ? 0 : valueMm,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Route order
// ─────────────────────────────────────────────────────────────────────────

class _Step {
  final int index;
  final bool reversed;
  const _Step(this.index, this.reversed);
}

class _Route {
  final List<_Step> steps;
  final int runCount;
  final bool branched;
  const _Route(this.steps, this.runCount, this.branched);
}

/// Walks the pipes as a graph (pipes = edges, shared end points = nodes):
/// from a free end first, depth first, so a plain run comes out in drawing
/// order along the route and every pipe is oriented in the walking direction.
/// Loops and orphans are picked up in a second pass.
_Route _orderRoute(
  List<SketchPipe> pipes,
  List<SketchComponent> components,
  double tol,
) {
  bool same(Offset p, Offset q) => (p - q).distance < tol;

  int touching(Offset p) {
    var n = 0;
    for (final q in pipes) {
      if (same(q.a, p)) n++;
      if (same(q.b, p)) n++;
    }
    return n;
  }

  final visited = List<bool>.filled(pipes.length, false);
  final steps = <_Step>[];
  var runs = 0;
  var branched = false;

  void visit(int index, Offset entry) {
    if (visited[index]) return;
    visited[index] = true;
    final p = pipes[index];
    final reversed = !same(p.a, entry) && same(p.b, entry);
    steps.add(_Step(index, reversed));
    final exit = reversed ? p.a : p.b;
    final next = <int>[];
    for (var j = 0; j < pipes.length; j++) {
      if (visited[j]) continue;
      if (same(pipes[j].a, exit) || same(pipes[j].b, exit)) next.add(j);
    }
    if (next.length > 1) branched = true;
    for (final j in next) {
      visit(j, exit);
    }
  }

  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < pipes.length; i++) {
      if (visited[i]) continue;
      final p = pipes[i];
      final aFree = touching(p.a) <= 1;
      final bFree = touching(p.b) <= 1;
      if (pass == 0 && !aFree && !bFree) continue;
      runs++;
      // Enter from the free end. When both are free (a lone pipe), from the
      // one with nothing welded on it — a route starts at an open end — and
      // otherwise in drawing direction.
      final Offset entry;
      if (aFree && bFree) {
        final aWelded = sketchEndIsWelded(p.a, components, tol);
        final bWelded = sketchEndIsWelded(p.b, components, tol);
        entry = (aWelded && !bWelded) ? p.b : p.a;
      } else {
        entry = aFree ? p.a : p.b;
      }
      visit(i, entry);
    }
  }
  return _Route(steps, runs, branched);
}

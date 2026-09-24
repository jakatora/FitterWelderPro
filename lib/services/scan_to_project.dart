/// Turns an AI isometric scan into a project plan the app can save.
///
/// This is the missing link of the ISO-scanner module. Until now a fitter
/// photographed a drawing, got the dimensions read back on screen — and then
/// had to retype every one of them into the segment builder by hand. This
/// layer converts an [AiScanResult] into:
///
///   * a [ScanProjectDraft] — the project header (diameter, wall thickness,
///     material group) as far as it can be derived from the title block and
///     the bill of materials,
///   * a list of [PlannedSegment] in route order, each carrying its ISO
///     dimension and its two end components,
///   * [ScanPlan.gaps] — what still has to be asked of the user before the
///     plan can be written to the database,
///   * [ScanPlan.warnings] — what the screen should flag but which does not
///     block a save.
///
/// The layer is deliberately pure: no database, no network, no BuildContext.
/// Bilingual text is carried as two plain strings on [ScanIssue] so a screen
/// can pick a language without this file importing the UI.
///
/// Two rules drive every decision here:
///
///   1. Nothing is invented. A number that could not be read off the drawing
///      or looked up in a dimensional standard stays `null` and becomes a
///      gap. A plausible-looking wrong length is worse than a blank field —
///      it gets cut.
///   2. CUT length is never computed locally. [PrefabEngine] is the single
///      source of truth and is called only when every input it needs is
///      actually known.
library;

import '../data/pipe_schedules.dart';
import '../models/prefab/component_behaviour.dart';
import '../models/prefab/dim_ref.dart';
import 'component_classification.dart';
import 'iso_parser.dart';
import 'iso_scanner_ai.dart';
import 'prefab_engine.dart';
import 'takeout_catalog.dart';
import 'unit_parser.dart';

// ─────────────────────────────────────────────────────────────────────────
// Vocabulary
// ─────────────────────────────────────────────────────────────────────────

/// What a planned value was derived from. Lets a screen label a prefilled
/// field ("from the drawing") and lets a test assert that a number was not
/// conjured out of nothing.
enum ScanValueSource {
  /// Not known — the field is blank and waiting for the user.
  none,

  /// Supplied by the caller (the fitter already set up the project).
  caller,

  /// Derived from the scan: title block, bill of materials or line number,
  /// possibly via a dimensional standard table.
  scan,
}

/// How a segment end behaves, in the vocabulary the segments table already
/// uses for `start_kind` / `end_kind`.
enum ScanEndKind { logical, axial, nonAxial }

extension ScanEndKindX on ScanEndKind {
  /// Value written to `segments.start_kind` / `segments.end_kind`.
  String get code {
    switch (this) {
      case ScanEndKind.logical:
        return 'logical';
      case ScanEndKind.axial:
        return 'axial';
      case ScanEndKind.nonAxial:
        return 'nonAxial';
    }
  }
}

/// Every distinct thing this planner can complain about.
///
/// Codes exist so the screen can react structurally (highlight a dimension,
/// open the take-out picker) instead of matching on message text.
enum ScanIssueCode {
  /// The backend returned an error / "not an isometric".
  scanFailed,

  /// Nothing left to plan after auxiliary lines were dropped.
  noUsableSegments,

  /// Drawing helper lines were skipped; informational only.
  auxiliarySegmentsSkipped,

  /// Project diameter could not be derived.
  missingDiameter,

  /// Project wall thickness could not be derived.
  missingWallThickness,

  /// SS / CS could not be told apart from the title block.
  missingMaterialGroup,

  /// A segment carries no readable dimension.
  missingDimension,

  /// The model was unsure about a dimension. Blocking while the number was
  /// read (the fitter confirms it), a warning when it was not read at all.
  lowConfidence,

  /// A component type the app does not know.
  unknownComponentType,

  /// `fromId` / `toId` points at a component that is not in the scan.
  unresolvedComponentRef,

  /// An end component needs a take-out we cannot look up yet.
  missingTakeout,

  /// The drawing could have been dimensioned to a face or to an end and
  /// there is no way to tell from a photo — the user has to say which.
  dimensionReferenceUnknown,

  /// Inputs were complete but the resulting cut is not a positive length.
  cutImpossible,

  /// A component is touched by more than two pipe segments (a tee header).
  branchInRoute,

  /// The scan produced more than one disconnected run.
  routeNotContinuous,

  /// A 90° elbow take-out defaulted to long radius.
  takeoutAssumedLongRadius,

  /// A valve was found but its type (gate / ball / check…) is unknown.
  valveTypeUnknown,

  /// A reducer sits in the route, so the diameter changes downstream.
  reducerChangesDiameter,
}

/// One gap or warning, with both UI languages baked in.
class ScanIssue {
  final ScanIssueCode code;

  /// True when the plan must not be saved until this is resolved.
  final bool blocking;

  final String pl;
  final String en;

  /// [AiSegment.id] this issue belongs to, when it is segment-scoped.
  final String? segmentId;

  /// [AiComponent.id] this issue belongs to, when it is component-scoped.
  final String? componentId;

  /// The dimension as printed on the drawing, so the screen can highlight
  /// exactly the number the fitter should re-check.
  final String? dimensionLabel;

  const ScanIssue({
    required this.code,
    required this.blocking,
    required this.pl,
    required this.en,
    this.segmentId,
    this.componentId,
    this.dimensionLabel,
  });

  /// Message in the requested language.
  String text({required bool polish}) => polish ? pl : en;

  @override
  String toString() => 'ScanIssue(${code.name}, '
      'blocking: $blocking, segment: $segmentId, component: $componentId)';
}

// ─────────────────────────────────────────────────────────────────────────
// Plan model
// ─────────────────────────────────────────────────────────────────────────

/// Project header proposal. Every field is nullable: an unreadable title
/// block leaves the form blank rather than filling it with a guess.
class ScanProjectDraft {
  /// Suggested project name — the line number, else the drawing number.
  final String? name;

  /// Nominal diameter, when it could be resolved against the pipe table.
  final int? dn;

  /// Outside diameter in mm — what `projects.diameter_mm` stores.
  final double? diameterMm;

  final double? wallThicknessMm;

  /// Schedule normalised to a key of [kSchedules], e.g. `40`, `STD`, `10S`.
  final String? schedule;

  /// `SS` or `CS`, the two groups the component library is filtered by.
  final String? materialGroup;

  /// Raw material text as printed, kept for display even when it could not
  /// be classified.
  final String? materialText;

  final ScanValueSource diameterSource;
  final ScanValueSource wallThicknessSource;
  final ScanValueSource materialGroupSource;

  const ScanProjectDraft({
    this.name,
    this.dn,
    this.diameterMm,
    this.wallThicknessMm,
    this.schedule,
    this.materialGroup,
    this.materialText,
    this.diameterSource = ScanValueSource.none,
    this.wallThicknessSource = ScanValueSource.none,
    this.materialGroupSource = ScanValueSource.none,
  });

  /// Whether every column `projects` requires is filled in.
  bool get isComplete =>
      diameterMm != null && wallThicknessMm != null && materialGroup != null;
}

/// One end of a planned pipe segment.
class ScanEndpoint {
  /// [AiComponent.id], or null for an open end.
  final String? componentId;

  /// The type string exactly as the model returned it, for display.
  final String? rawType;

  /// The component label from the drawing, when there was one.
  final String? label;

  final ScanEndKind kind;

  /// Geometric behaviour per [ComponentClassification]; null when the type
  /// was not recognised.
  final ComponentBehaviour? behaviour;

  /// Tool name the type resolved to (`elbow90`, `flange`, `gateValve`…) — the
  /// vocabulary of [ComponentClassification]. Null for an open end or an
  /// unrecognised type.
  final String? tool;

  /// Centre-to-end (take-out) in mm for an axial fitting; `0` for an end the
  /// dimension stops at (a face, an open end, a weld). Null means "not known
  /// yet" and blocks the cut.
  final double? takeoutMm;

  /// Body length in mm along the run, when a dimensional standard gives one
  /// unambiguously: a weld-neck flange's Y, a valve's face-to-face, a
  /// reducer's H. Taken off only at an [SideStop.end] stop.
  final double? bodyLengthMm;

  /// Where [takeoutMm] came from, e.g. `ASME B16.9 · 90° LR · DN100`.
  final String? takeoutNote;

  /// Where [bodyLengthMm] came from, e.g. `ASME B16.5 Cl.150 · WN Y · DN100`.
  final String? bodyNote;

  /// Where an isometric dimension normally stops on this end — the stop the
  /// plan PROPOSES for this side (it never cuts on a proposal alone):
  ///   * axial fittings (elbow, tee): their centreline — [SideStop.centre];
  ///   * a weld-neck flange: its sealing face, i.e. through the whole hub —
  ///     [SideStop.end], so its Y comes off the pipe;
  ///   * a valve and other bodies (reducer, cap, blind, slip-on flange): the
  ///     face the pipe meets — [SideStop.face], nothing comes off;
  ///   * an open end, a weld, a support: [SideStop.face] (nothing fitted).
  final SideStop proposedStop;

  /// False when the scan named something the app cannot identify (unknown
  /// type, or an id that is not in the components list). An unresolved end
  /// never contributes a silent zero to a cut.
  final bool isResolved;

  const ScanEndpoint({
    this.componentId,
    this.rawType,
    this.label,
    required this.kind,
    this.behaviour,
    this.tool,
    this.takeoutMm,
    this.bodyLengthMm,
    this.takeoutNote,
    this.bodyNote,
    this.proposedStop = SideStop.face,
    this.isResolved = true,
  });

  /// An open end of the spool — nothing is fitted here.
  static const ScanEndpoint openEnd = ScanEndpoint(
    kind: ScanEndKind.logical,
    takeoutMm: 0,
    bodyLengthMm: 0,
  );

  bool get isAxial => kind == ScanEndKind.axial;

  /// Whether the component occupies real space along the run. This is what
  /// forces the dimension-reference question — see
  /// [PrefabEngine.needsDimRefPicker].
  bool get isPhysical => behaviour?.hasPhysicalBody ?? false;

  /// A flange whose body is its weld-neck hub (not a slip-on / socket / lap /
  /// threaded one): its sealing face is where the drawing dimensions it.
  bool get isWeldNeckFlange =>
      tool == 'flange' && proposedStop == SideStop.end;

  /// What this end takes off at [stop], or null when that length is not
  /// known (an unresolved end, an axial fitting without a take-out, a body
  /// without a catalogue length).
  double? deductionAt(SideStop stop) {
    if (!isResolved) return null;
    switch (stop) {
      case SideStop.face:
        return 0;
      case SideStop.centre:
        return isAxial ? takeoutMm : 0;
      case SideStop.end:
        return isPhysical ? bodyLengthMm : 0;
    }
  }

  /// Value for `segments.start_value_mm` / `segments.end_value_mm` at the
  /// PROPOSED stop, matching [isoRefCode]. Null when the end is unresolved
  /// or the length for that stop is not known.
  double? get offsetMm => deductionAt(proposedStop);

  /// Reference point code the segment builder writes into `segments.iso_ref`,
  /// as proposed before the fitter confirmed how the dimension was measured:
  /// axial fittings to their axis, an end with nothing fitted (open end,
  /// weld, support) as `OPEN` — the code the builder gives its own open end —
  /// a weld-neck flange through its body (`FACE_FAR`, the builder's default
  /// for a flange) and everything else to the near face. Once the reference
  /// is known the stored code comes from [PlannedSegment.anchorColumns].
  String get isoRefCode => _storedRefCode(this, proposedStop);

  /// Whether nothing is welded here, so no root gap is taken off: the same
  /// end the segment builder calls OPEN_END and stores as kind `logical`.
  bool get isOpenEnd => kind == ScanEndKind.logical;
}

/// How the drawing's dimension meets each end of one scanned run — the stop
/// on the START side and the stop on the END side.
///
/// A [DimRef] names a pair of stops but not which side each belongs to, and
/// has no code at all for "through the body at both ends" (a spool between
/// two weld-neck flanges). The scan plan therefore carries the stops per
/// side and hands them to [PrefabEngine] as `leftStop` / `rightStop`; the
/// DimRef is only a label for the pairs it can name.
class ScanStops {
  final SideStop start;
  final SideStop end;

  const ScanStops(this.start, this.end);

  /// The DimRef naming this pair, or null when none does (end–end).
  DimRef? get dimRef {
    for (final ref in DimRef.values) {
      final (a, b) = _stopPairFor(ref);
      if ((a == start && b == end) || (a == end && b == start)) return ref;
    }
    return null;
  }

  /// Label in the picker's vocabulary (`oś-koniec`, `czoło-czoło`…).
  String label({required bool polish}) {
    final ref = dimRef;
    if (ref != null) return polish ? ref.labelPl : ref.labelEn;
    return polish ? 'koniec-koniec' : 'end-end';
  }

  @override
  bool operator ==(Object other) =>
      other is ScanStops && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ScanStops(${start.name}, ${end.name})';
}

/// The pair of stops a [DimRef] describes, in no side order — the same table
/// as PrefabEngine's own.
(SideStop, SideStop) _stopPairFor(DimRef ref) {
  switch (ref) {
    case DimRef.centreToCentre:
      return (SideStop.centre, SideStop.centre);
    case DimRef.centreToFace:
      return (SideStop.centre, SideStop.face);
    case DimRef.faceToFace:
      return (SideStop.face, SideStop.face);
    case DimRef.faceToEnd:
      return (SideStop.face, SideStop.end);
    case DimRef.centreToEnd:
      return (SideStop.centre, SideStop.end);
  }
}

/// One length of pipe between two ends, in route order.
class PlannedSegment {
  /// [AiSegment.id] this came from.
  final String sourceId;

  /// 1-based position along the route.
  final int seqNo;

  final ScanEndpoint start;
  final ScanEndpoint end;

  /// The dimension as printed on the drawing, e.g. `1500` or `4'-6"`.
  final String? isoExpr;

  /// [isoExpr] converted to millimetres. Null when it could not be read.
  final double? isoMm;

  /// Where the dimension stops on each side, when it follows from the two
  /// ends alone or the fitter confirmed it. Null means the user has to
  /// confirm it — see [ScanIssueCode.dimensionReferenceUnknown].
  final ScanStops? stops;

  /// Best guess to preselect in the picker, always set: each end's
  /// [ScanEndpoint.proposedStop] (centre–centre when neither end has a body).
  final ScanStops proposedStops;

  /// Cut length in mm from [PrefabEngine]. Null whenever any input was
  /// missing — never a filler number.
  final double? cutMm;

  final AiConfidence confidence;

  /// True when this segment opens a run that is not connected to the
  /// previous one (the drawing had a break, or the scan lost a link).
  final bool startsNewRun;

  /// True when one of this segment's ends is shared with more than one
  /// other segment — a branch, typically a tee header.
  final bool isBranch;

  /// Root gap per weld (mm) of the project this segment will be saved into —
  /// the same `projects.gap_mm` the segment builder subtracts. 0 = none.
  final double gapMm;

  const PlannedSegment({
    required this.sourceId,
    required this.seqNo,
    required this.start,
    required this.end,
    required this.proposedStops,
    this.isoExpr,
    this.isoMm,
    this.stops,
    this.cutMm,
    this.confidence = AiConfidence.unknown,
    this.startsNewRun = false,
    this.isBranch = false,
    this.gapMm = 0,
  });

  /// Welds on this run — one per end something is welded to, none for an
  /// open end ([PrefabEngine.weldCountForEnds], the builder's rule).
  int get weldCount => PrefabEngine.weldCountForEnds(
        startIsOpenEnd: start.isOpenEnd,
        endIsOpenEnd: end.isOpenEnd,
      );

  /// The confirmed (or derived) reference as a [DimRef], when one names it.
  /// Null both while unconfirmed and for an end–end run — use
  /// [needsDimRefConfirmation] to tell those apart.
  DimRef? get dimRef => stops?.dimRef;

  /// The proposal as a [DimRef], or null when no DimRef names it (end–end).
  DimRef? get proposedDimRef => proposedStops.dimRef;

  /// Copy with the stops the fitter confirmed and the cut that follows from
  /// them. Used by the screen once he answers a
  /// [ScanIssueCode.dimensionReferenceUnknown] gap.
  PlannedSegment withStops(ScanStops confirmed) {
    return PlannedSegment(
      sourceId: sourceId,
      seqNo: seqNo,
      start: start,
      end: end,
      isoExpr: isoExpr,
      isoMm: isoMm,
      stops: confirmed,
      proposedStops: proposedStops,
      cutMm: cutMmForStops(this, confirmed),
      confidence: confidence,
      startsNewRun: startsNewRun,
      isBranch: isBranch,
      gapMm: gapMm,
    );
  }

  /// Copy with a reference given as a [DimRef]; which side gets which stop
  /// follows [stopsForDimRef].
  PlannedSegment withDimRef(DimRef ref) => withStops(stopsForDimRef(this, ref));

  /// Whether the user still has to say how the dimension was measured.
  bool get needsDimRefConfirmation => stops == null;

  /// Whether every column `segments` needs is known.
  bool get isComplete =>
      isoMm != null &&
      cutMm != null &&
      start.isResolved &&
      end.isResolved &&
      anchorColumns != null;

  /// Value for `segments.iso_ref`, in the `START|END` encoding the segment
  /// builder writes: the stops actually used once the reference is known,
  /// the proposal before that.
  String get isoRefCode {
    final cols = anchorColumns;
    if (cols != null) return '${cols.startRef}|${cols.endRef}';
    return '${start.isoRefCode}|${end.isoRefCode}';
  }

  /// What `segments.start_value_mm` / `end_value_mm` / `iso_ref` must hold for
  /// this run, or null while the cut is not known.
  ///
  /// Each side stores the stop [PrefabEngine] actually used for it and the
  /// length that stop took off — the take-out on a centre stop, the body on
  /// an end stop, nothing on a face stop. Written that way the row explains
  /// its own `cut_mm`: the segment builder reopens it with the same stops and
  /// the same numbers and arrives at the same cut. Before this the row always
  /// said `AXIS` / `FACE_NEAR` with the take-out (or 0), so a run measured
  /// through a valve body (face-to-end) was stored as if it stopped at the
  /// valve face, and an untouched "Save changes" gave the body back to the
  /// pipe.
  ({String startRef, double startValueMm, String endRef, double endValueMm})?
      get anchorColumns {
    final confirmed = stops;
    if (confirmed == null || cutMm == null) return null;
    final a = _resolvedAnchors(this, confirmed);
    if (a == null) return null;
    return (
      startRef: _storedRefCode(start, a.startStop),
      startValueMm: a.startMm,
      endRef: _storedRefCode(end, a.endStop),
      endValueMm: a.endMm,
    );
  }
}

/// Code for `segments.iso_ref` of one side of a scanned run.
String _storedRefCode(ScanEndpoint e, SideStop stop) {
  // Nothing fitted: whatever the stop, nothing is taken off, and `OPEN` is
  // what the builder calls — and restores as — an end like that.
  if (e.isOpenEnd) return 'OPEN';
  switch (stop) {
    case SideStop.face:
      return 'FACE_NEAR';
    case SideStop.centre:
      return e.isAxial ? 'AXIS' : 'CENTER';
    case SideStop.end:
      return 'FACE_FAR';
  }
}

/// The `segments` row the scan review writes for [seg], or null while [seg]
/// is not complete.
///
/// Pure, so the round trip "scan → saved row → segment builder" can be tested
/// without a screen: the anchors go in as [PlannedSegment.anchorColumns]
/// describe them and the ISO text is one the builder's parser reads back to
/// the same millimetres.
Map<String, Object?>? segmentRowFor(
  PlannedSegment seg, {
  required String id,
  required String projectId,
  required double diameterMm,
  required double wallThicknessMm,
  required int nowMs,
}) {
  final isoMm = seg.isoMm;
  final cutMm = seg.cutMm;
  final cols = seg.anchorColumns;
  if (isoMm == null || cutMm == null || cols == null || !seg.isComplete) {
    return null;
  }
  return {
    'id': id,
    'project_id': projectId,
    'seq_no': seg.seqNo,
    'diameter_mm': diameterMm,
    'wall_thickness_mm': wallThicknessMm,
    'start_kind': seg.start.kind.code,
    // No component-library row exists for a scanned fitting — its take-off
    // is in start_value_mm / end_value_mm and the point it was measured to
    // in iso_ref (see PlannedSegment.anchorColumns).
    'start_library_id': null,
    'start_value_mm': cols.startValueMm,
    'end_kind': seg.end.kind.code,
    'end_library_id': null,
    'end_value_mm': cols.endValueMm,
    'iso_ref': '${cols.startRef}|${cols.endRef}',
    'iso_expr': _storedIsoExpr(seg.isoExpr, isoMm),
    'iso_mm': isoMm,
    'cut_mm': cutMm,
    'created_at': nowMs,
    'updated_at': nowMs,
  };
}

/// ISO text for `segments.iso_expr`: the dimension as printed when the
/// builder's parser reads it back to [isoMm], otherwise [isoMm] itself.
///
/// The builder puts this text in its ISO field on "edit" and recomputes from
/// it. A drawing's `4'-6"` it cannot parse would leave the edit with no CUT
/// and a dead save button, and the old whole-millimetre fallback turned a
/// 1371.6 dimension into 1372 on the first re-save.
String _storedIsoExpr(String? raw, double isoMm) {
  final t = raw?.trim();
  if (t != null && t.isNotEmpty) {
    try {
      if ((parseIsoExpression(t) - isoMm).abs() < 0.0005) return t;
    } on FormatException {
      // Falls through to the number itself.
    }
  }
  var text = isoMm.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

/// The complete plan: header, segments, and everything still open.
class ScanPlan {
  final ScanProjectDraft project;

  /// Pipe segments in route order. Auxiliary lines are not here.
  final List<PlannedSegment> segments;

  /// Blocking — the plan must not be written until these are answered.
  final List<ScanIssue> gaps;

  /// Non-blocking — worth showing, safe to save around.
  final List<ScanIssue> warnings;

  /// How many drawing helper lines were dropped.
  final int auxiliarySegmentCount;

  /// How many disconnected runs the segments fall into. 1 is a clean spool.
  final int runCount;

  const ScanPlan({
    required this.project,
    required this.segments,
    required this.gaps,
    required this.warnings,
    required this.auxiliarySegmentCount,
    required this.runCount,
  });

  /// True when nothing is blocking a save.
  bool get canSave => gaps.isEmpty && segments.isNotEmpty;

  /// Gaps attached to one segment.
  List<ScanIssue> gapsFor(String segmentId) =>
      gaps.where((g) => g.segmentId == segmentId).toList(growable: false);

  /// Warnings attached to one segment.
  List<ScanIssue> warningsFor(String segmentId) =>
      warnings.where((w) => w.segmentId == segmentId).toList(growable: false);

  /// Whether any issue of [code] was raised, in either list.
  bool has(ScanIssueCode code) =>
      gaps.any((g) => g.code == code) || warnings.any((w) => w.code == code);
}

// ─────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────

/// Builds a saveable plan out of a finished AI scan.
///
/// [diameterMm] and [wallThicknessMm] are what the fitter already set up (a
/// project he is scanning into). They always win over anything read off the
/// drawing, because he is standing in front of the pipe and the drawing may
/// be a revision behind.
ScanPlan planFromScan(
  AiScanResult scan, {
  double? diameterMm,
  double? wallThicknessMm,
  double gapMm = 0,
}) {
  // The project's root gap per weld, exactly as the segment builder takes it
  // off. A nonsense value (negative, NaN) is not a reason to LENGTHEN a pipe.
  final gap = (gapMm.isFinite && gapMm > 0) ? gapMm : 0.0;
  final gaps = <ScanIssue>[];
  final warnings = <ScanIssue>[];

  final draft = _inferProject(
    scan,
    callerDiameterMm: diameterMm,
    callerWallThicknessMm: wallThicknessMm,
  );

  if (scan.isError) {
    gaps.add(const ScanIssue(
      code: ScanIssueCode.scanFailed,
      blocking: true,
      pl: 'Skan nie powiódł się — powtórz zdjęcie rysunku.',
      en: 'The scan failed — retake the photo of the drawing.',
    ));
    return ScanPlan(
      project: draft,
      segments: const [],
      gaps: gaps,
      warnings: warnings,
      auxiliarySegmentCount: 0,
      runCount: 0,
    );
  }

  // ── Header gaps ──────────────────────────────────────────────────────
  if (draft.diameterMm == null) {
    gaps.add(const ScanIssue(
      code: ScanIssueCode.missingDiameter,
      blocking: true,
      pl: 'Podaj średnicę rury — nie dało się jej odczytać z rysunku.',
      en: 'Enter the pipe diameter — it could not be read from the drawing.',
    ));
  }
  if (draft.wallThicknessMm == null) {
    gaps.add(const ScanIssue(
      code: ScanIssueCode.missingWallThickness,
      blocking: true,
      pl: 'Podaj grubość ścianki — brak czytelnego schedule na rysunku.',
      en: 'Enter the wall thickness — no readable schedule on the drawing.',
    ));
  }
  if (draft.materialGroup == null) {
    gaps.add(const ScanIssue(
      code: ScanIssueCode.missingMaterialGroup,
      blocking: true,
      pl: 'Wskaż grupę materiału (SS / CS) — nie wynika jednoznacznie '
          'z tabelki rysunku.',
      en: 'Pick the material group (SS / CS) — the title block does not say '
          'it unambiguously.',
    ));
  }

  // ── Segments ─────────────────────────────────────────────────────────
  //
  // Auxiliary lines are dimension helpers, north arrows, match lines. They
  // are drawn like a pipe run and must not become one.
  final auxiliary = scan.segments.where((s) => s.auxiliary).toList();
  final pipeSegments = scan.segments.where((s) => !s.auxiliary).toList();

  if (auxiliary.isNotEmpty) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.auxiliarySegmentsSkipped,
      blocking: false,
      pl: 'Pominięto ${auxiliary.length} linii pomocniczych rysunku '
          '(to nie są odcinki rury).',
      en: 'Skipped ${auxiliary.length} auxiliary drawing lines '
          '(they are not pipe runs).',
    ));
  }

  if (pipeSegments.isEmpty) {
    gaps.add(const ScanIssue(
      code: ScanIssueCode.noUsableSegments,
      blocking: true,
      pl: 'Rysunek nie dał ani jednego odcinka rury — dodaj segmenty ręcznie '
          'albo powtórz skan.',
      en: 'The drawing yielded no pipe runs — add segments by hand or rescan.',
    ));
    return ScanPlan(
      project: draft,
      segments: const [],
      gaps: gaps,
      warnings: warnings,
      auxiliarySegmentCount: auxiliary.length,
      runCount: 0,
    );
  }

  final components = <String, AiComponent>{};
  for (final c in scan.components) {
    if (c.id.isEmpty) continue;
    components.putIfAbsent(c.id, () => c);
  }

  final route = _orderRoute(pipeSegments);

  for (final node in route.branchNodes) {
    final c = components[node];
    final what = c?.label ?? c?.type ?? node;
    warnings.add(ScanIssue(
      code: ScanIssueCode.branchInRoute,
      blocking: false,
      componentId: node,
      pl: 'Rozgałęzienie na "$what" — sprawdź, którą odnogą biegnie trasa.',
      en: 'Branch at "$what" — check which leg the route follows.',
    ));
  }
  if (route.runCount > 1) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.routeNotContinuous,
      blocking: false,
      pl: 'Trasa rozpada się na ${route.runCount} niepołączonych ciągów — '
          'kolejność segmentów sprawdź na rysunku.',
      en: 'The route falls into ${route.runCount} disconnected runs — verify '
          'the segment order against the drawing.',
    ));
  }

  final planned = <PlannedSegment>[];
  final assumedLongRadius = <String>{};
  final reducersSeen = <String>{};

  for (var position = 0; position < route.order.length; position++) {
    final seg = pipeSegments[route.order[position]];
    final segmentId = seg.id.isEmpty ? 'seg${position + 1}' : seg.id;

    final start = _endpoint(
      seg.fromId,
      components: components,
      dn: draft.dn,
      pipeClass: scan.titleBlock.pipeClass,
      segmentId: segmentId,
      warnings: warnings,
      assumedLongRadius: assumedLongRadius,
      reducersSeen: reducersSeen,
    );
    final end = _endpoint(
      seg.toId,
      components: components,
      dn: draft.dn,
      pipeClass: scan.titleBlock.pipeClass,
      segmentId: segmentId,
      warnings: warnings,
      assumedLongRadius: assumedLongRadius,
      reducersSeen: reducersSeen,
    );

    // ── Dimension ────────────────────────────────────────────────────
    final rawDimension = seg.rawDimension?.trim();
    double? isoMm = seg.dimensionMm;
    if (isoMm == null && rawDimension != null && rawDimension.isNotEmpty) {
      // The model sometimes reads the text but cannot normalise it (feet and
      // inches on an ASME drawing). Converting text we can actually parse is
      // a conversion, not a guess.
      isoMm = UnitParser.parseToMm(rawDimension);
    }
    if (isoMm != null && (!isoMm.isFinite || isoMm <= 0)) isoMm = null;

    final dimensionLabel = (rawDimension != null && rawDimension.isNotEmpty)
        ? rawDimension
        : (isoMm != null ? '${isoMm.toStringAsFixed(0)} mm' : null);

    if (isoMm == null) {
      gaps.add(ScanIssue(
        code: ScanIssueCode.missingDimension,
        blocking: true,
        segmentId: segmentId,
        dimensionLabel: rawDimension,
        pl: rawDimension == null
            ? 'Segment $segmentId nie ma wymiaru — wpisz go z rysunku.'
            : 'Nie udało się odczytać wymiaru "$rawDimension" '
                '(segment $segmentId) — wpisz go ręcznie.',
        en: rawDimension == null
            ? 'Segment $segmentId has no dimension — type it in from the '
                'drawing.'
            : 'Could not read the dimension "$rawDimension" '
                '(segment $segmentId) — type it in by hand.',
      ));
    }

    // ── Confidence ───────────────────────────────────────────────────
    // The fitter has to see what the model was unsure about, by the number
    // as printed, so the screen can highlight exactly that dimension.
    //
    // Since 2026-09-25 (spec §9, rule 6: an uncertain value never becomes a
    // cut length silently) a shaky number that WAS read blocks the save
    // until the fitter confirms it — re-entering it on the review screen
    // marks it as his own reading. The cut is still computed and shown, so
    // he sees what he is confirming. A dimension that was not read at all is
    // already blocked by [ScanIssueCode.missingDimension]; the doubt about it
    // stays a warning so it is not reported twice.
    if (seg.confidence == AiConfidence.low ||
        seg.confidence == AiConfidence.unknown) {
      final issue = ScanIssue(
        code: ScanIssueCode.lowConfidence,
        blocking: isoMm != null,
        segmentId: segmentId,
        dimensionLabel: dimensionLabel,
        pl: isoMm != null
            ? 'Niepewny odczyt wymiaru ${dimensionLabel ?? ""} — sprawdź go '
                'na rysunku i potwierdź (stuknij wymiar ISO odcinka).'
            : 'Niepewny odczyt wymiaru ${dimensionLabel ?? "(brak)"} — '
                'sprawdź na rysunku.',
        en: isoMm != null
            ? 'Low-confidence reading of ${dimensionLabel ?? ""} — check it '
                'against the drawing and confirm it (tap the segment\'s ISO '
                'dimension).'
            : 'Low-confidence reading of ${dimensionLabel ?? "(none)"} — '
                'check it against the drawing.',
      );
      (issue.blocking ? gaps : warnings).add(issue);
    }

    // ── Dimension reference ──────────────────────────────────────────
    //
    // PrefabEngine's own rule: two axial ends are always dimensioned
    // centre-to-centre, but the moment a bodied component (flange, valve,
    // reducer, cap) sits on an end, the drawing could have been measured to
    // its face or to its far end and a photo cannot tell which. That is a
    // question for the fitter, not a guess for us.
    final needsPicker = PrefabEngine.needsDimRefPicker(
      leftIsPhysical: start.isPhysical,
      rightIsPhysical: end.isPhysical,
    );
    final proposed = _proposeStops(start, end);
    final stops = needsPicker ? null : proposed;

    if (needsPicker) {
      final notePl = _proposalNote(start, end, proposed, polish: true);
      final noteEn = _proposalNote(start, end, proposed, polish: false);
      gaps.add(ScanIssue(
        code: ScanIssueCode.dimensionReferenceUnknown,
        blocking: true,
        segmentId: segmentId,
        dimensionLabel: dimensionLabel,
        pl: 'Potwierdź, jak zmierzono wymiar ${dimensionLabel ?? ""} '
            '(propozycja: ${proposed.label(polish: true)}$notePl) — na końcu '
            'segmentu jest element o własnej długości.',
        en: 'Confirm how ${dimensionLabel ?? "this dimension"} was measured '
            '(suggested: ${proposed.label(polish: false)}$noteEn) — the '
            'segment ends on a component with a body of its own.',
      ));
    }

    // ── Take-outs ────────────────────────────────────────────────────
    for (final side in <List<Object?>>[
      ['START', start],
      ['END', end],
    ]) {
      final label = side[0] as String;
      final e = side[1] as ScanEndpoint;
      if (!e.isResolved) {
        gaps.add(ScanIssue(
          code: ScanIssueCode.missingTakeout,
          blocking: true,
          segmentId: segmentId,
          componentId: e.componentId,
          pl: 'Nierozpoznany element na końcu $label segmentu $segmentId — '
              'wskaż komponent, żeby policzyć długość cięcia.',
          en: 'Unidentified component on the $label of segment $segmentId — '
              'pick it so the cut length can be computed.',
        ));
      } else if (e.isAxial && e.takeoutMm == null) {
        gaps.add(ScanIssue(
          code: ScanIssueCode.missingTakeout,
          blocking: true,
          segmentId: segmentId,
          componentId: e.componentId,
          pl: 'Brak take-outu dla "${e.rawType ?? "kształtka"}" na końcu '
              '$label — podaj wymiar oś–czoło.',
          en: 'No take-out for the "${e.rawType ?? "fitting"}" on the $label '
              '— enter its centre-to-end dimension.',
        ));
      }
    }

    // ── CUT ──────────────────────────────────────────────────────────
    var segment = PlannedSegment(
      sourceId: segmentId,
      seqNo: position + 1,
      start: start,
      end: end,
      isoExpr: rawDimension,
      isoMm: isoMm,
      stops: stops,
      proposedStops: proposed,
      confidence: seg.confidence,
      startsNewRun: position > 0 && route.runStarts.contains(position),
      isBranch: _touchesBranch(seg, route.branchNodes),
      gapMm: gap,
    );

    if (stops != null) {
      final cutMm = cutMmForStops(segment, stops);
      if (cutMm == null &&
          isoMm != null &&
          start.isResolved &&
          end.isResolved &&
          !(start.isAxial && start.takeoutMm == null) &&
          !(end.isAxial && end.takeoutMm == null)) {
        // Every input was known and the arithmetic still refuses: the
        // dimension is shorter than the fittings it spans. That is a real
        // finding — surfacing it beats writing a negative cut.
        gaps.add(ScanIssue(
          code: ScanIssueCode.cutImpossible,
          blocking: true,
          segmentId: segmentId,
          dimensionLabel: dimensionLabel,
          pl: 'Z wymiaru ${dimensionLabel ?? ""} nie wychodzi dodatnia '
              'długość cięcia — sprawdź wymiar i take-outy.',
          en: 'Dimension ${dimensionLabel ?? ""} does not yield a positive '
              'cut length — check the dimension and the take-outs.',
        ));
      }
      segment = PlannedSegment(
        sourceId: segment.sourceId,
        seqNo: segment.seqNo,
        start: segment.start,
        end: segment.end,
        isoExpr: segment.isoExpr,
        isoMm: segment.isoMm,
        stops: segment.stops,
        proposedStops: segment.proposedStops,
        cutMm: cutMm,
        confidence: segment.confidence,
        startsNewRun: segment.startsNewRun,
        isBranch: segment.isBranch,
        gapMm: segment.gapMm,
      );
    }

    planned.add(segment);
  }

  if (assumedLongRadius.isNotEmpty) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.takeoutAssumedLongRadius,
      blocking: false,
      pl: 'Dla ${assumedLongRadius.length} kolan 90° przyjęto długi promień '
          '(LR) — jeśli na budowie są SR, popraw take-out.',
      en: 'Long radius (LR) assumed for ${assumedLongRadius.length} 90° '
          'elbows — correct the take-out if the job uses SR.',
    ));
  }

  return ScanPlan(
    project: draft,
    segments: planned,
    gaps: gaps,
    warnings: warnings,
    auxiliarySegmentCount: auxiliary.length,
    runCount: route.runCount,
  );
}

/// Cut length for [segment] measured according to [ref], or null when an
/// input [PrefabEngine] needs is not known. Which side gets which stop of
/// the pair follows [stopsForDimRef].
double? cutMmForSegment(PlannedSegment segment, DimRef ref) =>
    cutMmForStops(segment, stopsForDimRef(segment, ref));

/// Cut length for [segment] with the dimension stopping at [stops], or null
/// when an input [PrefabEngine] needs is not known.
///
/// Public because the screen calls it again after the fitter answers a
/// [ScanIssueCode.dimensionReferenceUnknown] gap: the plan itself never cuts
/// on a reference it cannot derive — a proposal is only preselected.
///
/// The segment's root gap ([PlannedSegment.gapMm]) comes off once per weld
/// ([PlannedSegment.weldCount]), through the same
/// [PrefabEngine.anchoredCutMm] the segment builder uses, with the stop of
/// each side given explicitly (`leftStop` / `rightStop`) so the engine never
/// has to guess which anchor was measured which way.
double? cutMmForStops(PlannedSegment segment, ScanStops stops) {
  final a = _resolvedAnchors(segment, stops);
  if (a == null) return null;
  final cut = PrefabEngine.anchoredCutMm(
    isoMm: segment.isoMm!,
    startStop: a.startStop,
    startOffsetMm: a.startMm,
    endStop: a.endStop,
    endOffsetMm: a.endMm,
    gapMm: segment.gapMm,
    welds: segment.weldCount,
  );
  return cut.isFinite ? cut : null;
}

/// Which side of [segment] gets which stop of [ref]'s pair.
///
/// Each end has a stop the drawing normally uses for it
/// ([ScanEndpoint.proposedStop]); the assignment that matches more of them
/// wins. So FTE between a valve and a weld-neck flange puts the END on the
/// flange (Y comes off) and the FACE on the valve — where the engine's
/// generic tie-break for two bodied ends would pick the longer valve body
/// and cut the pipe 153 mm short (DN100). Only a genuine tie falls back to
/// [PrefabEngine.resolveSideStops].
ScanStops stopsForDimRef(PlannedSegment segment, DimRef ref) {
  final (a, b) = _stopPairFor(ref);
  if (a == b) return ScanStops(a, b);
  final start = segment.start;
  final end = segment.end;
  int score(SideStop s, SideStop e) =>
      (s == start.proposedStop ? 1 : 0) + (e == end.proposedStop ? 1 : 0);
  final direct = score(a, b);
  final swapped = score(b, a);
  if (direct != swapped) {
    return direct > swapped ? ScanStops(a, b) : ScanStops(b, a);
  }
  final r = PrefabEngine.resolveSideStops(
    ref: ref,
    leftCteMm: start.isAxial ? (start.takeoutMm ?? 0) : 0,
    rightCteMm: end.isAxial ? (end.takeoutMm ?? 0) : 0,
    leftPhysicalLenMm: start.isPhysical ? (start.bodyLengthMm ?? 0) : 0,
    rightPhysicalLenMm: end.isPhysical ? (end.bodyLengthMm ?? 0) : 0,
    leftIsPhysical: start.isPhysical,
    rightIsPhysical: end.isPhysical,
  );
  return r == null ? ScanStops(a, b) : ScanStops(r.left, r.right);
}

/// The references the picker offers for [segment], proposal first: every
/// [DimRef] placed per [stopsForDimRef], plus end–end when both ends have a
/// body (a spool between two flanges). Duplicates dropped.
List<ScanStops> referenceOptions(PlannedSegment segment) {
  final out = <ScanStops>[segment.proposedStops];
  void add(ScanStops s) {
    if (!out.contains(s)) out.add(s);
  }

  for (final ref in DimRef.values) {
    add(stopsForDimRef(segment, ref));
  }
  if (segment.start.isPhysical && segment.end.isPhysical) {
    add(const ScanStops(SideStop.end, SideStop.end));
  }
  return out;
}

/// The stop [PrefabEngine] gives each side of [segment] under [stops], with
/// the length that stop takes off; null when an input it needs is not known.
///
/// Shared by [cutMmForStops] and [PlannedSegment.anchorColumns], so the
/// saved row describes exactly the arithmetic its cut came from.
({SideStop startStop, double startMm, SideStop endStop, double endMm})?
    _resolvedAnchors(PlannedSegment segment, ScanStops stops) {
  final iso = segment.isoMm;
  if (iso == null || !iso.isFinite || iso <= 0) return null;

  // A resolved end contributes a genuine number for the stop (0 at a face);
  // an unresolved end, a missing take-out or a missing body contributes null
  // and stops the sum.
  final startMm = _roundOrNull(segment.start.deductionAt(stops.start));
  final endMm = _roundOrNull(segment.end.deductionAt(stops.end));
  if (startMm == null || endMm == null) return null;

  return (
    startStop: stops.start,
    startMm: startMm.toDouble(),
    endStop: stops.end,
    endMm: endMm.toDouble(),
  );
}

int? _roundOrNull(double? v) => v?.round();

/// Reference the two ends suggest, following normal isometric practice:
/// each end at its own [ScanEndpoint.proposedStop] — axial fittings at their
/// centreline, a weld-neck flange at its sealing face (through the body), a
/// valve at its face.
///
/// Ends with no body at all (an open pipe end, a weld, a support) contribute
/// nothing either way, so a run between them is plain centre-to-centre — the
/// case [PrefabEngine.needsDimRefPicker] says needs no question. Only a
/// proposal for the rest — see [PlannedSegment.proposedStops].
ScanStops _proposeStops(ScanEndpoint start, ScanEndpoint end) {
  if (!start.isPhysical && !end.isPhysical) {
    return const ScanStops(SideStop.centre, SideStop.centre);
  }
  return ScanStops(start.proposedStop, end.proposedStop);
}

/// ", kołnierz: −Y 76 mm" — what the proposal takes off a bodied end, so the
/// question names the number and not just a code. Empty when nothing does.
String _proposalNote(ScanEndpoint start, ScanEndpoint end, ScanStops stops,
    {required bool polish}) {
  final parts = <String>[];
  for (final (e, stop) in [(start, stops.start), (end, stops.end)]) {
    if (stop != SideStop.end || !e.isPhysical) continue;
    final body = e.bodyLengthMm;
    final what = e.isWeldNeckFlange
        ? (polish ? 'kołnierz' : 'flange')
        : (e.label ?? e.rawType ?? (polish ? 'element' : 'component'));
    if (body == null) {
      parts.add(polish
          ? '$what: brak długości w tabeli — podaj ją albo wybierz inne '
              'odniesienie'
          : '$what: no length in the tables — enter it or pick another '
              'reference');
    } else if (e.isWeldNeckFlange) {
      parts.add('$what: −Y ${body.toStringAsFixed(0)} mm');
    } else {
      parts.add('$what: −${body.toStringAsFixed(0)} mm');
    }
  }
  return parts.isEmpty ? '' : ', ${parts.join(', ')}';
}

/// Second line of an end on the review screen: what this end takes off the
/// dimension under the stops in effect (confirmed, else proposed), with the
/// table it came from. Never a bare number without saying where it came
/// from.
String endpointDeductionText(
  PlannedSegment segment, {
  required bool start,
  required bool polish,
}) {
  final e = start ? segment.start : segment.end;
  final effective = segment.stops ?? segment.proposedStops;
  final stop = start ? effective.start : effective.end;
  String t(String pl, String en) => polish ? pl : en;

  if (!e.isResolved) return t('nierozpoznane', 'unrecognised');
  if (e.isAxial) {
    final v = e.takeoutMm;
    if (v == null) return t('brak take-outu', 'no take-out');
    if (stop != SideStop.centre) {
      return t('wymiar do końca kształtki — nic nie odejmowane',
          'dimension to the fitting end — nothing deducted');
    }
    final value = t('oś–czoło ${v.toStringAsFixed(0)} mm',
        'centre–face ${v.toStringAsFixed(0)} mm');
    final note = e.takeoutNote;
    return note == null ? value : '$value · $note';
  }
  if (e.isPhysical) {
    if (stop == SideStop.end) {
      final body = e.bodyLengthMm;
      if (body == null) {
        return t('przez korpus — brak długości w tabeli',
            'through the body — no length in the tables');
      }
      final mm = body.toStringAsFixed(0);
      final value = e.isWeldNeckFlange
          ? t('do przylgi: −Y $mm mm', 'to the sealing face: −Y $mm mm')
          : t('przez korpus: −$mm mm', 'through the body: −$mm mm');
      final note = e.bodyNote;
      return note == null ? value : '$value · $note';
    }
    return t('wymiar do czoła — nic nie odejmowane',
        'dimension to the face — nothing deducted');
  }
  if (e.componentId == null) return t('otwarty koniec', 'open end');
  return t('punkt odniesienia', 'reference point');
}

bool _touchesBranch(AiSegment seg, List<String> branchNodes) {
  if (branchNodes.isEmpty) return false;
  return branchNodes.contains(seg.fromId) || branchNodes.contains(seg.toId);
}

// ─────────────────────────────────────────────────────────────────────────
// Route ordering
// ─────────────────────────────────────────────────────────────────────────

class _RouteOrder {
  /// Indices into the non-auxiliary segment list, in walking order.
  final List<int> order;

  /// Positions in [order] where a new, disconnected run begins.
  final Set<int> runStarts;

  final int runCount;

  /// Component ids touched by more than two pipe segments.
  final List<String> branchNodes;

  const _RouteOrder(
      this.order, this.runStarts, this.runCount, this.branchNodes);
}

/// Threads the segments into a walking order using `fromId` / `toId`.
///
/// Treats segments as edges and components as nodes, then walks depth-first
/// from a free end so a plain run comes out in drawing order. Branches and
/// breaks are recorded, never fatal: a spool with a tee is normal work, and
/// a scan that lost one link should still hand the fitter everything else.
///
/// Ids that do not resolve to a component still take part in the threading —
/// the drawing says the two segments meet there even if we cannot say what
/// sits at the joint.
_RouteOrder _orderRoute(List<AiSegment> segments) {
  final incident = <String, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    for (final id in [segments[i].fromId, segments[i].toId]) {
      if (id == null || id.isEmpty) continue;
      (incident[id] ??= <int>[]).add(i);
    }
  }

  final branchNodes = incident.entries
      .where((e) => e.value.length > 2)
      .map((e) => e.key)
      .toList()
    ..sort();

  final visited = List<bool>.filled(segments.length, false);
  final order = <int>[];
  final runStarts = <int>{};
  var runs = 0;

  bool isFreeEnd(String? id) =>
      id == null || id.isEmpty || (incident[id]?.length ?? 0) <= 1;
  bool hasFreeEnd(int i) =>
      isFreeEnd(segments[i].fromId) || isFreeEnd(segments[i].toId);

  void visit(int index, String? entry) {
    if (visited[index]) return;
    visited[index] = true;
    order.add(index);
    for (final id in [segments[index].fromId, segments[index].toId]) {
      if (id == null || id.isEmpty || id == entry) continue;
      for (final next in incident[id] ?? const <int>[]) {
        if (!visited[next]) visit(next, id);
      }
    }
  }

  // Two passes: seed at open ends first so a straight run threads in drawing
  // order, then mop up anything left (closed loops, orphans).
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 0; i < segments.length; i++) {
      if (visited[i]) continue;
      if (pass == 0 && !hasFreeEnd(i)) continue;
      runStarts.add(order.length);
      runs++;
      visit(i, null);
    }
  }

  return _RouteOrder(order, runStarts, runs, branchNodes);
}

// ─────────────────────────────────────────────────────────────────────────
// Endpoints
// ─────────────────────────────────────────────────────────────────────────

/// AI type strings mapped onto the tool names [ComponentClassification]
/// understands. Keys are normalised (lower case, alphanumerics only).
///
/// A bare `valve` is deliberately absent — it is routed through
/// [_valveToolName] because it tells us the behaviour but not the
/// face-to-face length.
const Map<String, String> _typeAliases = {
  'elbow90': 'elbow90',
  'elbow45': 'elbow45',
  'tee': 'tee',
  'olet': 'olet',
  'weldolet': 'olet',
  'sockolet': 'olet',
  'thredolet': 'olet',
  'reducer': 'reducer',
  'concentricreducer': 'reducer',
  'eccentricreducer': 'reducer',
  'flange': 'flange',
  'blindflange': 'blindFlange',
  'blind': 'blindFlange',
  'cap': 'cap',
  'weld': 'weld',
  'fieldweld': 'fieldWeld',
  'support': 'support',
  'instrument': 'instrument',
  'spoolbreak': 'spoolBreak',
  'northarrow': 'northArrow',
  'flowarrow': 'flowArrow',
  'text': 'text',
  'gatevalve': 'gateValve',
  'ballvalve': 'ballValve',
  'checkvalve': 'checkValve',
  'globevalve': 'globeValve',
  'butterflyvalve': 'butterflyValve',
};

String _normaliseType(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Tool name for a valve, from its subtype when the model gave one.
///
/// Every valve body behaves the same way geometrically
/// ([ComponentBehaviour.physicalLength]); the subtype only decides which
/// face-to-face table applies. So an unknown subtype still classifies — via
/// `gateValve`, chosen purely as a representative of the group — but it gets
/// no dimension out of the catalogue and raises a warning.
_ValveTool _valveToolName(String? valveType) {
  final t = _normaliseType(valveType ?? '');
  if (t.contains('gate')) return const _ValveTool('gateValve', true);
  if (t.contains('ball')) return const _ValveTool('ballValve', true);
  if (t.contains('check')) return const _ValveTool('checkValve', true);
  if (t.contains('globe')) return const _ValveTool('globeValve', true);
  if (t.contains('butterfly')) {
    return const _ValveTool('butterflyValve', true);
  }
  return const _ValveTool('gateValve', false);
}

class _ValveTool {
  final String tool;
  final bool subtypeKnown;
  const _ValveTool(this.tool, this.subtypeKnown);
}

ScanEndpoint _endpoint(
  String? componentId, {
  required Map<String, AiComponent> components,
  required int? dn,
  required String? pipeClass,
  required String segmentId,
  required List<ScanIssue> warnings,
  required Set<String> assumedLongRadius,
  required Set<String> reducersSeen,
}) {
  // Open end — the spool simply stops here. Nothing is fitted, so it
  // contributes nothing, and that zero is a fact rather than a guess.
  if (componentId == null || componentId.isEmpty) return ScanEndpoint.openEnd;

  final component = components[componentId];
  if (component == null) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.unresolvedComponentRef,
      blocking: false,
      segmentId: segmentId,
      componentId: componentId,
      pl: 'Segment $segmentId wskazuje na komponent "$componentId", którego '
          'nie ma na liście — przerwana trasa.',
      en: 'Segment $segmentId points at component "$componentId", which is '
          'not in the scan — broken route.',
    ));
    return ScanEndpoint(
      componentId: componentId,
      kind: ScanEndKind.logical,
      isResolved: false,
    );
  }

  final normalised = _normaliseType(component.type);
  String? tool = _typeAliases[normalised];
  var subtypeKnown = true;
  if (tool == null && (normalised == 'valve' || normalised.endsWith('valve'))) {
    final v = _valveToolName(component.valveType ?? component.type);
    tool = v.tool;
    subtypeKnown = v.subtypeKnown;
  }

  ComponentBehaviour? behaviour;
  if (tool != null) {
    try {
      behaviour = ComponentClassification.behaviourOfToolName(tool);
    } on ArgumentError {
      // The alias table and ComponentClassification drifted apart. Fail the
      // way an unreadable type does rather than inventing a behaviour.
      behaviour = null;
    }
  }

  if (behaviour == null) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.unknownComponentType,
      blocking: false,
      segmentId: segmentId,
      componentId: componentId,
      pl: 'Nieznany typ komponentu "${component.type}" — potraktowany jako '
          'punkt odniesienia, potwierdź co to jest.',
      en: 'Unknown component type "${component.type}" — treated as a '
          'reference point only; confirm what it is.',
    ));
    return ScanEndpoint(
      componentId: componentId,
      rawType: component.type,
      label: component.label,
      kind: ScanEndKind.logical,
      isResolved: false,
    );
  }

  if (!subtypeKnown) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.valveTypeUnknown,
      blocking: false,
      segmentId: segmentId,
      componentId: componentId,
      pl: 'Zawór bez określonego typu — wpisz jego długość zabudowy '
          '(czoło–czoło) ręcznie.',
      en: 'Valve with no stated type — enter its face-to-face length by hand.',
    ));
  }

  if (tool == 'reducer' && reducersSeen.add(componentId)) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.reducerChangesDiameter,
      blocking: false,
      componentId: componentId,
      pl: 'Redukcja w trasie — za nią zmienia się średnica, ustaw ją przy '
          'kolejnych segmentach.',
      en: 'Reducer in the route — the diameter changes past it; set it on '
          'the following segments.',
    ));
  }

  final ScanEndKind kind;
  if (behaviour.isAxial) {
    kind = ScanEndKind.axial;
  } else if (behaviour.hasPhysicalBody) {
    kind = ScanEndKind.nonAxial;
  } else {
    kind = ScanEndKind.logical;
  }

  double? takeoutMm;
  String? takeoutNote;
  if (kind == ScanEndKind.axial) {
    final t = _axialTakeout(
      tool!,
      dn,
      component,
      assumedLongRadius: assumedLongRadius,
    );
    takeoutMm = t?.mm;
    takeoutNote = t?.note;
  } else {
    // A face or a zero-length marker adds nothing to the dimensioned span.
    takeoutMm = 0;
  }

  // A valve of unknown type gets NO face-to-face: the group's behaviour is
  // the same for all of them, but a gate valve's body is not a check
  // valve's, and borrowing one for the other is exactly the invented number
  // this layer exists to prevent.
  final body = behaviour.hasPhysicalBody && subtypeKnown
      ? _bodyLength(tool!, dn, pipeClass, component: component)
      : null;

  final SideStop proposedStop;
  if (kind == ScanEndKind.axial) {
    proposedStop = SideStop.centre;
  } else if (tool == 'flange' && !_isSlipOnLike(component)) {
    // The isometric dimension to a flange runs to its sealing face — through
    // the weld-neck hub, whose length Y the pipe does NOT get (the segment
    // builder defaults a flange to FACE_FAR for the same reason).
    proposedStop = SideStop.end;
  } else {
    proposedStop = SideStop.face;
  }

  return ScanEndpoint(
    componentId: componentId,
    rawType: component.type,
    label: component.label,
    kind: kind,
    behaviour: behaviour,
    tool: tool,
    takeoutMm: takeoutMm,
    bodyLengthMm: behaviour.hasPhysicalBody
        ? body?.mm
        : (kind == ScanEndKind.logical ? 0 : null),
    takeoutNote: takeoutNote,
    bodyNote: behaviour.hasPhysicalBody ? body?.note : null,
    proposedStop: proposedStop,
  );
}

class _Takeout {
  final double mm;
  final String note;
  const _Takeout(this.mm, this.note);
}

/// Centre-to-end for an axial fitting, from the ASME tables the app already
/// ships. Null when the DN is unknown or the standard has no entry — that
/// blocks the cut instead of producing a filler number.
_Takeout? _axialTakeout(
  String tool,
  int? dn,
  AiComponent component, {
  required Set<String> assumedLongRadius,
}) {
  if (dn == null) return null;
  switch (tool) {
    case 'elbow90':
      final marking =
          '${component.label ?? ''} ${component.type}'.toUpperCase();
      final isShort =
          RegExp(r'\bSR\b').hasMatch(marking) || marking.contains('SHORT');
      if (isShort) {
        final sr = TakeoutCatalog.elbow90SR[dn];
        return sr == null
            ? null
            : _Takeout(sr.toDouble(), 'ASME B16.9 tab. 6.1-4 · 90° SR · DN$dn');
      }
      final lr = TakeoutCatalog.elbow90LR[dn];
      if (lr == null) return null;
      // Long radius is the process-piping default, but it IS a default — the
      // plan says so out loud instead of hiding it.
      assumedLongRadius.add(component.id);
      return _Takeout(lr.toDouble(), 'ASME B16.9 · 90° LR · DN$dn');
    case 'elbow45':
      final v = TakeoutCatalog.elbow45LR[dn];
      return v == null
          ? null
          : _Takeout(v.toDouble(), 'ASME B16.9 · 45° LR · DN$dn');
    case 'tee':
      final v = TakeoutCatalog.tee[dn];
      return v == null
          ? null
          : _Takeout(v.toDouble(), 'ASME B16.9 · tee · DN$dn');
    default:
      // Olets and anything else axial have no take-out table here.
      return null;
  }
}

/// Slip-on / socket / lap / threaded flanges swallow the pipe: their
/// set-back is not a catalogue length and their sealing face is not where a
/// weld-neck's Y would put it.
bool _isSlipOnLike(AiComponent component) {
  final marking = '${component.label ?? ''} ${component.type}'.toUpperCase();
  return RegExp(r'\b(SO|SW|LJ|THD|THRD)\b|SLIP|SOCKET|LAP|THREAD')
      .hasMatch(marking);
}

/// Body length along the run, only where a standard gives one unambiguously.
///
/// Flanges and valves are listed per pressure class, so they resolve only
/// when the title block actually says Class 150 — guessing a class would
/// change the cut by tens of millimetres.
_Takeout? _bodyLength(String tool, int? dn, String? pipeClass,
    {AiComponent? component}) {
  if (dn == null) return null;
  final is150 = _isClass150(pipeClass);
  _Takeout? pick(Map<int, int> table, String note) {
    final v = table[dn];
    return v == null ? null : _Takeout(v.toDouble(), '$note · DN$dn');
  }

  switch (tool) {
    case 'reducer':
      return pick(TakeoutCatalog.reducer, 'ASME B16.9 · H');
    case 'cap':
      return pick(TakeoutCatalog.cap, 'ASME B16.9 · E');
    case 'flange':
      if (!is150) return null;
      // A weld-neck's body is Y (face to hub end, DN100: 76 mm) — NOT the
      // disc thickness C (24 mm) this used to borrow, which left the pipe
      // ~52 mm long whenever the dimension ran through the flange.
      // Slip-on / socket / lap / threaded flanges swallow the pipe: the
      // set-back is not a catalogue length, so no number is invented and the
      // end stays an explicit gap for the fitter.
      if (component != null && _isSlipOnLike(component)) return null;
      return pick(TakeoutCatalog.flangeWN150Y, 'ASME B16.5 Cl.150 · WN Y');
    case 'blindFlange':
      return is150
          ? pick(TakeoutCatalog.flangeThickness150C, 'ASME B16.5 Cl.150 · C')
          : null;
    case 'globeValve':
      return is150
          ? pick(TakeoutCatalog.globeValve150, 'ASME B16.10 Cl.150 · globe')
          : null;
    case 'gateValve':
      return is150
          ? pick(TakeoutCatalog.gateValve150, 'ASME B16.10 Cl.150 · gate')
          : null;
    case 'ballValve':
      return is150
          ? pick(TakeoutCatalog.ballValve150, 'ASME B16.10 Cl.150 · ball')
          : null;
    case 'checkValve':
      return is150
          ? pick(TakeoutCatalog.checkValve150, 'ASME B16.10 Cl.150 · check')
          : null;
    default:
      return null;
  }
}

/// Drawings write the class as `150`, `150#`, `CL150`, `ANSI 150` — so the
/// digits are bounded by other digits, not by word boundaries (`\b150\b`
/// never fires inside `CL150`). Any other class present means this is not a
/// Class 150 line.
bool _isClass150(String? pipeClass) {
  if (pipeClass == null) return false;
  final t = pipeClass.toUpperCase();
  if (RegExp(r'(?<!\d)(300|400|600|900|1500|2500)(?!\d)').hasMatch(t)) {
    return false;
  }
  return RegExp(r'(?<!\d)150(?!\d)').hasMatch(t);
}

// ─────────────────────────────────────────────────────────────────────────
// Project header inference
// ─────────────────────────────────────────────────────────────────────────

ScanProjectDraft _inferProject(
  AiScanResult scan, {
  required double? callerDiameterMm,
  required double? callerWallThicknessMm,
}) {
  final tb = scan.titleBlock;

  // ── Nominal size ─────────────────────────────────────────────────────
  int? dn;
  var diameterSource = ScanValueSource.none;

  if (callerDiameterMm != null && callerDiameterMm > 0) {
    dn = _dnForOd(callerDiameterMm);
    diameterSource = ScanValueSource.caller;
  }

  final pipeBom = _pipeBomItem(scan.billOfMaterials);
  if (dn == null) {
    dn = _parseSizeToDn(pipeBom?.size, scan.sizeNotation) ??
        _parseSizeToDn(tb.lineNumber, scan.sizeNotation) ??
        _firstBomDn(scan.billOfMaterials, scan.sizeNotation);
    if (dn != null && callerDiameterMm == null) {
      diameterSource = ScanValueSource.scan;
    }
  }

  final row = dn == null ? null : _rowForDn(dn);

  double? diameterMm;
  if (callerDiameterMm != null && callerDiameterMm > 0) {
    diameterMm = callerDiameterMm;
  } else if (row != null) {
    diameterMm = row.od;
  } else {
    diameterSource = ScanValueSource.none;
  }

  // ── Schedule / wall ──────────────────────────────────────────────────
  final schedule = _normaliseSchedule(tb.schedule) ??
      _normaliseSchedule(pipeBom?.schedule) ??
      _firstBomSchedule(scan.billOfMaterials);

  double? wallThicknessMm;
  var wallSource = ScanValueSource.none;
  if (callerWallThicknessMm != null && callerWallThicknessMm > 0) {
    wallThicknessMm = callerWallThicknessMm;
    wallSource = ScanValueSource.caller;
  } else if (row != null && schedule != null) {
    // Schedule + nominal size is exactly what a wall-thickness table is
    // indexed by — ASME B36.10M / B36.19M, already shipped offline.
    wallThicknessMm = row.walls[schedule];
    if (wallThicknessMm != null) wallSource = ScanValueSource.scan;
  }

  // ── Material group ───────────────────────────────────────────────────
  final materialText = _clean(tb.material) ?? _clean(pipeBom?.material);
  final materialGroup = _materialGroup(materialText);

  return ScanProjectDraft(
    name: _clean(tb.lineNumber) ?? _clean(tb.drawingNumber),
    dn: dn,
    diameterMm: diameterMm,
    wallThicknessMm: wallThicknessMm,
    schedule: schedule,
    materialGroup: materialGroup,
    materialText: materialText,
    diameterSource: diameterSource,
    wallThicknessSource: wallSource,
    materialGroupSource:
        materialGroup == null ? ScanValueSource.none : ScanValueSource.scan,
  );
}

/// Strips the CR/LF that multi-line OCR leaves behind and clamps to the same
/// 80-character ceiling the scanner screen enforces on a project name.
String? _clean(String? raw) {
  if (raw == null) return null;
  final t = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  if (t.isEmpty) return null;
  return t.length > 80 ? t.substring(0, 80) : t;
}

AiBomItem? _pipeBomItem(List<AiBomItem> bom) {
  for (final item in bom) {
    final d = item.description.toUpperCase();
    if (d.contains('PIPE') || d.contains('RURA') || d.contains('TUBE')) {
      return item;
    }
  }
  return null;
}

int? _firstBomDn(List<AiBomItem> bom, String sizeNotation) {
  for (final item in bom) {
    final dn = _parseSizeToDn(item.size, sizeNotation);
    if (dn != null) return dn;
  }
  return null;
}

String? _firstBomSchedule(List<AiBomItem> bom) {
  for (final item in bom) {
    final s = _normaliseSchedule(item.schedule);
    if (s != null) return s;
  }
  return null;
}

PipeRow? _rowForDn(int dn) {
  for (final row in kPipeWalls) {
    if (row.dn == dn) return row;
  }
  return null;
}

/// Nominal diameter for an outside diameter. Close matches only — an OD that
/// is not in the table returns null instead of snapping to a neighbour.
int? _dnForOd(double od) {
  for (final row in kPipeWalls) {
    if ((row.od - od).abs() < 0.6) return row.dn;
  }
  return null;
}

/// Reads a size callout ("DN100", `4"`, "NPS 4", `1 1/2"`) into a DN.
///
/// A bare number is ambiguous — `100` is DN100 on an ISO drawing and a
/// nonsense NPS on an ASME one — so it resolves only when the scan told us
/// which notation the drawing uses. Anything still ambiguous returns null and
/// the user is asked.
int? _parseSizeToDn(String? raw, String sizeNotation) {
  if (raw == null) return null;
  final text = raw.toUpperCase().replaceAll(',', '.');

  final dnMatch = RegExp(r'\bDN\s*(\d{1,4})\b').firstMatch(text);
  if (dnMatch != null) return _knownDn(int.tryParse(dnMatch.group(1)!));

  const number = r'(\d+(?:\s+\d+\s*/\s*\d+|\s*/\s*\d+|\.\d+)?)';

  final inchMatch =
      RegExp('(?:\\bNPS\\s*)?$number\\s*(?:"|”|″|\\bIN\\b|\\bINCH\\b)')
          .firstMatch(text);
  if (inchMatch != null) return _dnForInches(_parseInches(inchMatch.group(1)!));

  final npsMatch = RegExp('\\bNPS\\s*$number').firstMatch(text);
  if (npsMatch != null) return _dnForInches(_parseInches(npsMatch.group(1)!));

  final bare = RegExp('\\b$number').firstMatch(text);
  if (bare == null) return null;
  switch (sizeNotation) {
    case 'DN':
      return _knownDn(int.tryParse(bare.group(1)!.trim()));
    case 'NPS':
      return _dnForInches(_parseInches(bare.group(1)!));
    case 'OD':
      final od = double.tryParse(bare.group(1)!.trim());
      return od == null ? null : _dnForOd(od);
    default:
      // Notation unknown — refuse to guess.
      return null;
  }
}

int? _knownDn(int? dn) {
  if (dn == null) return null;
  return _rowForDn(dn) == null ? null : dn;
}

/// Parses `4`, `4.5`, `3/4`, `1 1/2` into inches.
double? _parseInches(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s*/\s*'), '/');
  final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(t);
  if (mixed != null) {
    final den = double.parse(mixed.group(3)!);
    if (den == 0) return null;
    return double.parse(mixed.group(1)!) + double.parse(mixed.group(2)!) / den;
  }
  final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
  if (frac != null) {
    final den = double.parse(frac.group(2)!);
    if (den == 0) return null;
    return double.parse(frac.group(1)!) / den;
  }
  return double.tryParse(t);
}

int? _dnForInches(double? inches) {
  if (inches == null) return null;
  for (final row in kPipeWalls) {
    final nps = _parseInches(row.nps);
    if (nps != null && (nps - inches).abs() < 0.01) return row.dn;
  }
  return null;
}

/// Normalises a schedule callout to a key of [kSchedules], or null when it is
/// not one this app has wall thicknesses for.
String? _normaliseSchedule(String? raw) {
  if (raw == null) return null;
  var t = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  t = t.replaceFirst(RegExp(r'^(SCHEDULE|SCHD|SCH)'), '');
  if (t.isEmpty) return null;
  if (kSchedules.contains(t)) return t;
  // Drawings write stainless schedules both ways round ("S10" / "10S").
  final flipped = RegExp(r'^S(\d+)$').firstMatch(t);
  if (flipped != null) {
    final alt = '${flipped.group(1)}S';
    if (kSchedules.contains(alt)) return alt;
  }
  return null;
}

/// Stainless markers, checked first: `A403 WP316L` is stainless even though
/// the grade digits alone would say nothing.
const List<String> _stainlessMarkers = [
  'STAINLESS', 'NIERDZ', 'A312', 'A403', 'A358', 'A376',
  'TP304', 'TP316', 'TP321', 'TP347',
  '304L', '316L', '304', '316', '321', '347', '317', '310',
  '1.4301', '1.4306', '1.4401', '1.4404', '1.4541', '1.4571',
  'DUPLEX', '2205',
];

const List<String> _carbonMarkers = [
  'CARBON', 'WEGL', 'A106', 'A234', 'A105', 'A53', 'A333', 'A420', 'A216',
  'WPB', 'GRB', 'ST37', 'ST35', 'S235', 'P235', 'P265', 'L360',
];

/// Maps title-block material text onto the `SS` / `CS` groups the component
/// library is filtered by. Alloy steels (P11, P22) and anything unfamiliar
/// return null so the fitter is asked rather than misfiltered.
String? _materialGroup(String? materialText) {
  if (materialText == null) return null;
  final upper = materialText.toUpperCase();
  final squashed = upper.replaceAll(RegExp(r'[\s\-_]'), '');
  if (squashed.isEmpty) return null;
  for (final m in _stainlessMarkers) {
    if (squashed.contains(m)) return 'SS';
  }
  for (final m in _carbonMarkers) {
    if (squashed.contains(m)) return 'CS';
  }
  if (RegExp(r'\bSS\b').hasMatch(upper)) return 'SS';
  if (RegExp(r'\bCS\b').hasMatch(upper)) return 'CS';
  return null;
}

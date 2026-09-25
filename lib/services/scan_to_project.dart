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
import 'scan_geometry.dart';
import 'scan_graph.dart';
import 'takeout_catalog.dart';
import 'unit_parser.dart';

export 'scan_graph.dart' show PortRole;

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

/// Where a run's dimension reference (the stop on each side) came from.
enum ScanRefSource {
  /// Not settled — the fitter has to answer.
  none,

  /// Follows from the two ends alone (no bodied component on either).
  derived,

  /// Read off the drawing's dimension line (`CL` / `FACE` / `EOP`) with
  /// high confidence, where the code maps to exactly one stop.
  drawing,

  /// Confirmed by the fitter on the review screen.
  fitter,
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

  // ── v2 (graph, per-run sizes, geometry) ─────────────────────────────

  /// A tee / olet whose run cannot be told from its branch where it matters
  /// (a reducing tee: C vs M), or a node that is not a tee with more than
  /// two runs. Blocks only the runs meeting there.
  branchAmbiguous,

  /// The nominal size of this run is not known (past a reducer whose sides
  /// the drawing does not tell apart). Blocks only this run.
  missingSegmentDiameter,

  /// The wall of this run is not known (a size other than the project's and
  /// no schedule to look it up). Blocks only this run.
  missingSegmentWall,

  /// Two readings of the same run's size disagree.
  diameterConflict,

  /// A tee without printed sizes was taken as an equal tee (M = C).
  teeAssumedEqual,

  /// A socket-weld end in a project with a root gap: the gap comes off
  /// again on top of the 1.6 mm socket clearance already in the take-out.
  socketWeldWithGap,

  /// The printed skew length of an offset disagrees with its projections.
  /// Blocks the run until the fitter confirms the dimension.
  offsetDimensionMismatch,

  /// The length of an offset was derived from its projections (√ of the
  /// squares) — informational, the formula is shown.
  dimensionFromProjections,

  /// The bend at an elbow, from the directions of its two runs, is not the
  /// elbow's angle. Blocks the two runs (their take-out would be wrong).
  elbowAngleMismatch,

  /// A run that is not along an axis — an offset / rolling offset.
  offsetInRoute,

  /// The chain of run dimensions does not close against an overall
  /// dimension, an elevation mark or itself (a loop).
  closureMismatch,

  /// An elbow cut to an angle other than 45° / 90°: its take-out is the
  /// segment formula of B16.9 §6.2.4.
  cutElbow,
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

  // ── Identification from the title block (schema v22) ─────────────────
  /// Line number as printed.
  final String? lineNo;

  /// Drawing (isometric) number and its revision.
  final String? isoNo;
  final String? isoRev;

  /// Piping class (spec).
  final String? spec;

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
    this.lineNo,
    this.isoNo,
    this.isoRev,
    this.spec,
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

  /// At a tee / olet: whether this run is the straight-through run or the
  /// branch. Null elsewhere or when not known.
  final PortRole? role;

  /// Why [takeoutMm] (axial) or [bodyLengthMm] (a body) is missing, in both
  /// languages — e.g. "olet: height is the manufacturer's". Null when the
  /// value is known or there is nothing to say beyond the generic gap.
  final String? missingPl;
  final String? missingEn;

  /// True when the take-out / body length was typed in by the fitter.
  final bool fromFitter;

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
    this.role,
    this.missingPl,
    this.missingEn,
    this.fromFitter = false,
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

  // ── v2 ────────────────────────────────────────────────────────────────

  /// Nominal size of THIS run — read next to it, carried through the route
  /// (a reducer's other side, a reducing tee's branch) or the project's.
  /// Null when it cannot be known without the fitter.
  final int? dn;

  /// Outside diameter / wall of this run, mm — what `segments.diameter_mm`
  /// / `wall_thickness_mm` get. Null when not known.
  final double? diameterMm;
  final double? wallThicknessMm;

  /// Where [dn] came from, for the review screen.
  final String? dnNote;

  /// Spool this run belongs to, as printed.
  final String? spoolId;

  /// Label as the drawing numbers it: `SP-1/2` (spool / position in the
  /// spool) or the plain position when the drawing has no spools.
  final String label;

  /// The drawing segments this run is made of: itself, or the two header
  /// halves of an olet merged into the one pipe that is cut.
  final List<String> partIds;

  /// How [isoMm] was obtained when it was not printed as such — e.g. the
  /// true length of an offset from its projections.
  final String? isoNote;

  /// Where [stops] came from: derived from the two ends, read from the
  /// drawing's dimension line, or confirmed by the fitter.
  final ScanRefSource refSource;

  /// Index of the connected run (0-based) this segment belongs to.
  final int runIndex;

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
    this.dn,
    this.diameterMm,
    this.wallThicknessMm,
    this.dnNote,
    this.spoolId,
    String? label,
    List<String>? partIds,
    this.isoNote,
    this.refSource = ScanRefSource.none,
    this.runIndex = 0,
  })  : label = label ?? '$seqNo',
        partIds = partIds ?? const [];

  /// The drawing segment ids behind this run (never empty).
  List<String> get sourceParts => partIds.isEmpty ? [sourceId] : partIds;

  PlannedSegment _copy({
    int? seqNo,
    String? label,
    ScanStops? stops,
    bool clearStops = false,
    double? cutMm,
    bool clearCut = false,
    ScanRefSource? refSource,
    bool? startsNewRun,
  }) =>
      PlannedSegment(
        sourceId: sourceId,
        seqNo: seqNo ?? this.seqNo,
        start: start,
        end: end,
        isoExpr: isoExpr,
        isoMm: isoMm,
        stops: clearStops ? null : (stops ?? this.stops),
        proposedStops: proposedStops,
        cutMm: clearCut ? null : (cutMm ?? this.cutMm),
        confidence: confidence,
        startsNewRun: startsNewRun ?? this.startsNewRun,
        isBranch: isBranch,
        gapMm: gapMm,
        dn: dn,
        diameterMm: diameterMm,
        wallThicknessMm: wallThicknessMm,
        dnNote: dnNote,
        spoolId: spoolId,
        label: label ?? this.label,
        partIds: partIds,
        isoNote: isoNote,
        refSource: refSource ?? this.refSource,
        runIndex: runIndex,
      );

  /// Copy renumbered to [seqNo] with a new [label].
  PlannedSegment renumbered(int seqNo, String label, {bool? startsNewRun}) =>
      _copy(seqNo: seqNo, label: label, startsNewRun: startsNewRun);

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
    final cut = cutMmForStops(this, confirmed);
    return _copy(
      stops: confirmed,
      cutMm: cut,
      clearCut: cut == null,
      refSource: ScanRefSource.fitter,
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
      diameterMm != null &&
      wallThicknessMm != null &&
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
///
/// A run that belongs to a spool is saved with its piece mark ([PlannedSegment.
/// label], `SP-1/2`) in `segments.label` and the spool as printed in
/// `spool_id` — [spoolLabels] maps the spool's id to that printed form (the
/// id itself when missing). A run outside any spool gets neither: its plain
/// position is not a number from the drawing and is already `seq_no`.
Map<String, Object?>? segmentRowFor(
  PlannedSegment seg, {
  required String id,
  required String projectId,
  required double diameterMm,
  required double wallThicknessMm,
  required int nowMs,
  Map<String, String> spoolLabels = const {},
}) {
  final isoMm = seg.isoMm;
  final cutMm = seg.cutMm;
  final cols = seg.anchorColumns;
  if (isoMm == null || cutMm == null || cols == null || !seg.isComplete) {
    return null;
  }
  final spool = seg.spoolId;
  return {
    'id': id,
    'project_id': projectId,
    'seq_no': seg.seqNo,
    // The run's own size (a run past a reducer is not the project's).
    'diameter_mm': seg.diameterMm ?? diameterMm,
    'wall_thickness_mm': seg.wallThicknessMm ?? wallThicknessMm,
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
    'label': spool == null ? null : seg.label,
    'spool_id': spool == null ? null : (spoolLabels[spool] ?? spool),
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

/// What the fitter answered on the review screen that the planner itself
/// has to take into account (everything else — the dimension reference —
/// is applied on top of the plan with [PlannedSegment.withStops]).
class ScanFitterInput {
  /// Nominal size of a run, by segment id (a merged olet header by its
  /// merged id `a+b`). Feeds the size propagation like a printed size.
  final Map<String, int> segmentDn;

  /// Wall of a run, mm, by segment id.
  final Map<String, double> segmentWallMm;

  /// Take-out (axial end) or body length (bodied end) typed in for one end
  /// of one run, mm, keyed by [takeoutKey].
  final Map<String, double> takeoutMm;

  const ScanFitterInput({
    this.segmentDn = const {},
    this.segmentWallMm = const {},
    this.takeoutMm = const {},
  });

  static String takeoutKey(String componentId, String segmentId) =>
      '$componentId@$segmentId';
}

/// Builds a saveable plan out of a finished AI scan.
///
/// [diameterMm] and [wallThicknessMm] are what the fitter already set up (a
/// project he is scanning into). They always win over anything read off the
/// drawing, because he is standing in front of the pipe and the drawing may
/// be a revision behind. [fitter] carries his answers from the review
/// screen that change the plan itself (a run's size, a typed take-out).
///
/// The route is a graph (see `scan_graph.dart`): tees and olets branch it,
/// bolted joints keep it continuous, every run gets its own size — read,
/// carried through reducers and reducing tees, or the project's — and every
/// take-out is looked up for THAT size and THAT end (a tee's run or its
/// branch).
ScanPlan planFromScan(
  AiScanResult scan, {
  double? diameterMm,
  double? wallThicknessMm,
  double gapMm = 0,
  ScanFitterInput fitter = const ScanFitterInput(),
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
  final rawPipe = scan.segments.where((s) => !s.auxiliary).toList();

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

  if (rawPipe.isEmpty) {
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

  // Every run needs an id to be addressed by (a correction, a fitter
  // answer, a gap). An unnamed one gets its position in the drawing's list.
  final usedIds = rawPipe.map((s) => s.id).where((id) => id.isNotEmpty).toSet();
  var pipeSegments = <AiSegment>[];
  for (var i = 0; i < rawPipe.length; i++) {
    final s = rawPipe[i];
    if (s.id.isNotEmpty) {
      pipeSegments.add(s);
      continue;
    }
    var n = i + 1;
    while (usedIds.contains('seg$n')) {
      n++;
    }
    usedIds.add('seg$n');
    pipeSegments.add(s.copyWith(id: 'seg$n'));
  }

  final components = <String, AiComponent>{};
  for (final c in scan.components) {
    if (c.id.isEmpty) continue;
    components.putIfAbsent(c.id, () => c);
  }

  // ── Graph ────────────────────────────────────────────────────────────
  final merge = mergeOletHeaders(pipeSegments, components);
  pipeSegments = merge.segments;
  final assembly = assemblyLinks(components.values);

  final incidentSegs = <String, List<AiSegment>>{};
  for (final s in pipeSegments) {
    for (final id in {s.fromId, s.toId}) {
      if (id == null || id.isEmpty) continue;
      (incidentSegs[id] ??= <AiSegment>[]).add(s);
    }
  }
  final roles = <String, Map<String, PortRole>>{};
  for (final e in incidentSegs.entries) {
    final c = components[e.key];
    if (!isTeeComponent(c) && !isOletComponent(c)) continue;
    if (isOletComponent(c) && e.value.length == 1) {
      roles[e.key] = {e.value.single.id: PortRole.branch};
      continue;
    }
    final r = portRoles(c!, e.value);
    if (r != null) roles[e.key] = r;
  }

  final route = orderRouteGraph(pipeSegments, assembly: assembly, roles: roles);

  // Segment ids whose cut is blocked by the shape of the graph, with why.
  final graphBlocks = <String, ScanIssue>{};
  for (final node in route.branchNodes) {
    final c = components[node];
    final what = c?.label ?? c?.type ?? node;
    if (isTeeComponent(c) || isOletComponent(c)) {
      warnings.add(ScanIssue(
        code: ScanIssueCode.branchInRoute,
        blocking: false,
        componentId: node,
        pl: roles.containsKey(node)
            ? 'Rozgałęzienie na "$what" — przelot i odgałęzienie rozpoznane.'
            : 'Rozgałęzienie na "$what" — sprawdź, którą odnogą biegnie trasa.',
        en: roles.containsKey(node)
            ? 'Branch at "$what" — run and branch identified.'
            : 'Branch at "$what" — check which leg the route follows.',
      ));
    } else {
      for (final s in incidentSegs[node] ?? const <AiSegment>[]) {
        graphBlocks.putIfAbsent(
            s.id,
            () => ScanIssue(
                  code: ScanIssueCode.branchAmbiguous,
                  blocking: true,
                  segmentId: s.id,
                  componentId: node,
                  pl: '"$what" łączy ${incidentSegs[node]!.length} odcinki, '
                      'a to nie trójnik — sprawdź na rysunku, co tam jest.',
                  en: '"$what" joins ${incidentSegs[node]!.length} runs and '
                      'is not a tee — check the drawing.',
                ));
      }
    }
  }
  merge.ambiguous.forEach((olet, ids) {
    final c = components[olet];
    final what = c?.label ?? c?.type ?? olet;
    for (final id in ids) {
      graphBlocks.putIfAbsent(
          id,
          () => ScanIssue(
                code: ScanIssueCode.branchAmbiguous,
                blocking: true,
                segmentId: id,
                componentId: olet,
                pl: 'Olet "$what": nie wiadomo, który odcinek to rura główna, '
                    'a który odgałęzienie — rura główna nie jest cięta na '
                    'olecie. Sprawdź rysunek.',
                en: 'Olet "$what": the header cannot be told from the branch '
                    '— the header is not cut at an olet. Check the drawing.',
              ));
    }
  });
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

  // ── Sizes ────────────────────────────────────────────────────────────
  final sizes = _resolveSizes(
    segments: pipeSegments,
    components: components,
    incident: route.incident,
    roles: roles,
    assembly: assembly,
    notation: scan.sizeNotation,
    draft: draft,
    callerGiven: diameterMm != null && diameterMm > 0,
    fitter: fitter,
    warnings: warnings,
  );
  for (final node in sizes.ambiguousTees) {
    final c = components[node];
    final what = c?.label ?? c?.type ?? node;
    for (final s in incidentSegs[node] ?? const <AiSegment>[]) {
      graphBlocks.putIfAbsent(
          s.id,
          () => ScanIssue(
                code: ScanIssueCode.branchAmbiguous,
                blocking: true,
                segmentId: s.id,
                componentId: node,
                pl: 'Trójnik redukcyjny "$what": nie wiadomo, która odnoga '
                    'to odgałęzienie (take-out C przelotu ≠ M odgałęzienia). '
                    'Podaj średnicę odcinka albo sprawdź rysunek.',
                en: 'Reducing tee "$what": the branch leg is not known (run '
                    'C ≠ branch M). Set the run size or check the drawing.',
              ));
    }
  }

  final planned = <PlannedSegment>[];
  final assumedLongRadius = <String>{};
  final reducersSeen = <String>{};
  var socketWeldSeen = false;

  for (var position = 0; position < route.order.length; position++) {
    final index = route.order[position];
    final seg = pipeSegments[index];
    final segmentId = seg.id;
    final dn = sizes.dn[segmentId];

    _EndCtx ctxFor(String? node) {
      if (node == null || node.isEmpty) return _EndCtx(dn: dn);
      final tee = sizes.tee[node];
      return _EndCtx(
        dn: dn,
        role: roles[node]?[segmentId],
        runDn: tee?.run ?? sizes.reducerLarge[node],
        branchDn: tee?.branch,
        fitterMm: fitter.takeoutMm[ScanFitterInput.takeoutKey(node, segmentId)],
      );
    }

    final start = _endpoint(
      seg.fromId,
      components: components,
      ctx: ctxFor(seg.fromId),
      pipeClass: scan.titleBlock.pipeClass,
      segmentId: segmentId,
      warnings: warnings,
      assumedLongRadius: assumedLongRadius,
      reducersSeen: reducersSeen,
    );
    final end = _endpoint(
      seg.toId,
      components: components,
      ctx: ctxFor(seg.toId),
      pipeClass: scan.titleBlock.pipeClass,
      segmentId: segmentId,
      warnings: warnings,
      assumedLongRadius: assumedLongRadius,
      reducersSeen: reducersSeen,
    );
    if ((start.takeoutNote ?? '').contains('B16.11') ||
        (end.takeoutNote ?? '').contains('B16.11')) {
      socketWeldSeen = true;
    }

    // ── Dimension ────────────────────────────────────────────────────
    final rawDimension = seg.rawDimension?.trim();
    double? isoMm = seg.dimensionMm;
    if (isoMm == null && rawDimension != null && rawDimension.isNotEmpty) {
      // The model sometimes reads the text but cannot normalise it (feet and
      // inches on an ASME drawing). Converting text we can actually parse is
      // a conversion, not a guess.
      isoMm = UnitParser.parseToMm(rawDimension);
      if (isoMm == null) {
        try {
          isoMm = parseIsoExpression(rawDimension);
        } on FormatException {
          isoMm = null;
        }
      }
    }
    if (isoMm != null && (!isoMm.isFinite || isoMm <= 0)) isoMm = null;

    // An offset dimensioned only by its projections: its true length is
    // arithmetic on printed numbers (√ of the squares), shown with the
    // formula. A printed skew length that disagrees with the projections is
    // a contradiction on the drawing — the fitter decides which is right.
    String? isoNote;
    var isoExpr = rawDimension;
    final skew = skewLengthMm(seg.projections);
    if (skew != null) {
      final formula = skewFormula(seg.projections);
      if (isoMm == null) {
        isoMm = skew;
        isoExpr = null;
        isoNote = formula;
        warnings.add(ScanIssue(
          code: ScanIssueCode.dimensionFromProjections,
          blocking: false,
          segmentId: segmentId,
          pl: 'Długość offsetu z rzutów: $formula mm.',
          en: 'Offset length from its projections: $formula mm.',
        ));
      } else if ((isoMm - skew).abs() > kClosureToleranceMm) {
        final issue = ScanIssue(
          code: ScanIssueCode.offsetDimensionMismatch,
          blocking: !seg.userConfirmed,
          segmentId: segmentId,
          dimensionLabel: rawDimension,
          pl: 'Wymiar skośny ${_mmText(isoMm)} nie zgadza się z rzutami '
              '($formula mm) — sprawdź na rysunku i potwierdź wymiar.',
          en: 'The skew dimension ${_mmText(isoMm)} disagrees with its '
              'projections ($formula mm) — check the drawing and confirm it.',
        );
        (issue.blocking ? gaps : warnings).add(issue);
      }
    }

    final dimensionLabel = (rawDimension != null && rawDimension.isNotEmpty)
        ? rawDimension
        : (isoMm != null ? '${_mmText(isoMm)} mm' : null);

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
    if (!seg.userConfirmed &&
        (seg.confidence == AiConfidence.low ||
            seg.confidence == AiConfidence.unknown)) {
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

    // ── Size of this run ─────────────────────────────────────────────
    final geo = _sizeColumns(
      seg: seg,
      dn: dn,
      singleZone: sizes.singleZone,
      draft: draft,
      fitter: fitter,
    );
    if (!sizes.singleZone && dn == null) {
      gaps.add(ScanIssue(
        code: ScanIssueCode.missingSegmentDiameter,
        blocking: true,
        segmentId: segmentId,
        pl: 'Nie wiadomo, jaka średnica ma odcinek $segmentId (za zmianą '
            'średnicy) — wybierz DN odcinka.',
        en: 'The size of run $segmentId is not known (past a size change) — '
            'pick its DN.',
      ));
    } else if (dn != null &&
        dn != draft.dn &&
        geo.wall == null &&
        draft.wallThicknessMm != null) {
      gaps.add(ScanIssue(
        code: ScanIssueCode.missingSegmentWall,
        blocking: true,
        segmentId: segmentId,
        pl: 'Odcinek $segmentId ma DN$dn — brak schedule do odczytu ścianki. '
            'Podaj ściankę odcinka.',
        en: 'Run $segmentId is DN$dn — no schedule to look its wall up. '
            'Enter its wall.',
      ));
    }

    // ── Dimension reference ──────────────────────────────────────────
    //
    // PrefabEngine's own rule: two axial ends are always dimensioned
    // centre-to-centre, but the moment a bodied component (flange, valve,
    // reducer, cap) sits on an end, the drawing could have been measured to
    // its face or to its far end and a photo cannot tell which. That is a
    // question for the fitter — unless the model read the dimension line's
    // end marks (CL / FACE / EOP) with high confidence and they map to one
    // stop each.
    final needsPicker = PrefabEngine.needsDimRefPicker(
      leftIsPhysical: start.isPhysical,
      rightIsPhysical: end.isPhysical,
    );
    final proposed = _proposeStops(start, end);
    ScanStops? stops = needsPicker ? null : proposed;
    var refSource = needsPicker ? ScanRefSource.none : ScanRefSource.derived;
    if (seg.confidence == AiConfidence.high || seg.userConfirmed) {
      final a = _drawingStop(start, seg.refFrom);
      final b = _drawingStop(end, seg.refTo);
      final aOk = a ?? (start.isPhysical ? null : proposed.start);
      final bOk = b ?? (end.isPhysical ? null : proposed.end);
      if ((a != null || b != null) && aOk != null && bOk != null) {
        stops = ScanStops(aOk, bOk);
        refSource = ScanRefSource.drawing;
      }
    }

    if (stops == null) {
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
    final graphBlock = graphBlocks[segmentId];
    if (graphBlock != null) gaps.add(graphBlock);
    for (final (label, e) in [('START', start), ('END', end)]) {
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
      } else if (e.isAxial && e.takeoutMm == null && graphBlock == null) {
        final why = e.missingPl;
        gaps.add(ScanIssue(
          code: ScanIssueCode.missingTakeout,
          blocking: true,
          segmentId: segmentId,
          componentId: e.componentId,
          pl: why != null
              ? '${e.label ?? e.rawType ?? "Kształtka"} (koniec $label): $why'
              : 'Brak take-outu dla "${e.rawType ?? "kształtka"}" na końcu '
                  '$label — podaj wymiar oś–czoło.',
          en: e.missingEn != null
              ? '${e.label ?? e.rawType ?? "Fitting"} ($label end): '
                  '${e.missingEn}'
              : 'No take-out for the "${e.rawType ?? "fitting"}" on the '
                  '$label — enter its centre-to-end dimension.',
        ));
      }
    }

    // ── CUT ──────────────────────────────────────────────────────────
    var segment = PlannedSegment(
      sourceId: segmentId,
      seqNo: position + 1,
      start: start,
      end: end,
      isoExpr: isoExpr,
      isoMm: isoMm,
      stops: stops,
      proposedStops: proposed,
      confidence: seg.confidence,
      startsNewRun: position > 0 &&
          route.runOf[index] != route.runOf[route.order[position - 1]],
      isBranch: route.branchNodes.contains(seg.fromId) ||
          route.branchNodes.contains(seg.toId),
      gapMm: gap,
      dn: dn,
      diameterMm: geo.od,
      wallThicknessMm: geo.wall,
      dnNote: sizes.note[segmentId],
      spoolId: _spoolOf(seg, components),
      partIds: merge.parts[segmentId],
      isoNote: isoNote,
      refSource: refSource,
      runIndex: route.runOf[index] ?? 0,
    );

    if (stops != null) {
      final cutMm = cutMmForStops(segment, stops);
      if (cutMm == null &&
          isoMm != null &&
          start.isResolved &&
          end.isResolved &&
          !(start.isAxial && start.takeoutMm == null) &&
          !(end.isAxial && end.takeoutMm == null) &&
          start.deductionAt(stops.start) != null &&
          end.deductionAt(stops.end) != null) {
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
      if (cutMm != null) segment = segment._copy(cutMm: cutMm);
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
  if (socketWeldSeen && gap > 0) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.socketWeldWithGap,
      blocking: false,
      pl: 'Końce SW mają już w take-oucie luz 1,6 mm do dna gniazda, a '
          'projekt odejmuje jeszcze szczelinę ${_mmText(gap)} mm na spoinę — '
          'dla samych połączeń SW ustaw szczelinę 0.',
      en: 'Socket-weld ends already include the 1.6 mm socket clearance, and '
          'the project also takes off a ${_mmText(gap)} mm root gap per weld '
          '— set the gap to 0 for socket-weld work.',
    ));
  }

  final geometryIssues = _checkGeometry(
    scan: scan,
    segments: pipeSegments,
    components: components,
    planned: planned,
  );
  for (final issue in geometryIssues) {
    (issue.blocking ? gaps : warnings).add(issue);
  }

  return ScanPlan(
    project: draft,
    segments: _numberBySpool(planned, scan),
    gaps: gaps,
    warnings: warnings,
    auxiliarySegmentCount: auxiliary.length,
    runCount: route.runCount,
  );
}

String _mmText(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Stop a dimension line's end mark (`CL` / `FACE` / `EOP`) means at [e],
/// or null when the mark says nothing unambiguous for that kind of end.
SideStop? _drawingStop(ScanEndpoint e, String? ref) {
  if (ref == null || !e.isResolved || e.isOpenEnd) return null;
  final r = ref.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (e.isAxial) {
    if (r == 'CL' || r == 'WP' || r == 'C') return SideStop.centre;
    if (r == 'EOP' || r == 'FACE' || r == 'END') return SideStop.face;
    return null;
  }
  if (e.isWeldNeckFlange) {
    // A flange's face is its gasket face — through the hub.
    if (r == 'FACE' || r == 'GF') return SideStop.end;
    if (r == 'EOP') return SideStop.face;
    return null;
  }
  if (e.isPhysical && e.tool != 'flange' && e.tool != 'blindFlange') {
    // A butt-weld body (reducer, cap, BW valve): its face is where the pipe
    // is welded on.
    if (r == 'EOP' || r == 'FACE') return SideStop.face;
  }
  return null;
}

String? _spoolOf(AiSegment seg, Map<String, AiComponent> components) {
  if (seg.spoolId != null) return seg.spoolId;
  final a = seg.fromId == null ? null : components[seg.fromId]?.spoolId;
  final b = seg.toId == null ? null : components[seg.toId]?.spoolId;
  if (a != null && (b == null || a == b)) return a;
  if (b != null && a == null) return b;
  return null;
}

/// Orders runs spool by spool (the drawing's spool list first, then first
/// appearance), keeping the walking order inside each spool, and labels
/// them `SPOOL/n` — the numbering a fitter finds on the drawing. Without
/// spools the walking order and plain numbers stay.
List<PlannedSegment> _numberBySpool(
    List<PlannedSegment> planned, AiScanResult scan) {
  final hasSpools = planned.any((s) => s.spoolId != null);
  final display = <String, String>{
    for (final s in scan.spools) s.id: s.display,
  };
  var ordered = planned;
  if (hasSpools) {
    final rank = <String, int>{};
    for (final s in scan.spools) {
      rank.putIfAbsent(s.id, () => rank.length);
    }
    for (final s in planned) {
      final id = s.spoolId;
      if (id != null) rank.putIfAbsent(id, () => rank.length);
    }
    final indexed = [for (var i = 0; i < planned.length; i++) (i, planned[i])];
    indexed.sort((a, b) {
      final ra = a.$2.spoolId == null ? 1 << 30 : rank[a.$2.spoolId]!;
      final rb = b.$2.spoolId == null ? 1 << 30 : rank[b.$2.spoolId]!;
      return ra != rb ? ra.compareTo(rb) : a.$1.compareTo(b.$1);
    });
    ordered = [for (final e in indexed) e.$2];
  }
  final inSpool = <String, int>{};
  final out = <PlannedSegment>[];
  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    final spool = s.spoolId;
    String label;
    if (spool != null) {
      final k = (inSpool[spool] ?? 0) + 1;
      inSpool[spool] = k;
      label = '${display[spool] ?? spool}/$k';
    } else {
      label = '${i + 1}';
    }
    out.add(s.renumbered(
      i + 1,
      label,
      startsNewRun: i > 0 && ordered[i - 1].runIndex != s.runIndex,
    ));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────
// Sizes along the route
// ─────────────────────────────────────────────────────────────────────────

class _Sizes {
  /// DN per segment id; null = not known.
  final Map<String, int?> dn = {};

  /// Where each DN came from, for the review screen.
  final Map<String, String> note = {};

  /// Tee / olet node → DN of its run and of its branch.
  final Map<String, ({int? run, int? branch})> tee = {};

  /// Reducer node → its large-end DN (H is tabulated by the large end).
  final Map<String, int?> reducerLarge = {};

  /// Reducing tees whose branch leg is not known.
  final Set<String> ambiguousTees = {};

  /// True when no reducer / reducing tee / olet splits the route into
  /// runs of different sizes — then the project's size is every run's.
  bool singleZone = true;
}

class _SizeLink {
  final int a;
  final int b;
  final int large;
  final int small;
  final String node;
  const _SizeLink(this.a, this.b, this.large, this.small, this.node);
}

/// Sizes of a size-changing fitting, large first: printed `sizeLarge` /
/// `sizeSmall`, else parsed from its label (`DN100x80`, `4"x3"`).
(int?, int?) _componentSizes(AiComponent c, String notation) {
  int? parse(String? raw) => raw == null ? null : _parseSizeToDn(raw, notation);

  var a = parse(c.sizeLarge);
  var b = parse(c.sizeSmall);
  if (a == null && b == null) {
    final t = (c.label ?? '').toUpperCase().replaceAll(',', '.');
    final dn = RegExp(r'DN\s*(\d{1,4})\s*[X×*]\s*(?:DN\s*)?(\d{1,4})')
        .firstMatch(t);
    if (dn != null) {
      a = _knownDn(int.parse(dn.group(1)!));
      b = _knownDn(int.parse(dn.group(2)!));
    } else {
      const num = r'(\d+(?:\.\d+)?(?:\s+\d+/\d+|/\d+)?)';
      final inch = RegExp('$num\\s*(?:"|”|″)\\s*[X×*]\\s*$num\\s*(?:"|”|″)')
          .firstMatch(t);
      if (inch != null) {
        a = _dnForInches(_parseInches(inch.group(1)!));
        b = _dnForInches(_parseInches(inch.group(2)!));
      }
    }
  }
  if (a != null && b != null && b > a) return (b, a);
  return (a, b);
}

_Sizes _resolveSizes({
  required List<AiSegment> segments,
  required Map<String, AiComponent> components,
  required Map<String, List<int>> incident,
  required Map<String, Map<String, PortRole>> roles,
  required Map<String, Set<String>> assembly,
  required String notation,
  required ScanProjectDraft draft,
  required bool callerGiven,
  required ScanFitterInput fitter,
  required List<ScanIssue> warnings,
}) {
  final out = _Sizes();
  final n = segments.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  // What each run says about its own size.
  int? explicitOf(AiSegment s) {
    final f = fitter.segmentDn[s.id];
    if (f != null && _knownDn(f) != null) return f;
    if (s.dn != null && _knownDn(s.dn) != null) return s.dn;
    final nps = s.nps;
    if (nps != null) {
      return _parseSizeToDn(nps, notation) ?? _parseSizeToDn(nps, 'NPS');
    }
    return null;
  }

  final explicit = [for (final s in segments) explicitOf(s)];
  final fromFitter = [
    for (final s in segments)
      fitter.segmentDn[s.id] != null && _knownDn(fitter.segmentDn[s.id]) != null
  ];
  // Sizes fixed by a fitting on the run (a reducing tee's run / branch, an
  // olet's outlet), with where they come from.
  final fixed = <int, List<(int, String)>>{};
  void fix(int i, int dn, String note) => (fixed[i] ??= []).add((dn, note));
  final links = <_SizeLink>[];
  // Size changes: reducers and reducing tees (either side may be the line's
  // size) and olets (the header is the line, the outlet is not).
  var separators = 0;
  var oletSeparators = 0;
  final oletBranches = <int>{};
  final assumedEqual = <String>[];

  incident.forEach((node, idxs) {
    final c = components[node];
    if (c == null) {
      for (final i in idxs.skip(1)) {
        union(idxs.first, i);
      }
      return;
    }
    final type = normaliseScanType(c.type);
    final what = c.label ?? c.type;
    if (type.contains('reducer')) {
      separators++;
      final (large, small) = _componentSizes(c, notation);
      out.reducerLarge[node] = large;
      if (idxs.length == 2 && large != null && small != null) {
        links.add(_SizeLink(idxs[0], idxs[1], large, small, node));
      }
      return;
    }
    if (isTeeComponent(c)) {
      var (large, small) = _componentSizes(c, notation);
      final r = roles[node];
      final runs = [
        for (final i in idxs)
          if (r?[segments[i].id] == PortRole.run) i
      ];
      final branches = [
        for (final i in idxs)
          if (r?[segments[i].id] == PortRole.branch) i
      ];
      if (r != null) {
        for (final i in runs.skip(1)) {
          union(runs.first, i);
        }
        if (large == null && small == null) {
          // No printed tee size: the runs' own sizes tell a reducing tee.
          final runDn = runs.map((i) => explicit[i]).whereType<int>().toSet();
          final brDn =
              branches.map((i) => explicit[i]).whereType<int>().toSet();
          if (runDn.length == 1 && brDn.length == 1 && runDn != brDn) {
            large = runDn.single;
            small = brDn.single;
          }
        }
        final reducing = large != null && small != null && large != small;
        if (reducing) {
          separators++;
          for (final i in runs) {
            fix(i, large, 'przelot trójnika "$what"');
          }
          for (final i in branches) {
            fix(i, small, 'odgałęzienie trójnika "$what"');
          }
        } else {
          for (final i in branches) {
            if (runs.isNotEmpty) union(runs.first, i);
          }
          if (large != null) {
            for (final i in idxs) {
              fix(i, large, 'trójnik "$what"');
            }
          } else if (branches.isNotEmpty) {
            assumedEqual.add(what);
          }
        }
      } else {
        final reducing = large != null && small != null && large != small;
        if (reducing && idxs.length >= 3) {
          separators++;
          out.ambiguousTees.add(node);
        } else {
          for (final i in idxs.skip(1)) {
            union(idxs.first, i);
          }
          if (large != null) {
            for (final i in idxs) {
              fix(i, large, 'trójnik "$what"');
            }
          } else if (idxs.length >= 3) {
            assumedEqual.add(what);
          }
        }
      }
      return;
    }
    if (isOletComponent(c)) {
      oletSeparators++;
      oletBranches.addAll(idxs);
      final (_, small) = _componentSizes(c, notation);
      if (small != null) {
        for (final i in idxs) {
          fix(i, small, 'wylot oletu "$what"');
        }
      }
      return;
    }
    for (final i in idxs.skip(1)) {
      union(idxs.first, i);
    }
  });

  // Bolted joints carry the size across (a valve between two flanges).
  final seen = <String>{};
  for (final node in assembly.keys) {
    if (seen.contains(node)) continue;
    final group = <String>{node};
    final todo = [node];
    while (todo.isNotEmpty) {
      for (final m in assembly[todo.removeLast()] ?? const <String>{}) {
        if (group.add(m)) todo.add(m);
      }
    }
    seen.addAll(group);
    final idxs = [for (final g in group) ...?incident[g]];
    for (final i in idxs.skip(1)) {
      union(idxs.first, i);
    }
  }

  if (assumedEqual.isNotEmpty) {
    warnings.add(ScanIssue(
      code: ScanIssueCode.teeAssumedEqual,
      blocking: false,
      pl: 'Trójnik bez rozmiaru na rysunku (${assumedEqual.join(', ')}) — '
          'przyjęto równoprzelotowy: odgałęzienie M = C. Jeśli jest '
          'redukcyjny, ustaw DN odgałęzienia.',
      en: 'Tee with no printed size (${assumedEqual.join(', ')}) — taken as '
          'an equal tee: branch M = C. If it is reducing, set the branch DN.',
    ));
  }

  // ── Zones ────────────────────────────────────────────────────────────
  final zoneDn = <int, int?>{};
  final zoneNote = <int, String>{};
  final conflicted = <int>{};
  final roots = {for (var i = 0; i < n; i++) find(i)};
  out.singleZone =
      roots.length <= 1 || (separators == 0 && oletSeparators == 0);

  for (final root in roots) {
    final members = [for (var i = 0; i < n; i++) if (find(i) == root) i];
    final fitterVals = {
      for (final i in members)
        if (fromFitter[i]) explicit[i]!
    };
    if (fitterVals.isNotEmpty) {
      zoneDn[root] = fitterVals.first;
      zoneNote[root] = 'podane przez montera';
      continue;
    }
    final values = <int, String>{};
    for (final i in members) {
      final e = explicit[i];
      if (e != null) values.putIfAbsent(e, () => 'z rysunku (odcinek)');
      for (final (dn, note) in fixed[i] ?? const <(int, String)>[]) {
        values.putIfAbsent(dn, () => note);
      }
    }
    if (values.length == 1) {
      zoneDn[root] = values.keys.single;
      zoneNote[root] = values.values.single;
    } else if (values.length > 1) {
      conflicted.add(root);
      final ids = members.map((i) => segments[i].id).join(', ');
      final list = values.keys.map((d) => 'DN$d').join(' / ');
      warnings.add(ScanIssue(
        code: ScanIssueCode.diameterConflict,
        blocking: false,
        pl: 'Sprzeczne średnice na jednym ciągu ($ids): $list — każdy odcinek '
            'dostaje swój odczyt, sprawdź na rysunku.',
        en: 'Conflicting sizes on one run ($ids): $list — each segment keeps '
            'its own reading; check the drawing.',
      ));
    }
  }

  if (out.singleZone) {
    // One size everywhere: the project's — the fitter's own value wins over
    // the drawing, as for the header.
    final root = roots.isEmpty ? null : roots.first;
    final read = root == null ? null : zoneDn[root];
    final fitterSet = root != null && zoneNote[root] == 'podane przez montera';
    int? dn;
    String? note;
    if (fitterSet) {
      dn = read;
      note = zoneNote[root];
    } else if (callerGiven || read == null) {
      dn = draft.dn;
      note = draft.dn == null ? null : 'średnica projektu';
      if (read != null && draft.dn != null && read != draft.dn) {
        warnings.add(ScanIssue(
          code: ScanIssueCode.diameterConflict,
          blocking: false,
          pl: 'Rysunek przy odcinkach podaje DN$read, a projekt ma '
              'DN${draft.dn} — liczę dla DN${draft.dn}.',
          en: 'The drawing marks the runs DN$read while the project is '
              'DN${draft.dn} — computing for DN${draft.dn}.',
        ));
      }
    } else {
      dn = read;
      note = root == null ? null : zoneNote[root];
    }
    for (var i = 0; i < n; i++) {
      out.dn[segments[i].id] =
          conflicted.contains(find(i)) ? explicit[i] : dn;
      if (note != null) out.note[segments[i].id] = note;
    }
  } else {
    if (separators == 0) {
      // Only olets split the route: every zone that is not an olet's outlet
      // is the header the olets sit on — the line, the project's size.
      for (final root in roots) {
        if (zoneDn[root] != null || conflicted.contains(root)) continue;
        final header = [
          for (var i = 0; i < n; i++)
            if (find(i) == root && !oletBranches.contains(i)) i
        ];
        if (header.isNotEmpty && draft.dn != null) {
          zoneDn[root] = draft.dn;
          zoneNote[root] = 'średnica projektu (rura główna)';
        }
      }
    }
    // Carry sizes through reducers until nothing changes.
    var changed = true;
    final mismatched = <String>{};
    while (changed) {
      changed = false;
      for (final l in links) {
        final ra = find(l.a);
        final rb = find(l.b);
        if (ra == rb) continue;
        for (final (from, to) in [(ra, rb), (rb, ra)]) {
          final known = zoneDn[from];
          if (known == null || zoneDn[to] != null) continue;
          final c = components[l.node];
          final what = c?.label ?? c?.type ?? l.node;
          if (known == l.large) {
            zoneDn[to] = l.small;
          } else if (known == l.small) {
            zoneDn[to] = l.large;
          } else {
            if (mismatched.add(l.node)) {
              warnings.add(ScanIssue(
                code: ScanIssueCode.diameterConflict,
                blocking: false,
                componentId: l.node,
                pl: 'Redukcja "$what" (DN${l.large}×${l.small}) nie pasuje do '
                    'DN$known odcinka przy niej — sprawdź rysunek.',
                en: 'Reducer "$what" (DN${l.large}×${l.small}) does not fit '
                    'the DN$known run at it — check the drawing.',
              ));
            }
            continue;
          }
          zoneNote[to] = 'za redukcją "$what" DN${l.large}×${l.small}';
          changed = true;
        }
      }
    }
    for (var i = 0; i < n; i++) {
      final root = find(i);
      final id = segments[i].id;
      out.dn[id] = conflicted.contains(root) ? explicit[i] : zoneDn[root];
      final note = conflicted.contains(root)
          ? (explicit[i] != null ? 'z rysunku (odcinek)' : null)
          : zoneNote[root];
      if (note != null) out.note[id] = note;
    }
  }

  // Tee run / branch sizes and reducer large ends, from the runs' sizes.
  incident.forEach((node, idxs) {
    final c = components[node];
    if (c == null) return;
    if (isTeeComponent(c) || isOletComponent(c)) {
      final r = roles[node];
      final (large, small) = _componentSizes(c, notation);
      int? runDn;
      int? branchDn;
      for (final i in idxs) {
        final role = r?[segments[i].id];
        final d = out.dn[segments[i].id];
        if (role == PortRole.run) runDn ??= d;
        if (role == PortRole.branch) branchDn ??= d;
      }
      if (r == null && !out.ambiguousTees.contains(node)) {
        // Equal (or assumed equal) tee with unknown roles: one size.
        for (final i in idxs) {
          runDn ??= out.dn[segments[i].id];
        }
      }
      out.tee[node] = (run: runDn ?? large, branch: branchDn ?? small);
    } else if (normaliseScanType(c.type).contains('reducer')) {
      if (out.reducerLarge[node] == null && idxs.length == 2) {
        final a = out.dn[segments[idxs[0]].id];
        final b = out.dn[segments[idxs[1]].id];
        if (a != null && b != null && a != b) {
          out.reducerLarge[node] = a > b ? a : b;
        }
      }
    }
  });

  return out;
}

/// OD and wall of one run.
({double? od, double? wall}) _sizeColumns({
  required AiSegment seg,
  required int? dn,
  required bool singleZone,
  required ScanProjectDraft draft,
  required ScanFitterInput fitter,
}) {
  final fitterWall = fitter.segmentWallMm[seg.id];
  final ownSchedule = _normaliseSchedule(seg.schedule);
  double? tableWall(int? d, String? schedule) {
    if (d == null || schedule == null) return null;
    return _rowForDn(d)?.walls[schedule];
  }

  if (singleZone || (dn != null && dn == draft.dn)) {
    // The project's own size: its OD (the fitter's value when he gave one)
    // and wall, unless this run prints its own schedule.
    final od = draft.diameterMm ??
        (dn == null ? null : _rowForDn(dn)?.od);
    final wall = fitterWall ??
        tableWall(dn ?? draft.dn, ownSchedule) ??
        draft.wallThicknessMm;
    return (od: od, wall: wall);
  }
  if (dn == null) return (od: null, wall: fitterWall);
  final row = _rowForDn(dn);
  return (
    od: row?.od,
    wall: fitterWall ?? tableWall(dn, ownSchedule ?? draft.schedule),
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
    startMm: startMm,
    endStop: stops.end,
    endMm: endMm,
  );
}

/// Deductions go into the row at 0.1 mm — the B16.11 socket take-outs are
/// tabulated to half a millimetre (A 22.5 + 1.6 clearance = 24.1), and the
/// B16.9 / B16.5 / B16.10 values are whole numbers, which this leaves alone.
double? _roundOrNull(double? v) =>
    v == null ? null : (v * 10).roundToDouble() / 10;

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

// ─────────────────────────────────────────────────────────────────────────
// Geometry checks (offsets, elbow angles, closure)
// ─────────────────────────────────────────────────────────────────────────

/// Checks the drawing against itself in 3D:
///
///   * a run not along an axis is an offset — said out loud, with its
///     projections, so the fitter knows the length is a skew length;
///   * the bend at every elbow, from the directions of its two runs, must be
///     the elbow's angle — a "45°" elbow in a 38° offset would take the
///     wrong take-out, so both runs are blocked until the fitter types the
///     take-out himself;
///   * the chain of runs placed end to end must close: against itself (a
///     loop), against the overall dimensions and against the elevation
///     marks — a mismatch is a warning with both numbers.
///
/// Positions are taken at the points the dimensions run between (work
/// points for centreline dimensions), so a chain dimensioned to faces can
/// be off by a body length: the closure checks warn, never block.
List<ScanIssue> _checkGeometry({
  required AiScanResult scan,
  required List<AiSegment> segments,
  required Map<String, AiComponent> components,
  required List<PlannedSegment> planned,
}) {
  final out = <ScanIssue>[];
  final plannedById = {for (final p in planned) p.sourceId: p};

  // ── Offsets ──────────────────────────────────────────────────────────
  for (final s in segments) {
    final v = segmentVector(s);
    if (v == null || v.isAxial) continue;
    final p = plannedById[s.id];
    final rolling = [v.x, v.y, v.z].where((c) => c.abs() > 1e-6).length == 3;
    final kindPl = rolling ? 'rolling offset (skos w dwóch płaszczyznach)' : 'offset';
    final kindEn = rolling ? 'rolling offset' : 'offset';
    final len = p?.isoMm;
    out.add(ScanIssue(
      code: ScanIssueCode.offsetInRoute,
      blocking: false,
      segmentId: s.id,
      pl: 'Odcinek ${p?.label ?? s.id} to $kindPl'
          '${len == null ? '' : ' — długość skośna ${_mmText(len)} mm'}'
          '${s.projections.isEmpty ? '' : ' (rzuty: ${_projText(s.projections)})'}.',
      en: 'Run ${p?.label ?? s.id} is a $kindEn'
          '${len == null ? '' : ' — travel ${_mmText(len)} mm'}'
          '${s.projections.isEmpty ? '' : ' (projections: ${_projText(s.projections)})'}.',
    ));
  }

  // ── Elbow angles ─────────────────────────────────────────────────────
  final incident = <String, List<AiSegment>>{};
  for (final s in segments) {
    for (final id in {s.fromId, s.toId}) {
      if (id == null || id.isEmpty) continue;
      (incident[id] ??= []).add(s);
    }
  }
  incident.forEach((node, segs) {
    final c = components[node];
    if (c == null || segs.length != 2) return;
    final type = normaliseScanType(c.type);
    final double expected;
    if (c.angleDeg != null && c.angleDeg! > 0 && c.angleDeg! <= 90) {
      expected = c.angleDeg!;
    } else if (type == 'elbow90' || type == 'elbow') {
      expected = 90;
    } else if (type == 'elbow45') {
      expected = 45;
    } else {
      return;
    }
    final a = outwardAt(segs[0], node);
    final b = outwardAt(segs[1], node);
    if (a == null || b == null) return;
    // Outward vectors 180° apart = straight through; bend = 180 − angle.
    final bend = 180 - bendAngleDeg(a, b);
    if (!bend.isFinite || (bend - expected).abs() <= kAngleToleranceDeg) return;
    for (final s in segs) {
      final p = plannedById[s.id];
      final end = p == null
          ? null
          : (p.start.componentId == node ? p.start : p.end);
      if (end?.fromFitter == true) continue;
      out.add(ScanIssue(
        code: ScanIssueCode.elbowAngleMismatch,
        blocking: true,
        segmentId: s.id,
        componentId: node,
        pl: 'Kolano ${c.label ?? node}: kierunki odcinków dają łuk '
            '${bend.toStringAsFixed(1)}°, a kolano ma ${_mmText(expected)}° — '
            'take-out byłby zły. Sprawdź rysunek albo wpisz take-out kolana.',
        en: 'Elbow ${c.label ?? node}: the run directions bend '
            '${bend.toStringAsFixed(1)}° but the elbow is '
            '${_mmText(expected)}° — its take-out would be wrong. Check the '
            'drawing or enter the elbow take-out.',
      ));
    }
  });

  // ── Closure ──────────────────────────────────────────────────────────
  // Place the points the runs join, run by run, from the first one.
  final pos = <String, Vec3>{};
  final cluster = <String, int>{};
  final placed = <AiSegment>[];
  for (final s in segments) {
    final v = _displacement(s, plannedById[s.id]);
    if (v != null && s.fromId != null && s.toId != null) placed.add(s);
  }
  var clusters = 0;
  final loopReported = <String>{};
  for (final seed in placed) {
    if (pos.containsKey(seed.fromId)) continue;
    pos[seed.fromId!] = Vec3.zero;
    cluster[seed.fromId!] = clusters;
    final todo = [seed.fromId!];
    while (todo.isNotEmpty) {
      final node = todo.removeLast();
      for (final s in placed) {
        final v = _displacement(s, plannedById[s.id])!;
        String? other;
        Vec3? at;
        if (s.fromId == node) {
          other = s.toId;
          at = pos[node]! + v;
        } else if (s.toId == node) {
          other = s.fromId;
          at = pos[node]! - v;
        }
        if (other == null || at == null) continue;
        final known = pos[other];
        if (known == null) {
          pos[other] = at;
          cluster[other] = clusters;
          todo.add(other);
        } else if ((known - at).length > kClosureToleranceMm &&
            loopReported.add(s.id)) {
          out.add(ScanIssue(
            code: ScanIssueCode.closureMismatch,
            blocking: false,
            segmentId: s.id,
            pl: 'Pętla wymiarów nie zamyka się przy odcinku '
                '${plannedById[s.id]?.label ?? s.id}: rozbieżność '
                '${_mmText((known - at).length)} mm — sprawdź wymiary pętli.',
            en: 'The dimension loop does not close at run '
                '${plannedById[s.id]?.label ?? s.id}: off by '
                '${_mmText((known - at).length)} mm — check the loop.',
          ));
        }
      }
    }
    clusters++;
  }

  for (final d in scan.overallDimensions) {
    final a = pos[d.fromId];
    final b = pos[d.toId];
    final value = d.valueMm;
    if (a == null || b == null || value == null) continue;
    if (cluster[d.fromId] != cluster[d.toId]) continue;
    final diff = b - a;
    final measured = d.axis == null ? diff.length : diff.along(d.axis!)?.abs();
    if (measured == null) continue;
    if ((measured - value).abs() <= kClosureToleranceMm) continue;
    out.add(ScanIssue(
      code: ScanIssueCode.closureMismatch,
      blocking: false,
      pl: 'Wymiar całkowity ${d.raw ?? _mmText(value)} (${d.fromId} → '
          '${d.toId}${d.axis == null ? '' : ', oś ${d.axis}'}) ≠ suma '
          'wymiarów odcinków ${_mmText(measured)} mm — różnica '
          '${_mmText((measured - value).abs())} mm. Sprawdź łańcuch wymiarów.',
      en: 'Overall dimension ${d.raw ?? _mmText(value)} (${d.fromId} → '
          '${d.toId}${d.axis == null ? '' : ', axis ${d.axis}'}) ≠ sum of the '
          'runs ${_mmText(measured)} mm — off by '
          '${_mmText((measured - value).abs())} mm. Check the chain.',
    ));
  }

  final elevations = <(String, double)>[
    for (final e in scan.elevationPoints)
      if (pos.containsKey(e.atId) &&
          (e.elevationMm ?? parseElevationMm(e.value)) != null)
        (e.atId, e.elevationMm ?? parseElevationMm(e.value)!),
  ];
  for (var i = 1; i < elevations.length; i++) {
    final (a, elA) = elevations[0];
    final (b, elB) = elevations[i];
    if (cluster[a] != cluster[b]) continue;
    final dz = pos[b]!.z - pos[a]!.z;
    final dEl = elB - elA;
    if ((dz - dEl).abs() <= kClosureToleranceMm) continue;
    out.add(ScanIssue(
      code: ScanIssueCode.closureMismatch,
      blocking: false,
      componentId: b,
      pl: 'Rzędne: $a → $b różnią się o ${_mmText(dEl)} mm, a wymiary '
          'pionowe odcinków dają ${_mmText(dz)} mm. Sprawdź wymiary pionowe '
          'i rzędne EL.',
      en: 'Elevations: $a → $b differ by ${_mmText(dEl)} mm, the vertical '
          'runs add up to ${_mmText(dz)} mm. Check the vertical dimensions '
          'and the EL marks.',
    ));
  }
  return out;
}

/// The run as a displacement between the points it joins: its projections
/// when printed, else its direction × its dimension.
Vec3? _displacement(AiSegment s, PlannedSegment? p) {
  final proj = projectionVector(s.projections);
  if (proj != null) return proj;
  final dir = directionVector(s.direction);
  final len = p?.isoMm ?? s.dimensionMm;
  if (dir == null || len == null) return null;
  return dir * len;
}

String _projText(Map<String, double> projections) => projections.entries
    .map((e) => '${e.key} ${_mmText(e.value)}')
    .join(', ');

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
  'elbow': 'elbow90',
  'tee': 'tee',
  'reducingtee': 'tee',
  'redtee': 'tee',
  'olet': 'olet',
  'weldolet': 'olet',
  'sockolet': 'olet',
  'thredolet': 'olet',
  'threadolet': 'olet',
  'elbolet': 'olet',
  'latrolet': 'olet',
  'nipolet': 'olet',
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

String _normaliseType(String raw) => normaliseScanType(raw);

/// Tool name ([ComponentClassification] vocabulary) of a scanned component,
/// or null when the type is not one the planner knows. Public for the
/// outputs (BOM comparison, weld map).
String? scanToolName(AiComponent c) {
  final n = _normaliseType(c.type);
  final tool = _typeAliases[n];
  if (tool == 'flange' && c.flangeType == 'BL') return 'blindFlange';
  if (tool != null) return tool;
  if (n == 'valve' || n.endsWith('valve')) {
    return _valveToolName(c.valveType ?? c.type).tool;
  }
  return null;
}

/// A size callout read into a DN — the planner's own parser, public for the
/// outputs. Null when ambiguous (a bare number on an unknown notation).
int? scanSizeToDn(String? raw, String sizeNotation) =>
    _parseSizeToDn(raw, sizeNotation);

/// Sizes of a size-changing fitting, large first (printed, else from its
/// label). Public for the outputs.
(int?, int?) scanComponentSizes(AiComponent c, String sizeNotation) =>
    _componentSizes(c, sizeNotation);

/// End connection code (`BW` / `SW` / `THD` / `FL`) of a component.
String scanEndType(AiComponent c) => _endTypeOf(c);

/// Whether a flange is slip-on-like (SO / SW / LJ / threaded).
bool scanIsSlipOnFlange(AiComponent c) => _isSlipOnLike(c);

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

/// What one end of one run knows about its surroundings.
class _EndCtx {
  /// DN of the run this end belongs to.
  final int? dn;

  /// Role of the run at a tee / olet.
  final PortRole? role;

  /// Tee / olet: the run (header) size; reducer: its large end.
  final int? runDn;

  /// Tee / olet: the branch (outlet) size.
  final int? branchDn;

  /// Take-out / body length the fitter typed in for this end.
  final double? fitterMm;

  const _EndCtx({
    this.dn,
    this.role,
    this.runDn,
    this.branchDn,
    this.fitterMm,
  });
}

ScanEndpoint _endpoint(
  String? componentId, {
  required Map<String, AiComponent> components,
  required _EndCtx ctx,
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
  // A flange read as "blind" by its type letters is a blind flange.
  if (tool == 'flange' && component.flangeType == 'BL') tool = 'blindFlange';

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

  if (!subtypeKnown && ctx.fitterMm == null) {
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
    final large = ctx.runDn;
    warnings.add(ScanIssue(
      code: ScanIssueCode.reducerChangesDiameter,
      blocking: false,
      componentId: componentId,
      pl: 'Redukcja w trasie${large == null ? '' : ' (duży koniec DN$large)'} '
          '— za nią zmienia się średnica; każdy odcinek ma swoją DN.',
      en: 'Reducer in the route${large == null ? '' : ' (large end DN$large)'} '
          '— the size changes past it; every run carries its own DN.',
    ));
  }

  if (tool == 'elbow90' || tool == 'elbow45') {
    final a = component.angleDeg;
    final nominal = tool == 'elbow90' ? 90.0 : 45.0;
    if (a != null && (a - nominal).abs() > kAngleToleranceDeg && a > 0 && a < 90) {
      warnings.add(ScanIssue(
        code: ScanIssueCode.cutElbow,
        blocking: false,
        segmentId: segmentId,
        componentId: componentId,
        pl: 'Kolano ${component.label ?? componentId} pod kątem '
            '${a.toStringAsFixed(0)}° — take-out z segmentu kolana 90° '
            '(ASME B16.9 §6.2.4: A × tan(θ/2)); sprawdź, czy to kolano cięte.',
        en: 'Elbow ${component.label ?? componentId} at '
            '${a.toStringAsFixed(0)}° — take-out from a segment of a 90° '
            'elbow (ASME B16.9 §6.2.4: A × tan(θ/2)); check it is a cut elbow.',
      ));
    }
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
  String? missingPl;
  String? missingEn;
  var fromFitter = false;
  if (kind == ScanEndKind.axial) {
    if (ctx.fitterMm != null) {
      takeoutMm = ctx.fitterMm;
      takeoutNote = 'wpisane przez montera';
      fromFitter = true;
    } else {
      final t = _axialTakeout(
        tool!,
        ctx,
        component,
        assumedLongRadius: assumedLongRadius,
      );
      takeoutMm = t.mm;
      takeoutNote = t.note;
      missingPl = t.missingPl;
      missingEn = t.missingEn;
    }
  } else {
    // A face or a zero-length marker adds nothing to the dimensioned span.
    takeoutMm = 0;
  }

  // A valve of unknown type gets NO face-to-face: the group's behaviour is
  // the same for all of them, but a gate valve's body is not a check
  // valve's, and borrowing one for the other is exactly the invented number
  // this layer exists to prevent.
  _Takeout? body;
  if (behaviour.hasPhysicalBody) {
    if (ctx.fitterMm != null) {
      body = _Takeout(ctx.fitterMm!, 'wpisane przez montera');
      fromFitter = true;
    } else if (subtypeKnown) {
      body = _bodyLength(
        tool!,
        tool == 'reducer' ? ctx.runDn : ctx.dn,
        component.rating ?? pipeClass,
        component: component,
      );
    }
  }

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
    role: ctx.role,
    missingPl: missingPl,
    missingEn: missingEn,
    fromFitter: fromFitter,
  );
}

class _Takeout {
  final double mm;
  final String note;
  const _Takeout(this.mm, this.note);
}

/// A take-out, or why there is none.
class _AxialTakeout {
  final double? mm;
  final String? note;
  final String? missingPl;
  final String? missingEn;
  const _AxialTakeout.value(double this.mm, String this.note)
      : missingPl = null,
        missingEn = null;
  const _AxialTakeout.missing([this.missingPl, this.missingEn])
      : mm = null,
        note = null;
}

/// End connection of a fitting: `BW`, `SW`, `THD` or `FL` — printed, else
/// from its marking.
String _endTypeOf(AiComponent c) {
  final e = c.endType?.toUpperCase();
  if (e != null) {
    if (e.startsWith('SW') || e.contains('SOCKET')) return 'SW';
    if (e.startsWith('TH') || e == 'NPT' || e.startsWith('SCR')) return 'THD';
    if (e.startsWith('FL')) return 'FL';
    return 'BW';
  }
  final m = '${c.label ?? ''} ${c.type}'.toUpperCase();
  if (RegExp(r'\bSW\b|SOCKET|\bS\.W\.').hasMatch(m)) return 'SW';
  if (RegExp(r'\b(THD|THRD|NPT|SCRD|SCREWED|THREADED)\b').hasMatch(m)) {
    return 'THD';
  }
  return 'BW';
}

/// Pressure class of a forged (SW / threaded) fitting: 3000 / 6000 / 9000,
/// printed or in its marking; null when not stated.
int? _forgedClassOf(AiComponent c) {
  final text = '${c.rating ?? ''} ${c.label ?? ''}';
  final m = RegExp(r'(?<!\d)(3000|6000|9000)(?!\d)').firstMatch(text);
  return m == null ? null : int.parse(m.group(1)!);
}

String _n1(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Centre-to-end for an axial fitting, from the ASME tables the app ships.
/// Never a filler number: when the size, the class or the table entry is
/// not known, the result says why and the cut stays blocked.
_AxialTakeout _axialTakeout(
  String tool,
  _EndCtx ctx,
  AiComponent component, {
  required Set<String> assumedLongRadius,
}) {
  final dn = ctx.dn;
  final endType = _endTypeOf(component);

  if (tool == 'olet') {
    return const _AxialTakeout.missing(
      'wysokość oletu zależy od producenta (MSS SP-97 jej nie normuje) — '
          'wpisz take-out: oś rury głównej → koniec oletu.',
      'the height of an olet is the manufacturer\'s (MSS SP-97 does not '
          'standardise it) — enter the take-out: header centreline → olet end.',
    );
  }
  if (endType == 'THD') {
    return const _AxialTakeout.missing(
      'połączenie gwintowane — wkręcenie rury zależy od gwintu i momentu, '
          'tabela tego nie poda. Wpisz take-out (oś → koniec rury).',
      'threaded joint — thread engagement depends on the thread and the '
          'make-up, no table gives it. Enter the take-out (centre → pipe end).',
    );
  }

  if (endType == 'SW' && (tool == 'elbow90' || tool == 'elbow45' || tool == 'tee')) {
    final size = tool == 'tee' ? (ctx.runDn ?? dn) : dn;
    if (size == null) return const _AxialTakeout.missing();
    final is45 = tool == 'elbow45';
    final t3000 = is45
        ? TakeoutCatalog.socketWeld45C3000[size]
        : TakeoutCatalog.socketWeld90A3000[size];
    final t6000 = is45
        ? TakeoutCatalog.socketWeld45C6000[size]
        : TakeoutCatalog.socketWeld90A6000[size];
    final cls = _forgedClassOf(component);
    final a = cls == 3000 ? t3000 : (cls == 6000 ? t6000 : null);
    const gapMm = TakeoutCatalog.socketWeldGapMm;
    if (a == null) {
      final known = [
        if (t3000 != null) 'kl. 3000: ${_n1(t3000 + gapMm)} mm',
        if (t6000 != null) 'kl. 6000: ${_n1(t6000 + gapMm)} mm',
      ].join(', ');
      final knownEn = known.replaceAll('kl.', 'Cl.');
      return _AxialTakeout.missing(
        cls == null
            ? 'kształtka SW bez klasy na rysunku — ASME B16.11 (A + luz '
                '1,6 mm): $known. Wpisz take-out dla swojej klasy.'
            : 'kształtka SW kl. $cls DN$size — brak w tabeli B16.11 tej '
                'aplikacji. Wpisz take-out.',
        cls == null
            ? 'socket-weld fitting with no class on the drawing — ASME B16.11 '
                '(A + 1.6 mm clearance): $knownEn. Enter the take-out for '
                'your class.'
            : 'socket-weld fitting Cl.$cls DN$size — not in this app\'s '
                'B16.11 table. Enter the take-out.',
      );
    }
    final letter = is45 ? 'C' : 'A';
    return _AxialTakeout.value(
      a + gapMm,
      'ASME B16.11 kl.$cls · SW · $letter ${_n1(a)} + luz ${_n1(gapMm)} · '
          'DN$size',
    );
  }

  if (dn == null) return const _AxialTakeout.missing();
  switch (tool) {
    case 'elbow90':
    case 'elbow45':
      final marking =
          '${component.label ?? ''} ${component.type}'.toUpperCase();
      final isShort =
          RegExp(r'\bSR\b').hasMatch(marking) || marking.contains('SHORT');
      final angle = component.angleDeg;
      final nominal = tool == 'elbow90' ? 90.0 : 45.0;
      if (angle != null &&
          angle > 0 &&
          angle < 90 &&
          (angle - nominal).abs() > kAngleToleranceDeg) {
        final r = b169ElbowTakeout(
          dn: dn,
          type: isShort ? ElbowRadiusType.short1D : ElbowRadiusType.long15D,
          angleDeg: angle,
        );
        if (r == null) return const _AxialTakeout.missing();
        return _AxialTakeout.value(
          (r.mm * 10).roundToDouble() / 10,
          'ASME B16.9 §6.2.4 · ${isShort ? 'SR' : 'LR'} A ${r.a90Mm} × '
              'tan(${_n1(angle)}°/2) · DN$dn',
        );
      }
      if (tool == 'elbow45') {
        final v = TakeoutCatalog.elbow45LR[dn];
        return v == null
            ? const _AxialTakeout.missing()
            : _AxialTakeout.value(
                v.toDouble(), 'ASME B16.9 · 45° LR · DN$dn');
      }
      if (isShort) {
        final sr = TakeoutCatalog.elbow90SR[dn];
        return sr == null
            ? const _AxialTakeout.missing()
            : _AxialTakeout.value(
                sr.toDouble(), 'ASME B16.9 tab. 6.1-4 · 90° SR · DN$dn');
      }
      final lr = TakeoutCatalog.elbow90LR[dn];
      if (lr == null) return const _AxialTakeout.missing();
      // Long radius is the process-piping default, but it IS a default — the
      // plan says so out loud instead of hiding it.
      assumedLongRadius.add(component.id);
      return _AxialTakeout.value(lr.toDouble(), 'ASME B16.9 · 90° LR · DN$dn');
    case 'tee':
      final run = ctx.runDn ?? dn;
      final branch = ctx.branchDn;
      if (ctx.role == PortRole.branch && branch != null && branch != run) {
        final m = TakeoutCatalog.reducingTeeOutletM[run]?[branch];
        if (m == null) {
          return _AxialTakeout.missing(
            'trójnik redukcyjny DN$run×$branch — brak wymiaru M w tabeli '
                'ASME B16.9 tej aplikacji. Wpisz take-out odgałęzienia '
                '(oś przelotu → koniec odgałęzienia).',
            'reducing tee DN$run×$branch — no M in this app\'s ASME B16.9 '
                'table. Enter the branch take-out (run centreline → branch '
                'end).',
          );
        }
        return _AxialTakeout.value(m.toDouble(),
            'ASME B16.9 tab. 6.1-7 · trójnik red. M · DN$run×$branch');
      }
      final v = TakeoutCatalog.tee[run];
      return v == null
          ? const _AxialTakeout.missing()
          : _AxialTakeout.value(v.toDouble(), 'ASME B16.9 · tee · DN$run');
    default:
      return const _AxialTakeout.missing();
  }
}

/// Slip-on / socket / lap / threaded flanges swallow the pipe: their
/// set-back is not a catalogue length and their sealing face is not where a
/// weld-neck's Y would put it.
bool _isSlipOnLike(AiComponent component) {
  final t = component.flangeType;
  if (t != null) {
    return t == 'SO' || t == 'SW' || t == 'LJ' || t == 'THD' || t == 'TH';
  }
  final marking = '${component.label ?? ''} ${component.type}'.toUpperCase();
  return RegExp(r'\b(SO|SW|LJ|THD|THRD)\b|SLIP|SOCKET|LAP|THREAD')
      .hasMatch(marking);
}

/// Body length along the run, only where a standard gives one unambiguously.
///
/// Flanges and valves are listed per pressure class, so they resolve only
/// when the component or the title block actually says Class 150 — guessing
/// a class would change the cut by tens of millimetres.
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
    // A v2 reading prints the size next to the runs; with nothing in the
    // title block or the BOM, the first sized run is the line's size.
    if (dn == null) {
      for (final s in scan.segments) {
        if (s.auxiliary) continue;
        final d = _knownDn(s.dn);
        if (d != null) {
          dn = d;
          break;
        }
      }
    }
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
    lineNo: _clean(tb.lineNumber),
    isoNo: _clean(tb.drawingNumber),
    isoRev: _clean(tb.revision),
    spec: _clean(tb.pipeClass),
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

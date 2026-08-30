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

  /// The model was unsure about a dimension.
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

  /// Centre-to-end (take-out) in mm for an axial fitting; `0` for an end the
  /// dimension stops at (a face, an open end, a weld). Null means "not known
  /// yet" and blocks the cut.
  final double? takeoutMm;

  /// Face-to-face body length in mm, when a dimensional standard gives one
  /// unambiguously. Only needed if the user later re-references the
  /// dimension to the far END of the component.
  final double? bodyLengthMm;

  /// Where [takeoutMm] came from, e.g. `ASME B16.9 · 90° LR · DN100`.
  final String? takeoutNote;

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
    this.takeoutMm,
    this.bodyLengthMm,
    this.takeoutNote,
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

  /// Value for `segments.start_value_mm` / `segments.end_value_mm`, matching
  /// [isoRefCode]. Null when the end is unresolved.
  double? get offsetMm {
    if (!isResolved) return null;
    return isAxial ? takeoutMm : 0;
  }

  /// Reference point code the segment builder writes into `segments.iso_ref`.
  /// Axial fittings are dimensioned to their axis, everything else to the
  /// near face.
  String get isoRefCode => isAxial ? 'AXIS' : 'FACE_NEAR';
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

  /// How the dimension was measured, when it follows from the two ends
  /// alone. Null means the user has to confirm it — see
  /// [ScanIssueCode.dimensionReferenceUnknown].
  final DimRef? dimRef;

  /// Best guess to preselect in the picker, always set.
  final DimRef proposedDimRef;

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

  const PlannedSegment({
    required this.sourceId,
    required this.seqNo,
    required this.start,
    required this.end,
    required this.proposedDimRef,
    this.isoExpr,
    this.isoMm,
    this.dimRef,
    this.cutMm,
    this.confidence = AiConfidence.unknown,
    this.startsNewRun = false,
    this.isBranch = false,
  });

  /// Copy with a resolved dimension reference and the cut that follows from
  /// it. Used by the screen once the fitter answers a
  /// [ScanIssueCode.dimensionReferenceUnknown] gap.
  PlannedSegment withDimRef(DimRef ref) {
    return PlannedSegment(
      sourceId: sourceId,
      seqNo: seqNo,
      start: start,
      end: end,
      isoExpr: isoExpr,
      isoMm: isoMm,
      dimRef: ref,
      proposedDimRef: proposedDimRef,
      cutMm: cutMmForSegment(this, ref),
      confidence: confidence,
      startsNewRun: startsNewRun,
      isBranch: isBranch,
    );
  }

  /// Whether the user still has to say how the dimension was measured.
  bool get needsDimRefConfirmation => dimRef == null;

  /// Whether every column `segments` needs is known.
  bool get isComplete =>
      isoMm != null &&
      cutMm != null &&
      start.offsetMm != null &&
      end.offsetMm != null;

  /// Value for `segments.iso_ref`, in the `START|END` encoding the segment
  /// builder writes.
  String get isoRefCode => '${start.isoRefCode}|${end.isoRefCode}';
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
}) {
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
    if (seg.confidence == AiConfidence.low ||
        seg.confidence == AiConfidence.unknown) {
      warnings.add(ScanIssue(
        code: ScanIssueCode.lowConfidence,
        blocking: false,
        segmentId: segmentId,
        dimensionLabel: dimensionLabel,
        pl: 'Niepewny odczyt wymiaru ${dimensionLabel ?? "(brak)"} — '
            'sprawdź na rysunku.',
        en: 'Low-confidence reading of ${dimensionLabel ?? "(none)"} — '
            'check it against the drawing.',
      ));
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
    final proposed = _proposeDimRef(start, end);
    final dimRef = needsPicker ? null : proposed;

    if (needsPicker) {
      gaps.add(ScanIssue(
        code: ScanIssueCode.dimensionReferenceUnknown,
        blocking: true,
        segmentId: segmentId,
        dimensionLabel: dimensionLabel,
        pl: 'Potwierdź, jak zmierzono wymiar ${dimensionLabel ?? ""} '
            '(propozycja: ${proposed.labelPl}) — na końcu segmentu jest '
            'element o własnej długości.',
        en: 'Confirm how ${dimensionLabel ?? "this dimension"} was measured '
            '(suggested: ${proposed.labelEn}) — the segment ends on a '
            'component with a body of its own.',
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
      dimRef: dimRef,
      proposedDimRef: proposed,
      confidence: seg.confidence,
      startsNewRun: position > 0 && route.runStarts.contains(position),
      isBranch: _touchesBranch(seg, route.branchNodes),
    );

    if (dimRef != null) {
      final cutMm = cutMmForSegment(segment, dimRef);
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
        dimRef: segment.dimRef,
        proposedDimRef: segment.proposedDimRef,
        cutMm: cutMm,
        confidence: segment.confidence,
        startsNewRun: segment.startsNewRun,
        isBranch: segment.isBranch,
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
/// input [PrefabEngine] needs is not known.
///
/// Public because the screen calls it again after the fitter answers a
/// [ScanIssueCode.dimensionReferenceUnknown] gap: the plan itself never
/// picks a reference it cannot derive.
double? cutMmForSegment(PlannedSegment segment, DimRef ref) {
  final iso = segment.isoMm;
  if (iso == null || !iso.isFinite || iso <= 0) return null;

  final start = segment.start;
  final end = segment.end;
  if (!start.isResolved || !end.isResolved) return null;

  // A resolved non-axial end contributes a genuine zero (the dimension stops
  // at its face); an unresolved one contributes null and stops the sum.
  final leftCte = start.isAxial ? _roundOrNull(start.takeoutMm) : 0;
  final rightCte = end.isAxial ? _roundOrNull(end.takeoutMm) : 0;
  final leftBody = start.isPhysical ? _roundOrNull(start.bodyLengthMm) : 0;
  final rightBody = end.isPhysical ? _roundOrNull(end.bodyLengthMm) : 0;

  const centreRefs = {
    DimRef.centreToCentre,
    DimRef.centreToFace,
    DimRef.centreToEnd,
  };
  const endRefs = {DimRef.faceToEnd, DimRef.centreToEnd};

  if (centreRefs.contains(ref) && (leftCte == null || rightCte == null)) {
    return null;
  }
  if (endRefs.contains(ref) && (leftBody == null || rightBody == null)) {
    return null;
  }

  final cut = PrefabEngine.cutLengthMm(
    isoValueMm: iso,
    ref: ref,
    leftCteMm: leftCte,
    rightCteMm: rightCte,
    leftPhysicalLenMm: leftBody,
    rightPhysicalLenMm: rightBody,
    leftIsPhysical: start.isPhysical,
    rightIsPhysical: end.isPhysical,
  );
  return cut.isFinite ? cut : null;
}

int? _roundOrNull(double? v) => v?.round();

/// Reference the two ends suggest, following normal isometric practice:
/// axial fittings are dimensioned to their centreline, bodied components to
/// their face.
///
/// Ends with no body at all (an open pipe end, a weld, a support) contribute
/// nothing either way, so a run between them is plain centre-to-centre — the
/// case [PrefabEngine.needsDimRefPicker] says needs no question. Only a
/// proposal for the rest — see [PlannedSegment.proposedDimRef].
DimRef _proposeDimRef(ScanEndpoint start, ScanEndpoint end) {
  if (!start.isPhysical && !end.isPhysical) return DimRef.centreToCentre;
  if (start.isAxial || end.isAxial) return DimRef.centreToFace;
  return DimRef.faceToFace;
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

  return ScanEndpoint(
    componentId: componentId,
    rawType: component.type,
    label: component.label,
    kind: kind,
    behaviour: behaviour,
    takeoutMm: takeoutMm,
    // A valve of unknown type gets NO face-to-face: the group's behaviour is
    // the same for all of them, but a gate valve's body is not a check
    // valve's, and borrowing one for the other is exactly the invented
    // number this layer exists to prevent.
    bodyLengthMm: behaviour.hasPhysicalBody
        ? (subtypeKnown ? _bodyLengthMm(tool!, dn, pipeClass) : null)
        : (kind == ScanEndKind.logical ? 0 : null),
    takeoutNote: takeoutNote,
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
            : _Takeout(sr.toDouble(), 'ASME B16.28 · 90° SR · DN$dn');
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

/// Face-to-face body length, only where a standard gives one unambiguously.
///
/// Flanges and valves are listed per pressure class, so they resolve only
/// when the title block actually says Class 150 — guessing a class would
/// change the cut by tens of millimetres.
double? _bodyLengthMm(String tool, int? dn, String? pipeClass) {
  if (dn == null) return null;
  final is150 = _isClass150(pipeClass);
  switch (tool) {
    case 'reducer':
      return TakeoutCatalog.reducer[dn]?.toDouble();
    case 'cap':
      return TakeoutCatalog.cap[dn]?.toDouble();
    case 'flange':
    case 'blindFlange':
      return is150 ? TakeoutCatalog.flangeWN150[dn]?.toDouble() : null;
    case 'gateValve':
      return is150 ? TakeoutCatalog.gateValve150[dn]?.toDouble() : null;
    case 'ballValve':
      return is150 ? TakeoutCatalog.ballValve150[dn]?.toDouble() : null;
    case 'checkValve':
      return is150 ? TakeoutCatalog.checkValve150[dn]?.toDouble() : null;
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

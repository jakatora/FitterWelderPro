/// Last stop between a photographed isometric and a real cut list.
///
/// The scanner reads the drawing, [planFromScan] turns that reading into a
/// [ScanPlan], and this screen is where the fitter checks it before anything
/// is written to the database:
///
///   * the project header (diameter, wall, material) is editable, because a
///     vision model reads a title block far less reliably than the man
///     standing in front of the pipe, and so is the root gap per weld, which
///     no drawing carries but every cut on this screen takes off,
///   * everything the model was unsure about is shown in colour at full
///     size — never as small grey print,
///   * every blocking gap is listed at the top saying exactly what is
///     missing, and the save button stays dead until the last one is gone,
///   * every segment can be corrected (dimension, end component, how the
///     dimension was measured) without leaving the screen.
///
/// Nothing is invented here either. This screen never computes a cut length
/// itself: it edits the scan, re-runs [planFromScan], and asks
/// [cutMmForStops] for the arithmetic, so the number saved comes from
/// [PrefabEngine] exactly like a hand-built segment does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../services/iso_scanner_ai.dart';
import '../services/scan_to_project.dart';
import '../services/iso_parser.dart';
import '../utils/haptic.dart';
import 'cut_list_summary_screen.dart';
import '../theme/app_theme.dart' show kTextMut;

const _kCard = Color(0xFF141821);
const _kBorder = Color(0xFF2A3140);
const _kOrange = Color(0xFFFF8E1E);
const _kAmber = Color(0xFFFFC44D);
const _kRed = Color(0xFFE74C3C);
const _kGreen = Color(0xFF2ECC71);
const _kSec = Color(0xFF9BA3C7);
const _kMuted = kTextMut;

/// Default stock bar length (mm) for a project created from a scan — the
/// same 6 m the manual "new project" form starts from.
const double _kDefaultStockLengthMm = 6000;

/// Default saw kerf (mm), matching the manual form's default.
const double _kDefaultSawKerfMm = 1.5;

/// Default root gap per weld (mm) — the manual "new project" form starts
/// from 0 as well, so a scanned project and a typed one begin alike.
const String _kDefaultGapText = '0';

class ScanReviewScreen extends StatefulWidget {
  /// The finished AI reading of the drawing.
  final AiScanResult scan;

  /// Project name typed on the scanner screen, if any. Wins over the line
  /// number from the title block — the fitter named it on purpose.
  final String? suggestedName;

  /// Diameter / wall the fitter already knows. These beat anything read off
  /// the drawing (see [planFromScan]).
  final double? initialDiameterMm;
  final double? initialWallThicknessMm;

  const ScanReviewScreen({
    super.key,
    required this.scan,
    this.suggestedName,
    this.initialDiameterMm,
    this.initialWallThicknessMm,
  });

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  /// Working copy of the scan. Every correction the fitter makes is written
  /// back here and the plan is rebuilt from it, so one code path (the
  /// planner) decides what a corrected drawing means.
  late AiScanResult _scan;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _diaCtrl;
  late final TextEditingController _wallCtrl;

  /// Root gap per weld (mm) of the project this scan becomes. It is stored on
  /// the project and taken off every cut here exactly as the segment builder
  /// takes it off — this screen used to save every project with gap 0 and
  /// cut without one, so the same run came out longer than if it had been
  /// built by hand, by the gap on every weld.
  final TextEditingController _gapCtrl =
      TextEditingController(text: _kDefaultGapText);

  /// SS / CS. Starts from the title block, overridable — the group only
  /// filters the component library, but it is stored on the project.
  String? _materialGroup;

  /// Dimension references the fitter confirmed (stop per side), by segment id.
  final Map<String, ScanStops> _refChoice = {};

  /// Segment ids where the planner refused to derive a reference on its own.
  Set<String> _refNeeded = const {};

  late ScanPlan _plan;
  late List<PlannedSegment> _segments;
  late List<ScanIssue> _openGaps;

  bool _saving = false;

  /// Set when a save failed. Kept on screen (not just a SnackBar) because it
  /// carries what the fitter has to do about a half-written project.
  String? _saveError;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    _scan = _withSegmentIds(widget.scan);

    final first = planFromScan(
      _scan,
      diameterMm: widget.initialDiameterMm,
      wallThicknessMm: widget.initialWallThicknessMm,
    );

    final suggested = widget.suggestedName?.trim();
    _nameCtrl = TextEditingController(
      text: (suggested != null && suggested.isNotEmpty)
          ? suggested
          : (first.project.name ?? ''),
    );
    _diaCtrl = TextEditingController(
      text: _fmt(widget.initialDiameterMm ?? first.project.diameterMm),
    );
    _wallCtrl = TextEditingController(
      text: _fmt(widget.initialWallThicknessMm ?? first.project.wallThicknessMm),
    );
    _materialGroup = first.project.materialGroup;

    _recompute();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _diaCtrl.dispose();
    _wallCtrl.dispose();
    _gapCtrl.dispose();
    super.dispose();
  }

  // ── Plan ────────────────────────────────────────────────────────────────

  double? get _diameterMm => _positive(_diaCtrl.text);
  double? get _wallThicknessMm => _positive(_wallCtrl.text);

  /// The gap as typed, or null when it is not a number ≥ 0. Empty is not
  /// "no gap": the field starts at 0, so an empty one means the fitter
  /// deleted it and has not said what it is.
  double? get _gapMm {
    final v = double.tryParse(_gapCtrl.text.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite || v < 0) return null;
    return v;
  }

  /// Rebuilds the plan from the (possibly corrected) scan and re-applies the
  /// fitter's answers on top of it.
  void _recompute() {
    final base = planFromScan(
      _scan,
      diameterMm: _diameterMm,
      wallThicknessMm: _wallThicknessMm,
      gapMm: _gapMm ?? 0,
    );

    _refNeeded = base.segments
        .where((s) => s.needsDimRefConfirmation)
        .map((s) => s.sourceId)
        .toSet();

    // The fitter's answer only fills a reference the planner could not
    // derive. Where the two ends already decide it, a leftover answer must
    // not override the derived one.
    _segments = base.segments.map((s) {
      if (!s.needsDimRefConfirmation) return s;
      final choice = _refChoice[s.sourceId];
      return choice == null ? s : s.withStops(choice);
    }).toList(growable: false);

    _plan = base;
    _openGaps = _computeOpenGaps(base);
  }

  /// Blocking gaps that are still open.
  ///
  /// A gap raised by the planner disappears only when the fitter's answer
  /// actually produced the missing value — answering the reference question
  /// with an option that still yields no cut length leaves the segment
  /// blocked, on purpose.
  ///
  /// The last loop is the belt and braces: if a segment is somehow not
  /// writable and no gap explains why, this screen invents its own blocker
  /// rather than letting the save button go live over an incomplete row.
  List<ScanIssue> _computeOpenGaps(ScanPlan base) {
    final open = <ScanIssue>[];
    for (final gap in base.gaps) {
      switch (gap.code) {
        case ScanIssueCode.missingMaterialGroup:
          if (_materialGroup == null) open.add(gap);
          break;
        case ScanIssueCode.dimensionReferenceUnknown:
          final seg = _segmentById(gap.segmentId);
          if (seg == null || seg.cutMm == null) open.add(gap);
          break;
        default:
          open.add(gap);
      }
    }

    final explained = open.map((g) => g.segmentId).toSet();
    for (final seg in _segments) {
      if (seg.isComplete || explained.contains(seg.sourceId)) continue;
      open.add(ScanIssue(
        code: ScanIssueCode.cutImpossible,
        blocking: true,
        segmentId: seg.sourceId,
        pl: 'Odcinek ${seg.seqNo}: brak kompletu danych do zapisu '
            '(wymiar, take-outy albo odniesienie).',
        en: 'Segment ${seg.seqNo}: not enough data to save it '
            '(dimension, take-outs or reference).',
      ));
    }
    return open;
  }

  PlannedSegment? _segmentById(String? id) {
    if (id == null) return null;
    for (final s in _segments) {
      if (s.sourceId == id) return s;
    }
    return null;
  }

  bool get _canSave =>
      !_saving &&
      _openGaps.isEmpty &&
      _segments.isNotEmpty &&
      _diameterMm != null &&
      _wallThicknessMm != null &&
      _gapMm != null &&
      _materialGroup != null &&
      _segments.every((s) => s.isComplete);

  double get _totalCutMm {
    double sum = 0;
    for (final s in _segments) {
      final c = s.cutMm;
      if (c != null && c.isFinite && c > 0) sum += c;
    }
    return sum;
  }

  void _apply(void Function() change) {
    setState(() {
      change();
      _recompute();
    });
  }

  // ── Corrections on the scan ─────────────────────────────────────────────

  /// Replaces the dimension of one segment with what the fitter read off the
  /// drawing himself.
  ///
  /// Confidence is raised to [AiConfidence.high] because the number is no
  /// longer the model's guess — leaving it low would keep nagging him about
  /// his own reading.
  void _setDimension(String segmentId, double mm, String expr) {
    _apply(() {
      _scan = _copyScan(
        segments: _scan.segments
            .map((s) => s.id != segmentId
                ? s
                : AiSegment(
                    id: s.id,
                    dimensionMm: mm,
                    rawDimension: expr,
                    fromId: s.fromId,
                    toId: s.toId,
                    auxiliary: s.auxiliary,
                    confidence: AiConfidence.high,
                  ))
            .toList(),
      );
    });
  }

  /// Points one end of a segment at a component of the given type, creating
  /// the component when the drawing did not name one.
  ///
  /// [type] `null` means "open end" — the reference is cleared and the
  /// segment simply stops there.
  ///
  /// The fitter's earlier answer to "how was it measured" is dropped: it was
  /// given for the component that sat on this end before, and a different
  /// body (or none) makes it a different question.
  void _setEndComponent(
    PlannedSegment segment, {
    required bool isStart,
    required String? type,
    String? valveType,
  }) {
    _apply(() {
      final source = _scan.segments
          .where((s) => s.id == segment.sourceId)
          .toList(growable: false);
      if (source.isEmpty) return;
      _refChoice.remove(segment.sourceId);
      final existingId = isStart ? source.first.fromId : source.first.toId;

      String? targetId;
      var components = _scan.components;

      if (type != null) {
        targetId = (existingId != null && existingId.isNotEmpty)
            ? existingId
            : 'fix_${segment.sourceId}_${isStart ? 'a' : 'b'}';
        final previous = components.where((c) => c.id == targetId).toList();
        final keep = previous.isEmpty ? null : previous.first;
        components = [
          ...components.where((c) => c.id != targetId),
          AiComponent(
            id: targetId,
            type: type,
            valveType: valveType,
            supportType: keep?.supportType,
            label: keep?.label,
            weldNo: keep?.weldNo,
            weldType: keep?.weldType,
            weldNde: keep?.weldNde,
            weldPwht: keep?.weldPwht,
            weldPosition: keep?.weldPosition,
            throatA: keep?.throatA,
            isField: keep?.isField,
            instrumentTag: keep?.instrumentTag,
            confidence: AiConfidence.high,
          ),
        ];
      }

      _scan = _copyScan(
        components: components,
        segments: _scan.segments
            .map((s) => s.id != segment.sourceId
                ? s
                : AiSegment(
                    id: s.id,
                    dimensionMm: s.dimensionMm,
                    rawDimension: s.rawDimension,
                    fromId: isStart ? targetId : s.fromId,
                    toId: isStart ? s.toId : targetId,
                    auxiliary: s.auxiliary,
                    confidence: s.confidence,
                  ))
            .toList(),
      );
    });
  }

  AiScanResult _copyScan({
    List<AiSegment>? segments,
    List<AiComponent>? components,
  }) {
    return AiScanResult(
      drawingStandard: _scan.drawingStandard,
      sizeNotation: _scan.sizeNotation,
      isHygienic: _scan.isHygienic,
      titleBlock: _scan.titleBlock,
      northArrow: _scan.northArrow,
      scale: _scan.scale,
      segments: segments ?? _scan.segments,
      components: components ?? _scan.components,
      elevations: _scan.elevations,
      billOfMaterials: _scan.billOfMaterials,
      needsUserInput: _scan.needsUserInput,
      uncertainty: _scan.uncertainty,
      warnings: _scan.warnings,
      error: _scan.error,
      tookMs: _scan.tookMs,
      model: _scan.model,
    );
  }

  /// Gives every segment an id.
  ///
  /// The planner falls back to a positional id for an unnamed segment, and a
  /// positional id cannot be matched back onto the scan once the route has
  /// been reordered — a correction would land on the wrong pipe. Naming them
  /// up front keeps the mapping exact.
  AiScanResult _withSegmentIds(AiScanResult scan) {
    final used = scan.segments.map((s) => s.id).where((id) => id.isNotEmpty).toSet();
    var n = 0;
    var changed = false;
    final segments = scan.segments.map((s) {
      if (s.id.isNotEmpty) return s;
      changed = true;
      String candidate;
      do {
        n++;
        candidate = 'seg_$n';
      } while (used.contains(candidate));
      used.add(candidate);
      return AiSegment(
        id: candidate,
        dimensionMm: s.dimensionMm,
        rawDimension: s.rawDimension,
        fromId: s.fromId,
        toId: s.toId,
        auxiliary: s.auxiliary,
        confidence: s.confidence,
      );
    }).toList();

    if (!changed) return scan;
    return AiScanResult(
      drawingStandard: scan.drawingStandard,
      sizeNotation: scan.sizeNotation,
      isHygienic: scan.isHygienic,
      titleBlock: scan.titleBlock,
      northArrow: scan.northArrow,
      scale: scan.scale,
      segments: segments,
      components: scan.components,
      elevations: scan.elevations,
      billOfMaterials: scan.billOfMaterials,
      needsUserInput: scan.needsUserInput,
      uncertainty: scan.uncertainty,
      warnings: scan.warnings,
      error: scan.error,
      tookMs: scan.tookMs,
      model: scan.model,
    );
  }

  // ── Save ────────────────────────────────────────────────────────────────

  /// Writes the project and every segment, or nothing at all.
  ///
  /// The two DAOs do not share a transaction, so atomicity is enforced here:
  /// the first failure undoes what was already written and the fitter is
  /// told. A project with half its segments is worse than no project — he
  /// would cut from it.
  Future<void> _save() async {
    if (!_canSave) return;

    final diameterMm = _diameterMm;
    final wallMm = _wallThicknessMm;
    final gapMm = _gapMm;
    final material = _materialGroup;
    if (diameterMm == null ||
        wallMm == null ||
        gapMm == null ||
        material == null) {
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    await Haptic.tap();

    final projectDao = ProjectDao();
    final segmentDao = SegmentDao();
    final projectId = const Uuid().v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final typedName = _nameCtrl.text.trim();
    final name = typedName.isEmpty
        ? _tr('Skan izometryku', 'Isometric scan')
        : typedName;

    var projectWritten = false;
    try {
      await projectDao.insert(Project(
        id: projectId,
        name: name,
        materialGroup: material,
        diameterMm: diameterMm,
        wallThicknessMm: wallMm,
        currentDiameterMm: diameterMm,
        stockLengthMm: _kDefaultStockLengthMm,
        sawKerfMm: _kDefaultSawKerfMm,
        // The same gap every cut on this screen was computed with, so the
        // segment builder — which reads the project's gap on "edit" — gets
        // the same numbers back.
        gapMm: gapMm,
        createdAt: now,
        updatedAt: now,
      ));
      projectWritten = true;

      for (final seg in _segments) {
        // One pure function builds the row, so what is saved here is exactly
        // what the segment builder reads back on "edit": each side's stop in
        // iso_ref and the length it took off in *_value_mm. The row used to
        // say AXIS / FACE_NEAR whatever reference the fitter confirmed, and
        // an untouched re-save in the builder then changed the cut.
        final row = segmentRowFor(
          seg,
          id: const Uuid().v4(),
          projectId: projectId,
          diameterMm: diameterMm,
          wallThicknessMm: wallMm,
          nowMs: now,
        );
        if (row == null) {
          // Unreachable while _canSave holds; kept so a future change to the
          // gate can never silently write a segment with a missing column.
          throw StateError('segment ${seg.seqNo} is incomplete');
        }
        await segmentDao.insert(row);
      }
    } catch (e) {
      await _rollback(
        projectDao: projectDao,
        segmentDao: segmentDao,
        projectId: projectId,
        projectWritten: projectWritten,
        name: name,
        cause: e,
      );
      return;
    }

    if (!mounted) return;
    // Haptyka to sygnal dla palca, nie warunek przejscia — czekanie na nia
    // opoznialo (a w srodowisku testowym calkiem blokowalo) wejscie na cut liste.
    Haptic.saved();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CutListSummaryScreen(projectId: projectId),
      ),
    );
  }

  /// Undoes a partial save and says what happened.
  ///
  /// If the cleanup itself fails the fitter is given the project name so he
  /// can delete it from the project list by hand — silence would leave a
  /// half-project he might cut from tomorrow.
  Future<void> _rollback({
    required ProjectDao projectDao,
    required SegmentDao segmentDao,
    required String projectId,
    required bool projectWritten,
    required String name,
    required Object cause,
  }) async {
    var cleaned = true;
    if (projectWritten) {
      try {
        await segmentDao.deleteAllForProject(projectId);
        await projectDao.deleteById(projectId);
      } catch (_) {
        cleaned = false;
      }
    }

    if (!mounted) return;
    await Haptic.error();
    if (!mounted) return;

    final message = cleaned
        ? _tr(
            'Zapis nie powiódł się — nic nie zostało zapisane, projekt '
                'wycofany. Spróbuj ponownie. ($cause)',
            'The save failed — nothing was written, the project was rolled '
                'back. Try again. ($cause)',
          )
        : _tr(
            'Zapis nie powiódł się i nie udało się wycofać projektu '
                '"$name". Otwórz listę projektów i usuń go ręcznie, zanim '
                'zaczniesz ciąć. ($cause)',
            'The save failed and the project "$name" could not be rolled '
                'back. Open the project list and delete it by hand before '
                'you cut anything. ($cause)',
          );

    setState(() {
      _saving = false;
      _saveError = message;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 9),
        backgroundColor: _kRed,
      ));
  }

  // ── Editing dialogs ─────────────────────────────────────────────────────

  Future<void> _editDimension(PlannedSegment seg) async {
    final value = await showDialog<({double mm, String expr})>(
      context: context,
      builder: (ctx) => _DimensionDialog(
        seqNo: seg.seqNo,
        initial: seg.isoExpr?.trim().isNotEmpty == true
            ? seg.isoExpr!.trim()
            : (seg.isoMm != null ? seg.isoMm!.toStringAsFixed(0) : ''),
      ),
    );

    if (value == null) return;
    _setDimension(seg.sourceId, value.mm, value.expr);
  }

  Future<void> _editEnd(PlannedSegment seg, {required bool isStart}) async {
    final endpoint = isStart ? seg.start : seg.end;
    final picked = await showModalBottomSheet<_TypeChoice>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      builder: (ctx) => _TypePickerSheet(
        title: isStart
            ? _tr('Początek odcinka ${seg.seqNo}',
                'Start of segment ${seg.seqNo}')
            : _tr('Koniec odcinka ${seg.seqNo}', 'End of segment ${seg.seqNo}'),
        currentType: endpoint.rawType,
        tr: _tr,
      ),
    );
    if (picked == null) return;
    _setEndComponent(
      seg,
      isStart: isStart,
      type: picked.type,
      valveType: picked.valveType,
    );
  }

  Future<void> _editDimRef(PlannedSegment seg) async {
    // Proposal first (each end at its usual stop — a weld-neck flange to its
    // sealing face, so its Y comes off), then every other placement.
    final options = <ScanStops, double?>{
      for (final ref in referenceOptions(seg)) ref: cutMmForStops(seg, ref),
    };
    final current = _refChoice[seg.sourceId] ?? seg.proposedStops;

    final picked = await showModalBottomSheet<ScanStops>(
      context: context,
      backgroundColor: _kCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                _tr('Jak zmierzono wymiar? — odcinek ${seg.seqNo}',
                    'How was it measured? — segment ${seg.seqNo}'),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                _tr(
                  'Na końcu odcinka jest element o własnej długości. '
                      'Ze zdjęcia nie widać, czy wymiar idzie do osi, do '
                      'czoła czy do końca — przy każdej opcji widzisz, '
                      'ile wyjdzie cięcie.',
                  'The segment ends on a component with a body of its own. '
                      'A photo cannot tell whether the dimension runs to the '
                      'axis, the face or the end — each option shows the cut '
                      'it produces.',
                ),
                style: const TextStyle(fontSize: 12.5, color: _kSec),
              ),
            ),
            for (final ref in options.keys)
              ListTile(
                enabled: options[ref] != null,
                leading: Icon(
                  ref == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: options[ref] == null ? _kMuted : _kOrange,
                ),
                title: Text(
                  ref.label(polish: context.language != AppLanguage.en),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: options[ref] == null ? _kMuted : null,
                  ),
                ),
                subtitle: Text(
                  options[ref] == null
                      ? _tr('nie da się policzyć', 'cannot be computed')
                      : 'CUT ${options[ref]!.toStringAsFixed(1)} mm',
                  style: TextStyle(
                    color: options[ref] == null ? _kMuted : _kGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: options[ref] == null
                    ? null
                    : () => Navigator.pop(ctx, ref),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null) return;
    _apply(() => _refChoice[seg.sourceId] = picked);
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Segment-scoped warnings live on their own card, in colour, next to the
    // number they are about — repeating them here would bury the ones that
    // belong to the drawing as a whole.
    final warnings = <String>[
      ..._plan.warnings
          .where((w) => w.segmentId == null)
          .map((w) => w.text(polish: !_isEnglish)),
      ..._scan.uncertainty,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Sprawdź skan', 'Review scan')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (_saveError != null) _errorBanner(_saveError!),
          if (_openGaps.isNotEmpty) _gapsCard(),
          if (warnings.isNotEmpty) _warningsCard(warnings),
          _headerCard(),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Text(
              _tr('Odcinki (${_segments.length})',
                  'Segments (${_segments.length})'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: _kSec),
            ),
          ),
          for (final seg in _segments) _segmentCard(seg),
          if (_segments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _tr('Ze skanu nie wyszedł żaden odcinek rury.',
                    'The scan produced no pipe runs.'),
                style: const TextStyle(color: _kRed, fontSize: 14),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  bool get _isEnglish => context.language == AppLanguage.en;

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.18),
        border: Border.all(color: _kRed, width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_gmailerrorred, color: _kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _kRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gapsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kRed.withValues(alpha: 0.14),
        border: Border.all(color: _kRed, width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, color: _kRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr('Bez tego nie zapiszę (${_openGaps.length})',
                      'Blocking the save (${_openGaps.length})'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _kRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final gap in _openGaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${_gapPrefix(gap)}${gap.text(polish: !_isEnglish)}',
                style: const TextStyle(
                    fontSize: 13.5, height: 1.35, color: Color(0xFFFFD9D4)),
              ),
            ),
        ],
      ),
    );
  }

  String _gapPrefix(ScanIssue gap) {
    final seg = _segmentById(gap.segmentId);
    if (seg == null) return '';
    return _tr('Odcinek ${seg.seqNo}: ', 'Segment ${seg.seqNo}: ');
  }

  Widget _warningsCard(List<String> warnings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.13),
        border: Border.all(color: _kAmber, width: 1.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _kAmber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tr('AI nie jest pewna (${warnings.length}) — sprawdź na '
                      'rysunku', 'AI is unsure (${warnings.length}) — check '
                      'against the drawing'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _kAmber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $w',
                style: const TextStyle(
                    fontSize: 13.5, height: 1.35, color: Color(0xFFFFE9B8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    final draft = _plan.project;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('Projekt', 'Project'),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: _kSec),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 80,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              labelText: _tr('Nazwa / nr linii', 'Name / line number'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _numberField(
                  controller: _diaCtrl,
                  label: _tr('Średnica OD (mm)', 'Diameter OD (mm)'),
                  missing: _diameterMm == null,
                  source: draft.diameterSource,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numberField(
                  controller: _wallCtrl,
                  label: _tr('Ścianka (mm)', 'Wall (mm)'),
                  missing: _wallThicknessMm == null,
                  source: draft.wallThicknessSource,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gapCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => _apply(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: _tr('Gap (mm na spoinę)', 'Gap (mm per weld)'),
              helperText: _tr(
                'Szczelina pod spoinę — odejmowana od CUT na każdej spoinie, '
                    'jak w kreatorze segmentu',
                'Root gap — taken off the CUT at every weld, as in the '
                    'segment builder',
              ),
              helperMaxLines: 2,
              errorText: _gapMm == null
                  ? _tr('wpisz gap (0, jeśli bez szczeliny)',
                      'enter the gap (0 for none)')
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _tr('Materiał', 'Material'),
            style: const TextStyle(fontSize: 12.5, color: _kSec),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final group in const ['SS', 'CS'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(group == 'SS'
                        ? _tr('SS — nierdzewna', 'SS — stainless')
                        : _tr('CS — węglowa', 'CS — carbon')),
                    selected: _materialGroup == group,
                    onSelected: (_) => _apply(() => _materialGroup = group),
                  ),
                ),
            ],
          ),
          if (draft.materialText != null) ...[
            const SizedBox(height: 6),
            Text(
              _tr('Z rysunku: ${draft.materialText}',
                  'From drawing: ${draft.materialText}'),
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ],
          if (draft.dn != null || draft.schedule != null) ...[
            const SizedBox(height: 8),
            Text(
              [
                if (draft.dn != null) 'DN${draft.dn}',
                if (draft.schedule != null) 'SCH ${draft.schedule}',
                if (_plan.auxiliarySegmentCount > 0)
                  _tr('pominięto ${_plan.auxiliarySegmentCount} linii pomocn.',
                      '${_plan.auxiliarySegmentCount} aux lines skipped'),
              ].join('  ·  '),
              style: const TextStyle(fontSize: 12, color: _kMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required bool missing,
    required ScanValueSource source,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _apply(() {}),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            errorText: missing ? _tr('wpisz wartość', 'enter a value') : null,
            filled: missing,
            fillColor: missing ? _kRed.withValues(alpha: 0.12) : null,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          switch (source) {
            ScanValueSource.scan => _tr('z rysunku', 'from the drawing'),
            ScanValueSource.caller => _tr('Twoja wartość', 'your value'),
            ScanValueSource.none => _tr('nie odczytano', 'not read'),
          },
          style: TextStyle(
            fontSize: 11,
            color: source == ScanValueSource.none ? _kRed : _kMuted,
            fontWeight: source == ScanValueSource.none
                ? FontWeight.w700
                : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _segmentCard(PlannedSegment seg) {
    final segGaps =
        _openGaps.where((g) => g.segmentId == seg.sourceId).toList();
    final segWarnings = _plan.warningsFor(seg.sourceId);
    final blocked = segGaps.isNotEmpty;
    final unsure = segWarnings.isNotEmpty;
    final needsRef = _refNeeded.contains(seg.sourceId);

    final borderColor = blocked
        ? _kRed
        : unsure
            ? _kAmber
            : _kBorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: borderColor, width: blocked || unsure ? 1.4 : 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${seg.seqNo}',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, color: _kSec),
              ),
              const SizedBox(width: 8),
              if (seg.startsNewRun)
                _tag(_tr('NOWY CIĄG', 'NEW RUN'), _kAmber),
              if (seg.isBranch) _tag(_tr('ROZGAŁĘZIENIE', 'BRANCH'), _kAmber),
              const Spacer(),
              Text(
                seg.cutMm == null
                    ? _tr('CUT — brak', 'CUT — none')
                    : 'CUT ${seg.cutMm!.toStringAsFixed(1)} mm',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: seg.cutMm == null ? _kRed : _kOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _endButton(seg, isStart: true),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 16, color: _kMuted),
              ),
              Expanded(
                child: _endButton(seg, isStart: false),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editDimension(seg),
                  icon: const Icon(Icons.straighten, size: 18),
                  label: Text(
                    seg.isoMm == null
                        ? _tr('WPISZ WYMIAR', 'ENTER DIMENSION')
                        : 'ISO ${seg.isoExpr?.trim().isNotEmpty == true ? seg.isoExpr!.trim() : seg.isoMm!.toStringAsFixed(0)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: seg.isoMm == null ? _kRed : null,
                    side: BorderSide(
                        color: seg.isoMm == null ? _kRed : _kBorder),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: needsRef ? () => _editDimRef(seg) : null,
                  icon: Icon(
                    needsRef ? Icons.help_outline : Icons.check,
                    size: 18,
                  ),
                  label: Text(
                    seg.stops == null
                        ? _tr('ODNIESIENIE?', 'REFERENCE?')
                        : seg.stops!.label(polish: !_isEnglish),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: seg.stops == null ? _kRed : _kSec,
                    side: BorderSide(
                        color: seg.stops == null ? _kRed : _kBorder),
                  ),
                ),
              ),
            ],
          ),
          for (final w in segWarnings) ...[
            const SizedBox(height: 8),
            _noteLine(Icons.warning_amber_rounded, _kAmber,
                w.text(polish: !_isEnglish)),
          ],
          for (final g in segGaps) ...[
            const SizedBox(height: 8),
            _noteLine(Icons.block, _kRed, g.text(polish: !_isEnglish)),
          ],
        ],
      ),
    );
  }

  Widget _endButton(PlannedSegment seg, {required bool isStart}) {
    final e = isStart ? seg.start : seg.end;
    final bad = !e.isResolved || (e.isAxial && e.takeoutMm == null);
    final label = _endpointLabel(e);
    // What this end takes off (e.g. a weld-neck flange: −Y 76 mm) under the
    // confirmed reference, or the proposed one before that.
    final detail = endpointDeductionText(seg,
        start: isStart, polish: !_isEnglish);

    return InkWell(
      onTap: () => _editEnd(seg, isStart: isStart),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bad ? _kRed.withValues(alpha: 0.12) : const Color(0xFF1B2030),
          border: Border.all(color: bad ? _kRed : _kBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: bad ? _kRed : const Color(0xFFE7ECF3),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11.5, color: bad ? _kRed : _kMuted),
            ),
          ],
        ),
      ),
    );
  }

  String _endpointLabel(ScanEndpoint e) {
    if (e.componentId == null) return _tr('otwarty koniec', 'open end');
    final raw = e.label?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return _typeLabel(e.rawType) ?? _tr('element', 'component');
  }

  String? _typeLabel(String? type) {
    if (type == null) return null;
    for (final choice in _kScanTypeChoices) {
      if (choice.type == type) {
        return _isEnglish ? choice.en : choice.pl;
      }
    }
    return type;
  }

  Widget _noteLine(IconData icon, Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.3, color: color),
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }

  Widget _bottomBar() {
    final blocked = _openGaps.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          color: _kCard,
          border: Border(top: BorderSide(color: _kBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_tr('Suma CUT', 'Total CUT')}: '
                    '${_totalCutMm.toStringAsFixed(1)} mm',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _kOrange),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    blocked == 0
                        ? _tr('Gotowe do zapisu', 'Ready to save')
                        : _tr('Uzupełnij $blocked ${_gapWord(blocked)}',
                            'Fix $blocked blocking item(s)'),
                    style: TextStyle(
                      fontSize: 12,
                      color: blocked == 0 ? _kGreen : _kRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _canSave ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: Text(_tr('Zapisz projekt', 'Save project')),
            ),
          ],
        ),
      ),
    );
  }

  /// PL plural for "brak / braki / braków".
  String _gapWord(int n) {
    if (n == 1) return 'brak';
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'braki';
    }
    return 'braków';
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

double? _positive(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

String _fmt(double? v) {
  if (v == null) return '';
  if ((v - v.roundToDouble()).abs() < 0.005) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

/// One entry of the component picker.
///
/// [type] uses the same vocabulary the scanner backend emits, so a choice
/// made here goes back through exactly the classification path an AI-read
/// component takes. `null` is the open end of the spool.
class _TypeChoice {
  final String? type;
  final String? valveType;
  final String pl;
  final String en;
  const _TypeChoice(this.type, this.pl, this.en, {this.valveType});
}

/// Types the fitter can pick from. Deliberately limited to what
/// [planFromScan] can actually classify — offering a type that resolves to
/// nothing would just move the blockage.
const List<_TypeChoice> _kScanTypeChoices = [
  _TypeChoice(null, 'Otwarty koniec', 'Open end'),
  _TypeChoice('elbow90', 'Kolano 90°', 'Elbow 90°'),
  _TypeChoice('elbow45', 'Kolano 45°', 'Elbow 45°'),
  _TypeChoice('tee', 'Trójnik', 'Tee'),
  _TypeChoice('reducer', 'Redukcja', 'Reducer'),
  _TypeChoice('flange', 'Kołnierz', 'Flange'),
  _TypeChoice('blindFlange', 'Kołnierz ślepy', 'Blind flange'),
  _TypeChoice('cap', 'Zaślepka', 'Cap'),
  _TypeChoice('valve', 'Zawór zasuwowy', 'Gate valve', valveType: 'gate'),
  _TypeChoice('valve', 'Zawór kulowy', 'Ball valve', valveType: 'ball'),
  _TypeChoice('valve', 'Zawór zwrotny', 'Check valve', valveType: 'check'),
  _TypeChoice('valve', 'Zawór grzybkowy', 'Globe valve', valveType: 'globe'),
  _TypeChoice('valve', 'Przepustnica', 'Butterfly valve',
      valveType: 'butterfly'),
  _TypeChoice('weld', 'Spoina', 'Weld'),
  _TypeChoice('fieldWeld', 'Spoina montażowa', 'Field weld'),
  _TypeChoice('support', 'Podpora', 'Support'),
];

class _TypePickerSheet extends StatelessWidget {
  final String title;
  final String? currentType;
  final String Function(String pl, String en) tr;

  const _TypePickerSheet({
    required this.title,
    required this.currentType,
    required this.tr,
  });

  @override
  Widget build(BuildContext context) {
    final english = context.language == AppLanguage.en;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr(
                  'Czego nie ma w tabeli take-outów, tego nie policzę — '
                      'wtedy wskaż punkt, do którego wymiar jest mierzony '
                      '(np. spoinę albo otwarty koniec).',
                  'What is not in the take-out tables cannot be computed — '
                      'then pick the point the dimension is measured to '
                      '(a weld or an open end).',
                ),
                style: const TextStyle(fontSize: 12, color: _kSec),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final choice in _kScanTypeChoices)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        choice.type == null
                            ? Icons.horizontal_rule
                            : Icons.settings_input_component,
                        size: 20,
                        color: choice.type == currentType ? _kOrange : _kMuted,
                      ),
                      title: Text(english ? choice.en : choice.pl),
                      onTap: () => Navigator.pop(context, choice),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Ręczna korekta wymiaru odczytanego ze zdjęcia.
///
/// To jest miejsce, w którym monter poprawia model: skan bywa nieostry, a wymiar
/// z izometrii bywa zapisany działaniem (`3000+525-80`) albo w calach (`76"`).
/// Dlatego pole przyjmuje CAŁE WYRAŻENIE, a nie samą liczbę, i pokazuje wynik na
/// żywo — monter widzi milimetry, zanim zatwierdzi, i nie musi liczyć w głowie.
class _DimensionDialog extends StatefulWidget {
  /// Numer segmentu na liście — ten sam, który monter widzi na ekranie.
  final int seqNo;

  /// Wyrażenie do edycji; puste, gdy AI nie odczytało wymiaru.
  final String initial;

  const _DimensionDialog({required this.seqNo, required this.initial});

  @override
  State<_DimensionDialog> createState() => _DimensionDialogState();
}

class _DimensionDialogState extends State<_DimensionDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  double? _mm;
  String? _blad;

  @override
  void initState() {
    super.initState();
    _przelicz(widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  /// Liczy na każdym znaku, żeby monter widział wynik od razu. Puste pole nie
  /// jest błędem — to po prostu „jeszcze nie podałem wymiaru”.
  void _przelicz(String tekst) {
    final t = tekst.trim();
    if (t.isEmpty) {
      setState(() {
        _mm = null;
        _blad = null;
      });
      return;
    }
    try {
      final v = parseIsoExpression(t);
      setState(() {
        _mm = v > 0 ? v : null;
        _blad = v > 0
            ? null
            : _tr('Wymiar musi być większy od zera.',
                'The dimension must be greater than zero.');
      });
    } on FormatException {
      setState(() {
        _mm = null;
        _blad = _tr(
          'Nie rozumiem tego zapisu. Możesz wpisać działanie, np. 3000+525-80, '
          'albo wymiar w calach, np. 76".',
          'Cannot read this. You can type an expression like 3000+525-80, '
          'or an imperial dimension like 76".',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final gotowe = _mm != null;
    return AlertDialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _kBorder),
      ),
      title: Text(
        _tr('Wymiar odcinka ${widget.seqNo}', 'Segment ${widget.seqNo} dimension'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            // Klawiatura MUSI mieć kropkę: podpowiedź pokazuje wymiar dziesiętny,
            // a iOS na zwykłym `number` kropki nie daje (audyt 2026-08-29).
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+*() "a-zA-Z½¼¾-]')),
            ],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: _tr('Wymiar z rysunku', 'Dimension from the drawing'),
              hintText: '3000+525-80',
              helperText: _tr(
                'Przepisz tak, jak stoi na izometrii.',
                'Type it exactly as printed on the isometric.',
              ),
              helperMaxLines: 2,
              errorText: _blad,
              errorMaxLines: 3,
            ),
            onChanged: _przelicz,
            onSubmitted: (_) {
              if (_mm != null) Navigator.pop(context, (mm: _mm!, expr: _ctrl.text.trim()));
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.straighten, size: 18, color: _kMuted),
              const SizedBox(width: 8),
              Text(
                gotowe
                    ? '${_mm!.toStringAsFixed(1)} mm'
                    : _tr('— brak wymiaru —', '— no dimension —'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: gotowe ? _kGreen : _kMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_tr('Anuluj', 'Cancel'),
              style: const TextStyle(color: _kSec)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kOrange),
          onPressed: gotowe
              ? () {
                  Haptic.saved();
                  Navigator.pop(context, (mm: _mm!, expr: _ctrl.text.trim()));
                }
              : null,
          child: Text(_tr('Zapisz', 'Save')),
        ),
      ],
    );
  }
}

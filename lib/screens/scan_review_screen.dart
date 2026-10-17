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
///     missing — a gap about the project blocks the save, a gap about one
///     cut keeps only THAT cut out of the save (spec §2 rule 6, §9), and the
///     cuts left out are named before anything is written,
///   * every segment can be corrected (dimension, end component, its size,
///     a take-out, how the dimension was measured) without leaving the
///     screen,
///   * the rest of what the drawing gives is on its own tabs: the weld map
///     (with "create weld journal entries"), the bill of materials compared
///     with the scan, and the spools.
///
/// Nothing is invented here either. This screen never computes a cut length
/// itself: it edits the scan, re-runs [planFromScan], and asks
/// [cutMmForStops] for the arithmetic, so the number saved comes from
/// [PrefabEngine] exactly like a hand-built segment does.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../database/weld_journal_dao.dart';
import '../i18n/app_language.dart';
import '../models/project.dart';
import '../services/iso_scanner_ai.dart';
import '../services/scan_outputs.dart';
import '../services/scan_to_project.dart';
import '../services/iso_parser.dart';
import '../services/prefab_engine.dart' show SideStop;
import '../services/welder_identity.dart';
import '../data/pipe_schedules.dart';
import '../utils/haptic.dart';
import 'cut_list_summary_screen.dart';
import '../theme/app_theme.dart' show kTextMut;
import '../widgets/iso_expression_keys.dart';
import '../widgets/number_field.dart';
import '../widgets/project_identity_fields.dart';

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

  /// The photo the scan was read from, shown (zoomable) above the cuts — the
  /// messages here say "check it on the drawing", and the drawing used to be
  /// a screen back.
  final String? imagePath;

  const ScanReviewScreen({
    super.key,
    required this.scan,
    this.suggestedName,
    this.initialDiameterMm,
    this.initialWallThicknessMm,
    this.imagePath,
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

  /// Line / ISO + revision / client / class (schema v22), prefilled from the
  /// title block; saved on the project and carried into the weld journal.
  late final ProjectIdentityControllers _identityCtrl;

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

  /// The fitter's answers the planner itself takes into account.
  final Map<String, int> _segDn = {};
  final Map<String, double> _segWall = {};
  final Map<String, double> _takeouts = {};

  /// Segment ids where the planner refused to derive a reference on its own.
  Set<String> _refNeeded = const {};

  late ScanPlan _plan;
  late List<PlannedSegment> _segments;
  late ScanReviewGate _gate;
  late List<PlannedWeld> _welds;
  late List<BomLine> _bom;
  late List<ScanSpoolSummary> _spools;

  bool _saving = false;

  /// Set when a save failed. Kept on screen (not just a SnackBar) because it
  /// carries what the fitter has to do about a half-written project.
  String? _saveError;

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  @override
  void initState() {
    super.initState();
    // Every segment gets an id up front: the planner falls back to a
    // positional id for an unnamed one, and a positional id cannot be
    // matched back onto the scan once the route has been reordered — a
    // correction would land on the wrong pipe.
    _scan = scanWithSegmentIds(widget.scan);

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
    _identityCtrl = ProjectIdentityControllers(ProjectIdentity.clean(
      lineNo: first.project.lineNo,
      isoNo: first.project.isoNo,
      isoRev: first.project.isoRev,
      spec: first.project.spec,
    ));

    _recompute();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _diaCtrl.dispose();
    _wallCtrl.dispose();
    _gapCtrl.dispose();
    _identityCtrl.dispose();
    super.dispose();
  }

  // ── Plan ────────────────────────────────────────────────────────────────

  double? get _diameterMm => _positive(_diaCtrl.text);
  double? get _wallThicknessMm => _positive(_wallCtrl.text);

  /// The gap as typed, or null when it is not a number ≥ 0. Empty is not
  /// "no gap": the field starts at 0, so an empty one means the fitter
  /// deleted it and has not said what it is.
  double? get _gapMm {
    final v = parseDecimal(_gapCtrl.text);
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
      fitter: ScanFitterInput(
        segmentDn: Map.of(_segDn),
        segmentWallMm: Map.of(_segWall),
        takeoutMm: Map.of(_takeouts),
      ),
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
    _gate = evaluateReview(
      plan: base,
      segments: _segments,
      materialGroup: _materialGroup,
      headerComplete: _diameterMm != null &&
          _wallThicknessMm != null &&
          _materialGroup != null,
    );
    _welds = buildWeldMap(_scan, _segments);
    _bom = compareBom(_scan, _segments);
    _spools = buildSpools(_scan, _segments, _welds);
  }

  PlannedSegment? _segmentById(String? id) {
    if (id == null) return null;
    for (final s in _segments) {
      if (s.sourceId == id) return s;
    }
    return null;
  }

  bool get _canSave => !_saving && _gapMm != null && _gate.canSaveProject;

  double get _totalCutMm {
    double sum = 0;
    for (final s in _gate.savable) {
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

  /// Replaces the dimension of one drawing segment with what the fitter read
  /// off the drawing himself.
  ///
  /// Confidence is raised to [AiConfidence.high] and the reading is marked
  /// as his own, because the number is no longer the model's guess —
  /// leaving it low would keep nagging him about his own reading.
  void _setDimension(String segmentId, double mm, String expr) {
    _apply(() {
      _scan = _copyScan(
        segments: _scan.segments
            .map((s) => s.id != segmentId
                ? s
                : s.copyWith(
                    dimensionMm: mm,
                    rawDimension: expr,
                    confidence: AiConfidence.high,
                    userConfirmed: true,
                  ))
            .toList(),
      );
    });
  }

  /// The drawing segment and the field (`fromId` / `toId`) behind one end of
  /// a planned run — for a merged olet header, the far end of the half on
  /// that side.
  ({String segmentId, bool isFrom})? _endRef(
      PlannedSegment segment, bool isStart) {
    final parts = segment.sourceParts;
    if (parts.length == 1) {
      return (segmentId: parts.single, isFrom: isStart);
    }
    final a = _scan.segments.where((s) => s.id == parts.first).firstOrNull;
    final b = _scan.segments.where((s) => s.id == parts.last).firstOrNull;
    if (a == null || b == null) return null;
    final shared = {a.fromId, a.toId}.intersection({b.fromId, b.toId});
    final olet = shared.isEmpty ? null : shared.first;
    final half = isStart ? a : b;
    return (segmentId: half.id, isFrom: half.fromId != olet);
  }

  /// Points one end of a segment at a component of the given type, creating
  /// the component when the drawing did not name one.
  ///
  /// [type] `null` means "open end" — the reference is cleared and the
  /// segment simply stops there.
  ///
  /// The fitter's earlier answers for this end (how it was measured, a
  /// typed take-out) are dropped: they were given for the component that sat
  /// on this end before, and a different body (or none) makes it a
  /// different question.
  void _setEndComponent(
    PlannedSegment segment, {
    required bool isStart,
    required String? type,
    String? valveType,
  }) {
    _apply(() {
      final ref = _endRef(segment, isStart);
      if (ref == null) return;
      final source = _scan.segments
          .where((s) => s.id == ref.segmentId)
          .toList(growable: false);
      if (source.isEmpty) return;
      _refChoice.remove(segment.sourceId);
      final existingId = ref.isFrom ? source.first.fromId : source.first.toId;
      if (existingId != null) {
        _takeouts.remove(
            ScanFitterInput.takeoutKey(existingId, segment.sourceId));
      }

      String? targetId;
      var components = _scan.components;

      if (type != null) {
        targetId = (existingId != null && existingId.isNotEmpty)
            ? existingId
            : 'fix_${ref.segmentId}_${ref.isFrom ? 'a' : 'b'}';
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
            // What the drawing says about the place, not about the old
            // fitting's own type, stays.
            sizeLarge: keep?.sizeLarge,
            sizeSmall: keep?.sizeSmall,
            rating: keep?.rating,
            connectedTo: keep?.connectedTo ?? const [],
            runIds: keep?.runIds ?? const [],
            branchId: keep?.branchId,
            bomItem: keep?.bomItem,
            spoolId: keep?.spoolId,
          ),
        ];
      }

      _scan = _copyScan(
        components: components,
        segments: _scan.segments
            .map((s) => s.id != ref.segmentId
                ? s
                : s.copyWith(
                    fromId: ref.isFrom ? targetId : s.fromId,
                    toId: ref.isFrom ? s.toId : targetId,
                  ))
            .toList(),
      );
    });
  }

  AiScanResult _copyScan({
    List<AiSegment>? segments,
    List<AiComponent>? components,
  }) =>
      _scan.copyWith(segments: segments, components: components);

  // ── Save ────────────────────────────────────────────────────────────────

  /// Writes the project and every cut that can be saved, or nothing at all;
  /// with [withJournal] also the weld journal entries of the saved runs.
  ///
  /// The two DAOs do not share a transaction, so atomicity is enforced here:
  /// the first failure undoes what was already written and the fitter is
  /// told. A project with half its segments is worse than no project — he
  /// would cut from it. Cuts that are still blocked are NOT written; they
  /// are named in a confirmation before the save, so nothing is left out
  /// silently.
  Future<void> _save({bool withJournal = false}) async {
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

    final projectId = const Uuid().v4();
    final typedName = _nameCtrl.text.trim();
    final name = typedName.isEmpty
        ? _tr('Skan izometryku', 'Isometric scan')
        : typedName;
    final savable = _gate.savable;
    final blocked = _gate.blocked;
    final identity = _identityCtrl.value;
    final spoolLabels = {for (final s in _scan.spools) s.id: s.display};

    WeldJournalImport? journal;
    if (withJournal) {
      try {
        final existing = await WeldJournalDao().listAll();
        journal = weldJournalEntries(
          welds: _welds,
          scan: _scan,
          projectId: projectId,
          projectName: name,
          savedSegmentIds: savable.map((s) => s.sourceId).toSet(),
          existing: existing,
          newId: () => const Uuid().v4(),
          spoolLabels: spoolLabels,
          identity: identity,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _saveError = _tr(
              'Nie udało się odczytać dziennika spoin — nic nie zapisano. ($e)',
              'Could not read the weld journal — nothing was saved. ($e)',
            ));
        return;
      }
    }

    if (blocked.isNotEmpty || journal != null) {
      final ok = await _confirmSave(savable, blocked, journal);
      if (ok != true || !mounted) return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    await Haptic.tap();

    final projectDao = ProjectDao();
    final segmentDao = SegmentDao();
    final now = DateTime.now().millisecondsSinceEpoch;

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
        lineNo: identity.lineNo,
        isoNo: identity.isoNo,
        isoRev: identity.isoRev,
        client: identity.client,
        spec: identity.spec,
      ));
      projectWritten = true;

      for (var i = 0; i < savable.length; i++) {
        // One pure function builds the row, so what is saved here is exactly
        // what the segment builder reads back on "edit": each side's stop in
        // iso_ref and the length it took off in *_value_mm. Saved runs are
        // numbered 1..n without holes for the cuts left out.
        final seg = savable[i].renumbered(i + 1, savable[i].label);
        final row = segmentRowFor(
          seg,
          id: const Uuid().v4(),
          projectId: projectId,
          diameterMm: diameterMm,
          wallThicknessMm: wallMm,
          nowMs: now,
          spoolLabels: spoolLabels,
        );
        if (row == null) {
          // Unreachable while the gate holds; kept so a future change to it
          // can never silently write a segment with a missing column.
          throw StateError('segment ${seg.label} is incomplete');
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

    var journalError = '';
    var created = 0;
    if (journal != null && journal.toInsert.isNotEmpty) {
      String stamp = '';
      try {
        stamp = (await WelderIdentityService.instance.get())?.stamp ?? '';
      } catch (_) {}
      final dao = WeldJournalDao();
      for (final entry in journal.toInsert) {
        try {
          await dao.insert(entry, by: stamp);
          created++;
        } catch (e) {
          journalError = '$e';
          break;
        }
      }
    }

    if (!mounted) return;
    // Haptyka to sygnal dla palca, nie warunek przejscia — czekanie na nia
    // opoznialo (a w srodowisku testowym calkiem blokowalo) wejscie na cut liste.
    Haptic.saved();
    if (journal != null) {
      final msg = journalError.isEmpty
          ? _tr(
              'Dziennik spoin: utworzono $created wpisów (Oczekuje)'
                  '${journal.skipped.isEmpty ? '' : ', pominięto ${journal.skipped.length} już istniejących'}.',
              'Weld journal: $created entries created (Pending)'
                  '${journal.skipped.isEmpty ? '' : ', ${journal.skipped.length} already there skipped'}.',
            )
          : _tr(
              'Projekt zapisany, ale dziennik spoin przerwał po $created '
                  'wpisach: $journalError. Dopisz resztę w dzienniku.',
              'Project saved, but the weld journal stopped after $created '
                  'entries: $journalError. Add the rest in the journal.',
            );
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 7),
          backgroundColor: journalError.isEmpty ? null : _kRed,
        ));
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CutListSummaryScreen(projectId: projectId),
      ),
    );
  }

  /// Summary before a save that leaves cuts out or writes journal entries —
  /// spec §2 rule 5: a change of data is summarised and confirmed.
  Future<bool?> _confirmSave(List<PlannedSegment> savable,
      List<PlannedSegment> blocked, WeldJournalImport? journal) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: Text(_tr('Zapisać projekt?', 'Save the project?')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr(
                'Zapiszę ${savable.length} z ${savable.length + blocked.length} '
                    'odcinków.',
                'Saving ${savable.length} of '
                    '${savable.length + blocked.length} runs.',
              )),
              if (blocked.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _tr(
                    'NIE zapiszę (czekają na Twoją decyzję): '
                        '${blocked.map((s) => s.label).join(', ')}. Dopisz je '
                        'później w projekcie albo wróć i uzupełnij.',
                    'NOT saving (waiting for your decision): '
                        '${blocked.map((s) => s.label).join(', ')}. Add them '
                        'in the project later or go back and complete them.',
                  ),
                  style: const TextStyle(color: _kAmber),
                ),
              ],
              if (journal != null) ...[
                const SizedBox(height: 8),
                Text(_tr(
                  'Dziennik spoin: ${journal.toInsert.length} nowych wpisów '
                      '(status Oczekuje)'
                      '${journal.skipped.isEmpty ? '' : ', ${journal.skipped.length} już jest w dzienniku — pominę'}.',
                  'Weld journal: ${journal.toInsert.length} new entries '
                      '(status Pending)'
                      '${journal.skipped.isEmpty ? '' : ', ${journal.skipped.length} already in the journal — skipped'}.',
                )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Wróć', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Zapisz', 'Save')),
          ),
        ],
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
    var partId = seg.sourceId;
    var initial = seg.isoExpr?.trim().isNotEmpty == true
        ? seg.isoExpr!.trim()
        : (seg.isoMm != null ? _fmt(seg.isoMm) : '');
    if (seg.sourceParts.length > 1) {
      // A merged olet header: its two dimensions are corrected one by one.
      final parts = [
        for (final id in seg.sourceParts)
          _scan.segments.where((s) => s.id == id).firstOrNull,
      ].whereType<AiSegment>().toList();
      final picked = await showModalBottomSheet<AiSegment>(
        context: context,
        backgroundColor: _kCard,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_tr(
                  'Rura główna przy olecie ma na rysunku dwa wymiary — '
                      'który poprawiasz?',
                  'The header at the olet has two dimensions on the drawing '
                      '— which one?',
                )),
              ),
              for (final p in parts)
                ListTile(
                  title: Text(
                      '${p.id}: ${p.rawDimension ?? _fmt(p.dimensionMm)}'),
                  onTap: () => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      partId = picked.id;
      initial = picked.rawDimension ?? _fmt(picked.dimensionMm);
    }
    if (!mounted) return;
    final value = await showDialog<({double mm, String expr})>(
      context: context,
      builder: (ctx) => _DimensionDialog(
        seqNo: seg.seqNo,
        label: seg.label,
        initial: initial,
      ),
    );

    if (value == null) return;
    _setDimension(partId, value.mm, value.expr);
  }

  Future<void> _editEnd(PlannedSegment seg, {required bool isStart}) async {
    final endpoint = isStart ? seg.start : seg.end;
    final canType = endpoint.componentId != null &&
        endpoint.isResolved &&
        (endpoint.isAxial || endpoint.isPhysical);
    final picked = await showModalBottomSheet<_TypeChoice>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      builder: (ctx) => _TypePickerSheet(
        title: isStart
            ? _tr('Początek odcinka ${seg.label}',
                'Start of segment ${seg.label}')
            : _tr('Koniec odcinka ${seg.label}', 'End of segment ${seg.label}'),
        currentType: endpoint.rawType,
        offerTypedValue: canType,
        typedValueLabel: endpoint.isAxial
            ? _tr('Wpisz take-out (oś → koniec) ręcznie',
                'Type the take-out (centre → end)')
            : _tr('Wpisz długość korpusu ręcznie', 'Type the body length'),
        tr: _tr,
      ),
    );
    if (picked == null) return;
    if (picked.typedValue) {
      final id = endpoint.componentId!;
      final key = ScanFitterInput.takeoutKey(id, seg.sourceId);
      final mm = await _askNumber(
        title: endpoint.isAxial
            ? _tr('Take-out: ${endpoint.label ?? endpoint.rawType ?? id}',
                'Take-out: ${endpoint.label ?? endpoint.rawType ?? id}')
            : _tr('Długość korpusu: ${endpoint.label ?? endpoint.rawType ?? id}',
                'Body length: ${endpoint.label ?? endpoint.rawType ?? id}'),
        help: endpoint.missingPl != null && !_isEnglish
            ? endpoint.missingPl!
            : (endpoint.missingEn ??
                _tr('Wartość z karty producenta albo z pomiaru.',
                    'From the manufacturer\'s data sheet or measured.')),
        initial: _takeouts[key],
        unit: 'mm',
      );
      if (mm == null) return;
      _apply(() => _takeouts[key] = mm);
      return;
    }
    _setEndComponent(
      seg,
      isStart: isStart,
      type: picked.type,
      valveType: picked.valveType,
    );
  }

  /// DN (and, for a size other than the project's, the wall) of one run.
  Future<void> _editSize(PlannedSegment seg) async {
    final options = kPipeWalls.map((r) => r.dn).toList();
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: _kCard,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  _tr('Średnica odcinka ${seg.label}',
                      'Size of run ${seg.label}'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _tr(
                    'Odczytaj DN przy odcinku na rysunku. Wybór przenosi się '
                        'przez redukcje na sąsiednie odcinki.',
                    'Read the DN next to the run on the drawing. The choice '
                        'carries through reducers to the next runs.',
                  ),
                  style: const TextStyle(fontSize: 12.5, color: _kSec),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final dn in options)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          dn == seg.dn
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: dn == seg.dn ? _kOrange : _kMuted,
                        ),
                        title: Text('DN$dn'),
                        onTap: () => Navigator.pop(ctx, dn),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    _apply(() => _segDn[seg.sourceId] = picked);
  }

  Future<void> _editWall(PlannedSegment seg) async {
    final mm = await _askNumber(
      title: _tr('Ścianka odcinka ${seg.label}', 'Wall of run ${seg.label}'),
      help: _tr(
        'Rysunek nie podaje schedule dla DN${seg.dn ?? '?'} — wpisz ściankę '
            'z tabelki rysunku albo z pomiaru.',
        'The drawing gives no schedule for DN${seg.dn ?? '?'} — enter the '
            'wall from the drawing or measured.',
      ),
      initial: _segWall[seg.sourceId] ?? seg.wallThicknessMm,
      unit: 'mm',
    );
    if (mm == null) return;
    _apply(() => _segWall[seg.sourceId] = mm);
  }

  Future<double?> _askNumber({
    required String title,
    required String help,
    double? initial,
    required String unit,
  }) {
    return showDialog<double>(
      context: context,
      builder: (ctx) => _NumberDialog(
        title: title,
        help: help,
        initial: initial,
        unit: unit,
        tr: _tr,
      ),
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
                _tr('Jak zmierzono wymiar? — odcinek ${seg.label}',
                    'How was it measured? — segment ${seg.label}'),
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _stopsInWords(seg, ref),
                      style: const TextStyle(fontSize: 13, color: _kSec),
                    ),
                    Text(
                      options[ref] == null
                          ? _tr('nie da się policzyć', 'cannot be computed')
                          : 'CUT ${options[ref]!.toStringAsFixed(1)} mm',
                      style: TextStyle(
                        color: options[ref] == null ? _kMuted : _kGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_tr('Sprawdź skan', 'Review scan')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: _tr('Cięcia (${_segments.length})',
                  'Cuts (${_segments.length})')),
              Tab(text: _tr('Spoiny (${_welds.length})',
                  'Welds (${_welds.length})')),
              Tab(text: _tr('Materiały', 'Materials')),
              Tab(text: _tr('Spoole', 'Spools')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _cutsTab(),
            _weldsTab(),
            _bomTab(),
            _spoolsTab(),
          ],
        ),
        bottomNavigationBar: _bottomBar(),
      ),
    );
  }

  Widget _cutsTab() {
    // Segment-scoped warnings live on their own card, in colour, next to the
    // number they are about — repeating them here would bury the ones that
    // belong to the drawing as a whole.
    final warnings = <String>[
      ..._plan.warnings
          .where((w) => w.segmentId == null)
          .map((w) => w.text(polish: !_isEnglish)),
      ..._scan.uncertainty,
    ];
    final glance = [
      for (final s in _segments)
        if (_plan
            .warningsFor(s.sourceId)
            .any((w) => w.code == ScanIssueCode.mediumConfidence))
          s,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        if (widget.imagePath != null) _drawingPanel(widget.imagePath!),
        if (_saveError != null) _errorBanner(_saveError!),
        if (_gate.projectGaps.isNotEmpty) _gapsCard(),
        if (_gate.blocked.isNotEmpty) _blockedCutsCard(),
        if (warnings.isNotEmpty) _warningsCard(warnings),
        if (glance.isNotEmpty)
          _issueCard(
            color: _kAmber,
            icon: Icons.visibility_outlined,
            title: _tr(
                'Do rzutu oka (${glance.length}) — wymiar odczytany średnio '
                    'pewnie',
                'For a glance (${glance.length}) — dimension read with '
                    'medium confidence'),
            lines: [
              for (final s in glance)
                '${_tr('Odcinek', 'Segment')} ${s.label}: ISO '
                    '${s.isoExpr?.trim().isNotEmpty == true ? s.isoExpr!.trim() : _fmt(s.isoMm)}',
            ],
            textColor: const Color(0xFFFFE9B8),
          ),
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
    );
  }

  bool get _isEnglish => context.language == AppLanguage.en;

  /// The photographed drawing, pinch-zoomable, folded away on demand.
  Widget _drawingPanel(String path) {
    final file = File(path);
    return Padding(
      key: const ValueKey('scan-review-drawing'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
      color: _kCard,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: const Icon(Icons.image_outlined, color: _kSec),
          title: Text(
            _tr('Rysunek — zdjęcie ze skanu', 'Drawing — the scanned photo'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _tr('Rozsuń dwoma palcami, żeby przybliżyć wymiar',
                'Pinch to zoom in on a dimension'),
            style: const TextStyle(fontSize: 12.5, color: _kSec),
          ),
          children: [
            SizedBox(
              height: 280,
              child: file.existsSync()
                  ? ClipRect(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 8,
                        child: Image.file(file,
                            fit: BoxFit.contain, cacheWidth: 2048),
                      ),
                    )
                  : Center(
                      child: Text(
                        _tr('Zdjęcia nie ma już w telefonie.',
                            'The photo is no longer on the phone.'),
                        style: const TextStyle(color: _kMuted),
                      ),
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// A reference option in words, end by end — "kołnierz: do przylgi (−Y
  /// 76 mm)" — so "oś-koniec" never has to be decoded at a flange, where the
  /// fitter reads "czoło" as the gasket face.
  String _stopsInWords(PlannedSegment seg, ScanStops stops) {
    String side(ScanEndpoint e, SideStop stop) {
      if (e.isOpenEnd) return _tr('koniec rury', 'pipe end');
      final what = e.label ?? e.rawType ?? _tr('element', 'component');
      if (e.isAxial) {
        return stop == SideStop.centre
            ? _tr('$what: do osi', '$what: to the centreline')
            : _tr('$what: do końca kształtki', '$what: to the fitting end');
      }
      final body = e.bodyLengthMm;
      final len = body == null ? '' : ' ${_fmt(body)} mm';
      if (e.tool == 'flange') {
        return stop == SideStop.end
            ? _tr('$what: do przylgi (−Y$len)',
                '$what: to the gasket face (−Y$len)')
            : _tr('$what: do spoiny (bez Y)', '$what: to the weld (no Y)');
      }
      return stop == SideStop.end
          ? _tr('$what: przez korpus (−$len)',
              '$what: through the body (−$len)')
          : _tr('$what: do czoła', '$what: to its face');
    }

    return '${side(seg.start, stops.start)}  →  ${side(seg.end, stops.end)}';
  }

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

  /// What blocks the whole project (header, a failed scan).
  Widget _gapsCard() {
    final gaps = _gate.projectGaps;
    return _issueCard(
      color: _kRed,
      icon: Icons.block,
      title: _tr('Bez tego nie zapiszę projektu (${gaps.length})',
          'Blocking the save (${gaps.length})'),
      lines: [for (final g in gaps) g.text(polish: !_isEnglish)],
      textColor: const Color(0xFFFFD9D4),
    );
  }

  /// Cuts that stay out of the save until answered — each named with why.
  Widget _blockedCutsCard() {
    final lines = <String>[];
    for (final seg in _gate.blocked) {
      final gaps = _gate.gapsFor(seg.sourceId);
      for (final g in gaps) {
        lines.add('${_tr('Odcinek', 'Segment')} ${seg.label}: '
            '${g.text(polish: !_isEnglish)}');
      }
    }
    return _issueCard(
      color: _kRed,
      icon: Icons.content_cut,
      title: _tr(
        'Te cięcia czekają na decyzję (${_gate.blocked.length}) — reszta '
            'zapisze się bez nich',
        'These cuts wait for a decision (${_gate.blocked.length}) — the rest '
            'saves without them',
      ),
      lines: lines,
      textColor: const Color(0xFFFFD9D4),
    );
  }

  Widget _issueCard({
    required Color color,
    required IconData icon,
    required String title,
    required List<String> lines,
    required Color textColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $line',
                style: TextStyle(fontSize: 13.5, height: 1.35, color: textColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _warningsCard(List<String> warnings) {
    return _issueCard(
      color: _kAmber,
      icon: Icons.warning_amber_rounded,
      title: _tr('AI nie jest pewna (${warnings.length}) — sprawdź na rysunku',
          'AI is unsure (${warnings.length}) — check against the drawing'),
      lines: warnings,
      textColor: const Color(0xFFFFE9B8),
    );
  }

  /// Line / ISO + revision / client / class read off the title block — folded
  /// to one line (they are prefilled, usually right) and editable on tap.
  Widget _identityTile() {
    final summary = _identityCtrl.value
        .summary(english: context.language == AppLanguage.en);
    // Own transparent Material: the header card paints its colour in a
    // DecoratedBox, which would hide the tile's ink.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const ValueKey('scan-identity'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            _tr('Identyfikacja z rysunku', 'Drawing identification'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            summary.isEmpty
                ? _tr('Linia, ISO, rewizja, klient, klasa — brak na tabliczce',
                    'Line, ISO, revision, client, class — not on the title block')
                : summary,
            style: const TextStyle(fontSize: 12, color: _kSec),
          ),
          onExpansionChanged: (_) => setState(() {}),
          children: [
            ProjectIdentityFields(
              controllers: _identityCtrl,
              enabled: !_saving,
              dense: true,
            ),
          ],
        ),
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
          _identityTile(),
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
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
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
          keyboardType: numberKeyboard(),
          inputFormatters: numberInputFormatters(),
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
    final segGaps = _gate.gapsFor(seg.sourceId);
    final segWarnings = _plan.warningsFor(seg.sourceId);
    final blocked = segGaps.isNotEmpty;
    final unsure = segWarnings.isNotEmpty;
    final needsRef = _refNeeded.contains(seg.sourceId);
    final sizeMissing = segGaps.any((g) =>
        g.code == ScanIssueCode.missingSegmentDiameter);
    final wallMissing =
        segGaps.any((g) => g.code == ScanIssueCode.missingSegmentWall);

    // Read with medium confidence ("slightly illegible"): not a block, but
    // the number itself is coloured so a glance at the drawing is not missed.
    final medium =
        segWarnings.any((w) => w.code == ScanIssueCode.mediumConfidence);
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
              Flexible(
                child: Text(
                  '#${seg.label}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: _kSec),
                ),
              ),
              const SizedBox(width: 8),
              if (seg.startsNewRun)
                _tag(_tr('NOWY CIĄG', 'NEW RUN'), _kAmber),
              if (seg.isBranch) _tag(_tr('ROZGAŁĘZIENIE', 'BRANCH'), _kAmber),
              if (blocked) _tag(_tr('NIE ZAPISZĘ', 'NOT SAVED'), _kRed),
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
          const SizedBox(height: 6),
          _sizeLine(seg, sizeMissing: sizeMissing, wallMissing: wallMissing),
          const SizedBox(height: 8),
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
                  key: ValueKey('scan-iso-${seg.sourceId}'),
                  onPressed: () => _editDimension(seg),
                  icon: Icon(
                      medium ? Icons.visibility_outlined : Icons.straighten,
                      size: 18),
                  label: Text(
                    seg.isoMm == null
                        ? _tr('WPISZ WYMIAR', 'ENTER DIMENSION')
                        : '${medium ? '? ' : ''}ISO ${seg.isoExpr?.trim().isNotEmpty == true ? seg.isoExpr!.trim() : _fmt(seg.isoMm)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: seg.isoMm == null
                        ? _kRed
                        : (medium ? _kAmber : null),
                    backgroundColor:
                        medium ? _kAmber.withValues(alpha: 0.12) : null,
                    side: BorderSide(
                        color: seg.isoMm == null
                            ? _kRed
                            : (medium ? _kAmber : _kBorder),
                        width: medium ? 1.6 : 1),
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
          if (seg.isoNote != null) ...[
            const SizedBox(height: 8),
            _noteLine(Icons.functions, _kSec,
                _tr('Wymiar z rzutów: ${seg.isoNote} mm',
                    'Dimension from projections: ${seg.isoNote} mm')),
          ],
          if (seg.refSource == ScanRefSource.drawing) ...[
            const SizedBox(height: 8),
            _noteLine(Icons.visibility, _kSec,
                _tr('Odniesienie wymiaru odczytane z linii wymiarowej rysunku.',
                    'Dimension reference read off the drawing\'s dimension line.')),
          ],
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

  /// "DN80 · OD 88.9 × 5.49 · za redukcją…" — the run's own size, tappable.
  Widget _sizeLine(PlannedSegment seg,
      {required bool sizeMissing, required bool wallMissing}) {
    final bad = sizeMissing || wallMissing;
    final text = seg.dn == null
        ? (sizeMissing
            ? _tr('DN? — wybierz średnicę odcinka', 'DN? — pick the run size')
            : _tr('DN nieznane', 'DN unknown'))
        : [
            'DN${seg.dn}',
            if (seg.diameterMm != null)
              'OD ${_fmt(seg.diameterMm)}'
                  '${seg.wallThicknessMm == null ? '' : ' × ${_fmt(seg.wallThicknessMm)}'}',
            if (wallMissing) _tr('ścianka?', 'wall?'),
            if (seg.dnNote != null) seg.dnNote!,
          ].join(' · ');
    return InkWell(
      onTap: () => wallMissing ? _editWall(seg) : _editSize(seg),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.circle_outlined,
                size: 14, color: bad ? _kRed : _kMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: bad ? _kRed : _kMuted,
                  fontWeight: bad ? FontWeight.w800 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
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
              maxLines: 2,
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
    final role = switch (e.role) {
      PortRole.run => _tr(' (przelot)', ' (run)'),
      PortRole.branch => _tr(' (odgałęzienie)', ' (branch)'),
      null => '',
    };
    if (raw != null && raw.isNotEmpty) return '$raw$role';
    return '${_typeLabel(e.rawType) ?? _tr('element', 'component')}$role';
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

  // ── Welds tab ───────────────────────────────────────────────────────────

  Widget _weldsTab() {
    final field = _welds.where((w) => w.isField).length;
    final derived = _welds.isNotEmpty && _welds.first.source == WeldSource.derived;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        Text(
          _tr(
            'Mapa spoin: ${_welds.length} (montażowych: $field). '
                '${derived ? 'Rysunek nie oznacza spoin — po jednej na każdym '
                    'połączeniu rury z kształtką, numery W-001… nadane przez '
                    'aplikację.' : 'Numery i typ z rysunku.'}',
            'Weld map: ${_welds.length} (field: $field). '
                '${derived ? 'The drawing marks no welds — one per pipe-to-'
                    'fitting joint, numbered W-001… by the app.' : 'Numbers and '
                    'type from the drawing.'}',
          ),
          style: const TextStyle(fontSize: 13, color: _kSec),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _canSave && _welds.isNotEmpty
              ? () => _save(withJournal: true)
              : null,
          icon: const Icon(Icons.menu_book),
          label: Text(_tr('Utwórz wpisy w dzienniku spoin',
              'Create weld journal entries')),
        ),
        const SizedBox(height: 4),
        Text(
          _tr(
            'Zapisze projekt i doda spoiny zapisanych cięć do dziennika '
                '(status Oczekuje, powiązane z projektem). Spoiny już '
                'wpisane dla tego rysunku są pomijane.',
            'Saves the project and adds the welds of the saved cuts to the '
                'journal (status Pending, linked to the project). Welds '
                'already there for this drawing are skipped.',
          ),
          style: const TextStyle(fontSize: 11.5, color: _kMuted),
        ),
        const SizedBox(height: 10),
        for (final w in _welds) _weldCard(w),
        if (_welds.isEmpty)
          Text(_tr('Brak spoin do pokazania.', 'No welds to show.'),
              style: const TextStyle(color: _kMuted)),
      ],
    );
  }

  Widget _weldCard(PlannedWeld w) {
    final runs = w.segmentIds
        .map((id) => _segmentById(id)?.label ?? id)
        .join(', ');
    final loc = switch (w.location) {
      'field' => _tr('MONTAŻOWA', 'FIELD'),
      'shop' => _tr('WARSZTATOWA', 'SHOP'),
      _ => _tr('shop/field?', 'shop/field?'),
    };
    final unsure = w.source == WeldSource.drawing &&
        (w.confidence == AiConfidence.low ||
            w.confidence == AiConfidence.unknown);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: unsure ? _kAmber : _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(w.number,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              _tag(loc, w.isField ? _kOrange : _kSec),
              if (w.jointType.isNotEmpty) _tag(w.jointType, _kSec),
              if (w.numberAssigned) _tag(_tr('NR NADANY', 'AUTO NO.'), _kMuted),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (w.dn != null) 'DN${w.dn}',
              if (w.odMm != null)
                'OD ${_fmt(w.odMm)}${w.wallMm == null ? '' : ' × ${_fmt(w.wallMm)}'}',
              if (_plan.project.materialText != null) _plan.project.materialText!,
              if (runs.isNotEmpty) _tr('odcinek $runs', 'run $runs'),
              if (w.spoolId != null) 'spool ${w.spoolId}',
              if (w.nde != null) 'NDE ${w.nde}',
              if (w.pwht == true) 'PWHT',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          if (unsure)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _tr('Niepewny odczyt spoiny — sprawdź numer na rysunku.',
                    'Low-confidence weld reading — check its number.'),
                style: const TextStyle(fontSize: 12, color: _kAmber),
              ),
            ),
        ],
      ),
    );
  }

  // ── Materials tab ───────────────────────────────────────────────────────

  Widget _bomTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        Text(
          _tr(
            'Materiały ze skanu (kształtki policzone na trasie, rura jako '
                'suma cięć) porównane z tabelą materiałową rysunku.',
            'Materials from the scan (fittings counted on the route, pipe as '
                'the sum of the cuts) against the drawing\'s bill of '
                'materials.',
          ),
          style: const TextStyle(fontSize: 13, color: _kSec),
        ),
        const SizedBox(height: 10),
        if (_scan.billOfMaterials.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _tr('Rysunek nie ma tabeli materiałowej (albo AI jej nie '
                  'odczytała) — pokazuję tylko to, co wynika ze skanu.',
                  'The drawing has no bill of materials (or the AI did not '
                  'read it) — showing only what the scan gives.'),
              style: const TextStyle(fontSize: 12.5, color: _kAmber),
            ),
          ),
        for (final l in _bom) _bomCard(l),
      ],
    );
  }

  Widget _bomCard(BomLine l) {
    final color = switch (l.status) {
      BomLineStatus.ok => _kGreen,
      BomLineStatus.mismatch => _kRed,
      BomLineStatus.notCompared => _kMuted,
    };
    final icon = switch (l.status) {
      BomLineStatus.ok => Icons.check_circle,
      BomLineStatus.mismatch => Icons.error_outline,
      BomLineStatus.notCompared => Icons.remove_circle_outline,
    };
    String q(double? v) => v == null ? '—' : _fmt(v);
    final unit = l.unit == 'szt' ? _tr('szt', 'pcs') : l.unit;
    final note = _isEnglish ? l.noteEn : l.notePl;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(
            color: l.status == BomLineStatus.mismatch ? _kRed : _kBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isEnglish ? l.labelEn : l.labelPl,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  _tr('rysunek ${q(l.drawingQty)} $unit · skan '
                      '${q(l.scanQty)} $unit',
                      'drawing ${q(l.drawingQty)} $unit · scan '
                      '${q(l.scanQty)} $unit'),
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                ),
                if (note.isNotEmpty)
                  Text(note, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Spools tab ──────────────────────────────────────────────────────────

  Widget _spoolsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        if (_scan.spools.isEmpty &&
            _segments.every((s) => s.spoolId == null))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              _tr('Rysunek nie dzieli trasy na spoole — cała trasa poniżej.',
                  'The drawing marks no spools — the whole route below.'),
              style: const TextStyle(fontSize: 12.5, color: _kSec),
            ),
          ),
        for (final s in _spools) _spoolCard(s),
      ],
    );
  }

  Widget _spoolCard(ScanSpoolSummary s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kCard,
        border: Border.all(color: _kBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.id == null ? _tr('Poza spoolami', 'Outside spools') : s.label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            _tr(
              '${s.segments.length} cięć · ${_fmt(s.knownCutMm)} mm'
                  '${s.missingCuts == 0 ? '' : ' (+${s.missingCuts} bez CUT)'}'
                  ' · spoin ${s.welds.length} (montażowych ${s.fieldWelds})',
              '${s.segments.length} cuts · ${_fmt(s.knownCutMm)} mm'
                  '${s.missingCuts == 0 ? '' : ' (+${s.missingCuts} no CUT)'}'
                  ' · welds ${s.welds.length} (field ${s.fieldWelds})',
            ),
            style: const TextStyle(fontSize: 12, color: _kMuted),
          ),
          const SizedBox(height: 6),
          for (final seg in s.segments)
            Text(
              '• ${seg.label}: ${seg.cutMm == null ? _tr('CUT — brak', 'CUT — none') : 'CUT ${seg.cutMm!.toStringAsFixed(1)} mm'}'
              '${seg.dn == null ? '' : ' · DN${seg.dn}'}',
              style: TextStyle(
                  fontSize: 12.5, color: seg.cutMm == null ? _kRed : null),
            ),
          if (s.welds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_tr('Spoiny', 'Welds')}: ${s.welds.map((w) => w.isField ? '${w.number} (FW)' : w.number).join(', ')}',
                style: const TextStyle(fontSize: 12, color: _kSec),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final projectBlocked = _gate.projectGaps.length;
    final blockedCuts = _gate.blocked.length;
    final String status;
    final Color statusColor;
    if (projectBlocked > 0) {
      status = _tr('Uzupełnij $projectBlocked ${_gapWord(projectBlocked)}',
          'Fix $projectBlocked blocking item(s)');
      statusColor = _kRed;
    } else if (_gate.savable.isEmpty) {
      status = _tr('Żadne cięcie nie jest gotowe',
          'No cut is ready');
      statusColor = _kRed;
    } else if (blockedCuts > 0) {
      status = _tr(
          'Zapiszę ${_gate.savable.length} z ${_segments.length} cięć',
          'Saving ${_gate.savable.length} of ${_segments.length} cuts');
      statusColor = _kAmber;
    } else {
      status = _tr('Gotowe do zapisu', 'Ready to save');
      statusColor = _kGreen;
    }
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
                    status,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _canSave ? () => _save() : null,
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
  final v = parseDecimal(raw);
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

  /// Not a type: "type the take-out / body length by hand".
  final bool typedValue;
  const _TypeChoice(this.type, this.pl, this.en,
      {this.valveType, this.typedValue = false});
}

/// Types the fitter can pick from. Deliberately limited to what
/// [planFromScan] can actually classify — offering a type that resolves to
/// nothing would just move the blockage.
const List<_TypeChoice> _kScanTypeChoices = [
  _TypeChoice(null, 'Otwarty koniec', 'Open end'),
  _TypeChoice('elbow90', 'Kolano 90°', 'Elbow 90°'),
  _TypeChoice('elbow45', 'Kolano 45°', 'Elbow 45°'),
  _TypeChoice('tee', 'Trójnik', 'Tee'),
  _TypeChoice('olet', 'Olet (weldolet / sockolet)', 'Olet (weldolet / sockolet)'),
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

  /// Offer "type the take-out / body length by hand" first — for an end
  /// the tables cannot give (an olet, a thread, a class without a table).
  final bool offerTypedValue;
  final String typedValueLabel;

  const _TypePickerSheet({
    required this.title,
    required this.currentType,
    required this.tr,
    this.offerTypedValue = false,
    this.typedValueLabel = '',
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
                  if (offerTypedValue)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.edit, size: 20, color: _kOrange),
                      title: Text(typedValueLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      onTap: () => Navigator.pop(
                          context,
                          const _TypeChoice(null, '', '', typedValue: true)),
                    ),
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

  /// Etykieta odcinka z rysunku (spool/nr), gdy jest.
  final String? label;

  /// Wyrażenie do edycji; puste, gdy AI nie odczytało wymiaru.
  final String initial;

  const _DimensionDialog(
      {required this.seqNo, this.label, required this.initial});

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
        _tr('Wymiar odcinka ${widget.label ?? widget.seqNo}',
            'Segment ${widget.label ?? widget.seqNo} dimension'),
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
            // Działania (+ − × ( ) ") dokłada pasek przycisków pod polem —
            // klawiatura dziesiętna iOS ich nie ma. Filtr to ten sam zestaw
            // znaków, który rozumie parser ISO (wcześniej gubił ×, · i /,
            // więc wklejone „5×200" zamieniało się po cichu w 5200).
            keyboardType: numberKeyboard(),
            inputFormatters: isoExpressionInputFormatters(),
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
          const SizedBox(height: 8),
          IsoExpressionKeyBar(controller: _ctrl, onChanged: _przelicz),
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


/// Jedna liczba od montera (take-out, długość korpusu, ścianka) — pole
/// liczbowe z przecinkiem albo kropką, tylko wartość dodatnia.
class _NumberDialog extends StatefulWidget {
  final String title;
  final String help;
  final double? initial;
  final String unit;
  final String Function(String pl, String en) tr;

  const _NumberDialog({
    required this.title,
    required this.help,
    required this.initial,
    required this.unit,
    required this.tr,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _fmt(widget.initial));

  double? get _value {
    final v = parseDecimal(_ctrl.text);
    if (v == null || !v.isFinite || v <= 0) return null;
    return v;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _value != null;
    return AlertDialog(
      backgroundColor: _kCard,
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.help,
              style: const TextStyle(fontSize: 12.5, color: _kSec)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: numberKeyboard(),
            inputFormatters: numberInputFormatters(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              suffixText: widget.unit,
              errorText: _ctrl.text.trim().isEmpty || ok
                  ? null
                  : widget.tr('Wpisz liczbę większą od zera.',
                      'Enter a number greater than zero.'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.tr('Anuluj', 'Cancel'),
              style: const TextStyle(color: _kSec)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kOrange),
          onPressed: ok ? () => Navigator.pop(context, _value) : null,
          child: Text(widget.tr('Zapisz', 'Save')),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../database/component_library_dao.dart';
import '../i18n/app_language.dart';
import '../models/library_component.dart';
import '../models/segment.dart';
import '../services/iso_parser.dart';
import '../services/prefab_engine.dart';
import '../utils/haptic.dart';
import '../widgets/component_icon.dart';
import '../widgets/help_button.dart';

// ─── Punkt referencyjny ISO ────────────────────────────────────────────────
// Określa, od/do którego miejsca na komponencie mierzony jest wymiar ISO.
//
//  FACE_NEAR  = czoło bliskie (gdzie wchodzi rura)             → offset = 0
//  AXIS       = oś / punkt przecięcia centerlines (axial only) → offset = axisMm
//  CENTER     = środek komponentu                              → offset = length/2
//  FACE_FAR   = czoło dalekie (przeciwna strona)               → offset = length
//  OPEN       = logiczny (OPEN_END, PIPE)                      → offset = 0
//
enum IsoRefPoint { faceNear, axis, center, faceFar, open }

extension IsoRefPointExt on IsoRefPoint {
  String get code {
    switch (this) {
      case IsoRefPoint.faceNear: return 'FACE_NEAR';
      case IsoRefPoint.axis:     return 'AXIS';
      case IsoRefPoint.center:   return 'CENTER';
      case IsoRefPoint.faceFar:  return 'FACE_FAR';
      case IsoRefPoint.open:     return 'OPEN';
    }
  }

  String label(BuildContext ctx) {
    switch (this) {
      case IsoRefPoint.faceNear: return ctx.tr(pl: 'Czoło bliskie', en: 'Near face');
      case IsoRefPoint.axis:     return ctx.tr(pl: 'Oś', en: 'Axis');
      case IsoRefPoint.center:   return ctx.tr(pl: 'Środek', en: 'Center');
      case IsoRefPoint.faceFar:  return ctx.tr(pl: 'Czoło dalekie', en: 'Far face');
      case IsoRefPoint.open:     return ctx.tr(pl: 'Koniec otwarty', en: 'Open end');
    }
  }

  String shortLabel(BuildContext ctx) {
    switch (this) {
      case IsoRefPoint.faceNear: return ctx.tr(pl: 'czoło bl.', en: 'near face');
      case IsoRefPoint.axis:     return ctx.tr(pl: 'oś', en: 'axis');
      case IsoRefPoint.center:   return ctx.tr(pl: 'środek', en: 'center');
      case IsoRefPoint.faceFar:  return ctx.tr(pl: 'czoło dal.', en: 'far face');
      case IsoRefPoint.open:     return '';
    }
  }
}

// ─── Dostępne punkty dla danego typu komponentu ───────────────────────────
List<IsoRefPoint> _availableRefPoints(LibraryComponent comp) {
  if (comp.isAxial) {
    return [IsoRefPoint.axis, IsoRefPoint.faceNear];
  }
  if (comp.type == 'REDUCER') {
    return [IsoRefPoint.faceNear, IsoRefPoint.faceFar];
  }
  return [IsoRefPoint.faceNear, IsoRefPoint.center, IsoRefPoint.faceFar];
}

IsoRefPoint _defaultRefPoint(LibraryComponent comp) {
  if (comp.isAxial) return IsoRefPoint.axis;
  return IsoRefPoint.faceNear;
}

// ─── Obliczenie offsetu ────────────────────────────────────────────────────
double _calcOffset(LibraryComponent comp, IsoRefPoint ref) {
  switch (ref) {
    case IsoRefPoint.open:
    case IsoRefPoint.faceNear:
      return 0;
    case IsoRefPoint.axis:
      return comp.axisMm ?? 0;
    case IsoRefPoint.center:
      if (comp.isAxial) return comp.axisMm ?? 0;
      return (comp.lengthMm ?? 0) / 2.0;
    case IsoRefPoint.faceFar:
      if (comp.isAxial) return comp.axisMm ?? 0;
      return comp.lengthMm ?? 0;
  }
}

// ─── CUT ───────────────────────────────────────────────────────────────────

/// The engine stop-type an ISO reference point stands for.
///
/// The reference point records WHERE on the anchor the tape was hooked, which
/// is exactly what [SideStop] models: near face and open end stop at the pipe
/// face, axis and centre stop on the component's centreline, far face runs
/// through the whole body to the other side of it.
SideStop stopForRefPoint(IsoRefPoint ref) {
  switch (ref) {
    case IsoRefPoint.faceNear:
    case IsoRefPoint.open:
      return SideStop.face;
    case IsoRefPoint.axis:
    case IsoRefPoint.center:
      return SideStop.centre;
    case IsoRefPoint.faceFar:
      return SideStop.end;
  }
}

/// CUT length of one builder segment in millimetres, or NaN when the numbers
/// cannot make a cuttable pipe (ISO shorter than what the ends and the weld
/// gaps take off it).
///
/// Goes through [PrefabEngine] instead of doing its own arithmetic, because
/// the engine is the single source of truth for CUT and the builder was
/// quietly disagreeing with it: the builder subtracted `welds × gap`, a term
/// the engine did not know existed, so the SAME run entered here and in the
/// ISO notebook came out different by the gap total — with nothing on either
/// screen to explain which number the fitter should saw to. The gap now lives
/// in the engine (`weldGapMm` / `weldCount`) and both screens read one rule.
///
/// [startOffsetMm] / [endOffsetMm] are the offsets from `_calcOffset` — the
/// distance from the anchor's reference point to the pipe face — handed to
/// the engine as the take-out or the body length according to that side's
/// stop, which is the same number either way.
double builderCutMm({
  required double isoMm,
  required IsoRefPoint startRef,
  required double startOffsetMm,
  required IsoRefPoint endRef,
  required double endOffsetMm,
  required double gapMm,
  required int welds,
}) {
  final startStop = stopForRefPoint(startRef);
  final endStop = stopForRefPoint(endRef);
  return PrefabEngine.cutLengthMm(
    isoValueMm: isoMm,
    // Both stops are known exactly here, so the engine is given them
    // outright and needs no DimRef to guess from — which also lets the
    // builder express shapes DimRef cannot name, such as far-face on BOTH
    // anchors.
    leftStop: startStop,
    rightStop: endStop,
    leftCteMm: startStop == SideStop.centre ? startOffsetMm : null,
    leftPhysicalLenMm: startStop == SideStop.end ? startOffsetMm : null,
    rightCteMm: endStop == SideStop.centre ? endOffsetMm : null,
    rightPhysicalLenMm: endStop == SideStop.end ? endOffsetMm : null,
    weldGapMm: gapMm,
    weldCount: welds,
  );
}

// ─── Label dla typu komponentu ─────────────────────────────────────────────
String _typeLabel(BuildContext ctx, String type) {
  switch (type) {
    case 'ELB90':   return ctx.tr(pl: 'Kolano 90°', en: 'Elbow 90°');
    case 'ELB45':   return ctx.tr(pl: 'Kolano 45°', en: 'Elbow 45°');
    case 'TEE':     return ctx.tr(pl: 'Trójnik',    en: 'Tee');
    case 'REDUCER': return ctx.tr(pl: 'Redukcja',   en: 'Reducer');
    case 'FLANGE':  return ctx.tr(pl: 'Kołnierz',   en: 'Flange');
    case 'VALVE':   return ctx.tr(pl: 'Zawór',      en: 'Valve');
    default:        return type;
  }
}

// ─── Tagi elementów logicznych ────────────────────────────────────────────
// Both strings are also the type codes the palette buttons send into
// `_addFromType`, and are written there as literals — keep them in step.

/// Tag of the pipe that every segment is built around.
const String kPipeTag = 'PIPE';

/// Tag of a logical (library-less) end of a segment.
const String kOpenEndTag = 'OPEN_END';

/// Whether a picked sequence forms one complete, measurable segment.
///
/// A segment is a single length of pipe between two anchors, so the only
/// complete shape is START → PIPE → END: three entries with the pipe in the
/// middle. Anything shorter has nothing to cut; a pipe anywhere but the
/// middle means two components were picked back to back.
///
/// Pulled out of the widget as a pure function over the tag list because this
/// one rule gates three separate things — whether the ISO field is shown,
/// whether CUT is computed at all, and whether a further palette tap is
/// rejected as "segment already complete" — and it can be tested here without
/// pumping a screen or touching the component-library database.
bool isSegmentSequenceComplete(List<String> tags) =>
    tags.length >= 3 && tags[1] == kPipeTag;

/// Splits a stored `segments.iso_ref` back into its START and END codes.
///
/// The column holds both reference points joined with '|' (see the save
/// payload at the bottom of this screen), e.g. 'AXIS|FACE_NEAR'. Rows written
/// before that encoding existed hold the plain default 'FACE', and rows can
/// in principle hold anything, so this never throws: a missing half comes
/// back as an empty string and [isoRefPointFromCode] falls back to the
/// component's own default rather than silently measuring from the wrong
/// point — which would change the cut length.
({String start, String end}) splitIsoRef(String isoRef) {
  final parts = isoRef.split('|');
  return (
    start: parts.isNotEmpty ? parts[0].trim() : '',
    end: parts.length > 1 ? parts[1].trim() : '',
  );
}

/// Decodes one half of a stored `iso_ref` into a reference point.
///
/// Unknown or legacy codes ('FACE', '') resolve to [fallback] — the default
/// point for that component type — never to an arbitrary enum value.
IsoRefPoint isoRefPointFromCode(String code, {required IsoRefPoint fallback}) {
  for (final p in IsoRefPoint.values) {
    if (p.code == code) return p;
  }
  return fallback;
}

// ─── Picked ────────────────────────────────────────────────────────────────
class _Picked {
  final String tag;
  final LibraryComponent? component;
  final IsoRefPoint refPoint;

  _Picked({required this.tag, required this.component, required this.refPoint});

  bool get isLogical => component == null;
  bool get isAxial   => component?.isAxial ?? false;

  double get offsetMm {
    if (isLogical) return 0;
    return _calcOffset(component!, refPoint);
  }

  String chipLabel(BuildContext ctx) {
    if (tag == 'OPEN_END') return ctx.tr(pl: 'Open end', en: 'Open end');
    if (tag == 'PIPE')     return ctx.tr(pl: 'Rura',     en: 'Pipe');
    return _typeLabel(ctx, component?.type ?? tag);
  }

  String refLabel(BuildContext ctx) {
    if (isLogical) return '';
    return refPoint.shortLabel(ctx);
  }
}

// ─── SegmentBuilderScreen ──────────────────────────────────────────────────
class SegmentBuilderScreen extends StatefulWidget {
  final String materialGroup;
  final double currentDiameter;
  final double wallThickness;
  final double gapMm;

  /// Segment being corrected, or null when a brand-new one is being built.
  ///
  /// Until this existed a saved segment was read-only: a mistyped ISO value
  /// (3450 for 3540) could only be fixed by deleting the segment and
  /// rebuilding the entire sequence — palette, START, pipe, palette, END,
  /// dimension — in gloves, on a scaffold. When set, the screen opens with
  /// the sequence and the ISO expression already restored and the caller
  /// writes the result back with UPDATE instead of INSERT.
  final Segment? existing;

  const SegmentBuilderScreen({
    super.key,
    required this.materialGroup,
    required this.currentDiameter,
    required this.wallThickness,
    required this.gapMm,
    this.existing,
  });

  @override
  State<SegmentBuilderScreen> createState() => _SegmentBuilderScreenState();
}

class _SegmentBuilderScreenState extends State<SegmentBuilderScreen> {
  final _dao = ComponentLibraryDao();
  static const _uuid = Uuid();

  final List<_Picked> _sequence = [];

  List<String> get _tags => [for (final p in _sequence) p.tag];

  bool get hasStart => _sequence.isNotEmpty;
  bool get hasEnd   => _sequence.length >= 3;
  bool get readyForIso => isSegmentSequenceComplete(_tags);

  _Picked? get _startPicked => hasStart ? _sequence[0] : null;
  _Picked? get _endPicked   => hasEnd   ? _sequence[2] : null;

  bool get _isEditing => widget.existing != null;

  final _isoController = TextEditingController();
  double? _isoMm;
  double? _cutMm;
  String? _error;
  bool _saving = false;

  /// Signature of the state the screen opened with: empty for a new segment,
  /// the restored segment for a correction. See [_isDirty].
  String _baseline = '';

  String _tr(String pl, String en) => context.tr(pl: pl, en: en);

  /// Everything a save would write, flattened into one comparable string.
  /// The offsets are derived from component + reference point, so those two
  /// plus the tag fully describe a pick.
  String _signature() => [
        for (final p in _sequence)
          '${p.tag}/${p.component?.id ?? ''}/${p.refPoint.code}',
        _isoController.text.trim(),
      ].join('|');

  // Dirty when the fitter changed something since the screen opened — an
  // accidental swipe-back on a shop-floor phone would silently wipe it.
  //
  // Compared against a baseline rather than asking "is anything filled in?":
  // in edit mode the answer to that is always yes, so merely opening a
  // segment to read it and backing out would raise a "discard?" dialog and
  // train the fitter to dismiss the one prompt that protects real work.
  bool get _isDirty => !_saving && _signature() != _baseline;

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isEditing
            ? _tr('Porzucić poprawki?', 'Discard changes?')
            : _tr('Porzucić segment?', 'Discard segment?')),
        content: Text(_isEditing
            ? _tr(
                'Segment zostanie bez zmian — poprawki nie zostaną zapisane.',
                'The segment stays as it was — your changes will be lost.',
              )
            : _tr(
                'Sekwencja i wpisany wymiar ISO zostaną utracone.',
                'The sequence and entered ISO value will be lost.',
              )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Wróć do edycji', 'Keep editing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Porzuć', 'Discard')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  void initState() {
    super.initState();
    // Post-frame rather than straight from initState: the restore reports
    // problems through ScaffoldMessenger and localises them with `context.tr`
    // (an InheritedWidget lookup), and neither is legal until the element is
    // mounted in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreExisting());
  }

  @override
  void dispose() {
    _isoController.dispose();
    super.dispose();
  }

  // ── Odtworzenie zapisanego segmentu (tryb edycji) ──────────────────────
  /// Rebuilds the on-screen sequence and ISO expression from a saved segment.
  ///
  /// Only the two anchors are stored (`start_*` / `end_*`); the pipe between
  /// them is implied by the shape of every segment, so it is re-inserted here.
  /// Offsets are deliberately NOT taken from the stored `*_value_mm` columns
  /// but recomputed from the library component and reference point, so that a
  /// takeout corrected in the library since (a 76.2 typed as 762) is picked up
  /// by this edit instead of being frozen into the row forever.
  Future<void> _restoreExisting() async {
    final seg = widget.existing;
    if (seg == null) return;

    final refs = splitIsoRef(seg.isoRef);
    final start = await _restorePick(seg.startLibraryId, refs.start);
    if (!mounted) return;
    final end = start == null
        ? null
        : await _restorePick(seg.endLibraryId, refs.end);
    if (!mounted) return;

    setState(() {
      if (start != null) {
        _sequence
          ..add(start)
          ..add(_Picked(
              tag: kPipeTag, component: null, refPoint: IsoRefPoint.open));
        if (end != null) _sequence.add(end);
      }
      _isoController.text = seg.isoExpr;
      // Inside the same setState as the restore itself: _isDirty is read
      // during build (PopScope.canPop), so a baseline assigned afterwards
      // would leave the screen looking dirty for one frame and pop a
      // "discard changes?" dialog at a fitter who only pressed back.
      _baseline = _signature();
    });
    _recalc();

    // A component can be missing if it was deleted from the library after the
    // segment was welded, and then the sequence cannot be shown complete.
    // Say so plainly instead of leaving a half-built segment unexplained, and
    // carry the saved ISO expression in the message: rebuilding the sequence
    // clears the ISO field by design, so this is the fitter's only chance to
    // see the dimension without walking back to the drawing.
    if (!isSegmentSequenceComplete(_tags) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(_tr(
          'Komponentu z biblioteki już nie ma — wybierz go ponownie. '
              'Zapisany wymiar ISO: ${seg.isoExpr}',
          'A component is gone from the library — pick it again. '
              'Saved ISO dimension: ${seg.isoExpr}',
        )),
      ));
    }
  }

  Future<_Picked?> _restorePick(String? libraryId, String refCode) async {
    if (libraryId == null) {
      // No library row means the anchor was logical, and OPEN_END is the only
      // logical anchor a segment can start or finish on (PIPE lives strictly
      // in the middle).
      return _Picked(
          tag: kOpenEndTag, component: null, refPoint: IsoRefPoint.open);
    }
    final comp = await _dao.getById(libraryId);
    if (comp == null) return null;
    return _Picked(
      tag: comp.type,
      component: comp,
      refPoint: isoRefPointFromCode(refCode, fallback: _defaultRefPoint(comp)),
    );
  }

  // ── Obliczenie CUT ─────────────────────────────────────────────────────
  void _recalc() {
    setState(() {
      _error = null;
      _isoMm = null;
      _cutMm = null;
      if (!readyForIso) return;
      try {
        final iso = parseIsoExpression(_isoController.text);
        if (iso <= 0) {
          _error = _tr('ISO musi być > 0', 'ISO must be > 0');
          return;
        }
        // One formula, in PrefabEngine — including the weld gap, which used
        // to be subtracted here and nowhere else, so the same run measured
        // in the ISO notebook came out `welds × gap` longer.
        final cut = builderCutMm(
          isoMm: iso,
          startRef: _startPicked!.refPoint,
          startOffsetMm: _startPicked!.offsetMm,
          endRef: _endPicked!.refPoint,
          endOffsetMm: _endPicked!.offsetMm,
          gapMm: widget.gapMm,
          welds: (_startPicked!.tag == 'OPEN_END') ? 1 : 2,
        );
        _isoMm = iso;
        _cutMm = cut;
        // The engine answers NaN — not a negative number — for anything it
        // refuses to hand to the saw, so the guard tests finiteness rather
        // than the sign.
        if (!cut.isFinite || cut <= 0) {
          // The '≤' had been stored double-encoded (UTF-8 bytes re-read as
          // Latin-1), so the one message meant to STOP an impossible cut
          // rendered as three garbage glyphs on site and was ignored.
          _error = _tr('CUT ≤ 0 — sprawdź wymiary', 'CUT ≤ 0 — check dimensions');
        }
      } catch (e) {
        _error = '${_tr('Błąd', 'Error')}: $e';
      }
    });
  }

  // ── Wybór komponentu ───────────────────────────────────────────────────
  Future<void> _addFromType(String typeOrLogical) async {
    // The "already complete" guard has to run BEFORE anything is cleared.
    // Clearing first meant a mistap on the palette — easy in work gloves —
    // was not just a no-op: it silently wiped the ISO dimension the fitter
    // had already read off the drawing, forcing a re-read and inviting a
    // typo in the value the saw is set from.
    // Two conditions, not one: the sequence is complete (the normal case), or
    // it already holds three picks in some order the fitter has to untangle
    // with the chip X. Dropping the length half would let a tangled sequence
    // grow without limit — it can never be saved, so there is nothing to add.
    if (isSegmentSequenceComplete(_tags) || _sequence.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Ten segment jest kompletny. Zapisz go i dodaj następny.',
            'This segment is complete. Save it and add the next one.')),
      ));
      return;
    }

    // Past this point the sequence is going to change, so any ISO/CUT worked
    // out from the previous one is stale and must not stay on screen.
    setState(() {
      _isoController.text = '';
      _isoMm = null;
      _cutMm = null;
      _error = null;
    });

    // Logiczne (PIPE / OPEN_END)
    if (typeOrLogical == 'PIPE') {
      if (_sequence.isEmpty) {
        _sequence.add(_Picked(tag: 'OPEN_END', component: null, refPoint: IsoRefPoint.open));
      }
      if (_sequence.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_tr('Rura musi być między dwoma elementami.',
              'The pipe must be between two components.')),
        ));
        return;
      }
      setState(() => _sequence.add(
            _Picked(tag: 'PIPE', component: null, refPoint: IsoRefPoint.open)));
      return;
    }

    if (typeOrLogical == 'OPEN_END') {
      if (_sequence.isEmpty || _sequence.length == 2) {
        setState(() => _sequence.add(
              _Picked(tag: 'OPEN_END', component: null, refPoint: IsoRefPoint.open)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('OPEN END dodaj na początku albo na końcu.',
            'Add OPEN END at the beginning or end.')),
      ));
      return;
    }

    if (_sequence.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr('Dodaj najpierw rurę między elementami.',
            'Add the pipe between components first.')),
      ));
      return;
    }

    // Pobierz z biblioteki
    final list = await _dao.listFor(
      materialGroup: widget.materialGroup,
      currentDiameter: widget.currentDiameter,
      wallThickness: widget.wallThickness,
    );
    if (!mounted) return;

    final filtered = list.where((c) => c.type == typeOrLogical).toList();
    LibraryComponent? comp;

    if (filtered.isEmpty) {
      comp = await _createMissingComponent(typeOrLogical);
    } else if (filtered.length == 1) {
      comp = filtered.first;
    } else {
      comp = await showModalBottomSheet<LibraryComponent>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ComponentPickerSheet(type: typeOrLogical, items: filtered),
      );
    }
    if (!mounted || comp == null) return;

    // Wybierz punkt referencyjny ISO
    final isStart = _sequence.isEmpty;
    final refPoint = await showModalBottomSheet<IsoRefPoint>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RefPointSheet(
        component: comp!,
        isStart: isStart,
      ),
    );
    if (!mounted || refPoint == null) return;

    setState(() => _sequence.add(
          _Picked(tag: comp!.type, component: comp, refPoint: refPoint)));
    _recalc();
  }

  Future<LibraryComponent?> _createMissingComponent(String type) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (type == 'REDUCER') {
      final out = await _askValue(
        _tr('Redukcja – średnica WYJŚCIA (mm)', 'Reducer – OUTLET diameter (mm)'),
        'np. 48.3',
      );
      if (out == null) return null;
      final c = LibraryComponent(
        id: _uuid.v4(), materialGroup: widget.materialGroup, type: 'REDUCER',
        diameterMm: widget.currentDiameter, wallThicknessMm: widget.wallThickness,
        axisMm: null, lengthMm: 0, measurementMode: 'FACE',
        diameterOutMm: out, createdAt: now, updatedAt: now,
      );
      await _dao.insert(c);
      return c;
    }

    if (type == 'ELB90' || type == 'ELB45' || type == 'TEE') {
      final axis = await _askValue(
        '${_typeLabel(context, type)} – ${_tr('wymiar do osi (mm)', 'axis dimension (mm)')}',
        'np. 76.2',
      );
      if (axis == null) return null;
      final c = LibraryComponent(
        id: _uuid.v4(), materialGroup: widget.materialGroup, type: type,
        diameterMm: widget.currentDiameter, wallThicknessMm: widget.wallThickness,
        axisMm: axis, lengthMm: null, measurementMode: null,
        diameterOutMm: null, createdAt: now, updatedAt: now,
      );
      await _dao.insert(c);
      return c;
    }

    // Non-axial: długość całkowita
    final len = await _askValue(
      '${_typeLabel(context, type)} – ${_tr('długość całkowita (mm)', 'total length (mm)')}',
      'np. 150',
    );
    if (len == null) return null;
    final c = LibraryComponent(
      id: _uuid.v4(), materialGroup: widget.materialGroup, type: type,
      diameterMm: widget.currentDiameter, wallThicknessMm: widget.wallThickness,
      axisMm: null, lengthMm: len, measurementMode: 'FACE',
      diameterOutMm: null, createdAt: now, updatedAt: now,
    );
    await _dao.insert(c);
    return c;
  }

  Future<double?> _askValue(String title, String hint) async {
    final c = TextEditingController();
    return showDialog<double?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          // Takeouts are decimal millimetres — the hints passed in literally
          // read "np. 76.2" / "np. 48.3" — but TextInputType.number opens the
          // iOS numeric pad, which has NO decimal and NO comma key. The fitter
          // could only enter 762, losing 686 mm into the component library and
          // into every cut computed from it afterwards. The filter keeps both
          // separators because the parse below normalises ',' to '.'.
          // Same field pattern as weld_journal_screen.dart.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(_tr('Anuluj', 'Cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(c.text.replaceAll(',', '.'));
              Navigator.pop(context, (v != null && v > 0) ? v : null);
            },
            child: Text(_tr('OK', 'OK')),
          ),
        ],
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final canSave = (_cutMm != null && _cutMm! > 0);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (discard && mounted) nav.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        // In edit mode name the segment being corrected: the fitter arrives
        // here from a list of numbered segments and must be able to see he
        // opened the right one before he changes a dimension.
        title: Text(_isEditing
            ? _tr('Popraw segment ${widget.existing!.seqNo}',
                'Edit segment ${widget.existing!.seqNo}')
            : _tr('Nowy segment', 'New segment')),
        actions: [HelpButton(help: kHelpSegmentBuilder)],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info o trasie
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, size: 18),
                title: Text('Ø${widget.currentDiameter.toStringAsFixed(1)}  ·  t ${widget.wallThickness.toStringAsFixed(1)} mm  ·  gap ${widget.gapMm.toStringAsFixed(1)} mm'),
              ),
            ),
            const SizedBox(height: 10),

            // Sekwencja
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Sekwencja komponentów', 'Component sequence'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _tr(
                        'Dodaj: KOMP → RURA → KOMP  (lub OPEN_END na początku/końcu)',
                        'Add: COMP → PIPE → COMP  (or OPEN_END at start/end)',
                      ),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9BA3C7)),
                    ),
                    const SizedBox(height: 12),

                    // Chipy wybranej sekwencji
                    if (_sequence.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < _sequence.length; i++) ...[
                              _SequenceChip(
                                picked: _sequence[i],
                                onRemove: () {
                                  // Gloves-friendly: chip's close icon is tiny;
                                  // accidental tap on a cold morning would wipe
                                  // the segment silently. Offer UNDO so the
                                  // fitter can recover without re-picking.
                                  final removedIdx = i;
                                  final removed = _sequence[i];
                                  final prevIso = _isoController.text;
                                  final prevIsoMm = _isoMm;
                                  final prevCutMm = _cutMm;
                                  setState(() {
                                    _sequence.removeAt(i);
                                    _isoController.text = '';
                                    _isoMm = null;
                                    _cutMm = null;
                                    _error = null;
                                  });
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  messenger.hideCurrentSnackBar();
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(_tr(
                                        'Element usunięty.', 'Item removed.')),
                                    duration: const Duration(seconds: 4),
                                    action: SnackBarAction(
                                      label: _tr('COFNIJ', 'UNDO'),
                                      onPressed: () {
                                        if (!mounted) return;
                                        setState(() {
                                          final ins = removedIdx
                                                  .clamp(0, _sequence.length)
                                              .toInt();
                                          _sequence.insert(ins, removed);
                                          _isoController.text = prevIso;
                                          _isoMm = prevIsoMm;
                                          _cutMm = prevCutMm;
                                        });
                                      },
                                    ),
                                  ));
                                },
                              ),
                              if (i < _sequence.length - 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
                                  child: Icon(Icons.arrow_forward_ios,
                                      size: 12, color: Color(0xFF5A6478)),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    _ComponentPalette(onTapType: _addFromType),
                  ],
                ),
              ),
            ),

            // Wizualizacja + ISO input
            if (readyForIso) ...[
              const SizedBox(height: 10),
              _IsoVisualization(
                startPicked: _startPicked!,
                endPicked: _endPicked!,
                gapMm: widget.gapMm,
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _tr('Wymiar ISO z rysunku', 'ISO dimension from drawing'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _tr(
                          'Wyrażenia są dozwolone, np. 3000+525-80',
                          'Expressions allowed, e.g. 3000+525-80',
                        ),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9BA3C7)),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _isoController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: _tr('ISO (mm)', 'ISO (mm)'),
                          hintText: _tr(
                              'np. 3000+525-80, 5*200, (1500+200)*2',
                              'e.g. 3000+525-80, 5*200, (1500+200)*2'),
                          // Live evaluation shown right inside the field so a
                          // fitter does not need to look down at the breakdown.
                          suffixText: _isoMm != null
                              ? '= ${_isoMm!.toStringAsFixed(1)} mm'
                              : 'mm',
                          suffixStyle: _isoMm != null
                              ? const TextStyle(
                                  color: Color(0xFFFF8E1E),
                                  fontWeight: FontWeight.w700)
                              : null,
                        ),
                        onChanged: (_) => _recalc(),
                      ),
                      if (_isoMm != null) ...[
                        const SizedBox(height: 12),
                        // Rozbicie obliczeń
                        _CalcBreakdown(
                          isoMm: _isoMm!,
                          startOffset: _startPicked!.offsetMm,
                          endOffset: _endPicked!.offsetMm,
                          startRefLabel: _startPicked!.refLabel(context),
                          endRefLabel: _endPicked!.refLabel(context),
                          gapMm: widget.gapMm,
                          welds: _startPicked!.tag == 'OPEN_END' ? 1 : 2,
                          cutMm: _cutMm,
                        ),
                      ],
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 13),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: canSave
                  ? () {
                      Haptic.saved();
                      _saving = true;
                      Navigator.pop(context, {
                        'startKind':     _startPicked!.isLogical ? 'logical' : (_startPicked!.isAxial ? 'axial' : 'nonAxial'),
                        'endKind':       _endPicked!.isLogical   ? 'logical' : (_endPicked!.isAxial   ? 'axial' : 'nonAxial'),
                        'startValue':    _startPicked!.offsetMm,
                        'endValue':      _endPicked!.offsetMm,
                        'isoRef':        '${_startPicked!.refPoint.code}|${_endPicked!.refPoint.code}',
                        'isoExpr':       _isoController.text.trim(),
                        'isoMm':         _isoMm,
                        'cutMm':         _cutMm,
                        'startLibraryId': _startPicked!.component?.id,
                        'endLibraryId':   _endPicked!.component?.id,
                      });
                    }
                  : null,
              icon: const Icon(Icons.check),
              label: Text(_isEditing
                  ? _tr('Zapisz zmiany', 'Save changes')
                  : _tr('Zapisz segment', 'Save segment')),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Chip w sekwencji ─────────────────────────────────────────────────────
class _SequenceChip extends StatelessWidget {
  final _Picked picked;
  final VoidCallback onRemove;
  const _SequenceChip({required this.picked, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final label  = picked.chipLabel(context);
    final refLbl = picked.refLabel(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF22263A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3140)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (picked.component != null)
            ComponentIcon(type: picked.component!.type, size: 16)
          else
            const Icon(Icons.open_in_new, size: 16, color: Color(0xFF9BA3C7)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE7ECF3))),
              if (refLbl.isNotEmpty)
                Text(refLbl,
                    style: const TextStyle(fontSize: 10, color: Color(0xFFFF8E1E))),
            ],
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14, color: Color(0xFF5A6478)),
          ),
        ],
      ),
    );
  }
}

// ─── Wizualizacja schematu ISO ────────────────────────────────────────────
class _IsoVisualization extends StatelessWidget {
  final _Picked startPicked;
  final _Picked endPicked;
  final double gapMm;
  const _IsoVisualization({
    required this.startPicked, required this.endPicked, required this.gapMm});

  @override
  Widget build(BuildContext context) {
    final startOff = startPicked.offsetMm;
    final endOff   = endPicked.offsetMm;
    final startRef = startPicked.isLogical ? '' : startPicked.refPoint.shortLabel(context);
    final endRef   = endPicked.isLogical   ? '' : endPicked.refPoint.shortLabel(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF8E1E).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.straighten, size: 14, color: const Color(0xFFFF8E1E).withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                context.tr(pl: 'Schemat pomiaru ISO', en: 'ISO measurement diagram'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9BA3C7)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // START
              Expanded(
                flex: 2,
                child: _CompBlock(
                  label: startPicked.chipLabel(context),
                  refLabel: startRef,
                  offsetMm: startOff,
                  isStart: true,
                ),
              ),
              // RURA
              Expanded(
                flex: 3,
                child: Container(
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22263A),
                    border: Border.all(color: const Color(0xFFFF8E1E)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      context.tr(pl: 'RURA', en: 'PIPE'),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFFF8E1E), fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              // END
              Expanded(
                flex: 2,
                child: _CompBlock(
                  label: endPicked.chipLabel(context),
                  refLabel: endRef,
                  offsetMm: endOff,
                  isStart: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                startOff > 0 ? '← ${startOff.toStringAsFixed(1)} mm' : '← 0 mm',
                style: const TextStyle(fontSize: 10, color: Color(0xFF5A6478)),
              ),
              Text(
                context.tr(pl: '── ISO ──', en: '── ISO ──'),
                style: const TextStyle(fontSize: 10, color: Color(0xFF9BA3C7), letterSpacing: 1),
              ),
              Text(
                endOff > 0 ? '${endOff.toStringAsFixed(1)} mm →' : '0 mm →',
                style: const TextStyle(fontSize: 10, color: Color(0xFF5A6478)),
              ),
            ],
          ),
          if (gapMm > 0) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                pl: '+ gap: ${gapMm.toStringAsFixed(1)} mm × ${startPicked.tag == 'OPEN_END' ? 1 : 2} sp.',
                en: '+ gap: ${gapMm.toStringAsFixed(1)} mm × ${startPicked.tag == 'OPEN_END' ? 1 : 2} welds',
              ),
              style: const TextStyle(fontSize: 10, color: Color(0xFF4A9EFF)),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompBlock extends StatelessWidget {
  final String label;
  final String refLabel;
  final double offsetMm;
  final bool isStart;
  const _CompBlock({
    required this.label, required this.refLabel,
    required this.offsetMm, required this.isStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF22263A),
        border: Border.all(color: const Color(0xFF2A3140)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 9, color: Color(0xFFE7ECF3)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (refLabel.isNotEmpty)
                  Text(refLabel,
                      style: const TextStyle(fontSize: 8, color: Color(0xFFFF8E1E))),
              ],
            ),
          ),
          // Marker punktu referencyjnego
          Positioned(
            top: 0, bottom: 0,
            left: isStart ? null : 0,
            right: isStart ? 0 : null,
            child: Container(width: 2, color: const Color(0xFFFF8E1E).withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

// ─── Rozbicie obliczeń CUT ────────────────────────────────────────────────
class _CalcBreakdown extends StatelessWidget {
  final double isoMm;
  final double startOffset;
  final double endOffset;
  final String startRefLabel;
  final String endRefLabel;
  final double gapMm;
  final int welds;
  final double? cutMm;

  const _CalcBreakdown({
    required this.isoMm,
    required this.startOffset,
    required this.endOffset,
    required this.startRefLabel,
    required this.endRefLabel,
    required this.gapMm,
    required this.welds,
    required this.cutMm,
  });

  @override
  Widget build(BuildContext context) {
    final gapTotal = gapMm * welds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3140)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(label: 'ISO', value: '${isoMm.toStringAsFixed(1)} mm'),
          if (startOffset > 0)
            _Row(
              label: context.tr(pl: '− offset start ($startRefLabel)', en: '− start offset ($startRefLabel)'),
              value: '− ${startOffset.toStringAsFixed(1)} mm',
              dimmed: true,
            ),
          if (endOffset > 0)
            _Row(
              label: context.tr(pl: '− offset end ($endRefLabel)', en: '− end offset ($endRefLabel)'),
              value: '− ${endOffset.toStringAsFixed(1)} mm',
              dimmed: true,
            ),
          if (gapTotal > 0)
            _Row(
              label: context.tr(
                  pl: '− gap ($welds × ${gapMm.toStringAsFixed(1)} mm)',
                  en: '− gap ($welds × ${gapMm.toStringAsFixed(1)} mm)'),
              value: '− ${gapTotal.toStringAsFixed(1)} mm',
              dimmed: true,
            ),
          const Divider(height: 14, color: Color(0xFF2A3140)),
          if (cutMm != null)
            Center(
              child: Text(
                // The engine reports "not a cuttable length" as NaN, and
                // 'CUT = NaN mm' is a number-shaped thing a tired fitter can
                // mistake for one. A dash says plainly there is nothing to
                // cut; the red stop message below the breakdown says why.
                cutMm!.isFinite
                    ? 'CUT = ${cutMm!.toStringAsFixed(1)} mm'
                    : 'CUT = —',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: (cutMm!.isFinite && cutMm! > 0)
                      ? const Color(0xFFFF8E1E)
                      : const Color(0xFFE74C3C),
                  letterSpacing: -0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool dimmed;
  const _Row({required this.label, required this.value, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? const Color(0xFF5A6478) : const Color(0xFF9BA3C7);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: color))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ─── Bottom sheet: wybór punktu referencyjnego ────────────────────────────
class _RefPointSheet extends StatelessWidget {
  final LibraryComponent component;
  final bool isStart;
  const _RefPointSheet({required this.component, required this.isStart});

  @override
  Widget build(BuildContext context) {
    final available  = _availableRefPoints(component);
    final defaultRef = _defaultRefPoint(component);
    final compLen    = component.isAxial ? component.axisMm : component.lengthMm;

    final titleKey = isStart
        ? context.tr(pl: 'Gdzie ZACZYNA się wymiar ISO?', en: 'Where does the ISO START?')
        : context.tr(pl: 'Gdzie KOŃCZY się wymiar ISO?',  en: 'Where does the ISO END?');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Komponent
            Row(
              children: [
                ComponentIcon(type: component.type, size: 22),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(context, component.type),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE7ECF3)),
                    ),
                    Text(
                      'Ø${component.diameterMm.toStringAsFixed(1)}  t${component.wallThicknessMm.toStringAsFixed(1)}'
                      '${compLen != null ? "  L=${compLen.toStringAsFixed(1)} mm" : ""}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9BA3C7)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Pytanie
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8E1E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF8E1E).withValues(alpha: 0.3)),
              ),
              child: Text(
                titleKey,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFFF8E1E)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),

            // Diagram
            _RefDiagram(component: component, available: available, defaultRef: defaultRef),
            const SizedBox(height: 14),

            // Przyciski
            ...available.map((ref) {
              final offset    = _calcOffset(component, ref);
              final isDefault = ref == defaultRef;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RefOption(
                  ref: ref,
                  offset: offset,
                  component: component,
                  compLen: compLen,
                  isDefault: isDefault,
                  onTap: () => Navigator.pop(context, ref),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RefOption extends StatelessWidget {
  final IsoRefPoint ref;
  final double offset;
  final LibraryComponent component;
  final double? compLen;
  final bool isDefault;
  final VoidCallback onTap;

  const _RefOption({
    required this.ref, required this.offset, required this.component,
    required this.compLen, required this.isDefault, required this.onTap,
  });

  String _desc(BuildContext ctx) {
    switch (ref) {
      case IsoRefPoint.faceNear:
        return ctx.tr(
          pl: 'Wymiar ISO od/do czoła komponentu przy rurze → offset = 0 mm',
          en: 'ISO from/to the component face at the pipe → offset = 0 mm',
        );
      case IsoRefPoint.axis:
        return ctx.tr(
          pl: 'Standard ISO dla kolan/trójników — od/do osi → offset = ${offset.toStringAsFixed(1)} mm',
          en: 'Standard ISO for elbows/tees — from/to axis → offset = ${offset.toStringAsFixed(1)} mm',
        );
      case IsoRefPoint.center:
        return ctx.tr(
          pl: 'Do środka komponentu (L/2 = ${offset.toStringAsFixed(1)} mm) → offset = ${offset.toStringAsFixed(1)} mm',
          en: 'To the component center (L/2 = ${offset.toStringAsFixed(1)} mm) → offset = ${offset.toStringAsFixed(1)} mm',
        );
      case IsoRefPoint.faceFar:
        return ctx.tr(
          pl: 'Wymiar ISO do dalekiego czoła — odejmuje całą długość (${offset.toStringAsFixed(1)} mm)',
          en: 'ISO to the far face — subtracts full length (${offset.toStringAsFixed(1)} mm)',
        );
      case IsoRefPoint.open:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDefault
              ? const Color(0xFFFF8E1E).withValues(alpha: 0.07)
              : const Color(0xFF141821),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDefault
                ? const Color(0xFFFF8E1E).withValues(alpha: 0.5)
                : const Color(0xFF2A3140),
            width: isDefault ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDefault ? const Color(0xFFFF8E1E) : const Color(0xFF5A6478),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        ref.label(context),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDefault ? const Color(0xFFFF8E1E) : const Color(0xFFE7ECF3),
                        ),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8E1E).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(context.tr(pl: 'domyślny', en: 'default'),
                              style: const TextStyle(fontSize: 9, color: Color(0xFFFF8E1E))),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_desc(context),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9BA3C7))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diagram komponentu z zaznaczonymi punktami ref ───────────────────────
class _RefDiagram extends StatelessWidget {
  final LibraryComponent component;
  final List<IsoRefPoint> available;
  final IsoRefPoint defaultRef;

  const _RefDiagram({
    required this.component, required this.available, required this.defaultRef});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3140)),
      ),
      child: Stack(
        children: [
          // Kształt komponentu
          Positioned(
            left: 36, right: 36, top: 10, bottom: 10,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF22263A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A3140)),
              ),
              child: Center(child: ComponentIcon(type: component.type, size: 22)),
            ),
          ),
          // Lewa: FACE_NEAR
          if (available.contains(IsoRefPoint.faceNear))
            Positioned(
              left: 6, top: 0, bottom: 0,
              child: _DiagramDot(
                label: context.tr(pl: 'czoło\nbliskie', en: 'near\nface'),
                isDefault: defaultRef == IsoRefPoint.faceNear,
              ),
            ),
          // Środek: AXIS lub CENTER
          if (available.contains(IsoRefPoint.axis) || available.contains(IsoRefPoint.center))
            Positioned(
              left: 0, right: 0, top: 0, bottom: 0,
              child: Center(
                child: _DiagramDot(
                  label: component.isAxial
                      ? context.tr(pl: 'oś', en: 'axis')
                      : context.tr(pl: 'środek', en: 'center'),
                  isDefault: defaultRef == IsoRefPoint.axis || defaultRef == IsoRefPoint.center,
                ),
              ),
            ),
          // Prawa: FACE_FAR
          if (available.contains(IsoRefPoint.faceFar))
            Positioned(
              right: 6, top: 0, bottom: 0,
              child: _DiagramDot(
                label: context.tr(pl: 'czoło\ndalekie', en: 'far\nface'),
                isDefault: defaultRef == IsoRefPoint.faceFar,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiagramDot extends StatelessWidget {
  final String label;
  final bool isDefault;
  const _DiagramDot({required this.label, required this.isDefault});

  @override
  Widget build(BuildContext context) {
    final color = isDefault ? const Color(0xFFFF8E1E) : const Color(0xFF4A9EFF);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color,
            boxShadow: isDefault ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)] : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 7, color: color, height: 1.2)),
      ],
    );
  }
}

// ─── Paleta komponentów ───────────────────────────────────────────────────
class _ComponentPalette extends StatelessWidget {
  final void Function(String) onTapType;
  const _ComponentPalette({required this.onTapType});

  Widget _btn(BuildContext ctx, String type, String label, bool axial) {
    return InkWell(
      onTap: () => onTapType(type),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: axial ? const Color(0xFF1A3040) : const Color(0xFF2A2520),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: axial
                ? const Color(0xFF4A9EFF).withValues(alpha: 0.3)
                : const Color(0xFFFF8E1E).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (type == 'OPEN_END')
              const Icon(Icons.open_in_new, size: 18, color: Color(0xFFE7ECF3))
            else
              ComponentIcon(type: type, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFE7ECF3))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _btn(context, 'ELB90',    context.tr(pl: 'Kolano 90', en: 'Elbow 90'), true),
      _btn(context, 'ELB45',    context.tr(pl: 'Kolano 45', en: 'Elbow 45'), true),
      _btn(context, 'TEE',      context.tr(pl: 'Trójnik',   en: 'Tee'),      true),
      _btn(context, 'PIPE',     context.tr(pl: 'Rura',      en: 'Pipe'),     true),
      _btn(context, 'REDUCER',  context.tr(pl: 'Redukcja',  en: 'Reducer'),  false),
      _btn(context, 'FLANGE',   context.tr(pl: 'Kołnierz',  en: 'Flange'),   false),
      _btn(context, 'VALVE',    context.tr(pl: 'Zawór',     en: 'Valve'),    false),
      _btn(context, 'OTHER',    context.tr(pl: 'Inne',      en: 'Other'),    false),
      _btn(context, 'OPEN_END', 'Open end',                                  false),
    ]);
  }
}

// ─── Picker komponentu z biblioteki ──────────────────────────────────────
class _ComponentPickerSheet extends StatelessWidget {
  final String type;
  final List<LibraryComponent> items;
  const _ComponentPickerSheet({required this.type, required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Material(
          child: ListView(
            controller: scroll,
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              Text(
                '${context.tr(pl: 'Wybierz', en: 'Select')}: ${_typeLabel(context, type)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...items.map((c) => ListTile(
                    leading: ComponentIcon(type: c.type),
                    title: Text(c.displayLabel()),
                    onTap: () => Navigator.pop(context, c),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

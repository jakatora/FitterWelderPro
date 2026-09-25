/// Everything a scanned isometric gives the fitter and the welder beyond the
/// cut list: which cuts can be saved now, the weld map (numbers from the
/// drawing or W-001…, shop / field, size, wall, material), the spools, the
/// scan's own bill of materials compared with the drawing's, and the weld
/// journal entries the weld map becomes.
///
/// Pure Dart: no database, no network, no BuildContext. The review screen
/// renders these and the DAOs write them; tests check them directly.
library;

import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_ndt.dart';
import 'iso_scanner_ai.dart';
import 'scan_graph.dart';
import 'scan_to_project.dart';

// ─────────────────────────────────────────────────────────────────────────
// Review gate — what can be saved
// ─────────────────────────────────────────────────────────────────────────

/// Which issues are still open after the fitter's answers, which cuts can
/// be saved now and whether the project can be saved at all.
///
/// Spec §2 rule 6 / §9: an uncertain value blocks the CUT it concerns, not
/// the whole project. So a gap that belongs to a run blocks that run only —
/// the rest is saved, and the blocked runs are listed before the save. Only
/// a gap about the project as a whole (diameter, wall, material, a failed
/// scan) blocks everything.
class ScanReviewGate {
  /// Open blocking issues, project-level ones first.
  final List<ScanIssue> openGaps;

  /// Open issues with no run of their own — they block every save.
  final List<ScanIssue> projectGaps;

  /// Runs that can be written now (complete, nothing open on them).
  final List<PlannedSegment> savable;

  /// Runs that stay out of the save until their issues are answered.
  final List<PlannedSegment> blocked;

  /// The header fields every saved row needs.
  final bool headerComplete;

  const ScanReviewGate({
    required this.openGaps,
    required this.projectGaps,
    required this.savable,
    required this.blocked,
    required this.headerComplete,
  });

  /// Whether the project (with [savable]) can be saved.
  bool get canSaveProject =>
      headerComplete && projectGaps.isEmpty && savable.isNotEmpty;

  /// Whether every run is savable — nothing is left behind.
  bool get savesEverything => canSaveProject && blocked.isEmpty;

  /// Open issues of one run.
  List<ScanIssue> gapsFor(String segmentId) =>
      openGaps.where((g) => g.segmentId == segmentId).toList(growable: false);
}

/// The gate for [plan] with the fitter's references applied ([segments]).
///
/// A gap disappears only when the answer actually produced the missing
/// value — answering the reference question with an option that still
/// yields no cut keeps the run blocked. A run that is somehow not complete
/// with no gap explaining why gets one of its own (belt and braces), so no
/// incomplete row can ever be written.
ScanReviewGate evaluateReview({
  required ScanPlan plan,
  required List<PlannedSegment> segments,
  required String? materialGroup,
  required bool headerComplete,
}) {
  final open = <ScanIssue>[];
  for (final gap in plan.gaps) {
    switch (gap.code) {
      case ScanIssueCode.missingMaterialGroup:
        if (materialGroup == null) open.add(gap);
      case ScanIssueCode.dimensionReferenceUnknown:
        final seg = segments.where((s) => s.sourceId == gap.segmentId);
        if (seg.isEmpty || seg.first.cutMm == null) open.add(gap);
      default:
        open.add(gap);
    }
  }
  final explained = open.map((g) => g.segmentId).toSet();
  for (final seg in segments) {
    if (seg.isComplete || explained.contains(seg.sourceId)) continue;
    open.add(ScanIssue(
      code: ScanIssueCode.cutImpossible,
      blocking: true,
      segmentId: seg.sourceId,
      pl: 'Odcinek ${seg.label}: brak kompletu danych do zapisu '
          '(wymiar, take-outy, średnica albo odniesienie).',
      en: 'Run ${seg.label}: not enough data to save it '
          '(dimension, take-outs, size or reference).',
    ));
  }
  final projectGaps = open.where((g) => g.segmentId == null).toList();
  final blockedIds = open.map((g) => g.segmentId).whereType<String>().toSet();
  final savable = <PlannedSegment>[];
  final blocked = <PlannedSegment>[];
  for (final s in segments) {
    (s.isComplete && !blockedIds.contains(s.sourceId) ? savable : blocked)
        .add(s);
  }
  return ScanReviewGate(
    openGaps: [...projectGaps, ...open.where((g) => g.segmentId != null)],
    projectGaps: projectGaps,
    savable: savable,
    blocked: blocked,
    headerComplete: headerComplete,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// Weld map
// ─────────────────────────────────────────────────────────────────────────

enum WeldSource {
  /// Marked on the drawing (a dot / FW symbol, with or without a number).
  drawing,

  /// Not marked: one weld per pipe end joined to a fitting, numbered by
  /// the app (W-001…).
  derived,
}

/// One joint of the weld map.
class PlannedWeld {
  /// Number as on the drawing, or `W-001`… when the app numbered it.
  final String number;
  final WeldSource source;

  /// True when [number] was given by the app, not printed.
  final bool numberAssigned;

  /// `shop`, `field`, or null when the drawing does not say.
  final String? location;

  /// [WeldJointType] code (`BW`, `SW`, `BR`, `FW`) or empty.
  final String jointType;

  /// Runs this weld sits on (usually one).
  final List<String> segmentIds;

  /// Component the pipe is welded to, when known.
  final String? componentId;

  final String? spoolId;
  final int? dn;
  final double? odMm;
  final double? wallMm;
  final String? nde;
  final bool? pwht;
  final String? position;
  final AiConfidence confidence;

  const PlannedWeld({
    required this.number,
    required this.source,
    this.numberAssigned = false,
    this.location,
    this.jointType = '',
    this.segmentIds = const [],
    this.componentId,
    this.spoolId,
    this.dn,
    this.odMm,
    this.wallMm,
    this.nde,
    this.pwht,
    this.position,
    this.confidence = AiConfidence.unknown,
  });

  bool get isField => location == 'field';
}

const Set<String> _notJoined = {
  'weld', 'fieldWeld', 'support', 'instrument', 'spoolBreak', 'northArrow',
  'flowArrow', 'text',
};

/// The weld map of a scan: the welds marked on the drawing, or — when the
/// drawing marks none — one weld at every pipe end joined to a fitting.
List<PlannedWeld> buildWeldMap(AiScanResult scan, List<PlannedSegment> segments) {
  final byPart = <String, PlannedSegment>{};
  for (final s in segments) {
    for (final id in s.sourceParts) {
      byPart[id] = s;
    }
    byPart[s.sourceId] = s;
  }
  final components = {
    for (final c in scan.components)
      if (c.id.isNotEmpty) c.id: c,
  };
  List<PlannedSegment> touching(String componentId) => [
        for (final s in segments)
          if (s.start.componentId == componentId ||
              s.end.componentId == componentId)
            s,
      ];

  PlannedWeld fromDrawing({
    required String? number,
    required String? location,
    required String? jointType,
    required List<PlannedSegment> segs,
    required String? componentId,
    required String? spool,
    String? nde,
    bool? pwht,
    String? position,
    required AiConfidence confidence,
  }) {
    final seg = segs.isEmpty ? null : segs.first;
    return PlannedWeld(
      number: number ?? '',
      source: WeldSource.drawing,
      location: location,
      jointType: jointType ?? '',
      segmentIds: [for (final s in segs) s.sourceId],
      componentId: componentId,
      spoolId: spool ?? seg?.spoolId,
      dn: seg?.dn,
      odMm: seg?.diameterMm,
      wallMm: seg?.wallThicknessMm,
      nde: nde,
      pwht: pwht,
      position: position,
      confidence: confidence,
    );
  }

  final marked = <PlannedWeld>[];
  for (final w in scan.weldMarks) {
    final segs = <PlannedSegment>[];
    String? comp;
    for (final id in w.betweenIds) {
      final s = byPart[id];
      if (s != null && !segs.contains(s)) {
        segs.add(s);
      } else if (components.containsKey(id)) {
        comp ??= id;
      }
    }
    if (segs.isEmpty && comp != null) segs.addAll(touching(comp).take(1));
    marked.add(fromDrawing(
      number: w.number,
      location: w.location,
      jointType: w.jointType,
      segs: segs,
      componentId: comp,
      spool: w.spoolId,
      nde: w.nde,
      pwht: w.pwht,
      position: w.position,
      confidence: w.confidence,
    ));
  }
  // Legacy markers: weld / field-weld components (a v1 reading).
  final markedNumbers = marked.map((w) => w.number).toSet();
  for (final c in scan.welds) {
    final no = c.weldNo;
    if (no != null && markedNumbers.contains(no)) continue;
    final field = c.isField == true || scanToolName(c) == 'fieldWeld';
    marked.add(fromDrawing(
      number: no,
      location: field ? 'field' : (c.type == 'weld' ? 'shop' : null),
      jointType: c.weldType == 'FW' ? 'FW' : c.weldType,
      segs: touching(c.id).take(1).toList(),
      componentId: c.id,
      spool: c.spoolId,
      nde: c.weldNde,
      pwht: c.weldPwht,
      position: c.weldPosition,
      confidence: c.confidence,
    ));
  }
  if (marked.isNotEmpty) return _numberMissing(marked);

  // ── Derived: one joint per pipe end on a welded fitting ───────────────
  final derived = <PlannedWeld>[];
  final seen = <String>{};
  String? spoolAt(String componentId) {
    final spools = touching(componentId).map((s) => s.spoolId).toSet();
    if (spools.length == 1) return spools.single;
    return null;
  }

  String? locationAt(String componentId) {
    final spools = touching(componentId).map((s) => s.spoolId).toSet();
    if (spools.contains(null) || spools.isEmpty) return null;
    return spools.length == 1 ? 'shop' : 'field';
  }

  for (final s in segments) {
    for (final e in [s.start, s.end]) {
      final id = e.componentId;
      if (id == null || !e.isResolved) continue;
      final c = components[id];
      final tool = e.tool;
      if (c == null || tool == null || _notJoined.contains(tool)) continue;
      final end = scanEndType(c);
      if (end == 'THD') continue; // screwed, not welded
      if (tool.endsWith('Valve') && end != 'BW' && end != 'SW') continue;
      if (tool == 'blindFlange') continue;
      final key = '$id@${s.sourceId}';
      if (!seen.add(key)) continue;
      final joint = end == 'SW' || (tool == 'flange' && scanIsSlipOnFlange(c))
          ? (end == 'SW' ? WeldJointType.socket : WeldJointType.fillet)
          : WeldJointType.butt;
      derived.add(PlannedWeld(
        number: '',
        source: WeldSource.derived,
        location: locationAt(id),
        jointType: joint,
        segmentIds: [s.sourceId],
        componentId: id,
        spoolId: s.spoolId ?? spoolAt(id),
        dn: s.dn,
        odMm: s.diameterMm,
        wallMm: s.wallThicknessMm,
        confidence: AiConfidence.unknown,
      ));
    }
  }
  // An olet is welded onto its header too (a branch connection).
  for (final c in components.values) {
    if (!isOletComponent(c)) continue;
    final header = segments.where((s) => _mergedAt(s, scan, c.id));
    final h = header.isEmpty ? null : header.first;
    derived.add(PlannedWeld(
      number: '',
      source: WeldSource.derived,
      location: h == null ? null : 'shop',
      jointType: WeldJointType.branch,
      segmentIds: h == null ? const [] : [h.sourceId],
      componentId: c.id,
      spoolId: h?.spoolId ?? c.spoolId,
      dn: h?.dn,
      odMm: h?.diameterMm,
      wallMm: h?.wallThicknessMm,
    ));
  }
  return _numberMissing(derived);
}

/// Whether merged header [s] was split at olet [oletId] on the drawing.
bool _mergedAt(PlannedSegment s, AiScanResult scan, String oletId) {
  for (final part in s.partIds) {
    for (final raw in scan.segments) {
      if (raw.id == part && (raw.fromId == oletId || raw.toId == oletId)) {
        return true;
      }
    }
  }
  return false;
}

/// Gives every weld without a number the next free `W-001`… .
List<PlannedWeld> _numberMissing(List<PlannedWeld> welds) {
  final taken = welds.map((w) => w.number.toUpperCase()).toSet();
  var n = 0;
  String next() {
    String candidate;
    do {
      n++;
      candidate = 'W-${n.toString().padLeft(3, '0')}';
    } while (taken.contains(candidate));
    taken.add(candidate);
    return candidate;
  }

  return [
    for (final w in welds)
      w.number.isNotEmpty
          ? w
          : PlannedWeld(
              number: next(),
              source: w.source,
              numberAssigned: true,
              location: w.location,
              jointType: w.jointType,
              segmentIds: w.segmentIds,
              componentId: w.componentId,
              spoolId: w.spoolId,
              dn: w.dn,
              odMm: w.odMm,
              wallMm: w.wallMm,
              nde: w.nde,
              pwht: w.pwht,
              position: w.position,
              confidence: w.confidence,
            ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// Spools
// ─────────────────────────────────────────────────────────────────────────

class ScanSpoolSummary {
  /// Spool id, or null for runs the drawing puts in no spool.
  final String? id;
  final String label;
  final List<PlannedSegment> segments;
  final List<PlannedWeld> welds;

  const ScanSpoolSummary({
    required this.id,
    required this.label,
    required this.segments,
    required this.welds,
  });

  /// Sum of the known cuts, mm.
  double get knownCutMm => segments
      .map((s) => s.cutMm)
      .whereType<double>()
      .fold(0.0, (a, b) => a + b);

  /// Runs with no cut yet.
  int get missingCuts => segments.where((s) => s.cutMm == null).length;

  int get fieldWelds => welds.where((w) => w.isField).length;
}

/// Spools in drawing order, each with its runs and welds. Runs and welds
/// outside every spool end up in one last group (id null).
List<ScanSpoolSummary> buildSpools(AiScanResult scan,
    List<PlannedSegment> segments, List<PlannedWeld> welds) {
  final display = {for (final s in scan.spools) s.id: s.display};
  final order = <String?>[];
  void note(String? id) {
    if (!order.contains(id)) order.add(id);
  }

  for (final s in scan.spools) {
    note(s.id);
  }
  for (final s in segments) {
    note(s.spoolId);
  }
  for (final w in welds) {
    note(w.spoolId);
  }
  // The "no spool" group goes last.
  if (order.remove(null)) order.add(null);
  if (order.length == 1 && order.single == null) {
    return [
      ScanSpoolSummary(
          id: null, label: '—', segments: segments, welds: welds),
    ];
  }
  return [
    for (final id in order)
      ScanSpoolSummary(
        id: id,
        label: id == null ? '—' : (display[id] ?? id),
        segments: segments.where((s) => s.spoolId == id).toList(),
        welds: welds.where((w) => w.spoolId == id).toList(),
      ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────
// Bill of materials: scan vs drawing
// ─────────────────────────────────────────────────────────────────────────

enum BomLineStatus { ok, mismatch, notCompared }

class BomLine {
  final String labelPl;
  final String labelEn;

  /// BOM position number(s) on the drawing, when matched.
  final String? bomItem;

  /// Quantity in the drawing's table, in [unit].
  final double? drawingQty;

  /// Quantity the scan gives (components counted, pipe summed), in [unit].
  final double? scanQty;

  /// `szt` / `pcs` for pieces, `m` for pipe.
  final String unit;
  final BomLineStatus status;
  final String notePl;
  final String noteEn;

  const BomLine({
    required this.labelPl,
    required this.labelEn,
    this.bomItem,
    this.drawingQty,
    this.scanQty,
    required this.unit,
    required this.status,
    this.notePl = '',
    this.noteEn = '',
  });
}

/// Tolerance of the pipe comparison: a BOM usually rounds pipe up and adds
/// a cutting allowance, so the scan's sum is "ok" when it is not more than
/// the BOM and the BOM is not more than this share above it.
const double kBomPipeAllowance = 0.10;

/// Minimum absolute pipe tolerance, mm.
const double kBomPipeToleranceMm = 100;

String? _bomCategory(String description) {
  final d = description.toUpperCase();
  if (RegExp(r'GASKET|USZCZ|BOLT|STUD|NUT\b|ŚRUB|SRUB|NAKRĘT|NAKRET')
      .hasMatch(d)) {
    return null;
  }
  if (RegExp(r'OLET').hasMatch(d)) return 'olet';
  if (RegExp(r'TEE|TRÓJNIK|TROJNIK').hasMatch(d)) return 'tee';
  if (RegExp(r'ELBOW|\bELL\b|KOLANO').hasMatch(d)) {
    return RegExp(r'(?<!\d)45').hasMatch(d) ? 'elbow45' : 'elbow90';
  }
  if (RegExp(r'RED(UCER|\.|\b)|REDUKCJ').hasMatch(d)) return 'reducer';
  if (RegExp(r'BLIND|ŚLEP|SLEP').hasMatch(d)) return 'blindFlange';
  if (RegExp(r'FLANGE|KOŁNIERZ|KOLNIERZ|\bFLG\b').hasMatch(d)) return 'flange';
  if (RegExp(r'\bCAP\b|DENNIC|ZAŚLEPK|ZASLEPK').hasMatch(d)) return 'cap';
  if (RegExp(r'VALVE|ZAWÓR|ZAWOR|ZASUW|PRZEPUSTNIC').hasMatch(d)) {
    return 'valve';
  }
  if (RegExp(r'PIPE|RURA|TUBE|\bRUR').hasMatch(d)) return 'pipe';
  return null;
}

String? _categoryOfTool(String? tool) {
  if (tool == null) return null;
  if (tool.endsWith('Valve')) return 'valve';
  const known = {
    'elbow90', 'elbow45', 'tee', 'olet', 'reducer', 'flange', 'blindFlange',
    'cap',
  };
  return known.contains(tool) ? tool : null;
}

const Map<String, (String, String)> _categoryNames = {
  'elbow90': ('Kolano 90°', 'Elbow 90°'),
  'elbow45': ('Kolano 45°', 'Elbow 45°'),
  'tee': ('Trójnik', 'Tee'),
  'olet': ('Olet', 'Olet'),
  'reducer': ('Redukcja', 'Reducer'),
  'flange': ('Kołnierz', 'Flange'),
  'blindFlange': ('Kołnierz ślepy', 'Blind flange'),
  'cap': ('Dennica / zaślepka', 'Cap'),
  'valve': ('Zawór', 'Valve'),
};

String _qty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// The scan's own bill of materials — fittings counted off the route, pipe
/// summed from the cuts — compared with the table on the drawing.
///
/// A component that names its BOM position (`bomItem`) is compared with
/// exactly that position. Otherwise fittings are matched by kind and size
/// (by kind alone when either side has no size). Gaskets and bolts are not
/// on the route and are listed as not compared. Pipe: the sum of the cuts
/// that are known against the pipe positions converted to mm — only when
/// the table gives a length unit.
List<BomLine> compareBom(AiScanResult scan, List<PlannedSegment> segments) {
  final notation = scan.sizeNotation;
  final lines = <BomLine>[];

  // DN a component sits on: its printed large size, else the largest run.
  int? componentDn(AiComponent c) {
    final (large, _) = scanComponentSizes(c, notation);
    if (large != null) return large;
    int? best;
    for (final s in segments) {
      if (s.start.componentId == c.id || s.end.componentId == c.id) {
        final d = s.dn;
        if (d != null && (best == null || d > best)) best = d;
      }
    }
    return best;
  }

  final fittings = <AiComponent>[
    for (final c in scan.components)
      if (c.id.isNotEmpty && _categoryOfTool(scanToolName(c)) != null) c,
  ];

  // ── By BOM position ──────────────────────────────────────────────────
  final byItem = <String, List<AiComponent>>{};
  for (final c in fittings) {
    final item = c.bomItem;
    if (item != null) (byItem[item] ??= []).add(c);
  }
  final usedItems = <String>{};
  for (final e in byItem.entries) {
    final bom = scan.billOfMaterials.where((b) => b.item == e.key);
    final item = bom.isEmpty ? null : bom.first;
    final cat = _categoryOfTool(scanToolName(e.value.first))!;
    final names = _categoryNames[cat]!;
    usedItems.add(e.key);
    final scanQty = e.value.length.toDouble();
    final drawingQty = item?.quantity;
    final status = drawingQty == null
        ? BomLineStatus.mismatch
        : ((drawingQty - scanQty).abs() < 1e-9
            ? BomLineStatus.ok
            : BomLineStatus.mismatch);
    lines.add(BomLine(
      labelPl: '${names.$1} — poz. ${e.key}${item == null ? '' : ' (${item.description})'}',
      labelEn: '${names.$2} — item ${e.key}${item == null ? '' : ' (${item.description})'}',
      bomItem: e.key,
      drawingQty: drawingQty,
      scanQty: scanQty,
      unit: 'szt',
      status: status,
      notePl: item == null
          ? 'Pozycji ${e.key} nie ma w tabeli materiałowej.'
          : (status == BomLineStatus.ok
              ? ''
              : 'Na trasie ${_qty(scanQty)} szt., w tabeli ${_qty(drawingQty!)}.'),
      noteEn: item == null
          ? 'Item ${e.key} is not in the bill of materials.'
          : (status == BomLineStatus.ok
              ? ''
              : 'Route has ${_qty(scanQty)} pcs, the table ${_qty(drawingQty!)}.'),
    ));
  }

  // ── By kind and size ─────────────────────────────────────────────────
  final scanCount = <String, Map<int?, int>>{};
  for (final c in fittings) {
    if (c.bomItem != null) continue;
    final cat = _categoryOfTool(scanToolName(c))!;
    final m = scanCount[cat] ??= {};
    final dn = componentDn(c);
    m[dn] = (m[dn] ?? 0) + 1;
  }
  final bomCount = <String, Map<int?, double>>{};
  final bomItems = <String, List<String>>{};
  final pipeItems = <AiBomItem>[];
  for (final b in scan.billOfMaterials) {
    if (usedItems.contains(b.item)) continue;
    final cat = _bomCategory(b.description);
    if (cat == 'pipe') {
      pipeItems.add(b);
      continue;
    }
    if (cat == null) {
      lines.add(BomLine(
        labelPl: 'poz. ${b.item}: ${b.description}',
        labelEn: 'item ${b.item}: ${b.description}',
        bomItem: b.item,
        drawingQty: b.quantity,
        unit: b.unit?.toLowerCase() ?? 'szt',
        status: BomLineStatus.notCompared,
        notePl: 'Nie ma tego na trasie rurociągu (np. uszczelki, śruby) — '
            'nie porównywane.',
        noteEn: 'Not part of the pipe route (gaskets, bolts…) — not '
            'compared.',
      ));
      continue;
    }
    final dn = scanSizeToDn(b.size, notation) ??
        scanComponentSizes(
                AiComponent(id: '_', type: cat, label: b.size), notation)
            .$1;
    final m = bomCount[cat] ??= {};
    m[dn] = (m[dn] ?? 0) + (b.quantity ?? 0);
    (bomItems[cat] ??= []).add(b.item);
  }
  final cats = {...scanCount.keys, ...bomCount.keys};
  for (final cat in _categoryNames.keys.where(cats.contains)) {
    final names = _categoryNames[cat]!;
    final s = scanCount[cat] ?? const <int?, int>{};
    final b = bomCount[cat] ?? const <int?, double>{};
    final bySize = !s.containsKey(null) && !b.containsKey(null);
    final keys = bySize ? {...s.keys, ...b.keys}.toList() : <int?>[null];
    keys.sort((x, y) => (x ?? 0).compareTo(y ?? 0));
    for (final dn in keys) {
      final scanQty = bySize
          ? (s[dn] ?? 0).toDouble()
          : s.values.fold<int>(0, (a, v) => a + v).toDouble();
      final drawingQty =
          bySize ? (b[dn] ?? 0) : b.values.fold<double>(0, (a, v) => a + v);
      final inBom = bomCount.containsKey(cat);
      final ok = inBom && (scanQty - drawingQty).abs() < 1e-9;
      final size = dn == null ? '' : ' DN$dn';
      lines.add(BomLine(
        labelPl: '${names.$1}$size',
        labelEn: '${names.$2}$size',
        bomItem: bomItems[cat]?.join(', '),
        drawingQty: inBom ? drawingQty : null,
        scanQty: scanQty,
        unit: 'szt',
        status: ok ? BomLineStatus.ok : BomLineStatus.mismatch,
        notePl: ok
            ? ''
            : !inBom
                ? 'Na trasie ${_qty(scanQty)} szt., w tabeli materiałowej brak '
                    'takiej pozycji.'
                : 'Na trasie ${_qty(scanQty)} szt., w tabeli '
                    '${_qty(drawingQty)} szt.',
        noteEn: ok
            ? ''
            : !inBom
                ? 'Route has ${_qty(scanQty)} pcs, no such item in the bill '
                    'of materials.'
                : 'Route has ${_qty(scanQty)} pcs, the table '
                    '${_qty(drawingQty)} pcs.',
      ));
    }
  }

  // ── Pipe ─────────────────────────────────────────────────────────────
  final pipeByDn = <int?, (double, int)>{}; // dn → (known cuts mm, missing)
  for (final seg in segments) {
    final cur = pipeByDn[seg.dn] ?? (0.0, 0);
    pipeByDn[seg.dn] = seg.cutMm == null
        ? (cur.$1, cur.$2 + 1)
        : (cur.$1 + seg.cutMm!, cur.$2);
  }
  double? toMm(AiBomItem b) {
    final q = b.quantity;
    if (q == null) return null;
    switch (b.unit) {
      case 'M':
      case 'MTR':
      case 'MB':
        return q * 1000;
      case 'MM':
        return q;
      case 'FT':
        return q * 304.8;
      default:
        return null;
    }
  }

  final pipeBomByDn = <int?, double>{};
  final unknownUnit = <AiBomItem>[];
  for (final b in pipeItems) {
    final mm = toMm(b);
    if (mm == null) {
      unknownUnit.add(b);
      continue;
    }
    final dn = scanSizeToDn(b.size, notation);
    pipeBomByDn[dn] = (pipeBomByDn[dn] ?? 0) + mm;
  }
  final pipeBySize = !pipeBomByDn.containsKey(null) && !pipeByDn.containsKey(null);
  final pipeKeys = pipeBySize
      ? {...pipeByDn.keys, ...pipeBomByDn.keys}.toList()
      : <int?>[null];
  pipeKeys.sort((x, y) => (x ?? 0).compareTo(y ?? 0));
  if (pipeItems.isNotEmpty || segments.isNotEmpty) {
    for (final dn in pipeKeys) {
      final scanMm = pipeBySize
          ? (pipeByDn[dn]?.$1 ?? 0)
          : pipeByDn.values.fold<double>(0, (a, v) => a + v.$1);
      final missing = pipeBySize
          ? (pipeByDn[dn]?.$2 ?? 0)
          : pipeByDn.values.fold<int>(0, (a, v) => a + v.$2);
      final hasBom = pipeBySize
          ? pipeBomByDn.containsKey(dn)
          : pipeBomByDn.isNotEmpty;
      final bomMm = pipeBySize
          ? pipeBomByDn[dn]
          : (hasBom ? pipeBomByDn.values.fold<double>(0, (a, v) => a + v) : null);
      final size = dn == null ? '' : ' DN$dn';
      BomLineStatus status;
      String notePl;
      String noteEn;
      if (bomMm == null) {
        status = unknownUnit.isEmpty
            ? BomLineStatus.mismatch
            : BomLineStatus.notCompared;
        notePl = unknownUnit.isEmpty
            ? 'W tabeli materiałowej brak rury$size.'
            : 'Tabela nie podaje jednostki długości rury — nie porównuję.';
        noteEn = unknownUnit.isEmpty
            ? 'No$size pipe in the bill of materials.'
            : 'The table gives no length unit for the pipe — not compared.';
      } else {
        final tol = [kBomPipeToleranceMm, bomMm * kBomPipeAllowance]
            .reduce((a, b) => a > b ? a : b);
        final tooShort = scanMm > bomMm + 1e-6;
        final tooLong = bomMm - scanMm > tol;
        if (tooShort) {
          status = BomLineStatus.mismatch;
        } else if (missing > 0) {
          status = BomLineStatus.notCompared;
        } else {
          status = tooLong ? BomLineStatus.mismatch : BomLineStatus.ok;
        }
        final diff = bomMm - scanMm;
        notePl = [
          'Suma cięć ${_qty(scanMm / 1000)} m, w tabeli ${_qty(bomMm / 1000)} m '
              '(różnica ${_qty(diff / 1000)} m).',
          if (tooShort) 'W tabeli jest MNIEJ rury niż wychodzi z cięć.',
          if (!tooShort && tooLong && missing == 0)
            'Tabela ma więcej rury niż cięcia + ${(kBomPipeAllowance * 100).round()} % zapasu.',
          if (missing > 0) '$missing odcinków bez CUT — suma niepełna.',
        ].join(' ');
        noteEn = [
          'Cuts add up to ${_qty(scanMm / 1000)} m, the table '
              '${_qty(bomMm / 1000)} m (difference ${_qty(diff / 1000)} m).',
          if (tooShort) 'The table has LESS pipe than the cuts need.',
          if (!tooShort && tooLong && missing == 0)
            'The table has more pipe than the cuts + '
                '${(kBomPipeAllowance * 100).round()} % allowance.',
          if (missing > 0) '$missing runs without a CUT — the sum is partial.',
        ].join(' ');
      }
      lines.add(BomLine(
        labelPl: 'Rura$size',
        labelEn: 'Pipe$size',
        bomItem: pipeItems.map((b) => b.item).join(', '),
        drawingQty: bomMm == null ? null : bomMm / 1000,
        scanQty: scanMm / 1000,
        unit: 'm',
        status: status,
        notePl: notePl,
        noteEn: noteEn,
      ));
    }
  }
  return lines;
}

// ─────────────────────────────────────────────────────────────────────────
// Weld journal
// ─────────────────────────────────────────────────────────────────────────

class WeldJournalImport {
  /// Entries to insert (status PENDING, linked to the project).
  final List<WeldEntry> toInsert;

  /// Weld numbers already in the journal for this drawing — not repeated.
  final List<String> skipped;

  const WeldJournalImport(this.toInsert, this.skipped);
}

/// Key a weld is known by in the journal: the drawing number (else the
/// project name) and the weld number, case-insensitive. Re-importing the
/// same drawing creates nothing twice.
String weldJournalKey(String drawingOrProject, String weldNo) =>
    '${drawingOrProject.trim().toLowerCase()}|${weldNo.trim().toLowerCase()}';

String _fmtMm(double? v) {
  if (v == null) return '';
  var t = v.toStringAsFixed(2);
  t = t.replaceFirst(RegExp(r'0+$'), '');
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return t;
}

/// Journal entries for [welds] of a saved project — only for welds whose
/// run was saved, so no entry points at a cut that does not exist.
WeldJournalImport weldJournalEntries({
  required List<PlannedWeld> welds,
  required AiScanResult scan,
  required String projectId,
  required String projectName,
  required Set<String> savedSegmentIds,
  required Iterable<WeldEntry> existing,
  required String Function() newId,
  Map<String, String> spoolLabels = const {},
}) {
  final tb = scan.titleBlock;
  final drawing = tb.drawingNumber?.trim() ?? '';
  final keyBase = drawing.isNotEmpty ? drawing : projectName;
  final taken = <String>{
    for (final e in existing)
      if (!e.isDeleted)
        weldJournalKey(
            e.isoDrawing.isNotEmpty ? e.isoDrawing : e.projectName, e.weldNo),
  };
  final out = <WeldEntry>[];
  final skipped = <String>[];
  for (final w in welds) {
    if (w.segmentIds.isNotEmpty &&
        !w.segmentIds.any(savedSegmentIds.contains)) {
      continue;
    }
    final key = weldJournalKey(keyBase, w.number);
    if (!taken.add(key)) {
      skipped.add(w.number);
      continue;
    }
    final nde = <NdtMethod, WeldNdt>{};
    for (final m in NdtMethod.values) {
      if ((w.nde ?? '').toUpperCase().contains(m.code)) {
        nde[m] = const WeldNdt(scope: NdtScope.required);
      }
    }
    final position =
        kWeldPositions.contains(w.position?.toUpperCase()) ? w.position!.toUpperCase() : '';
    out.add(WeldEntry(
      id: newId(),
      weldNo: w.number,
      projectName: projectName,
      projectId: projectId,
      pipeName: tb.lineNumber?.trim() ?? '',
      isoDrawing: drawing,
      isoRev: tb.revision?.trim() ?? '',
      spool: w.spoolId == null ? '' : (spoolLabels[w.spoolId] ?? w.spoolId!),
      jointType: WeldJointType.values.contains(w.jointType) ? w.jointType : '',
      shopField: w.location == 'field'
          ? WeldLocation.field
          : (w.location == 'shop' ? WeldLocation.shop : ''),
      position: position,
      material: tb.material?.trim() ?? '',
      od: _fmtMm(w.odMm),
      t: _fmtMm(w.wallMm),
      method: '',
      welder: '',
      date: '',
      notes: w.source == WeldSource.drawing
          ? 'Ze skanu ISO${w.dn == null ? '' : ' · DN${w.dn}'}'
          : 'Ze skanu ISO · numer nadany automatycznie'
              '${w.dn == null ? '' : ' · DN${w.dn}'}',
      status: WeldStatus.pending,
      pwhtRequired: w.pwht,
      ndt: nde,
    ));
  }
  return WeldJournalImport(out, skipped);
}

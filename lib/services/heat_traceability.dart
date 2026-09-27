import '../database/component_heat_dao.dart';
import '../database/component_library_dao.dart';
import '../models/component_heat.dart';
import '../models/library_component.dart';
import '../models/segment.dart';
import 'cut_list_summary.dart' show segmentLabel;
import 'material_list_builder.dart';

/// One place of a CUT project a heat number (material certificate) can be
/// written for: the fitting a segment starts on, its pipe, or the fitting it
/// ends on.
///
/// Every place hangs on the segment's stable id ([Segment.id]) — never on
/// seq_no, which is reused after the last segment is deleted.
class TracePoint {
  const TracePoint({
    required this.segment,
    required this.side,
    this.joinedNext,
  });

  final Segment segment;
  final TraceSide side;

  /// For an END fitting that is ALSO the start of the next segment (the same
  /// piece of steel, see [MaterialListBuilder.isSameFittingAtJoint]): that
  /// next segment. Its START has no place of its own then.
  final Segment? joinedNext;

  String get key => '${segment.id}|${side.code}';

  String? get libraryId => switch (side) {
        TraceSide.start => segment.startLibraryId,
        TraceSide.end => segment.endLibraryId,
        TraceSide.pipe => null,
      };

  /// Stored end kind (`axial`, `nonAxial`); null for the pipe.
  String? get kind => switch (side) {
        TraceSide.start => segment.startKind,
        TraceSide.end => segment.endKind,
        TraceSide.pipe => null,
      };

  /// `S03`, `S03 → S04` for a fitting shared by two segments.
  String get segmentsLabel {
    final next = joinedNext;
    final own = segmentLabel(segment);
    return next == null ? own : '$own → ${segmentLabel(next)}';
  }
}

FittingKey? _fittingAt(Segment s, TraceSide side) => switch (side) {
      TraceSide.start => MaterialListBuilder.fittingKeyOf(
          libraryId: s.startLibraryId,
          kind: s.startKind,
          diameterMm: s.diameterMm,
          valueMm: s.startValueMm,
        ),
      TraceSide.end => MaterialListBuilder.fittingKeyOf(
          libraryId: s.endLibraryId,
          kind: s.endKind,
          diameterMm: s.diameterMm,
          valueMm: s.endValueMm,
        ),
      TraceSide.pipe => null,
    };

/// Every heat-number place of [segments], in run order (seq_no).
///
/// For each segment: its START fitting — unless it is the END fitting of the
/// previous segment (a joint: listed once, there) — then its pipe, then its
/// END fitting. An open end has no fitting and no place. Unlike the old list
/// this does not assume one continuous run: a branch, a second spool or a
/// segment that starts on an OPEN END after a fitting gets its own START.
///
/// [portsOf] gives a fitting's weld ports (library type); a flange (1 port)
/// at the end of one segment and the start of the next is a bolted PAIR —
/// two places.
List<TracePoint> traceabilityPoints(
  List<Segment> segments, {
  int Function(FittingKey key)? portsOf,
}) {
  final ordered = [...segments]..sort((a, b) => a.seqNo.compareTo(b.seqNo));
  final out = <TracePoint>[];
  bool joined(int i) {
    if (i + 1 >= ordered.length) return false;
    final end = _fittingAt(ordered[i], TraceSide.end);
    if (end == null) return false;
    return MaterialListBuilder.isSameFittingAtJoint(
      end,
      _fittingAt(ordered[i + 1], TraceSide.start),
      ports: portsOf?.call(end) ?? 2,
    );
  }

  for (var i = 0; i < ordered.length; i++) {
    final s = ordered[i];
    if (_fittingAt(s, TraceSide.start) != null && !(i > 0 && joined(i - 1))) {
      out.add(TracePoint(segment: s, side: TraceSide.start));
    }
    out.add(TracePoint(segment: s, side: TraceSide.pipe));
    if (_fittingAt(s, TraceSide.end) != null) {
      out.add(TracePoint(
        segment: s,
        side: TraceSide.end,
        joinedNext: joined(i) ? ordered[i + 1] : null,
      ));
    }
  }
  return out;
}

/// Heat entries of a project, looked up by place.
class HeatIndex {
  HeatIndex(Iterable<ComponentHeat> heats) {
    for (final h in heats) {
      final id = h.segmentId;
      final side = h.side;
      if (id == null || side == null) {
        _unplaced.add(h);
        continue;
      }
      _byPlace.putIfAbsent('$id|${side.code}', () => []).add(h);
    }
  }

  final _byPlace = <String, List<ComponentHeat>>{};
  final _unplaced = <ComponentHeat>[];

  List<ComponentHeat> at(String segmentId, TraceSide side) =>
      _byPlace['$segmentId|${side.code}'] ?? const [];

  /// Heats of [p] — for a joint also those written on the next segment's
  /// START (the same fitting).
  List<ComponentHeat> forPoint(TracePoint p) {
    final next = p.joinedNext;
    return [
      ...at(p.segment.id, p.side),
      if (next != null) ...at(next.id, TraceSide.start),
    ];
  }

  /// Entries that match no place of [points]: rows migrated from a deleted
  /// segment (no segment id), or a place that no longer exists (the segment
  /// was deleted, its end turned into an open end). Shown, never dropped.
  List<ComponentHeat> unplaced(List<TracePoint> points) {
    final shown = <String>{
      for (final p in points) ...[
        p.key,
        if (p.joinedNext != null) '${p.joinedNext!.id}|${TraceSide.start.code}',
      ],
    };
    return [
      ..._unplaced,
      for (final e in _byPlace.entries)
        if (!shown.contains(e.key)) ...e.value,
    ];
  }

  bool get isEmpty => _byPlace.isEmpty && _unplaced.isEmpty;
}

/// Heat numbers of one segment for the cut-list export: the fitting it
/// starts on (its own START or the previous END it shares), its pipe and
/// the fitting it ends on.
class SegmentHeats {
  const SegmentHeats({
    this.start = const [],
    this.pipe = const [],
    this.end = const [],
  });

  final List<String> start;
  final List<String> pipe;
  final List<String> end;

  bool get isEmpty => start.isEmpty && pipe.isEmpty && end.isEmpty;
}

/// Segment id → [SegmentHeats], for the CSV / PDF of the cut list.
Map<String, SegmentHeats> segmentHeats(
  List<TracePoint> points,
  HeatIndex index,
) {
  final start = <String, List<String>>{};
  final pipe = <String, List<String>>{};
  final end = <String, List<String>>{};
  List<String> nums(TracePoint p) =>
      [for (final h in index.forPoint(p)) h.heatNo];
  for (final p in points) {
    switch (p.side) {
      case TraceSide.start:
        start[p.segment.id] = nums(p);
      case TraceSide.pipe:
        pipe[p.segment.id] = nums(p);
      case TraceSide.end:
        final n = nums(p);
        end[p.segment.id] = n;
        final next = p.joinedNext;
        if (next != null) start[next.id] = n;
    }
  }
  final ids = {...start.keys, ...pipe.keys, ...end.keys};
  return {
    for (final id in ids)
      id: SegmentHeats(
        start: start[id] ?? const [],
        pipe: pipe[id] ?? const [],
        end: end[id] ?? const [],
      ),
  };
}

/// One line of the heat-number report (PDF table, BOM text).
class HeatReportRow {
  const HeatReportRow({
    required this.segments,
    required this.place,
    required this.heats,
  });

  /// `S03` or `S03 → S04`.
  final String segments;

  /// What the heat is of, in the chosen language (`Rura Ø114.3 × 3.05`,
  /// `ELB90 Ø114.3`, `Kształtka (skan) Ø60.3`).
  final String place;

  /// Heat numbers, `, `-joined.
  final String heats;

  String get line => '$segments · $place: $heats';
}

/// Report rows for every place that HAS a heat number, then the unplaced
/// entries. [typeOf] names a library id (`ELB90`); null when unknown.
List<HeatReportRow> heatReportRows(
  List<TracePoint> points,
  HeatIndex index, {
  required bool english,
  required String? Function(String libraryId) typeOf,
}) {
  final rows = <HeatReportRow>[];
  for (final p in points) {
    final heats = index.forPoint(p);
    if (heats.isEmpty) continue;
    rows.add(HeatReportRow(
      segments: p.segmentsLabel,
      place: tracePlaceLabel(p, english: english, typeOf: typeOf),
      heats: heats.map((h) => h.heatNo).join(', '),
    ));
  }
  for (final h in index.unplaced(points)) {
    rows.add(HeatReportRow(
      segments: '—',
      place: english ? 'no place (segment deleted)' : 'bez miejsca (segment usunięty)',
      heats: h.heatNo,
    ));
  }
  return rows;
}

/// What a place is, in words: the pipe with its size, a library fitting by
/// its type, a scanned fitting by its kind (never "OPEN END" — an elbow from
/// the scan has no library id but is still an elbow).
String tracePlaceLabel(
  TracePoint p, {
  required bool english,
  required String? Function(String libraryId) typeOf,
}) {
  final s = p.segment;
  final d = 'Ø${s.diameterMm.toStringAsFixed(1)}';
  if (p.side == TraceSide.pipe) {
    return english
        ? 'Pipe $d × ${s.wallThicknessMm.toStringAsFixed(2)}'
        : 'Rura $d × ${s.wallThicknessMm.toStringAsFixed(2)}';
  }
  final side = p.side == TraceSide.start
      ? (english ? 'start' : 'początek')
      : (english ? 'end' : 'koniec');
  final id = p.libraryId;
  final type = id == null ? null : typeOf(id);
  final String what;
  if (type != null) {
    what = type;
  } else if (p.kind == 'axial') {
    what = english ? 'Fitting (scan)' : 'Kształtka (skan)';
  } else {
    what = english ? 'Component (scan)' : 'Element (skan)';
  }
  return '$what $d · $side';
}

/// Everything the heat screens and exports need, read in one go.
class HeatTrace {
  const HeatTrace({
    required this.points,
    required this.index,
    required this.library,
  });

  final List<TracePoint> points;
  final HeatIndex index;

  /// Library entries referenced by the segments (id → entry, null = gone).
  final Map<String, LibraryComponent?> library;

  String? typeOf(String libraryId) => library[libraryId]?.type;

  Map<String, SegmentHeats> get bySegment => segmentHeats(points, index);

  List<HeatReportRow> report({required bool english}) =>
      heatReportRows(points, index, english: english, typeOf: typeOf);
}

/// Reads the heat entries and the library types of [segments] (one project)
/// and builds the places. Library entries are looked up once each.
Future<HeatTrace> loadHeatTrace(
  String projectId,
  List<Segment> segments, {
  ComponentHeatDao? heats,
  ComponentLibraryDao? library,
}) async {
  final heatDao = heats ?? ComponentHeatDao();
  final libDao = library ?? ComponentLibraryDao();
  final lib = <String, LibraryComponent?>{};
  for (final s in segments) {
    for (final id in [s.startLibraryId, s.endLibraryId]) {
      if (id != null && !lib.containsKey(id)) lib[id] = await libDao.getById(id);
    }
  }
  final points = traceabilityPoints(
    segments,
    portsOf: (key) => key.libraryId == null
        ? 2
        : MaterialListBuilder.portsForType(lib[key.libraryId]?.type),
  );
  final index = HeatIndex(await heatDao.listForProject(projectId));
  return HeatTrace(points: points, index: index, library: lib);
}

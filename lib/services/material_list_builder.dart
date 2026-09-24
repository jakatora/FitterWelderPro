import '../database/component_library_dao.dart';
import '../database/project_dao.dart';
import '../database/segment_dao.dart';
import '../models/library_component.dart';
import '../models/material_item.dart';
import '../models/segment.dart';

/// Identity of the fitting at one end of a segment — what decides whether
/// two segment ends can be the same physical piece.
///
/// * a component-library entry: its `library_id`;
/// * no library entry (ISO-scanner projects store none): the end kind plus
///   pipe OD and take-out, e.g. `axial / Ø114.3 / 152.4 mm`.
class FittingKey {
  final String? libraryId;
  final String? kind;
  final double? diameterMm;
  final double? takeoutMm;

  const FittingKey.library(String this.libraryId)
      : kind = null,
        diameterMm = null,
        takeoutMm = null;

  const FittingKey.kind(String this.kind, this.diameterMm, this.takeoutMm)
      : libraryId = null;

  @override
  bool operator ==(Object other) =>
      other is FittingKey &&
      other.libraryId == libraryId &&
      other.kind == kind &&
      other.diameterMm == diameterMm &&
      other.takeoutMm == takeoutMm;

  @override
  int get hashCode => Object.hash(libraryId, kind, diameterMm, takeoutMm);

  @override
  String toString() => libraryId != null
      ? 'FittingKey($libraryId)'
      : 'FittingKey($kind, $diameterMm, $takeoutMm)';
}

class MaterialListBuilder {
  final SegmentDao _segments;
  final ComponentLibraryDao _library;
  final ProjectDao? _projects;

  MaterialListBuilder(this._segments, this._library, [this._projects]);

  /// Project name for the BOM title (copy / share); null when unknown or when
  /// the builder was created without a [ProjectDao].
  Future<String?> projectName(String projectId) async {
    final dao = _projects;
    if (dao == null) return null;
    final p = await dao.getById(projectId);
    final name = p?.name?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<List<MaterialItem>> buildForProject(String projectId) async {
    final segs = await _segments.listForProject(projectId);

    // PIPE totals (length sum by diameter+wall)
    final pipeMap = <String, double>{};
    for (final s in segs) {
      final key = 'PIPE|${s.diameterMm}|${s.wallThicknessMm}';
      pipeMap[key] = (pipeMap[key] ?? 0) + s.cutMm;
    }

    // Resolve every library entry once; remember how the segments describe
    // an id in case the entry has since been deleted from the library.
    final library = <String, LibraryComponent?>{};
    final seenAs = <String, (String kind, double diameter, double value)>{};
    for (final s in segs) {
      for (final (id, kind, value) in [
        (s.startLibraryId, s.startKind, s.startValueMm),
        (s.endLibraryId, s.endKind, s.endValueMm),
      ]) {
        if (id == null) continue;
        seenAs.putIfAbsent(id, () => (kind, s.diameterMm, value));
        if (!library.containsKey(id)) library[id] = await _library.getById(id);
      }
    }

    final counts = countFittings(
      segs,
      portsOf: (key) => key.libraryId == null
          ? 2
          : portsForType(library[key.libraryId]?.type),
    );

    final items = <MaterialItem>[];

    // Pipes first
    for (final e in pipeMap.entries) {
      final parts = e.key.split('|');
      final diameter = double.parse(parts[1]);
      final wall = double.parse(parts[2]);
      items.add(
        MaterialItem(
          category: 'PIPE',
          description: 'Pipe Ø${diameter.toStringAsFixed(1)} x ${wall.toStringAsFixed(1)}',
          totalLengthMm: e.value,
        ),
      );
    }

    // Components
    for (final entry in counts.entries) {
      final key = entry.key;
      final qty = entry.value;
      final libraryId = key.libraryId;
      if (libraryId != null) {
        final comp = library[libraryId];
        if (comp != null) {
          items.add(MaterialItem(
            category: comp.type,
            description: comp.displayLabel(),
            quantity: qty,
          ));
          continue;
        }
        // Entry deleted from the library after the segment was saved: the
        // fittings are still in the run and still have to be ordered, so the
        // row stays — described by what the segment stored.
        final seen = seenAs[libraryId];
        final kind = seen?.$1 == 'axial' ? 'axial' : 'nonAxial';
        items.add(_kindItem(
          kind: kind,
          diameterMm: seen?.$2,
          takeoutMm: kind == 'axial' ? seen?.$3 : null,
          quantity: qty,
          libraryEntryMissing: true,
        ));
        continue;
      }
      items.add(_kindItem(
        kind: key.kind!,
        diameterMm: key.diameterMm,
        takeoutMm: key.takeoutMm,
        quantity: qty,
        libraryEntryMissing: false,
      ));
    }

    // Sort: pipes first, then by category; within a category by size so the
    // order is stable from one load to the next.
    items.sort((a, b) {
      if (a.category == 'PIPE' && b.category != 'PIPE') return -1;
      if (a.category != 'PIPE' && b.category == 'PIPE') return 1;
      final byCategory = a.category.compareTo(b.category);
      if (byCategory != 0) return byCategory;
      final byDiameter = (a.diameterMm ?? 0).compareTo(b.diameterMm ?? 0);
      if (byDiameter != 0) return byDiameter;
      final byTakeout = (a.takeoutMm ?? 0).compareTo(b.takeoutMm ?? 0);
      if (byTakeout != 0) return byTakeout;
      return a.description.compareTo(b.description);
    });

    return items;
  }

  /// BOM row for a fitting known only by its end kind. [description] is an
  /// English fallback; the screen localises the row from the structured
  /// fields.
  static MaterialItem _kindItem({
    required String kind,
    required double? diameterMm,
    required double? takeoutMm,
    required int quantity,
    required bool libraryEntryMissing,
  }) {
    final axial = kind == 'axial';
    final dia = diameterMm == null ? '' : ' Ø${diameterMm.toStringAsFixed(1)}';
    final takeout = axial && takeoutMm != null && takeoutMm > 0
        ? ' · C-E ${takeoutMm.toStringAsFixed(1)} mm'
        : '';
    final what = axial
        ? 'Axial fitting (elbow / tee)'
        : 'Fitting with body (flange / valve / reducer)';
    final why = libraryEntryMissing
        ? 'deleted from component library'
        : 'type not stored (scan)';
    return MaterialItem(
      category: axial ? 'FITTING_AXIAL' : 'FITTING_BODY',
      description: '$what$dia$takeout — $why',
      quantity: quantity,
      endKind: axial ? 'axial' : 'nonAxial',
      diameterMm: diameterMm,
      takeoutMm: axial ? takeoutMm : null,
      libraryEntryMissing: libraryEntryMissing,
    );
  }

  /// Number of weld ends ("ports") of a library fitting type: a tee has
  /// three (run in, run out, branch), a flange one (the other face bolts to
  /// a mating flange), everything else two.
  static int portsForType(String? type) {
    switch (type) {
      case 'TEE':
        return 3;
      case 'FLANGE':
        return 1;
      default:
        return 2;
    }
  }

  /// The fitting at one segment end, or null when nothing is fitted there
  /// (open end / logical point).
  static FittingKey? fittingKeyOf({
    required String? libraryId,
    required String kind,
    required double diameterMm,
    required double valueMm,
  }) {
    if (libraryId != null) return FittingKey.library(libraryId);
    if (kind == 'axial') return FittingKey.kind('axial', diameterMm, valueMm);
    // A face or body carries no take-out in the scan (value 0), so only the
    // OD tells such fittings apart.
    if (kind == 'nonAxial') return FittingKey.kind('nonAxial', diameterMm, null);
    return null;
  }

  /// Number of PHYSICAL fittings per [FittingKey].
  ///
  /// `library_id` identifies an ENTRY IN THE COMPONENT LIBRARY (a fitting
  /// *type*), never a single piece of steel: a run with twelve DN100 elbows
  /// stores the same id twelve times. Segments carry no per-instance id, so
  /// pieces are derived from the run topology (segments in `seqNo` order):
  ///
  ///   1. Joint — the end of segment n and the start of segment n+1 with the
  ///      same key are ONE fitting (two of its ports used). Neighbourhood is
  ///      adjacency in `seqNo` order, not `seqNo + 1`: deleting a middle
  ///      segment leaves a hole in the numbering (`SegmentDao.deleteById`
  ///      does not renumber) while the remaining segments still meet.
  ///      A fitting with a single port (flange) cannot form a joint: a flange
  ///      at the end of n and the start of n+1 is a bolted PAIR, two pieces.
  ///   2. Branch — a fitting with more than two ports (tee) whose run is a
  ///      joint still has a free port. A segment end on the same key that is
  ///      not part of a joint (a "stub") is the branch taken off that tee —
  ///      e.g. FLANGE→TEE, TEE→ELB, TEE→FLANGE is ONE tee. Each joint takes
  ///      at most `ports − 2` stubs; stubs beyond that are separate pieces,
  ///      and stubs never merge with each other (two tees that each have only
  ///      one connected port stay two tees).
  ///   3. Every other end is its own piece.
  ///
  /// [portsOf] gives the port count per key; default 2 for every key (no
  /// branch sharing, joints only).
  static Map<FittingKey, int> countFittings(
    List<Segment> segments, {
    int Function(FittingKey key)? portsOf,
  }) {
    // Sort defensively: the joint rule only holds if the segments are in run
    // order. `SegmentDao.listForProject` already orders by seq_no, but this
    // method must not silently miscount when handed rows from anywhere else.
    final ordered = [...segments]..sort((a, b) => a.seqNo.compareTo(b.seqNo));
    int ports(FittingKey key) => portsOf?.call(key) ?? 2;

    final starts = [
      for (final s in ordered)
        fittingKeyOf(
          libraryId: s.startLibraryId,
          kind: s.startKind,
          diameterMm: s.diameterMm,
          valueMm: s.startValueMm,
        ),
    ];
    final ends = [
      for (final s in ordered)
        fittingKeyOf(
          libraryId: s.endLibraryId,
          kind: s.endKind,
          diameterMm: s.diameterMm,
          valueMm: s.endValueMm,
        ),
    ];

    final joints = <FittingKey, int>{};
    final stubs = <FittingKey, int>{};
    final startJoined = List<bool>.filled(ordered.length, false);
    final endJoined = List<bool>.filled(ordered.length, false);

    for (var i = 0; i + 1 < ordered.length; i++) {
      final key = ends[i];
      if (key != null && key == starts[i + 1] && ports(key) >= 2) {
        joints[key] = (joints[key] ?? 0) + 1;
        endJoined[i] = true;
        startJoined[i + 1] = true;
      }
    }
    for (var i = 0; i < ordered.length; i++) {
      final s = starts[i];
      if (s != null && !startJoined[i]) stubs[s] = (stubs[s] ?? 0) + 1;
      final e = ends[i];
      if (e != null && !endJoined[i]) stubs[e] = (stubs[e] ?? 0) + 1;
    }

    final counts = <FittingKey, int>{};
    for (final key in {...joints.keys, ...stubs.keys}) {
      final j = joints[key] ?? 0;
      final st = stubs[key] ?? 0;
      final free = j * (ports(key) - 2).clamp(0, 1 << 20);
      final attached = st < free ? st : free;
      final pieces = j + st - attached;
      if (pieces > 0) counts[key] = pieces;
    }
    return counts;
  }

  /// Library-entry counts only (`library_id` → pieces) — see [countFittings]
  /// for the rules. [portsOf] maps a library id to its port count (use
  /// [portsForType] with the entry's type); without it every fitting is
  /// treated as two-port, i.e. only neighbouring joints are merged.
  static Map<String, int> countComponentInstances(
    List<Segment> segments, {
    int Function(String libraryId)? portsOf,
  }) {
    final counts = countFittings(
      segments,
      portsOf: portsOf == null
          ? null
          : (key) => key.libraryId == null ? 2 : portsOf(key.libraryId!),
    );
    return {
      for (final e in counts.entries)
        if (e.key.libraryId != null) e.key.libraryId!: e.value,
    };
  }
}

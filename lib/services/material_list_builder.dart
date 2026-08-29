import '../database/component_library_dao.dart';
import '../database/segment_dao.dart';
import '../models/material_item.dart';
import '../models/segment.dart';

class MaterialListBuilder {
  final SegmentDao _segments;
  final ComponentLibraryDao _library;

  MaterialListBuilder(this._segments, this._library);

  Future<List<MaterialItem>> buildForProject(String projectId) async {
    final segs = await _segments.listForProject(projectId);

    // PIPE totals (length sum by diameter+wall)
    final pipeMap = <String, double>{};
    for (final s in segs) {
      final key = 'PIPE|${s.diameterMm}|${s.wallThicknessMm}';
      pipeMap[key] = (pipeMap[key] ?? 0) + s.cutMm;
    }

    final compCounts = countComponentInstances(segs);

    // Resolve component labels
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
    for (final entry in compCounts.entries) {
      final comp = await _library.getById(entry.key);
      if (comp == null) continue;
      items.add(
        MaterialItem(
          category: comp.type,
          description: comp.displayLabel(),
          quantity: entry.value,
        ),
      );
    }

    // Sort: pipes first, then by category
    items.sort((a, b) {
      if (a.category == 'PIPE' && b.category != 'PIPE') return -1;
      if (a.category != 'PIPE' && b.category == 'PIPE') return 1;
      return a.category.compareTo(b.category);
    });

    return items;
  }

  /// Number of PHYSICAL fittings per library entry, keyed by `library_id`.
  ///
  /// Why this is not a distinct-id count: `library_id` identifies an ENTRY IN
  /// THE COMPONENT LIBRARY (a fitting *type*), never a single piece of steel.
  /// A run with twelve DN100 elbows stores the very same `library_id` twelve
  /// times, so collecting the ids into a `Set` and giving each one quantity 1
  /// printed "ELB90 ... — 1 pc." and the fitter ordered one elbow for twelve
  /// welds. The opposite naive fix (adding start + end of every segment) is
  /// wrong too: a segment boundary is ONE fitting described twice, because the
  /// tee in the middle of a run is stored as the end of segment N and again as
  /// the start of segment N+1.
  ///
  /// Segments carry no per-instance id, so instances are derived from the run
  /// topology instead:
  ///   1. every non-null `startLibraryId` / `endLibraryId` counts as one
  ///      occurrence;
  ///   2. two segments that are neighbours in the run share ONE fitting when
  ///      `segment[n].endLibraryId == segment[n + 1].startLibraryId`, so each
  ///      such joint is subtracted once.
  ///
  /// Neighbourhood is adjacency in `seqNo` order, not `seqNo + 1`: deleting a
  /// middle segment leaves a hole in the numbering (`SegmentDao.deleteById`
  /// does not renumber) while the remaining segments still meet in the run.
  /// Ends that meet with different ids are NOT merged — two different fittings
  /// are two orders — and identical ids on non-neighbouring boundaries stay
  /// separate pieces.
  ///
  /// Net effect: three chained segments with the same elbow at both ends give
  /// 4 elbows (n + 1 boundaries), while a tee shared by two segments stays 1.
  static Map<String, int> countComponentInstances(List<Segment> segments) {
    // Sort defensively: the joint rule only holds if the segments are in run
    // order. `SegmentDao.listForProject` already orders by seq_no, but this
    // method must not silently miscount when handed rows from anywhere else.
    final ordered = [...segments]..sort((a, b) => a.seqNo.compareTo(b.seqNo));

    final counts = <String, int>{};
    void bump(String? libraryId, int delta) {
      if (libraryId == null) return; // open end / logical point: nothing to buy
      final next = (counts[libraryId] ?? 0) + delta;
      if (next <= 0) {
        counts.remove(libraryId);
      } else {
        counts[libraryId] = next;
      }
    }

    for (final s in ordered) {
      bump(s.startLibraryId, 1);
      bump(s.endLibraryId, 1);
    }

    // Collapse shared boundaries: one joint = one fitting counted twice above.
    for (var i = 0; i + 1 < ordered.length; i++) {
      final joint = ordered[i].endLibraryId;
      if (joint != null && joint == ordered[i + 1].startLibraryId) {
        bump(joint, -1);
      }
    }

    return counts;
  }
}

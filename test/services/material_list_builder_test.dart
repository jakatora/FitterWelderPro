import 'package:flutter_test/flutter_test.dart';

import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/material_item.dart';
import 'package:cut_list_app/models/segment.dart';
import 'package:cut_list_app/services/material_list_builder.dart';

/// Segment DAO stub. `MaterialListBuilder` only ever calls `listForProject`,
/// so overriding that one method keeps the whole test off sqflite — no FFI
/// factory, no on-disk DB, no cross-test row leakage.
class _FakeSegmentDao extends SegmentDao {
  final List<Segment> rows;
  _FakeSegmentDao(this.rows);

  @override
  Future<List<Segment>> listForProject(String projectId) async =>
      rows.where((s) => s.projectId == projectId).toList();
}

/// Component library stub; `MaterialListBuilder` only calls `getById`.
class _FakeLibraryDao extends ComponentLibraryDao {
  final Map<String, LibraryComponent> byId;
  _FakeLibraryDao(this.byId);

  @override
  Future<LibraryComponent?> getById(String id) async => byId[id];
}

const _projectId = 'PRJ-1';

/// Segment with only the fields the material list cares about; everything
/// else gets a plausible constant so the tests stay readable.
Segment _seg({
  required int seq,
  String? start,
  String? end,
  double diameter = 114.3,
  double wall = 3.6,
  double cut = 1000,
}) {
  return Segment(
    id: 'SEG-$seq',
    projectId: _projectId,
    seqNo: seq,
    diameterMm: diameter,
    wallThicknessMm: wall,
    startKind: start == null ? 'logical' : 'axial',
    startLibraryId: start,
    startValueMm: 0,
    endKind: end == null ? 'logical' : 'axial',
    endLibraryId: end,
    endValueMm: 0,
    isoRef: 'FACE|FACE',
    isoExpr: '$cut',
    isoMm: cut,
    cutMm: cut,
    createdAt: 0,
    updatedAt: 0,
  );
}

LibraryComponent _lib(String id, String type) {
  return LibraryComponent(
    id: id,
    materialGroup: 'SS',
    type: type,
    diameterMm: 114.3,
    wallThicknessMm: 3.6,
    axisMm: 76.2,
    lengthMm: null,
    measurementMode: null,
    diameterOutMm: null,
    createdAt: 0,
    updatedAt: 0,
  );
}

MaterialItem? _itemOfCategory(List<MaterialItem> items, String category) {
  for (final i in items) {
    if (i.category == category) return i;
  }
  return null;
}

void main() {
  final libraryDao = _FakeLibraryDao({
    'lib-elb90': _lib('lib-elb90', 'ELB90'),
    'lib-elb45': _lib('lib-elb45', 'ELB45'),
    'lib-tee': _lib('lib-tee', 'TEE'),
  });

  Future<List<MaterialItem>> build(List<Segment> segs) {
    return MaterialListBuilder(_FakeSegmentDao(segs), libraryDao)
        .buildForProject(_projectId);
  }

  group('component quantities count physical pieces, not library entries', () {
    test('(a) three chained segments, same elbow type on both ends -> 4 pcs',
        () async {
      // The run is ELB - pipe - ELB - pipe - ELB - pipe - ELB: three segments
      // have four boundaries, and every boundary is a separate physical elbow
      // even though all four share one library entry.
      final items = await build([
        _seg(seq: 1, start: 'lib-elb90', end: 'lib-elb90'),
        _seg(seq: 2, start: 'lib-elb90', end: 'lib-elb90'),
        _seg(seq: 3, start: 'lib-elb90', end: 'lib-elb90'),
      ]);

      final elbow = _itemOfCategory(items, 'ELB90');
      expect(elbow, isNotNull);
      // Regression guard: the old Set-based count reported 1 pc. here, so a
      // fitter ordered one elbow for a run that needs four.
      expect(elbow!.quantity, 4);
    });

    test('(b) tee shared by two neighbouring segments is counted once',
        () async {
      // Segment 1 ends on the tee, segment 2 starts on the SAME tee — one
      // physical fitting stored twice, so it must not be double counted.
      final items = await build([
        _seg(seq: 1, start: 'lib-elb90', end: 'lib-tee'),
        _seg(seq: 2, start: 'lib-tee', end: 'lib-elb90'),
      ]);

      expect(_itemOfCategory(items, 'TEE')!.quantity, 1);
      // ...while the two elbows on the outer ends are genuinely two pieces.
      expect(_itemOfCategory(items, 'ELB90')!.quantity, 2);
    });

    test('(c) project without fittings yields pipes only', () async {
      final items = await build([
        _seg(seq: 1, cut: 1200),
        _seg(seq: 2, cut: 800),
      ]);

      expect(items.every((i) => i.category == 'PIPE'), isTrue);
      expect(items.single.totalLengthMm, 2000);
      expect(items.single.quantity, isNull);
    });

    test('(d) pipes are summed by length per diameter + wall', () async {
      final items = await build([
        _seg(seq: 1, cut: 1000),
        _seg(seq: 2, cut: 2500),
        _seg(seq: 3, diameter: 60.3, cut: 800),
      ]);

      final pipes = items.where((i) => i.category == 'PIPE').toList();
      expect(pipes.length, 2);

      final big = pipes.firstWhere((i) => i.description.contains('114.3'));
      final small = pipes.firstWhere((i) => i.description.contains('60.3'));
      expect(big.totalLengthMm, 3500);
      expect(small.totalLengthMm, 800);
      // Pipes are measured, not counted.
      expect(big.quantity, isNull);
    });

    test('same fitting type on non-neighbouring boundaries stays two pieces',
        () async {
      // Segment 1 ends on a tee and segment 3 starts on a tee, but segment 2
      // sits between them. Neither tee carries a run (end of one segment +
      // start of the next), so neither is a branch point the other could
      // hang off — these stay two different physical tees.
      final items = await build([
        _seg(seq: 1, end: 'lib-tee'),
        _seg(seq: 2),
        _seg(seq: 3, start: 'lib-tee'),
      ]);

      expect(_itemOfCategory(items, 'TEE')!.quantity, 2);
    });

    test('different fittings meeting at a boundary are both counted',
        () async {
      // No shared id => no joint to subtract, so the material list keeps both.
      final items = await build([
        _seg(seq: 1, end: 'lib-tee'),
        _seg(seq: 2, start: 'lib-elb45'),
      ]);

      expect(_itemOfCategory(items, 'TEE')!.quantity, 1);
      expect(_itemOfCategory(items, 'ELB45')!.quantity, 1);
    });

    test('a gap in seq numbers (deleted segment) still joins the neighbours',
        () async {
      // Deleting a middle segment leaves seq 1 and seq 3 next to each other in
      // the run, so their shared tee is still one piece.
      final items = await build([
        _seg(seq: 1, end: 'lib-tee'),
        _seg(seq: 3, start: 'lib-tee'),
      ]);

      expect(_itemOfCategory(items, 'TEE')!.quantity, 1);
    });

    test('unordered DAO rows are sorted by seq before joints are detected',
        () async {
      final items = await build([
        _seg(seq: 2, start: 'lib-tee', end: 'lib-elb90'),
        _seg(seq: 1, start: 'lib-elb90', end: 'lib-tee'),
      ]);

      expect(_itemOfCategory(items, 'TEE')!.quantity, 1);
      expect(_itemOfCategory(items, 'ELB90')!.quantity, 2);
    });

    test('empty project produces an empty list', () async {
      expect(await build(const []), isEmpty);
    });
  });

  group('MaterialListBuilder.countComponentInstances', () {
    test('counts every occurrence and subtracts shared joints', () {
      final counts = MaterialListBuilder.countComponentInstances([
        _seg(seq: 1, start: 'lib-elb90', end: 'lib-tee'),
        _seg(seq: 2, start: 'lib-tee', end: 'lib-elb90'),
        _seg(seq: 3, start: 'lib-elb90', end: 'lib-elb45'),
      ]);

      // elbow 90 occurs 3x (s1.start, s2.end, s3.start); s2.end and s3.start
      // are the same physical elbow (one joint) -> 2 pieces.
      expect(counts['lib-elb90'], 2);
      expect(counts['lib-tee'], 1);
      expect(counts['lib-elb45'], 1);
    });

    test('open ends (null library id) are not counted', () {
      final counts = MaterialListBuilder.countComponentInstances([
        _seg(seq: 1),
        _seg(seq: 2),
      ]);
      expect(counts, isEmpty);
    });

    test('a run with twelve elbows reports twelve, not one', () {
      // The reported bug, reproduced: eleven segments chained elbow to elbow
      // are 22 occurrences minus 10 shared joints = 12 physical elbows.
      final segs = <Segment>[
        for (var i = 1; i <= 11; i++)
          _seg(seq: i, start: 'lib-elb90', end: 'lib-elb90'),
      ];
      expect(
        MaterialListBuilder.countComponentInstances(segs)['lib-elb90'],
        12,
      );
    });
  });
}

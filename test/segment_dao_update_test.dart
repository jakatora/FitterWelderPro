// Regression net for the missing UPDATE on segments.
//
// `SegmentDao` had six methods and none of them could change a saved row, so
// a mistyped ISO dimension (3450 for 3540) could only be fixed by deleting the
// segment and rebuilding its whole sequence from the palette. Deleting also
// punched a hole in the seq_no numbering that the cut list and the PDF are
// ordered by.
//
// The two things this pins down:
//   1. an update actually rewrites the measured columns of the addressed row,
//   2. and it cannot move a segment in the cut list or rewrite its history —
//      seq_no and created_at survive even when a caller passes new ones.

import 'package:flutter_test/flutter_test.dart';
import 'support/test_database.dart';

import 'package:cut_list_app/database/segment_dao.dart';

/// One segment row, shaped exactly as `fitter_screen` writes it.
Map<String, Object?> _row({
  required String id,
  required String projectId,
  required int seqNo,
  required String isoExpr,
  required double isoMm,
  required double cutMm,
  required int createdAt,
}) =>
    {
      'id': id,
      'project_id': projectId,
      'seq_no': seqNo,
      'diameter_mm': 60.3,
      'wall_thickness_mm': 2.77,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': isoExpr,
      'iso_mm': isoMm,
      'cut_mm': cutMm,
      'created_at': createdAt,
      'updated_at': createdAt,
    };

void main() {
  useTestDatabase();

  test('update rewrites a segment in place without moving it in the cut list',
      () async {
    final dao = SegmentDao();
    // Unique ids so the test is isolated from any pre-existing rows in the
    // suite-local test DB.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final projectId = 'test_project_$stamp';
    final first = 'seg_a_$stamp';
    final second = 'seg_b_$stamp';
    await insertTestProject(projectId);

    await dao.insert(_row(
      id: first,
      projectId: projectId,
      seqNo: 1,
      isoExpr: '3450',
      isoMm: 3450,
      cutMm: 3450,
      createdAt: 1000,
    ));
    await dao.insert(_row(
      id: second,
      projectId: projectId,
      seqNo: 2,
      isoExpr: '1200',
      isoMm: 1200,
      cutMm: 1200,
      createdAt: 1000,
    ));

    // The correction on site: 3450 was a typo for 3540. The caller passes a
    // full row, including a deliberately wrong seq_no and created_at, to prove
    // the DAO refuses to let an edit renumber the sheet or rewrite history.
    final changed = await dao.update(_row(
      id: first,
      projectId: projectId,
      seqNo: 99,
      isoExpr: '3540',
      isoMm: 3540,
      cutMm: 3540,
      createdAt: 0,
    ));
    expect(changed, 1, reason: 'exactly the addressed segment must change');

    final rows = await dao.listForProject(projectId);
    expect(rows.length, 2, reason: 'an edit must not add or drop a segment');

    final edited = rows.firstWhere((s) => s.id == first);
    expect(edited.isoExpr, '3540');
    expect(edited.isoMm, 3540);
    expect(edited.cutMm, 3540,
        reason: 'the cut length the saw is set from must be the corrected one');
    expect(edited.seqNo, 1,
        reason: 'segment order drives the cut list and the PDF — a corrected '
            'dimension must not move the segment');
    expect(edited.createdAt, 1000,
        reason: 'created_at records when the segment was first measured');

    // listForProject orders by seq_no, so an unchanged order also proves the
    // seq_no of the untouched segment was not disturbed.
    expect(rows.map((s) => s.id).toList(), [first, second]);

    final untouched = rows.firstWhere((s) => s.id == second);
    expect(untouched.isoExpr, '1200');
    expect(untouched.cutMm, 1200,
        reason: 'WHERE id = ? — a neighbouring segment must be left alone');

    // A segment deleted on another screen while the builder was open: the
    // update must report that it wrote nothing, so the caller can say so
    // instead of showing a save that never happened.
    final missing = await dao.update(_row(
      id: 'seg_gone_$stamp',
      projectId: projectId,
      seqNo: 1,
      isoExpr: '999',
      isoMm: 999,
      cutMm: 999,
      createdAt: 1000,
    ));
    expect(missing, 0);

    await dao.deleteAllForProject(projectId);
  });
}

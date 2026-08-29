import '../database/db.dart';
import '../models/segment.dart';

class SegmentDao {
  Future<int> nextSeqNo(String projectId) async {
    final db = await AppDatabase.get();
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(seq_no), 0) AS m FROM segments WHERE project_id = ?;',
      [projectId],
    );
    final m = (rows.first['m'] as num?)?.toInt() ?? 0;
    return m + 1;
  }

  Future<void> insert(Map<String, Object?> row) async {
    final db = await AppDatabase.get();
    await db.insert('segments', row);
  }

  /// Overwrites an existing segment in place, matched on `row['id']`.
  ///
  /// The DAO had no update at all, so a mistyped ISO dimension could only be
  /// fixed by deleting the segment and rebuilding its whole sequence from the
  /// palette — and deleting also punched a hole in the seq_no numbering that
  /// the cut list and the PDF are ordered by.
  ///
  /// [row] takes the same shape as [insert] so a caller can build one map and
  /// choose insert-or-update. Four columns are dropped from the payload on
  /// purpose: `id` and `project_id` are the row's identity, `seq_no` fixes its
  /// place in the cut list (a correction must never renumber a sheet the
  /// fitter is already cutting from, and the table's UNIQUE(project_id,
  /// seq_no) would reject a clash anyway), and `created_at` records when the
  /// segment was first measured.
  ///
  /// Returns the number of rows changed — 0 means the segment is no longer
  /// there (deleted on another screen in the meantime), which the caller must
  /// not report as a successful save.
  Future<int> update(Map<String, Object?> row) async {
    final db = await AppDatabase.get();
    final id = row['id'] as String;
    final values = Map<String, Object?>.from(row)
      ..remove('id')
      ..remove('project_id')
      ..remove('seq_no')
      ..remove('created_at');
    return db.update('segments', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Segment>> listForProject(String projectId) async {
    final db = await AppDatabase.get();
    final rows = await db.query(
      'segments',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'seq_no ASC',
    );
    return rows.map(Segment.fromRow).toList();
  }

  Future<void> deleteById(String segmentId) async {
    final db = await AppDatabase.get();
    await db.delete('segments', where: 'id = ?', whereArgs: [segmentId]);
  }

  Future<void> deleteAllForProject(String projectId) async {
    final db = await AppDatabase.get();
    await db.delete('segments', where: 'project_id = ?', whereArgs: [projectId]);
  }

  Future<double> sumCutForProject(String projectId, double diameter, double wall) async {
    final db = await AppDatabase.get();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(cut_mm),0) AS s FROM segments WHERE project_id = ? AND diameter_mm = ? AND wall_thickness_mm = ?;',
      [projectId, diameter, wall],
    );
    return ((rows.first['s'] as num?)?.toDouble() ?? 0.0);
  }
}

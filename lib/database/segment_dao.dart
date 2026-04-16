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

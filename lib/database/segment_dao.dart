import 'package:sqflite/sqflite.dart';

import '../models/segment.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

/// Segmenty listy cięć. v34: należą do właściciela projektu — każdy odczyt
/// i zapis dotyczy wyłącznie projektów bieżącego konta.
class SegmentDao {
  SegmentDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _projects = OwnedProjects(captureOwner: captureOwner);
  final OwnedProjects _projects;

  static const _owned = OwnedProjects.childOfOwnedProject;

  Future<int> nextSeqNo(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    await _projects.requireProject(db, projectId, owner);
    final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(seq_no), 0) AS m FROM segments WHERE project_id = ?;',
      [projectId],
    );
    owner.requireCurrent();
    final m = (rows.first['m'] as num?)?.toInt() ?? 0;
    return m + 1;
  }

  Future<void> insert(Map<String, Object?> row) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _projects.requireProject(txn, row['project_id'] as String, owner);
      await txn.insert('segments', normalizeIdentity(row));
      owner.requireCurrent();
    });
  }

  /// `label` / `spool_id` (schema v22) trimmed, blank stored as NULL — a
  /// piece mark of "  " must not show up as a label on the saw list. Other
  /// columns pass through untouched; a row without those keys is unchanged.
  static Map<String, Object?> normalizeIdentity(Map<String, Object?> row) {
    if (!row.containsKey('label') && !row.containsKey('spool_id')) return row;
    final out = Map<String, Object?>.from(row);
    for (final key in const ['label', 'spool_id']) {
      if (!out.containsKey(key)) continue;
      final v = out[key];
      final t = v is String ? v.trim() : null;
      out[key] = (t == null || t.isEmpty) ? null : t;
    }
    return out;
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
  /// there (deleted on another screen in the meantime) or belongs to another
  /// account, which the caller must not report as a successful save.
  Future<int> update(Map<String, Object?> row) async {
    final (owner, db) = await _projects.ownerAndDb();
    final id = row['id'] as String;
    final values = Map<String, Object?>.from(normalizeIdentity(row))
      ..remove('id')
      ..remove('project_id')
      ..remove('seq_no')
      ..remove('created_at');
    final n = await db.update('segments', values,
        where: 'id = ? AND $_owned', whereArgs: [id, owner.key]);
    owner.requireCurrent();
    return n;
  }

  Future<List<Segment>> listForProject(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query(
      'segments',
      where: 'project_id = ? AND $_owned',
      whereArgs: [projectId, owner.key],
      orderBy: 'seq_no ASC',
    );
    owner.requireCurrent();
    return rows.map(Segment.fromRow).toList();
  }

  Future<void> deleteById(String segmentId) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.delete('segments',
        where: 'id = ? AND $_owned', whereArgs: [segmentId, owner.key]);
    owner.requireCurrent();
  }

  /// Deletes a segment and hands back its row, for Undo ([restore]).
  ///
  /// Heat numbers and saw ticks of the segment are left alone: they are
  /// pinned to its id, so Undo brings them back with it, and until then the
  /// heat screen lists the entries as "no place" instead of losing them.
  /// Null when the segment was already gone (or is another account's).
  Future<Map<String, Object?>?> deleteWithSnapshot(String segmentId) async {
    final (owner, db) = await _projects.ownerAndDb();
    return db.transaction<Map<String, Object?>?>((txn) async {
      owner.requireCurrent();
      final rows = await txn.query('segments',
          where: 'id = ? AND $_owned',
          whereArgs: [segmentId, owner.key],
          limit: 1);
      if (rows.isEmpty) return null;
      await txn.delete('segments', where: 'id = ?', whereArgs: [segmentId]);
      owner.requireCurrent();
      return Map<String, Object?>.from(rows.first);
    });
  }

  /// Puts back a segment deleted by [deleteWithSnapshot], with its id (so
  /// its heat numbers reattach) and, if still free, its number. When a new
  /// segment has taken the number in the meantime, the restored one goes to
  /// the end (next free number) rather than failing the Undo. Returns the
  /// seq_no it got.
  Future<int> restore(Map<String, Object?> row) async {
    final (owner, db) = await _projects.ownerAndDb();
    return db.transaction<int>((txn) async {
      owner.requireCurrent();
      final projectId = row['project_id'] as String;
      await _projects.requireProject(txn, projectId, owner);
      final seq = (row['seq_no'] as num).toInt();
      final taken = await txn.query('segments',
          columns: ['id'],
          where: 'project_id = ? AND seq_no = ?',
          whereArgs: [projectId, seq],
          limit: 1);
      var useSeq = seq;
      if (taken.isNotEmpty) {
        final m = await txn.rawQuery(
          'SELECT COALESCE(MAX(seq_no), 0) AS m FROM segments WHERE project_id = ?;',
          [projectId],
        );
        useSeq = ((m.first['m'] as num?)?.toInt() ?? 0) + 1;
      }
      await txn.insert(
        'segments',
        {...row, 'seq_no': useSeq},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      owner.requireCurrent();
      return useSeq;
    });
  }

  Future<void> deleteAllForProject(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.delete('segments',
        where: 'project_id = ? AND $_owned', whereArgs: [projectId, owner.key]);
    owner.requireCurrent();
  }

  Future<double> sumCutForProject(String projectId, double diameter, double wall) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(cut_mm),0) AS s FROM segments WHERE project_id = ? AND diameter_mm = ? AND wall_thickness_mm = ? AND $_owned;',
      [projectId, diameter, wall, owner.key],
    );
    owner.requireCurrent();
    return ((rows.first['s'] as num?)?.toDouble() ?? 0.0);
  }
}

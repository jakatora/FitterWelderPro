import 'package:sqflite/sqflite.dart';

import 'local_record_owner.dart';
import 'owned_table.dart';

/// Pieces of the cut list ticked off at the saw (schema v23 `cut_marks`),
/// stored locally — the saw is where there is no signal.
///
/// A piece is a segment (stable id) and the part of a split cut (1 when the
/// cut fits one bar). The segment's CUT at the moment of ticking is kept: a
/// segment corrected since then (different CUT) is NOT shown as cut — the
/// piece lying by the saw is the old length.
///
/// v34: ticks belong to the owner of their project.
class CutMarkDao {
  CutMarkDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _projects = OwnedProjects(captureOwner: captureOwner);
  final OwnedProjects _projects;

  static const _owned = OwnedProjects.childOfOwnedProject;

  /// Tolerance for "the same CUT as when it was ticked".
  static const double sameCutToleranceMm = 0.05;

  static String keyOf(String segmentId, int part) => '$segmentId|$part';

  /// `segmentId|part` → CUT (mm) the piece had when it was ticked.
  Future<Map<String, double>> forProject(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query('cut_marks',
        where: 'project_id = ? AND $_owned', whereArgs: [projectId, owner.key]);
    owner.requireCurrent();
    return {
      for (final r in rows)
        keyOf(r['segment_id'] as String, (r['part'] as num).toInt()):
            (r['cut_mm'] as num).toDouble(),
    };
  }

  Future<void> mark({
    required String projectId,
    required String segmentId,
    required int part,
    required double cutMm,
  }) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _projects.requireProject(txn, projectId, owner);
      await txn.insert(
        'cut_marks',
        {
          'project_id': projectId,
          'segment_id': segmentId,
          'part': part,
          'cut_mm': cutMm,
          'marked_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      owner.requireCurrent();
    });
  }

  Future<void> unmark({required String segmentId, required int part}) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.delete('cut_marks',
        where: 'segment_id = ? AND part = ? AND $_owned',
        whereArgs: [segmentId, part, owner.key]);
    owner.requireCurrent();
  }

  /// Whether a mark stored at [markedCutMm] still counts for a segment whose
  /// CUT is now [currentCutMm].
  static bool stillValid(double? markedCutMm, double currentCutMm) =>
      markedCutMm != null &&
      (markedCutMm - currentCutMm).abs() <= sameCutToleranceMm;
}

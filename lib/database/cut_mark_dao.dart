import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// Pieces of the cut list ticked off at the saw (schema v23 `cut_marks`),
/// stored locally — the saw is where there is no signal.
///
/// A piece is a segment (stable id) and the part of a split cut (1 when the
/// cut fits one bar). The segment's CUT at the moment of ticking is kept: a
/// segment corrected since then (different CUT) is NOT shown as cut — the
/// piece lying by the saw is the old length.
class CutMarkDao {
  Future<Database> _db() => AppDatabase.get();

  /// Tolerance for "the same CUT as when it was ticked".
  static const double sameCutToleranceMm = 0.05;

  static String keyOf(String segmentId, int part) => '$segmentId|$part';

  /// `segmentId|part` → CUT (mm) the piece had when it was ticked.
  Future<Map<String, double>> forProject(String projectId) async {
    final db = await _db();
    final rows = await db.query('cut_marks',
        where: 'project_id = ?', whereArgs: [projectId]);
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
    final db = await _db();
    await db.insert(
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
  }

  Future<void> unmark({required String segmentId, required int part}) async {
    final db = await _db();
    await db.delete('cut_marks',
        where: 'segment_id = ? AND part = ?', whereArgs: [segmentId, part]);
  }

  /// Whether a mark stored at [markedCutMm] still counts for a segment whose
  /// CUT is now [currentCutMm].
  static bool stillValid(double? markedCutMm, double currentCutMm) =>
      markedCutMm != null &&
      (markedCutMm - currentCutMm).abs() <= sameCutToleranceMm;
}

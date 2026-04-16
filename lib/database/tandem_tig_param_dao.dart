import 'package:sqflite/sqflite.dart';

import 'db.dart';
import '../models/tandem_tig_param.dart';

class TandemTigParamDao {
  static const double _eps = 0.0001;

  Future<List<TandemTigParam>> listApprovedFiltered({
    required String materialGroup,
    required String position,
    required String jointType,
    double? landMm,
    double? gapMm,
  }) async {
    final db = await AppDatabase.get();

    final where = StringBuffer('approved = 1 AND material_group = ? AND position = ? AND joint_type = ?');
    final args = <Object?>[materialGroup, position, jointType];

    // land
    if (jointType == 'BEVEL') {
      where.write(' AND land_mm = ?');
      args.add(landMm ?? 0.0);
    } else {
      where.write(' AND land_mm IS NULL');
    }

    // gap
    final g = (gapMm ?? 0.0);
    if (jointType == 'BUTT' || g <= 0.0) {
      where.write(' AND gap_mm IS NULL');
    } else {
      where.write(' AND gap_mm = ?');
      args.add(g);
    }

    final rows = await db.query(
      'tandem_tig_params',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'wall_thickness_mm ASC, wall_thickness2_mm ASC',
    );
    return rows.map(TandemTigParam.fromMap).toList();
  }

  /// Returns an approved record only if it matches the thickness pair (order-insensitive).
  Future<TandemTigParam?> getExactApproved({
    required String materialGroup,
    required String position,
    required String jointType,
    required double wallThicknessMm,
    double? wallThickness2Mm,
    double? landMm,
    double? gapMm,
  }) async {
    final pts = await listApprovedFiltered(
      materialGroup: materialGroup,
      position: position,
      jointType: jointType,
      landMm: landMm,
      gapMm: gapMm,
    );
    if (pts.isEmpty) return null;

    final t1 = wallThicknessMm;
    final t2 = wallThickness2Mm ?? wallThicknessMm;
    final targetMin = t1 < t2 ? t1 : t2;
    final targetMax = t1 < t2 ? t2 : t1;

    for (final p in pts) {
      final a = p.wallThicknessMm;
      final b = p.wallThickness2Mm ?? p.wallThicknessMm;
      final pMin = a < b ? a : b;
      final pMax = a < b ? b : a;
      if ((pMin - targetMin).abs() < _eps && (pMax - targetMax).abs() < _eps) {
        return p;
      }
    }
    return null;
  }
  Future<List<TandemTigParam>> listApproved({String? materialGroup}) async {
    final db = await AppDatabase.get();
    final where = StringBuffer('approved = 1');
    final args = <Object?>[];
    if (materialGroup != null && materialGroup.trim().isNotEmpty) {
      where.write(' AND material_group = ?');
      args.add(materialGroup);
    }
    final rows = await db.query(
      'tandem_tig_params',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'material_group, position, joint_type, land_mm, wall_thickness_mm, wall_thickness2_mm',
    );
    return rows.map(TandemTigParam.fromMap).toList();
  }

  Future<void> upsert(TandemTigParam p) async {
    final db = await AppDatabase.get();
    await db.insert('tandem_tig_params', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Users must not delete approved records.
  Future<void> deleteById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query('tandem_tig_params', columns: ['approved'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final approved = ((rows.first['approved'] as int?) ?? 0) == 1;
    if (approved) return; // locked
    await db.delete('tandem_tig_params', where: 'id = ?', whereArgs: [id]);
  }

  /// Finds best matching approved record for the given filter.
  ///
  /// NOTE: We use nearest-neighbor in (minThickness, maxThickness) space.
  Future<TandemTigParam?> getBestApproved({
    required String materialGroup,
    required String position,
    required String jointType,
    required double wallThicknessMm,
    double? wallThickness2Mm,
    double? landMm,
  }) async {
    final db = await AppDatabase.get();

    final where = StringBuffer('material_group = ? AND position = ? AND joint_type = ? AND approved = 1');
    final args = <Object?>[materialGroup, position, jointType];

    if (jointType == 'BEVEL') {
      where.write(' AND land_mm = ?');
      args.add(landMm ?? 0.0);
    } else {
      where.write(' AND land_mm IS NULL');
    }

    final rows = await db.query(
      'tandem_tig_params',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'wall_thickness_mm ASC',
    );
    if (rows.isEmpty) return null;

    final pts = rows.map(TandemTigParam.fromMap).toList();

    final t1 = wallThicknessMm;
    final t2 = wallThickness2Mm ?? wallThicknessMm;
    final targetMin = t1 < t2 ? t1 : t2;
    final targetMax = t1 < t2 ? t2 : t1;

    double bestScore = 1e18;
    TandemTigParam? best;

    for (final p in pts) {
      final a = p.wallThicknessMm;
      final b = p.wallThickness2Mm ?? p.wallThicknessMm;
      final pMin = a < b ? a : b;
      final pMax = a < b ? b : a;

      final score = (pMin - targetMin).abs() + (pMax - targetMax).abs();
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
      if (score < 0.0001) return p;
    }

    return best;
  }
}

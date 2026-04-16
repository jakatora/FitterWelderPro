import 'package:sqflite/sqflite.dart';

import 'db.dart';
import '../models/component_heat.dart';

class ComponentHeatDao {
  Future<Database> _db() => AppDatabase.get();

  Future<void> insert(Map<String, Object?> row) async {
    final db = await _db();
    await db.insert('component_heats', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ComponentHeat>> listForComponent({required String projectId, required String componentKey}) async {
    final db = await _db();
    final rows = await db.query(
      'component_heats',
      where: 'project_id = ? AND component_key = ?',
      whereArgs: [projectId, componentKey],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => ComponentHeat.fromMap(r)).toList();
  }

  Future<int> countForComponent({required String projectId, required String componentKey}) async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM component_heats WHERE project_id = ? AND component_key = ?',
      [projectId, componentKey],
    );
    return (rows.first['c'] as num).toInt();
  }
}

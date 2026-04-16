import '../database/db.dart';
import '../models/project.dart';

class ProjectDao {
  Future<void> insert(Project p) async {
    final db = await AppDatabase.get();
    await db.insert('projects', {
      'id': p.id,
      'name': p.name,
      'material_group': p.materialGroup,
      'diameter_mm': p.diameterMm,
      'wall_thickness_mm': p.wallThicknessMm,
      'current_diameter_mm': p.currentDiameterMm,
      'stock_length_mm': p.stockLengthMm,
      'saw_kerf_mm': p.sawKerfMm,
      'gap_mm': p.gapMm,
      'created_at': p.createdAt,
      'updated_at': p.updatedAt,
    });
  }

  Future<List<Project>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(Project.fromRow).toList();
  }

  Future<Project?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Project.fromRow(rows.first);
  }

  /// Kasuje projekt (bez kaskady — usuń segmenty osobno przez SegmentDao).
  Future<void> deleteById(String projectId) async {
    final db = await AppDatabase.get();
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  Future<void> updateName(String projectId, String name) async {
    final db = await AppDatabase.get();
    await db.update(
      'projects',
      {'name': name, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  Future<void> updateCurrentDiameter(String projectId, double currentDiameter) async {
    final db = await AppDatabase.get();
    await db.update(
      'projects',
      {
        'current_diameter_mm': currentDiameter,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }
}

import '../database/db.dart';
import '../models/project.dart';

class ProjectDeletionSnapshot {
  const ProjectDeletionSnapshot({
    this.projectRows = const [],
    this.segmentRows = const [],
    this.heatPhotoRows = const [],
    this.componentHeatRows = const [],
  });

  final List<Map<String, Object?>> projectRows;
  final List<Map<String, Object?>> segmentRows;
  final List<Map<String, Object?>> heatPhotoRows;
  final List<Map<String, Object?>> componentHeatRows;
}

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
    final rows =
        await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Project.fromRow(rows.first);
  }

  /// Zapisuje komplet danych projektu i usuwa je w tej samej transakcji.
  Future<ProjectDeletionSnapshot> deleteWithSnapshot(String projectId) async {
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      List<Map<String, Object?>> copyRows(List<Map<String, Object?>> rows) =>
          rows.map((row) => Map<String, Object?>.from(row)).toList();

      final snapshot = ProjectDeletionSnapshot(
        projectRows: copyRows(await txn.query(
          'projects',
          where: 'id = ?',
          whereArgs: [projectId],
          limit: 1,
        )),
        segmentRows: copyRows(await txn.query(
          'segments',
          where: 'project_id = ?',
          whereArgs: [projectId],
        )),
        heatPhotoRows: copyRows(await txn.query(
          'heat_photos',
          where: 'project_id = ?',
          whereArgs: [projectId],
        )),
        componentHeatRows: copyRows(await txn.query(
          'component_heats',
          where: 'project_id = ?',
          whereArgs: [projectId],
        )),
      );

      for (final table in ['segments', 'heat_photos', 'component_heats']) {
        await txn.delete(
          table,
          where: 'project_id = ?',
          whereArgs: [projectId],
        );
      }
      await txn.delete('projects', where: 'id = ?', whereArgs: [projectId]);
      return snapshot;
    });
  }

  Future<void> restoreDeletion(ProjectDeletionSnapshot snapshot) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      for (final row in snapshot.projectRows) {
        await txn.insert('projects', Map<String, Object?>.from(row));
      }
      for (final row in snapshot.segmentRows) {
        await txn.insert('segments', Map<String, Object?>.from(row));
      }
      for (final row in snapshot.heatPhotoRows) {
        await txn.insert('heat_photos', Map<String, Object?>.from(row));
      }
      for (final row in snapshot.componentHeatRows) {
        await txn.insert('component_heats', Map<String, Object?>.from(row));
      }
    });
  }

  /// Kasuje projekt atomowo. Ekran z Cofnij używa [deleteWithSnapshot].
  Future<void> deleteById(String projectId) async {
    await deleteWithSnapshot(projectId);
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

  Future<void> updateCurrentDiameter(
      String projectId, double currentDiameter) async {
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

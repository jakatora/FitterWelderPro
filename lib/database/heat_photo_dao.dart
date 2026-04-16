import '../database/db.dart';
import '../models/heat_photo.dart';

class HeatPhotoDao {
  Future<void> insert(Map<String, Object?> row) async {
    final db = await AppDatabase.get();
    await db.insert('heat_photos', row);
  }

  Future<List<HeatPhoto>> listForProject(String projectId) async {
    final db = await AppDatabase.get();
    final rows = await db.query(
      'heat_photos',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(HeatPhoto.fromRow).toList();
  }
}

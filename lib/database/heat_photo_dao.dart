import '../models/heat_photo.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

/// Zdjęcia wytopów projektu listy cięć. v34: należą do właściciela projektu.
class HeatPhotoDao {
  HeatPhotoDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _projects = OwnedProjects(captureOwner: captureOwner);
  final OwnedProjects _projects;

  static const _owned = OwnedProjects.childOfOwnedProject;

  Future<void> insert(Map<String, Object?> row) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _projects.requireProject(txn, row['project_id'] as String, owner);
      await txn.insert('heat_photos', row);
      owner.requireCurrent();
    });
  }

  Future<List<HeatPhoto>> listForProject(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query(
      'heat_photos',
      where: 'project_id = ? AND $_owned',
      whereArgs: [projectId, owner.key],
      orderBy: 'created_at DESC',
    );
    owner.requireCurrent();
    return rows.map(HeatPhoto.fromRow).toList();
  }

  Future<void> deleteById(String id) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.delete('heat_photos',
        where: 'id = ? AND $_owned', whereArgs: [id, owner.key]);
    owner.requireCurrent();
  }
}

import 'package:sqflite/sqflite.dart';

import '../app_database.dart';
import '../models/project.dart';
import '../models/heat_number.dart';

class ProjectRepository {
  Future<Database> get _db async => AppDatabase.instance.db;

  Future<int> createProject(Project project) async {
    final db = await _db;
    return db.insert('projects', project.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> updateProject(Project project) async {
    final db = await _db;
    if (project.id == null) return;
    await db.update(
      'projects',
      project.toMap(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<void> deleteProject(int projectId) async {
    final db = await _db;
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  Future<Project?> getProject(int projectId) async {
    final db = await _db;
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [projectId], limit: 1);
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  Future<List<Project>> listProjects({String? search}) async {
    final db = await _db;

    final s = (search ?? '').trim();
    if (s.isEmpty) {
      final rows = await db.query('projects', orderBy: 'updated_at DESC');
      return rows.map(Project.fromMap).toList();
    }

    final like = '%$s%';
    final rows = await db.query(
      'projects',
      where: 'name LIKE ? OR client LIKE ? OR location LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'updated_at DESC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<int> addHeatNumber(HeatNumber heat) async {
    final db = await _db;
    return db.insert('heat_numbers', heat.toMap(), conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> deleteHeatNumber(int id) async {
    final db = await _db;
    await db.delete('heat_numbers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HeatNumber>> listHeatNumbers(int projectId) async {
    final db = await _db;
    final rows = await db.query(
      'heat_numbers',
      where: 'project_id = ?',
      whereArgs: [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(HeatNumber.fromMap).toList();
  }
}

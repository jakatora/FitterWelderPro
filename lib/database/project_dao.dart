import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db.dart';
import '../models/project.dart';

/// Everything a cascade delete took out, kept as raw rows so it can be put
/// back byte for byte.
///
/// The project list offers a 6-second Undo on swipe-to-delete, so the cascade
/// cannot simply drop the rows and forget them: it hands them back here, and
/// either [ProjectDao.restore] re-inserts them or [ProjectDao.purgePhotoFiles]
/// finishes the job once the Undo window has closed.
class DeletedProject {
  DeletedProject({
    required this.projectId,
    required this.projects,
    required this.segments,
    required this.heatPhotos,
    required this.componentHeats,
  });

  final String projectId;
  final List<Map<String, Object?>> projects;
  final List<Map<String, Object?>> segments;
  final List<Map<String, Object?>> heatPhotos;
  final List<Map<String, Object?>> componentHeats;

  /// False when the id matched nothing - the row was already gone.
  bool get existed => projects.isNotEmpty;

  /// On-disk photos the app itself wrote, and therefore may delete.
  ///
  /// Deliberately heat_photos only. `component_heats.image_path` holds the
  /// path FilePicker handed back and was never copied anywhere
  /// (project_components_screen.dart stores `imgPath` verbatim), so it can
  /// point straight at a file in the user's gallery or Downloads. Deleting
  /// those would destroy the fitter's own photos, not the app's copies.
  List<String> get ownedPhotoPaths => heatPhotos
      .map((r) => r['image_path'] as String?)
      .whereType<String>()
      .toList(growable: false);
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
    final rows = await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Project.fromRow(rows.first);
  }

  /// Deletes the projects row only.
  ///
  /// Leaves segments, heat photos and component heats behind - prefer
  /// [deleteProjectCascade] for anything the user calls "delete project".
  /// Kept for the scan-import rollback, which removes a project it has only
  /// just written and that therefore has no photos or heats yet.
  Future<void> deleteById(String projectId) async {
    final db = await AppDatabase.get();
    await db.delete('projects', where: 'id = ?', whereArgs: [projectId]);
  }

  /// Deletes a project and everything that hangs off it, atomically.
  ///
  /// This is the first transaction in the app, so the pattern it sets matters:
  ///
  /// * **One [Database.transaction], four tables.** Deleting a project used to
  ///   be two separate awaits - segments, then the project. If the second one
  ///   threw (database locked, disk full on the shop tablet) the first had
  ///   already committed, and the fitter was left with a project whose cut
  ///   list had silently emptied, under a message saying the delete failed.
  ///   Inside a transaction either all four deletes land or none of them do.
  /// * **Only `txn` inside the callback, never the outer `db`.** sqflite runs
  ///   a transaction on a reserved connection; a statement issued on `db`
  ///   while one is open waits for the transaction, which is waiting on this
  ///   callback, and the app deadlocks.
  /// * **No file I/O inside the transaction.** A rollback can undo a DELETE,
  ///   it cannot un-delete a .jpg. The rows go here; the photo paths are
  ///   handed back so the caller can unlink the files *after* the commit -
  ///   see [purgePhotoFiles].
  ///
  /// heat_photos, component_heats and their .jpg files were all left orphaned
  /// by the old two-step delete: rows pointing at a project that no longer
  /// exists, and photo files no screen can ever reach again.
  Future<DeletedProject> deleteProjectCascade(String projectId) async {
    final db = await AppDatabase.get();
    return db.transaction<DeletedProject>((txn) async {
      // Snapshot before deleting: the caller needs the rows for Undo and the
      // image paths for the file cleanup, and after the DELETEs they are gone.
      // txn.query hands back read-only maps, so copy them to stay insertable.
      Future<List<Map<String, Object?>>> snapshot(
        String table,
        String column,
      ) async {
        final rows = await txn.query(
          table,
          where: '$column = ?',
          whereArgs: [projectId],
        );
        return rows.map(Map<String, Object?>.from).toList();
      }

      final projects = await snapshot('projects', 'id');
      final segments = await snapshot('segments', 'project_id');
      final heatPhotos = await snapshot('heat_photos', 'project_id');
      final componentHeats = await snapshot('component_heats', 'project_id');

      // Children first, parent last, so the database never holds a projects
      // row whose dependents are already gone, not even mid-transaction.
      await txn.delete('segments', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('heat_photos', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('component_heats', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [projectId]);

      return DeletedProject(
        projectId: projectId,
        projects: projects,
        segments: segments,
        heatPhotos: heatPhotos,
        componentHeats: componentHeats,
      );
    });
  }

  /// Puts a [deleted] project back exactly as it was.
  ///
  /// Also a single transaction: a half-restored Undo is the same orphan-making
  /// bug from the other direction. Only meaningful while the photo files are
  /// still on disk, i.e. before [purgePhotoFiles] has run.
  Future<void> restore(DeletedProject deleted) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      Future<void> putBack(String table, List<Map<String, Object?>> rows) async {
        for (final row in rows) {
          // replace, not abort: if something re-used the id in the meantime,
          // the snapshot is the version the fitter asked to get back.
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await putBack('projects', deleted.projects);
      await putBack('segments', deleted.segments);
      await putBack('heat_photos', deleted.heatPhotos);
      await putBack('component_heats', deleted.componentHeats);
    });
  }

  /// Unlinks the heat photo files of a [deleted] project; returns how many
  /// files were removed.
  ///
  /// Call this only once Undo is off the table - the rows are already gone,
  /// but the files are what make restoring them worth anything.
  ///
  /// Every path is checked to be inside [ownedRoot] (the app's own
  /// `<documents>/heat_photos` directory) before it is touched. Rows written
  /// before heat_photos_screen started copying picked images into that
  /// directory still hold the path FilePicker returned, which on Android can
  /// be a real file in the user's storage. Skipping those leaks a cache file
  /// the OS reclaims anyway; deleting them would destroy a photo the app never
  /// owned. Per-file failures are swallowed: the rows are committed, so one
  /// unremovable .jpg must not turn a successful delete into an error.
  Future<int> purgePhotoFiles(DeletedProject deleted, {Directory? ownedRoot}) async {
    final paths = deleted.ownedPhotoPaths;
    if (paths.isEmpty) return 0;

    Directory root;
    try {
      root = ownedRoot ??
          Directory(p.join(
            (await getApplicationDocumentsDirectory()).path,
            'heat_photos',
          ));
    } catch (_) {
      // No documents directory (plugin missing in a test host) - never guess
      // at a root, or the containment check below stops protecting anything.
      return 0;
    }
    final rootPath = p.normalize(root.path);

    var removed = 0;
    for (final raw in paths) {
      final filePath = p.normalize(raw);
      if (!p.isWithin(rootPath, filePath)) continue;
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          removed++;
        }
      } catch (_) {
        // Best effort; see the doc comment.
      }
    }
    return removed;
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

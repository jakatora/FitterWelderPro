import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/project.dart';
import '../models/segment.dart';
import '../services/account_service.dart' show AccountException;
import '../services/prefab_engine.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

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
    this.cutMarks = const [],
  });

  final String projectId;
  final List<Map<String, Object?>> projects;
  final List<Map<String, Object?>> segments;
  final List<Map<String, Object?>> heatPhotos;
  final List<Map<String, Object?>> componentHeats;

  /// v23: pieces ticked off at the saw.
  final List<Map<String, Object?>> cutMarks;

  /// False when the id matched nothing - the row was already gone.
  bool get existed => projects.isNotEmpty;

  /// On-disk photos the app itself wrote, and therefore may delete.
  ///
  /// heat_photos AND component_heats: both screens copy the picked photo
  /// into `<documents>/heat_photos` now. Older rows of either table may
  /// still point at the user's own gallery file — [ProjectDao.purgePhotoFiles]
  /// only ever deletes paths inside the app's own directory, so those stay.
  List<String> get ownedPhotoPaths => [...heatPhotos, ...componentHeats]
      .map((r) => r['image_path'] as String?)
      .whereType<String>()
      .toList(growable: false);
}

/// What [ProjectDao.updateSettings] did to the project's segments.
class ProjectSettingsUpdate {
  const ProjectSettingsUpdate({
    required this.recomputed,
    required this.changedBeyondGap,
  });

  /// Segments whose CUT was recomputed — 0 when the gap did not change.
  final int recomputed;

  /// Seq numbers of segments whose CUT moved by more than the gap difference
  /// times their welds, i.e. whose stored cut did not follow their own
  /// columns. Worth showing to the fitter before he cuts them.
  final List<int> changedBeyondGap;
}

/// The new gap leaves segment [seqNo] with nothing to cut (CUT ≤ 0).
class GapMakesCutImpossible implements Exception {
  const GapMakesCutImpossible({required this.seqNo, required this.gapMm});

  final int seqNo;
  final double gapMm;

  @override
  String toString() =>
      'GapMakesCutImpossible(segment $seqNo, gap $gapMm mm)';
}

/// v34: projekty należą do konta (`owner_scope`), a z nimi segmenty,
/// wytopy, zdjęcia i znaczniki cięcia — zob. [OwnedProjects].
class ProjectDao {
  ProjectDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _projects = OwnedProjects(captureOwner: captureOwner);
  final OwnedProjects _projects;

  OwnedTable get _owned => _projects.table;

  Future<void> insert(Project p) async {
    final (owner, db) = await _projects.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, p.id, owner);
      await txn.insert('projects', {
        'id': p.id,
        'owner_scope': owner.key,
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
        ...p.identity.toRow(),
      });
      owner.requireCurrent();
    });
  }

  Future<List<Project>> listAll() async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query('projects',
        where: _owned.where(),
        whereArgs: [owner.key],
        orderBy: 'updated_at DESC');
    owner.requireCurrent();
    return rows.map(Project.fromRow).toList();
  }

  Future<Project?> getById(String id) async {
    final (owner, db) = await _projects.ownerAndDb();
    final rows = await db.query('projects',
        where: _owned.where('id = ?'), whereArgs: [owner.key, id], limit: 1);
    owner.requireCurrent();
    if (rows.isEmpty) return null;
    return Project.fromRow(rows.first);
  }

  /// Deletes all project rows atomically; the UI keeps the cascade snapshot for Undo.
  Future<void> deleteById(String projectId) async {
    await deleteProjectCascade(projectId);
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
  ///
  /// v34: a project of another account is refused ([AccountException]) and
  /// nothing is touched.
  Future<DeletedProject> deleteProjectCascade(String projectId) async {
    final (owner, db) = await _projects.ownerAndDb();
    return db.transaction<DeletedProject>((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, projectId, owner);
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
      final cutMarks = await snapshot('cut_marks', 'project_id');

      // Children first, parent last, so the database never holds a projects
      // row whose dependents are already gone, not even mid-transaction.
      await txn.delete('segments', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('heat_photos', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('component_heats', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('cut_marks', where: 'project_id = ?', whereArgs: [projectId]);
      await txn.delete('projects', where: 'id = ?', whereArgs: [projectId]);
      owner.requireCurrent();

      return DeletedProject(
        projectId: projectId,
        projects: projects,
        segments: segments,
        heatPhotos: heatPhotos,
        componentHeats: componentHeats,
        cutMarks: cutMarks,
      );
    });
  }

  /// Puts a [deleted] project back exactly as it was.
  ///
  /// Also a single transaction: a half-restored Undo is the same orphan-making
  /// bug from the other direction. Only meaningful while the photo files are
  /// still on disk, i.e. before [purgePhotoFiles] has run.
  ///
  /// v34: only the account that deleted it gets it back — after switching
  /// accounts the Undo is refused instead of planting the project in the
  /// other account.
  Future<void> restore(DeletedProject deleted) async {
    final (owner, db) = await _projects.ownerAndDb();
    for (final row in deleted.projects) {
      if ((row['owner_scope'] ?? LocalRecordOwner.guest) != owner.key) {
        throw AccountException(_owned.foreignMessage);
      }
    }
    await db.transaction((txn) async {
      owner.requireCurrent();
      for (final row in deleted.projects) {
        await _owned.refuseForeign(txn, row['id'] as String, owner);
      }
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
      await putBack('cut_marks', deleted.cutMarks);
      owner.requireCurrent();
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

  /// Changes the settings a project can outlive its creation with — name,
  /// stock length, saw kerf and root gap — and, when the gap changed,
  /// recomputes the saved CUT of every segment of the project.
  ///
  /// Until this existed none of it could be changed: a gap typed as 0
  /// instead of 3 meant rebuilding the whole project, or cutting every pipe
  /// the gap too long.
  ///
  /// The recompute uses [PrefabEngine.storedSegmentCutMm] — the segment
  /// builder's own rule ([PrefabEngine.anchoredCutMm], welds from
  /// [PrefabEngine.weldCountForEnds]) applied to what each row stores — so a
  /// segment reopened in the builder afterwards shows the same number.
  ///
  /// One transaction for the project row and every segment: a gap that makes
  /// any cut impossible (≤ 0) throws [GapMakesCutImpossible] and NOTHING is
  /// changed — not the gap, not the name, not a single cut. Half a project
  /// on the new gap and half on the old is worse than either.
  ///
  /// [identity] (line, ISO, revision, client, class — schema v22) is written
  /// in the same transaction when given; null leaves those columns as they
  /// are, so a caller that does not edit them cannot wipe them.
  Future<ProjectSettingsUpdate> updateSettings(
    String projectId, {
    required String? name,
    required double stockLengthMm,
    required double sawKerfMm,
    required double gapMm,
    ProjectIdentity? identity,
  }) async {
    final (owner, db) = await _projects.ownerAndDb();
    return db.transaction<ProjectSettingsUpdate>((txn) async {
      owner.requireCurrent();
      final current = await txn.query('projects',
          where: _owned.where('id = ?'),
          whereArgs: [owner.key, projectId],
          limit: 1);
      if (current.isEmpty) {
        throw StateError('project $projectId does not exist');
      }
      final oldGap = ((current.first['gap_mm'] as num?) ?? 0).toDouble();
      final now = DateTime.now().millisecondsSinceEpoch;

      await txn.update(
        'projects',
        {
          'name': name,
          'stock_length_mm': stockLengthMm,
          'saw_kerf_mm': sawKerfMm,
          'gap_mm': gapMm,
          'updated_at': now,
          if (identity != null) ...identity.toRow(),
        },
        where: 'id = ?',
        whereArgs: [projectId],
      );

      if ((gapMm - oldGap).abs() < 1e-9) {
        return const ProjectSettingsUpdate(recomputed: 0, changedBeyondGap: []);
      }

      final rows = await txn.query('segments',
          where: 'project_id = ?',
          whereArgs: [projectId],
          orderBy: 'seq_no ASC');
      final beyond = <int>[];
      for (final row in rows) {
        final seg = Segment.fromRow(row);
        final cut = PrefabEngine.storedSegmentCutMm(
          isoMm: seg.isoMm,
          isoRef: seg.isoRef,
          startKind: seg.startKind,
          startValueMm: seg.startValueMm,
          endKind: seg.endKind,
          endValueMm: seg.endValueMm,
          gapMm: gapMm,
        );
        if (!cut.isFinite || cut <= 0) {
          // Throwing rolls the whole transaction back, project row included.
          throw GapMakesCutImpossible(seqNo: seg.seqNo, gapMm: gapMm);
        }
        // A row saved consistently moves by exactly (old − new gap) × welds.
        // Anything else means its stored cut did not follow its own columns
        // (e.g. saved under the builder's old start-only weld count): the
        // recompute is still the builder's number, but the fitter is told
        // which segments to look at before he cuts them.
        final welds = PrefabEngine.weldCountForEnds(
          startIsOpenEnd: seg.startKind == 'logical',
          endIsOpenEnd: seg.endKind == 'logical',
        );
        final expected = seg.cutMm + (oldGap - gapMm) * welds;
        if ((cut - expected).abs() > 0.05) beyond.add(seg.seqNo);

        await txn.update(
          'segments',
          {'cut_mm': cut, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [seg.id],
        );
      }
      owner.requireCurrent();
      return ProjectSettingsUpdate(
        recomputed: rows.length,
        changedBeyondGap: beyond,
      );
    });
  }

  /// Writes line / ISO / revision / client / class (schema v22) of a project.
  /// Returns the number of rows changed — 0 when the project is gone.
  Future<int> updateIdentity(String projectId, ProjectIdentity identity) =>
      _updateOwned(projectId, identity.toRow());

  /// Marks the project as just worked on: the project list is sorted by
  /// `updated_at`, and adding / editing / deleting a segment used not to
  /// move it — the project the fitter worked on today sank down the list.
  Future<void> touch(String projectId) => _updateOwned(projectId, const {});

  Future<void> updateName(String projectId, String name) =>
      _updateOwned(projectId, {'name': name});

  Future<void> updateCurrentDiameter(
          String projectId, double currentDiameter) =>
      _updateOwned(projectId, {'current_diameter_mm': currentDiameter});

  /// [values] + `updated_at` on the project, only if it is this account's.
  /// Returns rows changed — 0 when the project is gone or another account's.
  Future<int> _updateOwned(
      String projectId, Map<String, Object?> values) async {
    final (owner, db) = await _projects.ownerAndDb();
    final n = await db.update(
      'projects',
      {...values, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: _owned.where('id = ?'),
      whereArgs: [owner.key, projectId],
    );
    owner.requireCurrent();
    return n;
  }
}

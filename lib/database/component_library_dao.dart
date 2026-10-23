import 'package:sqflite/sqflite.dart';

import '../models/library_component.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

/// One saved segment that uses a component-library entry.
class LibraryUsage {
  const LibraryUsage({
    required this.projectId,
    required this.projectName,
    required this.seqNo,
  });

  final String projectId;
  final String? projectName;
  final int seqNo;
}

/// How far a stored Ø / wall may differ from the one asked for and still be
/// "the same pipe" in [ComponentLibraryDao.listFor].
///
/// WHY a tolerance: both columns are SQLite REAL, and they used to be matched
/// with `=`. A component saved as 114.3 was then invisible to a project whose
/// diameter came in as 114.30000000000001 (arithmetic on the way in), 114.29
/// (rounded differently on another screen), or anything else that is
/// physically the same tube but not bit-for-bit the same double — the builder
/// then asked for the takeout again and a second, possibly different, entry
/// went into the library. ±0.05 mm absorbs that noise (and e.g. the ASME
/// 60.33 vs the metric 60.3 of the same 2" tube) but stays below the gap
/// between genuinely different ODs — the closest pair in use, EN 76.1 vs
/// sanitary 76.2, is 0.1 mm apart. On the wall, 0.05 mm never changes a
/// fitting's take-out, which is what the library is looked up for.
const double kLibraryMatchToleranceMm = 0.05;

/// Guards the `<=` against the binary representation of the tolerance itself:
/// |114.35 - 114.3| is 0.04999999999999716 or 0.05000000000000426 depending
/// on the operands, and a value exactly on the ±0.05 edge must match both ways.
const double _kToleranceSlack = 1e-9;

/// v34: biblioteka należy do konta (`owner_scope`); dwa konta mogą mieć
/// tę samą kształtkę (UNIQUE obejmuje właściciela).
class ComponentLibraryDao {
  ComponentLibraryDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _owned = OwnedTable('component_library',
            captureOwner: captureOwner,
            foreignMessage: 'Ta kształtka należy do innego konta. / '
                'This component belongs to another account.');
  final OwnedTable _owned;

  /// Components for project diameter+wall, matched within
  /// ±[kLibraryMatchToleranceMm] (see there for why not `=`).
  /// Reducer is special:
  /// - For END selection: inlet diameter (diameter_mm) matches current
  /// - For START selection: outlet diameter (diameter_out_mm) matches current
  /// We return reducers that match either; UI can still allow choosing them.
  Future<List<LibraryComponent>> listFor({
    required String materialGroup,
    required double currentDiameter,
    required double wallThickness,
  }) async {
    const tol = kLibraryMatchToleranceMm + _kToleranceSlack;
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.rawQuery('''
SELECT * FROM component_library
WHERE owner_scope = ?
  AND material_group = ?
  AND ABS(wall_thickness_mm - ?) <= ?
  AND (
    (type = 'REDUCER' AND (ABS(diameter_mm - ?) <= ? OR ABS(diameter_out_mm - ?) <= ?))
    OR
    (type <> 'REDUCER' AND ABS(diameter_mm - ?) <= ?)
  )
ORDER BY type ASC;
''', [
      owner.key,
      materialGroup,
      wallThickness, tol,
      currentDiameter, tol, currentDiameter, tol,
      currentDiameter, tol,
    ]);
    owner.requireCurrent();

    return rows.map(LibraryComponent.fromRow).toList();
  }

  Future<void> insert(LibraryComponent c) async {
    final (owner, db) = await _owned.ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, c.id, owner);
      await txn.insert('component_library', {
        'id': c.id,
        'owner_scope': owner.key,
        'material_group': c.materialGroup,
        'type': c.type,
        'diameter_mm': c.diameterMm,
        'wall_thickness_mm': c.wallThicknessMm,
        'axis_mm': c.axisMm,
        'length_mm': c.lengthMm,
        'measurement_mode': c.measurementMode,
        'diameter_out_mm': c.diameterOutMm,
        'created_at': c.createdAt,
        'updated_at': c.updatedAt,
      });
      owner.requireCurrent();
    });
  }

  Future<List<LibraryComponent>> listAll() async {
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query('component_library',
        where: _owned.where(),
        whereArgs: [owner.key],
        orderBy: 'type ASC, material_group ASC, diameter_mm ASC');
    owner.requireCurrent();
    return rows.map(LibraryComponent.fromRow).toList();
  }

  /// Overwrites the values of an existing entry, matched on [c]'s id; keeps
  /// its `created_at`. Returns the number of rows changed (0 = gone).
  ///
  /// The library used to be append-only: a take-off typed as 762 instead of
  /// 76.2, or a reducer saved with length 0, stayed there forever — and the
  /// UNIQUE key stopped a corrected copy from being added next to it.
  /// Editing the entry in place is the fix; a change that would collide with
  /// ANOTHER entry's key still throws (the caller says so).
  Future<int> update(LibraryComponent c) async {
    final (owner, db) = await _owned.ownerAndDb();
    final n = await db.update(
      'component_library',
      {
        'material_group': c.materialGroup,
        'type': c.type,
        'diameter_mm': c.diameterMm,
        'wall_thickness_mm': c.wallThicknessMm,
        'axis_mm': c.axisMm,
        'length_mm': c.lengthMm,
        'measurement_mode': c.measurementMode,
        'diameter_out_mm': c.diameterOutMm,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: _owned.where('id = ?'),
      whereArgs: [owner.key, c.id],
    );
    owner.requireCurrent();
    return n;
  }

  /// Entry with the same material, type and sizes as [c] (within
  /// ±[kLibraryMatchToleranceMm]), other than [c] itself — what the add
  /// dialog offers to edit instead of failing on the UNIQUE key. For a
  /// reducer the pair of ends matches either way round (114.3→60.3 is the
  /// same fitting as 60.3→114.3).
  Future<LibraryComponent?> findSameKind(LibraryComponent c) async {
    const tol = kLibraryMatchToleranceMm + _kToleranceSlack;
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query(
      'component_library',
      where: _owned.where('material_group = ? AND type = ? AND id <> ? '
          'AND ABS(wall_thickness_mm - ?) <= ?'),
      whereArgs: [
        owner.key,
        c.materialGroup,
        c.type,
        c.id,
        c.wallThicknessMm,
        tol
      ],
    );
    owner.requireCurrent();
    bool near(double? a, double? b) =>
        a == null || b == null ? a == b : (a - b).abs() <= tol;
    for (final r in rows.map(LibraryComponent.fromRow)) {
      if (c.type == 'REDUCER') {
        final same = near(r.diameterMm, c.diameterMm) &&
            near(r.diameterOutMm, c.diameterOutMm);
        final flipped = near(r.diameterMm, c.diameterOutMm) &&
            near(r.diameterOutMm, c.diameterMm);
        if (same || flipped) return r;
      } else if (near(r.diameterMm, c.diameterMm)) {
        return r;
      }
    }
    return null;
  }

  /// Segments (in any project of this account) that use entry [id] as
  /// START or END.
  Future<List<LibraryUsage>> usages(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    final used = await _usages(db, id, owner);
    owner.requireCurrent();
    return used;
  }

  static Future<List<LibraryUsage>> _usages(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.rawQuery('''
SELECT s.project_id AS project_id, p.name AS project_name, s.seq_no AS seq_no
FROM segments s JOIN projects p ON p.id = s.project_id
WHERE (s.start_library_id = ? OR s.end_library_id = ?) AND p.owner_scope = ?
ORDER BY p.name, s.seq_no;
''', [id, id, owner.key]);
    return [
      for (final r in rows)
        LibraryUsage(
          projectId: r['project_id'] as String,
          projectName: r['project_name'] as String?,
          seqNo: (r['seq_no'] as num).toInt(),
        ),
    ];
  }

  /// Deletes entry [id] unless a saved segment still uses it; returns the
  /// segments that block the delete (empty = deleted).
  ///
  /// Checked and deleted in one transaction, so a segment saved in between
  /// cannot be left pointing at nothing. A used entry is what every stored
  /// CUT of those segments was computed from — and what reopening one of
  /// them recomputes from.
  Future<List<LibraryUsage>> deleteIfUnused(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    return db.transaction<List<LibraryUsage>>((txn) async {
      owner.requireCurrent();
      final used = await _usages(txn, id, owner);
      if (used.isNotEmpty) return used;
      await txn.delete('component_library',
          where: _owned.where('id = ?'), whereArgs: [owner.key, id]);
      owner.requireCurrent();
      return const [];
    });
  }

  Future<LibraryComponent?> getById(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query('component_library',
        where: _owned.where('id = ?'), whereArgs: [owner.key, id], limit: 1);
    owner.requireCurrent();
    if (rows.isEmpty) return null;
    return LibraryComponent.fromRow(rows.first);
  }
}

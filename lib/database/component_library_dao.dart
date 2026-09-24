import '../database/db.dart';
import '../models/library_component.dart';

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

class ComponentLibraryDao {
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
    final db = await AppDatabase.get();
    final rows = await db.rawQuery('''
SELECT * FROM component_library
WHERE material_group = ?
  AND ABS(wall_thickness_mm - ?) <= ?
  AND (
    (type = 'REDUCER' AND (ABS(diameter_mm - ?) <= ? OR ABS(diameter_out_mm - ?) <= ?))
    OR
    (type <> 'REDUCER' AND ABS(diameter_mm - ?) <= ?)
  )
ORDER BY type ASC;
''', [
      materialGroup,
      wallThickness, tol,
      currentDiameter, tol, currentDiameter, tol,
      currentDiameter, tol,
    ]);

    return rows.map(LibraryComponent.fromRow).toList();
  }

  Future<void> insert(LibraryComponent c) async {
    final db = await AppDatabase.get();
    await db.insert('component_library', {
      'id': c.id,
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
  }

  Future<List<LibraryComponent>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query('component_library', orderBy: 'type ASC');
    return rows.map(LibraryComponent.fromRow).toList();
  }

  Future<LibraryComponent?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query('component_library', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LibraryComponent.fromRow(rows.first);
  }
}

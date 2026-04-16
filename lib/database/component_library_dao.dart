import '../database/db.dart';
import '../models/library_component.dart';

class ComponentLibraryDao {
  /// Components for project diameter+wall.
  /// Reducer is special:
  /// - For END selection: inlet diameter (diameter_mm) matches current
  /// - For START selection: outlet diameter (diameter_out_mm) matches current
  /// We return reducers that match either; UI can still allow choosing them.
  Future<List<LibraryComponent>> listFor({
    required String materialGroup,
    required double currentDiameter,
    required double wallThickness,
  }) async {
    final db = await AppDatabase.get();
    final rows = await db.rawQuery('''
SELECT * FROM component_library
WHERE material_group = ?
  AND wall_thickness_mm = ?
  AND (
    (type = 'REDUCER' AND (diameter_mm = ? OR diameter_out_mm = ?))
    OR
    (type <> 'REDUCER' AND diameter_mm = ?)
  )
ORDER BY type ASC;
''', [materialGroup, wallThickness, currentDiameter, currentDiameter, currentDiameter]);

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

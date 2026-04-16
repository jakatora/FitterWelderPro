import '../database/db.dart';
import '../models/weld_param.dart';

class WeldParamDao {
  Future<void> insert(WeldParam p) async {
    final db = await AppDatabase.get();
    await db.insert('weld_params', {
      'id': p.id,
      'method': p.method,
      'base_material': p.baseMaterial,
      'welder_model': p.welderModel,
      'diameter_mm': p.diameterMm,
      'wall_thickness_mm': p.wallThicknessMm,
      'electrode_mm': p.electrodeMm,
      'torch_gas_lpm': p.torchGasLpm,
      'nozzle_type': p.nozzleType,
      'nozzle_size': p.nozzleSize,
      'purge_lpm': p.purgeLpm,
      'amps': p.amps,
      'outlet_holes': p.outletHoles,
      'tempo': p.tempo,
      'note': p.note,
      'created_at': p.createdAt,
      'updated_at': p.updatedAt,
    });
  }

  Future<List<WeldParam>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query('weld_params', orderBy: 'updated_at DESC');
    return rows.map(WeldParam.fromRow).toList();
  }


  Future<void> update(WeldParam p) async {
    final db = await AppDatabase.get();
    await db.update(
      'weld_params',
      {
        'method': p.method,
        'base_material': p.baseMaterial,
        'welder_model': p.welderModel,
        'diameter_mm': p.diameterMm,
        'wall_thickness_mm': p.wallThicknessMm,
        'electrode_mm': p.electrodeMm,
        'torch_gas_lpm': p.torchGasLpm,
        'nozzle_type': p.nozzleType,
        'nozzle_size': p.nozzleSize,
        'purge_lpm': p.purgeLpm,
        'amps': p.amps,
      'outlet_holes': p.outletHoles,
      'tempo': p.tempo,
        'note': p.note,
        'updated_at': p.updatedAt,
      },
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  Future<void> deleteById(String id) async {
    final db = await AppDatabase.get();
    await db.delete('weld_params', where: 'id = ?', whereArgs: [id]);
  }
}

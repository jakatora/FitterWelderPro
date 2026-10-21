import 'package:flutter/foundation.dart' show mapEquals;
import '../database/db.dart';
import '../models/weld_param.dart';

class WeldParamDao {
  static Map<String, Object?> _row(WeldParam p) => {
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
      };

  Future<void> insert(WeldParam p) async {
    final db = await AppDatabase.get();
    await db.insert('weld_params', _row(p));
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

  /// A retry after a lost completion reuses the same approved record identity.
  Future<bool> insertAssistantIdempotent(WeldParam expected) async {
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      final rows = await txn
          .query('weld_params', where: 'id = ?', whereArgs: [expected.id]);
      if (rows.isNotEmpty) return mapEquals(rows.single, _row(expected));
      await txn.insert('weld_params', _row(expected));
      return true;
    });
  }

  /// Atomic compare-and-delete for assistant Undo. A manually edited row stays.
  Future<bool> deleteIfUnchanged(WeldParam expected) async {
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      final rows = await txn
          .query('weld_params', where: 'id = ?', whereArgs: [expected.id]);
      if (rows.isEmpty || !mapEquals(rows.single, _row(expected))) return false;
      return await txn.delete('weld_params',
              where: 'id = ?', whereArgs: [expected.id]) ==
          1;
    });
  }
}

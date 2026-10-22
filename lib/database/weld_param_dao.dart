import 'package:flutter/foundation.dart' show mapEquals;
import 'package:sqflite/sqflite.dart';
import '../models/weld_param.dart';
import 'db.dart';
import 'local_record_owner.dart';

class WeldParamDao {
  WeldParamDao({Future<LocalRecordOwner> Function()? owner})
      : _owner = owner ?? LocalRecordOwner.capture;
  final Future<LocalRecordOwner> Function() _owner;
  static Map<String, Object?> _row(WeldParam p, String owner) => {
        'id': p.id,
        'owner_scope': owner,
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

  Future<T> _write<T>(Future<T> Function(Transaction, LocalRecordOwner) action,
      {LocalRecordOwner? expectedOwner}) async {
    final owner = expectedOwner ?? await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final result = await db.transaction((txn) async {
      owner.requireCurrent();
      final result = await action(txn, owner);
      owner.requireCurrent();
      return result;
    });
    owner.requireCurrent();
    return result;
  }

  Future<void> insert(WeldParam p) => _write((txn, owner) async {
        await txn.insert('weld_params', _row(p, owner.key));
      });

  Future<List<WeldParam>> listAll() async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final rows = await db.query('weld_params',
        where: 'owner_scope = ?',
        whereArgs: [owner.key],
        orderBy: 'updated_at DESC');
    owner.requireCurrent();
    return rows.map(WeldParam.fromRow).toList();
  }

  Future<void> update(WeldParam p) => _write((txn, owner) async {
        final row = _row(p, owner.key)
          ..remove('id')
          ..remove('created_at')
          ..remove('owner_scope');
        final count = await txn.update('weld_params', row,
            where: 'id = ? AND owner_scope = ?', whereArgs: [p.id, owner.key]);
        if (count != 1) {
          throw StateError('Saved parameter is not available in this account');
        }
      });

  Future<void> deleteById(String id) => _write((txn, owner) async {
        await txn.delete('weld_params',
            where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      });

  Future<bool> insertAssistantIdempotent(WeldParam expected,
          {LocalRecordOwner? expectedOwner}) =>
      _write((txn, owner) async {
        // Check the global UUID collision without returning any other owner's data.
        final rows = await txn
            .query('weld_params', where: 'id = ?', whereArgs: [expected.id]);
        if (rows.isNotEmpty) {
          return mapEquals(rows.single, _row(expected, owner.key));
        }
        await txn.insert('weld_params', _row(expected, owner.key));
        return true;
      }, expectedOwner: expectedOwner);

  Future<bool> deleteIfUnchanged(WeldParam expected) =>
      _write((txn, owner) async {
        final rows = await txn.query('weld_params',
            where: 'id = ? AND owner_scope = ?',
            whereArgs: [expected.id, owner.key]);
        if (rows.isEmpty ||
            !mapEquals(rows.single, _row(expected, owner.key))) {
          return false;
        }
        return await txn.delete('weld_params',
                where: 'id = ? AND owner_scope = ?',
                whereArgs: [expected.id, owner.key]) ==
            1;
      });
}

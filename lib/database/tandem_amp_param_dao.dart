import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'db.dart';
import '../models/tandem_amp_param.dart';

class TandemAmpParamDao {
  Future<Database> get _db async => AppDatabase.get();

  Future<TandemAmpParam?> getExact({
    required String position,
    required double t1Mm,
    required double t2Mm,
    required String tempo,
    required bool approved,
  }) async {
    final a = min(t1Mm, t2Mm);
    final b = max(t1Mm, t2Mm);
    final res = await (await _db).query(
      'tandem_amp_params',
      where: 'position=? AND tempo=? AND approved=? AND ((t1_mm=? AND t2_mm=?) OR (t1_mm=? AND t2_mm=?))',
      whereArgs: [position, tempo, approved ? 1 : 0, a, b, b, a],
      limit: 1,
    );
    return res.isEmpty ? null : TandemAmpParam.fromRow(res.first);
  }

  Future<List<TandemAmpParam>> list({
    required String position,
    required bool approved,
    String? tempo,
  }) async {
    final where = <String>['position=?', 'approved=?'];
    final args = <Object?>[position, approved ? 1 : 0];
    if (tempo != null) {
      where.add('tempo=?');
      args.add(tempo);
    }
    final res = await (await _db).query(
      'tandem_amp_params',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 't1_mm ASC, t2_mm ASC, tempo ASC',
    );
    return res.map(TandemAmpParam.fromRow).toList();
  }

  Future<void> insert(TandemAmpParam p) async {
    await (await _db).insert('tandem_amp_params', p.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'tandem_amp_params',
      columns: ['approved'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final approved = ((rows.first['approved'] as int?) ?? 0) == 1;
    if (approved) return; // locked
    await db.delete('tandem_amp_params', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TandemAmpParam>> listPureThickness({
    required String position,
    required String tempo,
    required bool approved,
  }) async {
    final res = await (await _db).query(
      'tandem_amp_params',
      where: 'position=? AND tempo=? AND approved=? AND abs(t1_mm - t2_mm) < 0.000001',
      whereArgs: [position, tempo, approved ? 1 : 0],
      orderBy: 't1_mm ASC',
    );
    return res.map(TandemAmpParam.fromRow).toList();
  }
}

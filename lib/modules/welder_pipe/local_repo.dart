import '../../data/app_database.dart';
import 'welder_pipe_param.dart';
import 'param_signature.dart';

class WelderPipeLocalRepo {
  Future<int> upsertMyParam({
    int? id,
    required WelderPipeParam param,
  }) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now();

    final payload = param.toCommunityPayload();
    final sig = WelderPipeSignature.signature(payload);

    final row = param.toMap()
      ..remove('id')
      ..['signature'] = sig
      ..['updated_at'] = now.millisecondsSinceEpoch;

    if (id == null) {
      row['created_at'] = now.millisecondsSinceEpoch;
      return db.insert('welder_pipe_params', row);
    } else {
      await db.update('welder_pipe_params', row, where: 'id = ?', whereArgs: [id]);
      return id;
    }
  }

  Future<void> deleteMyParam(int id) async {
    final db = await AppDatabase.instance.db;
    await db.delete('welder_pipe_params', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WelderPipeParam>> listMyParams({String? material, double? odMm, double? wtMm}) async {
    final db = await AppDatabase.instance.db;

    final where = <String>[];
    final args = <Object?>[];

    if (material != null && material.trim().isNotEmpty) {
      where.add('material = ?');
      args.add(material.trim().toUpperCase());
    }
    if (odMm != null) {
      where.add('od_mm = ?');
      args.add(odMm);
    }
    if (wtMm != null) {
      where.add('wt_mm = ?');
      args.add(wtMm);
    }

    final rows = await db.query(
      'welder_pipe_params',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );

    return rows.map(WelderPipeParam.fromMap).toList();
  }
}

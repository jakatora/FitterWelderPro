import 'dart:convert';

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

  Future<int> enqueueCommunitySubmission({
    required String signature,
    required Map<String, dynamic> payload,
  }) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.insert('community_outbox', {
      'module': 'welder_pipe',
      'signature': signature,
      'payload_json': jsonEncode(payload),
      'status': 'pending',
      'last_error': null,
      'attempts': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<Map<String, Object?>>> listPendingOutbox({int limit = 20}) async {
    final db = await AppDatabase.instance.db;
    return db.query(
      'community_outbox',
      where: 'status = ? AND module = ?',
      whereArgs: ['pending', 'welder_pipe'],
      orderBy: 'created_at ASC',
      limit: limit,
    );
  }

  Future<void> markOutboxSent(int id) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update('community_outbox', {'status': 'sent', 'updated_at': now, 'last_error': null},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markOutboxError(int id, String error) async {
    final db = await AppDatabase.instance.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    final row = await db.query('community_outbox', where: 'id = ?', whereArgs: [id], limit: 1);
    final attempts = (row.isNotEmpty ? (row.first['attempts'] as int? ?? 0) : 0) + 1;

    await db.update(
      'community_outbox',
      {'status': 'pending', 'attempts': attempts, 'last_error': error, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

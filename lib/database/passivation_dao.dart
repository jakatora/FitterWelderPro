/// Rejestr trawienia / pasywacji — tabela `passivation_records` (v25).
/// W `cutlist.db`, więc kopia zapasowa go obejmuje. Usuwanie miękkie.
library;

import '../domain/passivation/passivation_record.dart';
import 'db.dart';

class PassivationDao {
  static const String table = 'passivation_records';

  final int Function() _clock;

  PassivationDao({int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Najnowsze pierwsze; usunięte tylko z [includeDeleted].
  Future<List<PassivationRecord>> listAll({bool includeDeleted = false}) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: includeDeleted ? null : 'deleted_at IS NULL',
        orderBy: 'date DESC, created_at DESC');
    return rows.map(PassivationRecord.fromRow).toList();
  }

  Future<void> save(PassivationRecord r) async {
    final db = await AppDatabase.get();
    final row = r.toRow()..['updated_at'] = _clock();
    final n = await db.update(table, row, where: 'id = ?', whereArgs: [r.id]);
    if (n == 0) await db.insert(table, row);
  }

  Future<void> softDelete(String id) async {
    final db = await AppDatabase.get();
    await db.update(table, {'deleted_at': _clock()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restore(String id) async {
    final db = await AppDatabase.get();
    await db.update(table, {'deleted_at': null},
        where: 'id = ?', whereArgs: [id]);
  }
}

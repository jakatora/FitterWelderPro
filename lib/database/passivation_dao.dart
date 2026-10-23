/// Rejestr trawienia / pasywacji — tabela `passivation_records` (v25).
/// W `cutlist.db`, więc kopia zapasowa go obejmuje. Usuwanie miękkie.
/// v34: wpisy należą do konta (`owner_scope`; dawne — gościa).
library;

import '../domain/passivation/passivation_record.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

class PassivationDao {
  static const String table = 'passivation_records';

  final int Function() _clock;
  final OwnedTable _owned;

  PassivationDao(
      {int Function()? clock,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _owned = OwnedTable(table,
            captureOwner: captureOwner,
            foreignMessage: 'Ten wpis pasywacji należy do innego konta. / '
                'This passivation entry belongs to another account.');

  /// Najnowsze pierwsze; usunięte tylko z [includeDeleted].
  Future<List<PassivationRecord>> listAll({bool includeDeleted = false}) async {
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query(table,
        where: _owned.where(includeDeleted ? null : 'deleted_at IS NULL'),
        whereArgs: [owner.key],
        orderBy: 'date DESC, created_at DESC');
    owner.requireCurrent();
    return rows.map(PassivationRecord.fromRow).toList();
  }

  Future<void> save(PassivationRecord r) async {
    final (owner, db) = await _owned.ownerAndDb();
    final row = _owned.owned(r.toRow()..['updated_at'] = _clock(), owner);
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, r.id, owner);
      final n = await txn.update(table, row,
          where: _owned.where('id = ?'), whereArgs: [owner.key, r.id]);
      if (n == 0) await txn.insert(table, row);
      owner.requireCurrent();
    });
  }

  Future<void> softDelete(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    await db.update(table, {'deleted_at': _clock()},
        where: _owned.where('id = ?'), whereArgs: [owner.key, id]);
    owner.requireCurrent();
  }

  Future<void> restore(String id) async {
    final (owner, db) = await _owned.ownerAndDb();
    await db.update(table, {'deleted_at': null},
        where: _owned.where('id = ?'), whereArgs: [owner.key, id]);
    owner.requireCurrent();
  }
}

/// Rejestr przyrządów i kalibracji — tabela `instruments` (v27). W
/// `cutlist.db`, więc kopia zapasowa go obejmuje. Usuwanie miękkie.
/// v34: przyrządy należą do konta (`owner_scope`; dawne — gościa).
library;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../domain/instruments/instrument.dart';
import 'local_record_owner.dart';
import 'owned_table.dart';

class InstrumentDao {
  static const String table = 'instruments';

  final int Function() _clock;
  final OwnedTable _owned;

  InstrumentDao(
      {int Function()? clock,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _owned = OwnedTable(table,
            captureOwner: captureOwner,
            foreignMessage: 'Ten przyrząd należy do innego konta. / '
                'This instrument belongs to another account.');

  Future<List<Instrument>> listAll({bool onlyDeleted = false}) async {
    final (owner, db) = await _owned.ownerAndDb();
    final rows = await db.query(table,
        where: _owned.where(
            onlyDeleted ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL'),
        whereArgs: [owner.key]);
    owner.requireCurrent();
    return rows.map(Instrument.fromRow).toList();
  }

  Future<Instrument> save(Instrument i) async {
    final (owner, db) = await _owned.ownerAndDb();
    final saved = i.copyWith(updatedAt: _clock());
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _owned.refuseForeign(txn, saved.id, owner);
      await txn.insert(table, _owned.owned(saved.toRow(), owner),
          conflictAlgorithm: ConflictAlgorithm.replace);
      owner.requireCurrent();
    });
    return saved;
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

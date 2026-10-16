/// Rejestr przyrządów i kalibracji — tabela `instruments` (v27). W
/// `cutlist.db`, więc kopia zapasowa go obejmuje. Usuwanie miękkie.
library;

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../domain/instruments/instrument.dart';
import 'db.dart';

class InstrumentDao {
  static const String table = 'instruments';

  final int Function() _clock;

  InstrumentDao({int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<List<Instrument>> listAll({bool onlyDeleted = false}) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: onlyDeleted ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL');
    return rows.map(Instrument.fromRow).toList();
  }

  Future<Instrument> save(Instrument i) async {
    final db = await AppDatabase.get();
    final saved = i.copyWith(updatedAt: _clock());
    await db.insert(table, saved.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return saved;
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

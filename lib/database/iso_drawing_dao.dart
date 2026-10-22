/// Persistence for ISO notebook sketches (`iso_drawings`, schema v18).
///
/// The notebook used to keep the whole drawing in RAM: a back gesture, an
/// incoming call that got the app killed, or a flat battery threw away an
/// afternoon of dimensioning. Every sketch is now a row here, written by the
/// screen's autosave. Living in `cutlist.db` means the backup archive carries
/// it with no extra code (`data_backup.dart` copies every table).
///
/// The drawing itself is one JSON document in the versioned format of
/// `lib/screens/iso_notebook_sketch_codec.dart`; this DAO does not look
/// inside it. `name` is a copy of the drawing's name so a list of sketches
/// needs no JSON parsing.
library;

import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'local_record_owner.dart';

/// One stored sketch.
class IsoDrawingRecord {
  final String id;
  final String name;
  final String json;

  /// `millisecondsSinceEpoch` of the first save.
  final int createdAt;

  /// `millisecondsSinceEpoch` of the latest save. The notebook reopens the
  /// most recently updated sketch.
  final int updatedAt;

  const IsoDrawingRecord({
    required this.id,
    required this.name,
    required this.json,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'json': json,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static IsoDrawingRecord fromRow(Map<String, Object?> r) => IsoDrawingRecord(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        json: (r['json'] as String?) ?? '',
        createdAt: (r['created_at'] as num?)?.toInt() ?? 0,
        updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// A sketch as the "saved sketches" list shows it — without the drawing.
class IsoDrawingSummary {
  final String id;
  final String name;
  final int updatedAt;

  /// Size of the stored JSON in characters — lets the list tell an empty
  /// sheet from a real drawing without parsing either.
  final int jsonLength;

  const IsoDrawingSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
    required this.jsonLength,
  });
}

class IsoDrawingDao {
  static const String table = 'iso_drawings';
  IsoDrawingDao({Future<LocalRecordOwner> Function()? owner})
      : _owner = owner ?? LocalRecordOwner.capture;
  final Future<LocalRecordOwner> Function() _owner;

  /// The most recently saved sketch, or null when there is none.
  Future<IsoDrawingRecord?> latest() async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final rows = await db.query(
      table,
      where: 'owner_scope = ?',
      whereArgs: [owner.key],
      orderBy: 'updated_at DESC, created_at DESC',
      limit: 1,
    );
    owner.requireCurrent();
    return rows.isEmpty ? null : IsoDrawingRecord.fromRow(rows.first);
  }

  Future<IsoDrawingRecord?> getById(String id) async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final rows = await db.query(table,
        where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
    owner.requireCurrent();
    return rows.isEmpty ? null : IsoDrawingRecord.fromRow(rows.first);
  }

  /// Newest first.
  Future<List<IsoDrawingSummary>> listAll() async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final rows = await db.rawQuery(
      'SELECT id, name, updated_at, LENGTH(json) AS json_length '
      'FROM $table WHERE owner_scope = ? ORDER BY updated_at DESC, created_at DESC',
      [owner.key],
    );
    owner.requireCurrent();
    return rows
        .map((r) => IsoDrawingSummary(
              id: r['id'] as String,
              name: (r['name'] as String?) ?? '',
              updatedAt: (r['updated_at'] as num?)?.toInt() ?? 0,
              jsonLength: (r['json_length'] as num?)?.toInt() ?? 0,
            ))
        .toList();
  }

  /// Inserts [r], or updates the stored sketch with the same id while
  /// keeping its original `created_at`.
  ///
  /// UPDATE-then-INSERT rather than `INSERT ... ON CONFLICT DO UPDATE`: the
  /// upsert clause needs SQLite 3.24, newer than the system library on the
  /// oldest Android versions this app still installs on.
  Future<void> upsert(IsoDrawingRecord r) async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    await db.transaction((txn) async {
      owner.requireCurrent();
      final updated = await txn.update(
        table,
        {'name': r.name, 'json': r.json, 'updated_at': r.updatedAt},
        where: 'id = ? AND owner_scope = ?',
        whereArgs: [r.id, owner.key],
      );
      if (updated == 0) {
        await txn.insert(table, {...r.toRow(), 'owner_scope': owner.key},
            conflictAlgorithm: ConflictAlgorithm.abort);
      }
      owner.requireCurrent();
    });
    owner.requireCurrent();
  }

  Future<void> deleteById(String id) async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await txn.delete(table,
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      owner.requireCurrent();
    });
    owner.requireCurrent();
  }
}

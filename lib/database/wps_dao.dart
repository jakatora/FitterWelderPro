/// Biblioteka WPS — tabela `wps_library` (schemat v21).
///
/// W `cutlist.db`, więc kopia zapasowa ją obejmuje; załącznik (PDF / zdjęcie
/// WPS, kolumna `attachment_path`) leży w `<documents>/heat_photos` i jest
/// przepinany przy odtwarzaniu (`kPhotoPathColumns` w data_backup.dart).
///
/// Dla dziennika spoin (inny moduł): [listAll] do listy wyboru WPS, [findByNumber]
/// do dopasowania starego wolnego tekstu `weld_journal.wps_ref` do rekordu.
library;

import 'package:sqflite/sqflite.dart';

import '../domain/wps/wps_record.dart';
import 'db.dart';

class WpsDao {
  static const String table = 'wps_library';

  /// Wszystkie WPS po numerze i rewizji.
  Future<List<WpsRecord>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        orderBy: 'wps_no COLLATE NOCASE ASC, revision COLLATE NOCASE ASC');
    return rows.map(WpsRecord.fromRow).toList();
  }

  Future<WpsRecord?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : WpsRecord.fromRow(rows.single);
  }

  /// WPS o numerze [wpsNo] (bez rozróżniania wielkości liter i spacji na
  /// brzegach); przy kilku rewizjach — najnowsza zapisana. [revision] zawęża.
  Future<WpsRecord?> findByNumber(String wpsNo, {String? revision}) async {
    final no = wpsNo.trim();
    if (no.isEmpty) return null;
    final db = await AppDatabase.get();
    final rev = revision?.trim();
    final rows = await db.query(
      table,
      where: rev == null || rev.isEmpty
          ? 'TRIM(wps_no) = ? COLLATE NOCASE'
          : 'TRIM(wps_no) = ? COLLATE NOCASE AND '
              'TRIM(COALESCE(revision, \'\')) = ? COLLATE NOCASE',
      whereArgs: <Object?>[no, if (rev != null && rev.isNotEmpty) rev],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WpsRecord.fromRow(rows.single);
  }

  Future<void> upsert(WpsRecord wps) async {
    final db = await AppDatabase.get();
    await db.insert(table, wps.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.get();
    await db.delete(table, where: 'id = ?', whereArgs: <Object?>[id]);
  }
}

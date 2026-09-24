/// Rejestr uprawnień spawacza — tabela `welder_certificates` (schemat v21).
///
/// Mieszka w `cutlist.db`, więc kopia zapasowa (`data_backup.dart`) zabiera
/// ją bez dodatkowego kodu, a zdjęcie certyfikatu (kolumna `photo_path`,
/// kopia w `<documents>/heat_photos`) jest przepinane przy odtwarzaniu tak jak
/// zdjęcia wytopów (`kPhotoPathColumns`).
library;

import 'package:sqflite/sqflite.dart';

import '../domain/qualification/welder_certificate.dart';
import 'db.dart';

class WelderCertificateDao {
  static const String table = 'welder_certificates';

  /// Wszystkie certyfikaty: najpierw z najwcześniejszą datą ważności (te bez
  /// daty na końcu), potem po dacie dodania.
  Future<List<WelderCertificate>> listAll({DatabaseExecutor? db}) async {
    final executor = db ?? await AppDatabase.get();
    final rows = await executor.query(
      table,
      orderBy: 'CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, '
          'expiry_date ASC, created_at ASC',
    );
    return rows.map(WelderCertificate.fromRow).toList();
  }

  Future<WelderCertificate?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    return rows.isEmpty ? null : WelderCertificate.fromRow(rows.single);
  }

  Future<int> count({DatabaseExecutor? db}) async {
    final executor = db ?? await AppDatabase.get();
    return Sqflite.firstIntValue(
            await executor.rawQuery('SELECT COUNT(*) FROM $table')) ??
        0;
  }

  /// Wstawia albo nadpisuje (po `id`).
  Future<void> upsert(WelderCertificate certificate,
      {DatabaseExecutor? db}) async {
    final executor = db ?? await AppDatabase.get();
    await executor.insert(table, certificate.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.get();
    await db.delete(table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// „Usuń moje dane" — cały rejestr. Zwraca skasowane wiersze (ścieżki zdjęć
  /// do usunięcia z dysku).
  Future<List<WelderCertificate>> deleteAll() async {
    final db = await AppDatabase.get();
    final all = await listAll(db: db);
    await db.delete(table);
    return all;
  }
}

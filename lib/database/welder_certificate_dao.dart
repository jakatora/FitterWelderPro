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

  /// Historia potwierdzeń (v25).
  static const String confirmationsTable = 'welder_cert_confirmations';

  /// Wszystkie certyfikaty: najpierw z najwcześniejszą datą ważności (te bez
  /// daty na końcu), potem po dacie dodania — z dołączoną historią
  /// potwierdzeń.
  Future<List<WelderCertificate>> listAll({DatabaseExecutor? db}) async {
    final executor = db ?? await AppDatabase.get();
    final rows = await executor.query(
      table,
      orderBy: 'CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, '
          'expiry_date ASC, created_at ASC',
    );
    final history = await _confirmationsByCert(executor);
    return rows.map((r) {
      final c = WelderCertificate.fromRow(r);
      final h = history[c.id];
      return h == null ? c : c.copyWith(confirmations: h);
    }).toList();
  }

  Future<WelderCertificate?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return WelderCertificate.fromRow(rows.single)
        .copyWith(confirmations: await confirmationsOf(id, db: db));
  }

  /// Potwierdzenia certyfikatu [certificateId], od najstarszego.
  Future<List<CertificateConfirmation>> confirmationsOf(String certificateId,
      {DatabaseExecutor? db}) async {
    final executor = db ?? await AppDatabase.get();
    final rows = await executor.query(confirmationsTable,
        where: 'certificate_id = ?',
        whereArgs: <Object?>[certificateId],
        orderBy: 'date ASC, created_at ASC');
    return [
      for (final r in rows)
        if (CertificateConfirmation.fromRow(r) case final c?) c,
    ];
  }

  Future<Map<String, List<CertificateConfirmation>>> _confirmationsByCert(
      DatabaseExecutor db) async {
    final rows = await db.query(confirmationsTable,
        orderBy: 'certificate_id, date ASC, created_at ASC');
    final out = <String, List<CertificateConfirmation>>{};
    for (final r in rows) {
      final c = CertificateConfirmation.fromRow(r);
      if (c == null) continue;
      (out[c.certificateId] ??= <CertificateConfirmation>[]).add(c);
    }
    return out;
  }

  /// Dopisuje potwierdzenie i ustawia `last_confirmed_date` na najnowszą
  /// datę historii — w jednej transakcji.
  Future<void> addConfirmation(CertificateConfirmation confirmation) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      await txn.insert(confirmationsTable, confirmation.toRow());
      await _syncLastConfirmed(txn, confirmation.certificateId);
    });
  }

  /// Usuwa błędnie wpisane potwierdzenie (literówka w dacie).
  Future<void> deleteConfirmation(CertificateConfirmation confirmation) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      await txn.delete(confirmationsTable,
          where: 'id = ?', whereArgs: <Object?>[confirmation.id]);
      await _syncLastConfirmed(txn, confirmation.certificateId);
    });
  }

  Future<void> _syncLastConfirmed(DatabaseExecutor txn, String certId) async {
    final rows = await txn.rawQuery(
        'SELECT MAX(date) AS d FROM $confirmationsTable '
        'WHERE certificate_id = ?',
        <Object?>[certId]);
    final last = rows.isEmpty ? null : rows.single['d'] as String?;
    await txn.update(table, <String, Object?>{'last_confirmed_date': last},
        where: 'id = ?', whereArgs: <Object?>[certId]);
  }

  /// Przepisuje stempel z [from] na [to] we wszystkich certyfikatach
  /// (zmiana stempla w tożsamości, za zgodą spawacza). Zwraca liczbę
  /// zmienionych certyfikatów.
  Future<int> reassignStamp(String from, String to) async {
    final db = await AppDatabase.get();
    return db.update(table, <String, Object?>{'welder_stamp': to},
        where: 'UPPER(TRIM(welder_stamp)) = ?',
        whereArgs: <Object?>[from.trim().toUpperCase()]);
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
    await db.transaction((txn) async {
      await txn.delete(table, where: 'id = ?', whereArgs: <Object?>[id]);
      await txn.delete(confirmationsTable,
          where: 'certificate_id = ?', whereArgs: <Object?>[id]);
    });
  }

  /// „Usuń moje dane" — cały rejestr. Zwraca skasowane wiersze (ścieżki zdjęć
  /// do usunięcia z dysku).
  Future<List<WelderCertificate>> deleteAll() async {
    final db = await AppDatabase.get();
    final all = await listAll(db: db);
    await db.delete(table);
    await db.delete(confirmationsTable);
    return all;
  }
}

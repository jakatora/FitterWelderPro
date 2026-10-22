/// Account-owned qualification register. Pre-account records remain guest data.
library;

import 'package:sqflite/sqflite.dart';
import '../domain/qualification/welder_certificate.dart';
import '../services/account_service.dart';
import 'db.dart';
import 'local_record_owner.dart';

class WelderCertificateDao {
  WelderCertificateDao({Future<LocalRecordOwner> Function()? captureOwner})
      : _captureOwner = captureOwner ?? LocalRecordOwner.capture;
  final Future<LocalRecordOwner> Function() _captureOwner;
  static const String table = 'welder_certificates';
  static const String confirmationsTable = 'welder_cert_confirmations';

  Future<T> _owned<T>(
      Future<T> Function(DatabaseExecutor, LocalRecordOwner) action,
      {DatabaseExecutor? db,
      bool write = false}) async {
    final owner = await _captureOwner();
    owner.requireCurrent();
    final executor = db ?? await AppDatabase.get();
    owner.requireCurrent();
    Future<T> run(DatabaseExecutor executor) async {
      owner.requireCurrent();
      final result = await action(executor, owner);
      owner.requireCurrent();
      return result;
    }

    // A caller-supplied executor already belongs to its outer transaction.
    return write && db == null
        ? (executor as Database).transaction(run)
        : run(executor);
  }

  Future<void> _requireCertificate(
      DatabaseExecutor db, LocalRecordOwner owner, String id) async {
    final rows = await db.query(table,
        columns: ['id'],
        where: 'id = ? AND owner_scope = ?',
        whereArgs: [id, owner.key],
        limit: 1);
    owner.requireCurrent();
    if (rows.isEmpty) {
      throw AccountException(
          'Nie znaleziono uprawnienia na tym koncie. / Qualification not found for this account.');
    }
  }

  Future<List<WelderCertificate>> _list(
      DatabaseExecutor db, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        where: 'owner_scope = ?',
        whereArgs: [owner.key],
        orderBy:
            'CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, expiry_date ASC, created_at ASC');
    final history = await db.rawQuery(
        'SELECT h.* FROM $confirmationsTable h JOIN $table c ON c.id = h.certificate_id '
        'WHERE c.owner_scope = ? ORDER BY h.certificate_id, h.date ASC, h.created_at ASC',
        [owner.key]);
    final byCert = <String, List<CertificateConfirmation>>{};
    for (final row in history) {
      final c = CertificateConfirmation.fromRow(row);
      if (c != null) (byCert[c.certificateId] ??= []).add(c);
    }
    return [
      for (final row in rows)
        WelderCertificate.fromRow(row)
            .copyWith(confirmations: byCert[row['id']] ?? const [])
    ];
  }

  Future<List<WelderCertificate>> listAll({DatabaseExecutor? db}) =>
      _owned(_list, db: db);

  Future<WelderCertificate?> getById(String id) => _owned((db, owner) async {
        final rows = await _list(db, owner);
        for (final c in rows) {
          if (c.id == id) return c;
        }
        return null;
      });

  Future<List<CertificateConfirmation>> confirmationsOf(String certificateId,
          {DatabaseExecutor? db}) =>
      _owned((executor, owner) async {
        final rows = await executor.rawQuery(
            'SELECT h.* FROM $confirmationsTable h JOIN $table c ON c.id = h.certificate_id '
            'WHERE c.owner_scope = ? AND c.id = ? ORDER BY h.date ASC, h.created_at ASC',
            [owner.key, certificateId]);
        return [
          for (final row in rows)
            if (CertificateConfirmation.fromRow(row) case final c?) c
        ];
      }, db: db);

  Future<void> addConfirmation(CertificateConfirmation confirmation) =>
      _owned((db, owner) async {
        await _requireCertificate(db, owner, confirmation.certificateId);
        await db.insert(confirmationsTable, confirmation.toRow());
        await _syncLastConfirmed(db, owner, confirmation.certificateId);
      }, write: true);

  Future<void> deleteConfirmation(CertificateConfirmation confirmation) =>
      _owned((db, owner) async {
        await _requireCertificate(db, owner, confirmation.certificateId);
        await db.delete(confirmationsTable,
            where: 'id = ? AND certificate_id = ?',
            whereArgs: [confirmation.id, confirmation.certificateId]);
        await _syncLastConfirmed(db, owner, confirmation.certificateId);
      }, write: true);

  Future<void> _syncLastConfirmed(
      DatabaseExecutor db, LocalRecordOwner owner, String id) async {
    final rows = await db.rawQuery(
        'SELECT MAX(date) AS d FROM $confirmationsTable WHERE certificate_id = ?',
        [id]);
    await db.update(table, {'last_confirmed_date': rows.single['d']},
        where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
  }

  Future<int> reassignStamp(String from, String to) => _owned(
      (db, owner) => db.update(table, {'welder_stamp': to},
          where: 'owner_scope = ? AND UPPER(TRIM(welder_stamp)) = ?',
          whereArgs: [owner.key, from.trim().toUpperCase()]),
      write: true);

  Future<int> count({DatabaseExecutor? db}) => _owned(
      (executor, owner) async =>
          Sqflite.firstIntValue(await executor.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE owner_scope = ?',
              [owner.key])) ??
          0,
      db: db);

  Future<void> upsert(WelderCertificate certificate, {DatabaseExecutor? db}) =>
      _owned((executor, owner) async {
        final existing = await executor.query(table,
            columns: ['owner_scope'],
            where: 'id = ?',
            whereArgs: [certificate.id],
            limit: 1);
        if (existing.isNotEmpty &&
            existing.single['owner_scope'] != owner.key) {
          throw AccountException(
              'Uprawnienie należy do innego konta. / Qualification belongs to another account.');
        }
        if (existing.isEmpty) {
          await executor.insert(
              table, {...certificate.toRow(), 'owner_scope': owner.key});
        } else {
          await executor.update(table, certificate.toRow(),
              where: 'id = ? AND owner_scope = ?',
              whereArgs: [certificate.id, owner.key]);
        }
      }, db: db, write: true);

  Future<void> delete(String id) => _owned((db, owner) async {
        await _requireCertificate(db, owner, id);
        await db.delete(confirmationsTable,
            where: 'certificate_id = ?', whereArgs: [id]);
        await db.delete(table,
            where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      }, write: true);

  /// Only this owner's rows and their photo paths, atomically.
  Future<List<WelderCertificate>> deleteAll() => _owned((db, owner) async {
        final all = await _list(db, owner);
        await db.rawDelete(
            'DELETE FROM $confirmationsTable WHERE certificate_id IN '
            '(SELECT id FROM $table WHERE owner_scope = ?)',
            [owner.key]);
        await db
            .delete(table, where: 'owner_scope = ?', whereArgs: [owner.key]);
        return all;
      }, write: true);
}

/// Storage of the daily test-coupon log (`weld_coupons`, schema v18/v20/v25)
/// and its change history (`weld_coupon_history`, v25).
///
/// Every write logs to the history in the SAME transaction (like the weld
/// journal). And because welds link a coupon by `coupon_id` and print its
/// reference (`coupon_ref`, which contains the result), a change of the
/// coupon — a result turned NOK, a delete — is carried into every linked
/// weld in that transaction too, with a history row on the weld: the weld
/// journal and its PDF can no longer show "· OK" for a coupon the log
/// says is NOK or gone.
///
/// v33: the log belongs to the data owner (account or offline guest) via
/// `weld_coupons.owner_scope`; legacy rows stay with the guest and the
/// history follows its coupon. A foreign coupon id is never read, replaced,
/// deleted or restored.
library;

import '../services/account_service.dart';
import 'local_record_owner.dart';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/weld_journal/coupon_entry.dart';
import '../domain/weld_journal/weld_history.dart';
import 'db.dart';

/// Coupon history actions.
abstract final class CouponHistoryAction {
  static const String create = 'CREATE';
  static const String update = 'UPDATE';
  static const String delete = 'DELETE';
  static const String restore = 'RESTORE';
}

/// One row of `weld_coupon_history`.
class CouponHistoryEntry {
  final String id;
  final String couponId;
  final int at;
  final String byStamp;
  final String action;
  final String field;
  final String oldValue;
  final String newValue;

  const CouponHistoryEntry({
    required this.id,
    required this.couponId,
    required this.at,
    required this.byStamp,
    required this.action,
    this.field = '',
    this.oldValue = '',
    this.newValue = '',
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'coupon_id': couponId,
        'at': at,
        'by_stamp': byStamp,
        'action': action,
        'field': field,
        'old_value': oldValue,
        'new_value': newValue,
      };

  static CouponHistoryEntry fromRow(Map<String, Object?> r) =>
      CouponHistoryEntry(
        id: r['id'] as String,
        couponId: (r['coupon_id'] as String?) ?? '',
        at: (r['at'] as num?)?.toInt() ?? 0,
        byStamp: (r['by_stamp'] as String?) ?? '',
        action: (r['action'] as String?) ?? '',
        field: (r['field'] as String?) ?? '',
        oldValue: (r['old_value'] as String?) ?? '',
        newValue: (r['new_value'] as String?) ?? '',
      );
}

class CouponDao {
  static const String table = 'weld_coupons';
  static const String historyTable = 'weld_coupon_history';

  static const Uuid _uuid = Uuid();

  /// Bumped after every committed write, so an open log refreshes when the
  /// assistant adds or undoes a coupon behind it.
  static final changes = ValueNotifier<int>(0);

  final int Function() _clock;
  final String Function() _newId;
  final Future<LocalRecordOwner> Function() _captureOwner;

  CouponDao(
      {int Function()? clock,
      String Function()? newId,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? (() => _uuid.v4()),
        _captureOwner = captureOwner ?? LocalRecordOwner.capture;

  Future<(LocalRecordOwner, Database)> _ownerAndDb() async {
    final owner = await _captureOwner();
    owner.requireCurrent();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    return (owner, db);
  }

  /// Newest first. Soft-deleted coupons only with [includeDeleted] (the log
  /// screen's "show deleted" view, the weld card resolving a link).
  Future<List<CouponEntry>> listAll({bool includeDeleted = false}) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(table,
        where: includeDeleted
            ? 'owner_scope = ?'
            : 'owner_scope = ? AND deleted_at IS NULL',
        whereArgs: [owner.key],
        orderBy: 'date DESC, rowid DESC');
    owner.requireCurrent();
    return rows.map(CouponEntry.fromRow).toList();
  }

  /// Any coupon of the current owner, deleted ones included (a weld still
  /// points at it).
  Future<CouponEntry?> getById(String id) async {
    final (owner, db) = await _ownerAndDb();
    final found = await _read(db, id, owner);
    owner.requireCurrent();
    return found;
  }

  Future<CouponEntry?> _read(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        where: 'id = ? AND owner_scope = ?',
        whereArgs: [id, owner.key],
        limit: 1);
    return rows.isEmpty ? null : CouponEntry.fromRow(rows.single);
  }

  /// A row with [id] that belongs to ANOTHER owner must never be replaced:
  /// the id is taken, not free.
  Future<void> _refuseForeign(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        columns: ['owner_scope'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.single['owner_scope'] != owner.key) {
      throw AccountException('Ten kupon należy do innego konta. / '
          'This coupon belongs to another account.');
    }
  }

  Map<String, Object?> _ownedRow(CouponEntry e, LocalRecordOwner owner) =>
      {...e.toRow(), 'owner_scope': owner.key};

  Future<void> insert(CouponEntry e, {String by = ''}) async {
    final (owner, db) = await _ownerAndDb();
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _refuseForeign(txn, e.id, owner);
      await txn.insert(table, _ownedRow(e, owner));
      await _log(txn, e.id, by, CouponHistoryAction.create,
          newValue: e.reference);
      owner.requireCurrent();
    });    changes.value++;
  }

  /// Saves [e] over the stored coupon, logs every changed field and
  /// refreshes the reference of linked welds. Returns the number of welds
  /// whose coupon reference changed.
  Future<int> update(CouponEntry e, {String by = ''}) async {
    final (owner, db) = await _ownerAndDb();
    final n = await db.transaction((txn) async {
      owner.requireCurrent();
      final before = await _read(txn, e.id, owner);
      if (before == null) {
        await _refuseForeign(txn, e.id, owner);
        await txn.insert(table, _ownedRow(e, owner));
        await _log(txn, e.id, by, CouponHistoryAction.create,
            newValue: e.reference);
        return 0;
      }
      // The delete marker is not the editor's to change.
      final after = e.copyWith(deletedAt: before.deletedAt);
      final changes = diffCoupons(before, after);
      if (changes.isEmpty) return 0;
      await txn.update(table, _ownedRow(after, owner),
          where: 'id = ? AND owner_scope = ?', whereArgs: [e.id, owner.key]);
      for (final (field, oldValue, newValue) in changes) {
        await _log(txn, e.id, by, CouponHistoryAction.update,
            field: field, oldValue: oldValue, newValue: newValue);
      }
      return _propagate(txn, after, by, owner);
    });
    changes.value++;
    return n;
  }

  /// Soft delete: the row, its history and the links of welds stay; every
  /// linked weld's reference gets [kCouponDeletedMarker].
  Future<int> softDelete(String id, {String by = ''}) async {
    final (owner, db) = await _ownerAndDb();
    final n = await db.transaction((txn) async {
      owner.requireCurrent();
      final before = await _read(txn, id, owner);
      if (before == null || before.isDeleted) return 0;
      final after = before.copyWith(deletedAt: _clock());
      await txn.update(table, {'deleted_at': after.deletedAt},
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, id, by, CouponHistoryAction.delete,
          oldValue: before.reference);
      return _propagate(txn, after, by, owner);
    });
    changes.value++;
    return n;
  }

  Future<int> restore(String id, {String by = ''}) async {
    final (owner, db) = await _ownerAndDb();
    final n = await db.transaction((txn) async {
      owner.requireCurrent();
      final before = await _read(txn, id, owner);
      if (before == null || !before.isDeleted) return 0;
      final after = before.copyWith(deletedAt: null);
      await txn.update(table, {'deleted_at': null},
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, id, by, CouponHistoryAction.restore,
          newValue: after.reference);
      return _propagate(txn, after, by, owner);
    });
    changes.value++;
    return n;
  }

  /// Welds (live and deleted) linked to coupon [id]: `(id, weld_no)`.
  Future<List<(String, String)>> linkedWelds(String id) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query('weld_journal',
        columns: ['id', 'weld_no'],
        where: 'coupon_id = ? AND owner_scope = ? AND deleted_at IS NULL',
        whereArgs: [id, owner.key],
        orderBy: 'weld_no');
    owner.requireCurrent();
    return [
      for (final r in rows)
        (r['id'] as String, (r['weld_no'] as String?) ?? ''),
    ];
  }

  /// History of coupon [id] (of the current owner), newest first.
  Future<List<CouponHistoryEntry>> history(String id) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.rawQuery(
        'SELECT h.* FROM $historyTable h JOIN $table c ON c.id = h.coupon_id '
        'WHERE h.coupon_id = ? AND c.owner_scope = ? '
        'ORDER BY h.at DESC, h.rowid DESC',
        [id, owner.key]);
    owner.requireCurrent();
    return rows.map(CouponHistoryEntry.fromRow).toList();
  }

  /// Writes the current reference of [c] into every weld linked to it
  /// whose text differs, with an `UPDATE coupon_ref` row in the weld
  /// history. Returns the number of welds changed.
  Future<int> _propagate(DatabaseExecutor txn, CouponEntry c, String by,
      LocalRecordOwner owner) async {
    owner.requireCurrent();
    final ref = c.reference;
    final rows = await txn.query('weld_journal',
        columns: ['id', 'coupon_ref'],
        where: 'coupon_id = ? AND owner_scope = ?',
        whereArgs: [c.id, owner.key]);
    var n = 0;
    for (final r in rows) {
      final old = (r['coupon_ref'] as String?) ?? '';
      if (old == ref) continue;
      final weldId = r['id'] as String;
      await txn.update('weld_journal', {'coupon_ref': ref},
          where: 'id = ? AND owner_scope = ?', whereArgs: [weldId, owner.key]);
      await txn.insert(
        'weld_journal_history',
        {
          ...WeldHistoryEntry(
            id: _newId(),
            weldId: weldId,
            at: _clock(),
            byStamp: by.trim(),
            action: WeldHistoryAction.update,
            field: 'coupon_ref',
            oldValue: old,
            newValue: ref,
          ).toRow(),
          'owner_scope': owner.key
        },
      );
      n++;
    }
    owner.requireCurrent();
    return n;
  }

  Future<void> _log(
    DatabaseExecutor txn,
    String couponId,
    String by,
    String action, {
    String field = '',
    String oldValue = '',
    String newValue = '',
  }) =>
      txn.insert(
        historyTable,
        CouponHistoryEntry(
          id: _newId(),
          couponId: couponId,
          at: _clock(),
          byStamp: by.trim(),
          action: action,
          field: field,
          oldValue: oldValue,
          newValue: newValue,
        ).toRow(),
      );
}

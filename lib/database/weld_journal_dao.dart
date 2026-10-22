/// Storage of the weld journal, its change history, repairs and per-project
/// settings (schema v20, `lib/database/db.dart`).
///
/// Every write that changes a weld also writes its history row(s) in the
/// SAME transaction, so the journal and its audit trail cannot disagree:
///   * [WeldJournalDao.insert] → `CREATE`;
///   * [WeldJournalDao.update] → one `UPDATE` row per changed field;
///   * [WeldJournalDao.setStatus] → `STATUS` (the explicit, confirmed
///     status action on the list);
///   * [WeldJournalDao.softDelete] / [WeldJournalDao.restore] → `DELETE` /
///     `RESTORE`. Nothing is ever removed from `weld_journal`;
///   * [WeldJournalDao.addRepair] → the repair record plus `REPAIR` rows for
///     every field the repair changed (status back to PENDING, NDT results
///     cleared) — the previous values are what the repair record keeps.
///
/// "Who" is the welder stamp of the phone's welder identity, passed in by
/// the caller as `by` (empty when the owner never set one up).
library;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_history.dart';
import '../domain/weld_journal/weld_journal_settings.dart';
import '../domain/weld_journal/weld_numbering.dart';
import '../domain/weld_journal/weld_repair.dart';
import 'db.dart';
import 'local_record_owner.dart';

/// Shared transaction-safe read for compliance/qualification consumers.
Future<List<Map<String, Object?>>> readOwnedWeldJournalRows(
    DatabaseExecutor db, LocalRecordOwner owner) async {
  owner.requireCurrent();
  final rows = await db
      .query('weld_journal', where: 'owner_scope = ?', whereArgs: [owner.key]);
  owner.requireCurrent();
  return rows;
}

mixin _JournalOwnerAccess {
  Future<LocalRecordOwner> Function() get _owner;
  Future<T> _ownedRead<T>(
      Future<T> Function(DatabaseExecutor db, LocalRecordOwner owner)
          read) async {
    final owner = await _owner();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final result = await read(db, owner);
    owner.requireCurrent();
    return result;
  }

  Future<T> _ownedTransaction<T>(
      Future<T> Function(Transaction txn, LocalRecordOwner owner) write,
      {LocalRecordOwner? expectedOwner}) async {
    final owner = expectedOwner ?? await _owner();
    owner.requireCurrent();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    final result = await db.transaction((txn) async {
      owner.requireCurrent();
      final result = await write(txn, owner);
      owner.requireCurrent();
      return result;
    });
    owner.requireCurrent();
    return result;
  }
}

class WeldJournalDao with _JournalOwnerAccess {
  static const String table = 'weld_journal';
  static const String historyTable = 'weld_journal_history';
  static const String repairsTable = 'weld_repairs';

  static const Uuid _uuid = Uuid();

  @override
  final Future<LocalRecordOwner> Function() _owner;
  final int Function() _clock;
  final String Function() _newId;

  /// [clock] (epoch ms) and [newId] are injectable for tests.
  WeldJournalDao(
      {int Function()? clock,
      String Function()? newId,
      Future<LocalRecordOwner> Function()? owner})
      : _owner = owner ?? LocalRecordOwner.capture,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? (() => _uuid.v4());

  /// Every entry, soft-deleted ones included (the screen filters), with
  /// their repairs attached, in natural weld-number order.
  Future<List<WeldEntry>> listAll() => _ownedRead((db, owner) async {
        final rows = await db
            .query(table, where: 'owner_scope = ?', whereArgs: [owner.key]);
        final repairs = await _repairsByWeld(db, owner);
        return sortWeldEntries(rows.map((r) {
          final e = WeldEntry.fromRow(r);
          return e.copyWith(repairs: repairs[e.id] ?? const []);
        }));
      });
  Future<WeldEntry?> getById(String id) =>
      _ownedRead((db, owner) => _read(db, id, owner));

  /// [warning] — the WPS / qualification warning the welder saved over
  /// (`WeldCompliance.historyText`); logged as `CHECK` in the same
  /// transaction.
  Future<void> insert(WeldEntry e, {String by = '', String? warning}) async {
    await _ownedTransaction((txn, owner) async {
      await txn.insert(table, {...e.toRow(), 'owner_scope': owner.key});
      await _log(txn, owner, e.id, by, WeldHistoryAction.create,
          newValue: e.weldNo);
      await _logWarning(txn, owner, e.id, by, warning);
    });
  }

  /// The assistant rechecks the approved project/number in the write transaction.
  Future<bool> insertAssistantIfAvailable(WeldEntry e,
      {required String by, LocalRecordOwner? expectedOwner}) async {
    return _ownedTransaction((txn, owner) async {
      final existing = await txn.query(table,
          columns: ['owner_scope'], where: 'id = ?', whereArgs: [e.id]);
      if (existing.isNotEmpty) {
        return existing.single['owner_scope'] == owner.key &&
            await _unchangedAssistantCreation(txn, e, owner);
      }
      final rows = await txn.query(table,
          columns: ['project_name', 'weld_no'],
          where: 'owner_scope = ?',
          whereArgs: [owner.key]);
      final project = e.projectName.trim().toLowerCase();
      for (final row in rows) {
        final name = (row['project_name'] as String).trim();
        if (name.toLowerCase() != project) continue;
        if (name != e.projectName ||
            (row['weld_no'] as String).trim().toUpperCase() ==
                e.weldNo.trim().toUpperCase()) {
          return false;
        }
      }
      await txn.insert(table, {...e.toRow(), 'owner_scope': owner.key});
      await _log(txn, owner, e.id, by, WeldHistoryAction.create,
          newValue: e.weldNo);
      return true;
    }, expectedOwner: expectedOwner);
  }

  /// Undo only the original unedited creation, preserving the journal evidence.
  Future<bool> softDeleteAssistantIfUnchanged(WeldEntry expected,
      {required String by, LocalRecordOwner? expectedOwner}) async {
    return _ownedTransaction((txn, owner) async {
      if (!await _unchangedAssistantCreation(txn, expected, owner)) {
        return false;
      }
      await txn.update(table, {'deleted_at': _clock()},
          where: 'id = ? AND owner_scope = ?',
          whereArgs: [expected.id, owner.key]);
      await _log(txn, owner, expected.id, by, WeldHistoryAction.delete,
          oldValue: expected.weldNo);
      return true;
    }, expectedOwner: expectedOwner);
  }

  Future<bool> _unchangedAssistantCreation(
      DatabaseExecutor txn, WeldEntry expected, LocalRecordOwner owner) async {
    final current = await _read(txn, expected.id, owner);
    if (current == null ||
        current.isDeleted ||
        current.repairs.isNotEmpty ||
        !mapEquals(current.toRow(), expected.toRow())) {
      return false;
    }
    final history = await txn.query(historyTable,
        where: 'weld_id = ? AND owner_scope = ?',
        whereArgs: [expected.id, owner.key]);
    return history.length == 1 &&
        history.single['action'] == WeldHistoryAction.create;
  }

  /// Saves [e] over the stored row and logs every changed field. Returns the
  /// changes (empty when nothing changed — then nothing is written at all).
  /// A status change made here (in the editor) is logged as `STATUS`.
  ///
  /// [warning] as in [insert]; logged only when something was saved.
  /// [unlockReason] — justification for editing an accepted weld, logged as
  /// `UNLOCK` before the field changes.
  Future<List<WeldChange>> update(WeldEntry e,
      {String by = '', String? warning, String? unlockReason}) async {
    return _ownedTransaction((txn, owner) async {
      final before = await _read(txn, e.id, owner);
      if (before == null) {
        throw StateError('weld ${e.id} does not exist');
      }
      // The delete marker is not the editor's to change.
      final after = e.copyWith(deletedAt: before.deletedAt);
      final changes = diffWeldEntries(before, after);
      if (changes.isEmpty) return const <WeldChange>[];
      await txn.update(table, after.toRow(),
          where: 'id = ? AND owner_scope = ?', whereArgs: [e.id, owner.key]);
      final reason = unlockReason?.trim() ?? '';
      if (reason.isNotEmpty) {
        await _log(txn, owner, e.id, by, WeldHistoryAction.unlock,
            newValue: reason);
      }
      for (final c in changes) {
        await _log(
          txn,
          owner,
          e.id,
          by,
          c.field == 'status'
              ? WeldHistoryAction.status
              : WeldHistoryAction.update,
          field: c.field,
          oldValue: c.oldValue,
          newValue: c.newValue,
        );
      }
      await _logWarning(txn, owner, e.id, by, warning);
      return changes;
    });
  }

  /// The explicit status action. Returns false when [status] is already the
  /// stored one (nothing written). [warning] — the consistency warning the
  /// user confirmed (logged as `CHECK`).
  Future<bool> setStatus(String id, String status,
      {String by = '', String? warning}) async {
    return _ownedTransaction((txn, owner) async {
      final before = await _read(txn, id, owner);
      if (before == null) throw StateError('weld $id does not exist');
      if (before.status == status) return false;
      await txn.update(table, {'status': status},
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, owner, id, by, WeldHistoryAction.status,
          field: 'status', oldValue: before.status, newValue: status);
      await _logWarning(txn, owner, id, by, warning);
      return true;
    });
  }

  /// Marks the weld deleted. The row, its history and repairs stay.
  Future<void> softDelete(String id, {String by = ''}) async {
    await _ownedTransaction((txn, owner) async {
      final before = await _read(txn, id, owner);
      if (before == null || before.isDeleted) return;
      await txn.update(table, {'deleted_at': _clock()},
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, owner, id, by, WeldHistoryAction.delete,
          oldValue: before.weldNo);
    });
  }

  Future<void> restore(String id, {String by = ''}) async {
    await _ownedTransaction((txn, owner) async {
      final before = await _read(txn, id, owner);
      if (before == null || !before.isDeleted) return;
      await txn.update(table, {'deleted_at': null},
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, owner, id, by, WeldHistoryAction.restore,
          newValue: before.weldNo);
    });
  }

  /// Records the next repair (R1, R2, …) of weld [id]. See [planWeldRepair].
  Future<WeldRepair> addRepair(
    String id, {
    required String date,
    required String reason,
    String by = '',
  }) async {
    return _ownedTransaction((txn, owner) async {
      final before = await _read(txn, id, owner);
      if (before == null) throw StateError('weld $id does not exist');
      final plan = planWeldRepair(
        before,
        id: _newId(),
        date: date,
        reason: reason,
        byStamp: by,
        createdAt: _clock(),
      );
      await txn.insert(
          repairsTable, {...plan.repair.toRow(), 'owner_scope': owner.key});
      await txn.update(table, plan.weld.toRow(),
          where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
      await _log(txn, owner, id, by, WeldHistoryAction.repair,
          field: 'repair', newValue: plan.repair.summary());
      for (final c in diffWeldEntries(before, plan.weld)) {
        await _log(txn, owner, id, by, WeldHistoryAction.repair,
            field: c.field, oldValue: c.oldValue, newValue: c.newValue);
      }
      return plan.repair;
    });
  }

  /// Records a completed pre-weld checklist on weld [id] (`CHECKLIST`).
  Future<void> addChecklist(String id, String summary, {String by = ''}) async {
    await _ownedTransaction((txn, owner) async {
      if (await _read(txn, id, owner) == null) {
        throw StateError('weld $id does not exist');
      }
      await _log(txn, owner, id, by, WeldHistoryAction.checklist,
          newValue: summary);
    });
  }

  /// History of many welds at once (PDF appendix): weld id → entries,
  /// oldest first.
  Future<Map<String, List<WeldHistoryEntry>>> historyFor(Iterable<String> ids) {
    final wanted = ids.toSet();
    return _ownedRead((db, owner) async {
      if (wanted.isEmpty) return <String, List<WeldHistoryEntry>>{};
      final rows = await db.query(historyTable,
          where:
              'owner_scope = ? AND weld_id IN (SELECT id FROM weld_journal WHERE owner_scope = ?)',
          whereArgs: [owner.key, owner.key],
          orderBy: 'at ASC, rowid ASC');
      final out = <String, List<WeldHistoryEntry>>{};
      for (final row in rows) {
        final h = WeldHistoryEntry.fromRow(row);
        if (wanted.contains(h.weldId)) (out[h.weldId] ??= []).add(h);
      }
      return out;
    });
  }

  Future<List<WeldHistoryEntry>> history(String id) =>
      _ownedRead((db, owner) async {
        final rows = await db.query(historyTable,
            where:
                'weld_id = ? AND owner_scope = ? AND weld_id IN (SELECT id FROM weld_journal WHERE owner_scope = ?)',
            whereArgs: [id, owner.key, owner.key],
            orderBy: 'at DESC, rowid DESC');
        return rows.map(WeldHistoryEntry.fromRow).toList();
      });
  Future<WeldEntry?> _read(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        where: 'id = ? AND owner_scope = ?',
        whereArgs: [id, owner.key],
        limit: 1);
    if (rows.isEmpty) return null;
    final repairs = await db.query(repairsTable,
        where: 'weld_id = ? AND owner_scope = ?',
        whereArgs: [id, owner.key],
        orderBy: 'seq ASC');
    return WeldEntry.fromRow(rows.single)
        .copyWith(repairs: repairs.map(WeldRepair.fromRow).toList());
  }

  Future<Map<String, List<WeldRepair>>> _repairsByWeld(
      DatabaseExecutor db, LocalRecordOwner owner) async {
    final rows = await db.query(repairsTable,
        where:
            'owner_scope = ? AND weld_id IN (SELECT id FROM weld_journal WHERE owner_scope = ?)',
        whereArgs: [owner.key, owner.key],
        orderBy: 'weld_id, seq ASC');
    final out = <String, List<WeldRepair>>{};
    for (final row in rows) {
      final repair = WeldRepair.fromRow(row);
      (out[repair.weldId] ??= []).add(repair);
    }
    return out;
  }

  Future<void> _logWarning(DatabaseExecutor txn, LocalRecordOwner owner,
      String weldId, String by, String? warning) async {
    final text = warning?.trim() ?? '';
    if (text.isEmpty) return;
    await _log(txn, owner, weldId, by, WeldHistoryAction.check, newValue: text);
  }

  Future<void> _log(
    DatabaseExecutor txn,
    LocalRecordOwner owner,
    String weldId,
    String by,
    String action, {
    String field = '',
    String oldValue = '',
    String newValue = '',
  }) =>
      txn.insert(
        historyTable,
        {
          ...WeldHistoryEntry(
            id: _newId(),
            weldId: weldId,
            at: _clock(),
            byStamp: by.trim(),
            action: action,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
          ).toRow(),
          'owner_scope': owner.key
        },
      );
}

/// Per-project journal settings (PDF header, RT/UT target).
class WeldJournalSettingsDao with _JournalOwnerAccess {
  static const String table = 'weld_journal_projects';
  WeldJournalSettingsDao({Future<LocalRecordOwner> Function()? owner})
      : _owner = owner ?? LocalRecordOwner.capture;
  @override
  final Future<LocalRecordOwner> Function() _owner;
  Future<Map<String, WeldJournalProjectSettings>> listAll() =>
      _ownedRead((db, owner) async {
        final rows = await db
            .query(table, where: 'owner_scope = ?', whereArgs: [owner.key]);
        return {
          for (final row in rows)
            (row['project_key'] as String):
                WeldJournalProjectSettings.fromRow(row)
        };
      });
  Future<WeldJournalProjectSettings?> forProject(String name) =>
      _ownedRead((db, owner) async {
        final rows = await db.query(table,
            where: 'project_key = ? AND owner_scope = ?',
            whereArgs: [WeldJournalProjectSettings.keyFor(name), owner.key],
            limit: 1);
        return rows.isEmpty
            ? null
            : WeldJournalProjectSettings.fromRow(rows.single);
      });
  Future<void> save(WeldJournalProjectSettings settings) =>
      _ownedTransaction((txn, owner) async {
        await txn.insert(table, {...settings.toRow(), 'owner_scope': owner.key},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
}

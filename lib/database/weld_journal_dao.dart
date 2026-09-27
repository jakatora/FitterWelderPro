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

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/weld_journal/weld_entry.dart';
import '../domain/weld_journal/weld_history.dart';
import '../domain/weld_journal/weld_journal_settings.dart';
import '../domain/weld_journal/weld_numbering.dart';
import '../domain/weld_journal/weld_repair.dart';
import 'db.dart';

class WeldJournalDao {
  static const String table = 'weld_journal';
  static const String historyTable = 'weld_journal_history';
  static const String repairsTable = 'weld_repairs';

  static const Uuid _uuid = Uuid();

  final int Function() _clock;
  final String Function() _newId;

  /// [clock] (epoch ms) and [newId] are injectable for tests.
  WeldJournalDao({int Function()? clock, String Function()? newId})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? (() => _uuid.v4());

  /// Every entry, soft-deleted ones included (the screen filters), with
  /// their repairs attached, in natural weld-number order.
  Future<List<WeldEntry>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query(table);
    final repairs = await _repairsByWeld(db);
    return sortWeldEntries(rows.map((r) {
      final e = WeldEntry.fromRow(r);
      final rs = repairs[e.id];
      return rs == null ? e : e.copyWith(repairs: rs);
    }));
  }

  Future<WeldEntry?> getById(String id) async {
    final db = await AppDatabase.get();
    return _read(db, id);
  }

  /// [warning] — the WPS / qualification warning the welder saved over
  /// (`WeldCompliance.historyText`); logged as `CHECK` in the same
  /// transaction.
  Future<void> insert(WeldEntry e, {String by = '', String? warning}) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      await txn.insert(table, e.toRow());
      await _log(txn, e.id, by, WeldHistoryAction.create,
          newValue: e.weldNo);
      await _logWarning(txn, e.id, by, warning);
    });
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
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      final before = await _read(txn, e.id);
      if (before == null) {
        throw StateError('weld ${e.id} does not exist');
      }
      // The delete marker is not the editor's to change.
      final after = e.copyWith(deletedAt: before.deletedAt);
      final changes = diffWeldEntries(before, after);
      if (changes.isEmpty) return const <WeldChange>[];
      await txn.update(table, after.toRow(),
          where: 'id = ?', whereArgs: [e.id]);
      final reason = unlockReason?.trim() ?? '';
      if (reason.isNotEmpty) {
        await _log(txn, e.id, by, WeldHistoryAction.unlock, newValue: reason);
      }
      for (final c in changes) {
        await _log(
          txn,
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
      await _logWarning(txn, e.id, by, warning);
      return changes;
    });
  }

  /// The explicit status action. Returns false when [status] is already the
  /// stored one (nothing written). [warning] — the consistency warning the
  /// user confirmed (logged as `CHECK`).
  Future<bool> setStatus(String id, String status,
      {String by = '', String? warning}) async {
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      final before = await _read(txn, id);
      if (before == null) throw StateError('weld $id does not exist');
      if (before.status == status) return false;
      await txn.update(table, {'status': status},
          where: 'id = ?', whereArgs: [id]);
      await _log(txn, id, by, WeldHistoryAction.status,
          field: 'status', oldValue: before.status, newValue: status);
      await _logWarning(txn, id, by, warning);
      return true;
    });
  }

  /// Marks the weld deleted. The row, its history and repairs stay.
  Future<void> softDelete(String id, {String by = ''}) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      final before = await _read(txn, id);
      if (before == null || before.isDeleted) return;
      await txn.update(table, {'deleted_at': _clock()},
          where: 'id = ?', whereArgs: [id]);
      await _log(txn, id, by, WeldHistoryAction.delete,
          oldValue: before.weldNo);
    });
  }

  Future<void> restore(String id, {String by = ''}) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      final before = await _read(txn, id);
      if (before == null || !before.isDeleted) return;
      await txn.update(table, {'deleted_at': null},
          where: 'id = ?', whereArgs: [id]);
      await _log(txn, id, by, WeldHistoryAction.restore,
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
    final db = await AppDatabase.get();
    return db.transaction((txn) async {
      final before = await _read(txn, id);
      if (before == null) throw StateError('weld $id does not exist');
      final plan = planWeldRepair(
        before,
        id: _newId(),
        date: date,
        reason: reason,
        byStamp: by,
        createdAt: _clock(),
      );
      await txn.insert(repairsTable, plan.repair.toRow());
      await txn.update(table, plan.weld.toRow(),
          where: 'id = ?', whereArgs: [id]);
      await _log(txn, id, by, WeldHistoryAction.repair,
          field: 'repair',
          newValue: plan.repair.summary());
      for (final c in diffWeldEntries(before, plan.weld)) {
        await _log(txn, id, by, WeldHistoryAction.repair,
            field: c.field, oldValue: c.oldValue, newValue: c.newValue);
      }
      return plan.repair;
    });
  }

  /// Records a completed pre-weld checklist on weld [id] (`CHECKLIST`).
  Future<void> addChecklist(String id, String summary, {String by = ''}) async {
    final db = await AppDatabase.get();
    await db.transaction((txn) async {
      await _log(txn, id, by, WeldHistoryAction.checklist, newValue: summary);
    });
  }

  /// History of many welds at once (PDF appendix): weld id → entries,
  /// oldest first.
  Future<Map<String, List<WeldHistoryEntry>>> historyFor(
      Iterable<String> ids) async {
    final wanted = ids.toSet();
    if (wanted.isEmpty) return const {};
    final db = await AppDatabase.get();
    final rows = await db.query(historyTable, orderBy: 'at ASC, rowid ASC');
    final out = <String, List<WeldHistoryEntry>>{};
    for (final r in rows) {
      final h = WeldHistoryEntry.fromRow(r);
      if (!wanted.contains(h.weldId)) continue;
      (out[h.weldId] ??= <WeldHistoryEntry>[]).add(h);
    }
    return out;
  }

  /// History of weld [id], newest first.
  Future<List<WeldHistoryEntry>> history(String id) async {
    final db = await AppDatabase.get();
    final rows = await db.query(historyTable,
        where: 'weld_id = ?',
        whereArgs: [id],
        orderBy: 'at DESC, rowid DESC');
    return rows.map(WeldHistoryEntry.fromRow).toList();
  }

  Future<WeldEntry?> _read(DatabaseExecutor db, String id) async {
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final repairs = await db.query(repairsTable,
        where: 'weld_id = ?', whereArgs: [id], orderBy: 'seq ASC');
    return WeldEntry.fromRow(rows.single)
        .copyWith(repairs: repairs.map(WeldRepair.fromRow).toList());
  }

  Future<Map<String, List<WeldRepair>>> _repairsByWeld(
      DatabaseExecutor db) async {
    final rows = await db.query(repairsTable, orderBy: 'weld_id, seq ASC');
    final out = <String, List<WeldRepair>>{};
    for (final r in rows) {
      final repair = WeldRepair.fromRow(r);
      (out[repair.weldId] ??= []).add(repair);
    }
    return out;
  }

  Future<void> _logWarning(
      DatabaseExecutor txn, String weldId, String by, String? warning) async {
    final text = warning?.trim() ?? '';
    if (text.isEmpty) return;
    await _log(txn, weldId, by, WeldHistoryAction.check, newValue: text);
  }

  Future<void> _log(
    DatabaseExecutor txn,
    String weldId,
    String by,
    String action, {
    String field = '',
    String oldValue = '',
    String newValue = '',
  }) =>
      txn.insert(
        historyTable,
        WeldHistoryEntry(
          id: _newId(),
          weldId: weldId,
          at: _clock(),
          byStamp: by.trim(),
          action: action,
          field: field,
          oldValue: oldValue,
          newValue: newValue,
        ).toRow(),
      );
}

/// Per-project journal settings (PDF header, RT/UT target).
class WeldJournalSettingsDao {
  static const String table = 'weld_journal_projects';

  /// Every project's settings, keyed by [WeldJournalProjectSettings.keyFor].
  Future<Map<String, WeldJournalProjectSettings>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query(table);
    return {
      for (final r in rows)
        (r['project_key'] as String): WeldJournalProjectSettings.fromRow(r),
    };
  }

  Future<WeldJournalProjectSettings?> forProject(String projectName) async {
    final db = await AppDatabase.get();
    final rows = await db.query(table,
        where: 'project_key = ?',
        whereArgs: [WeldJournalProjectSettings.keyFor(projectName)],
        limit: 1);
    return rows.isEmpty ? null : WeldJournalProjectSettings.fromRow(rows.single);
  }

  Future<void> save(WeldJournalProjectSettings s) async {
    final db = await AppDatabase.get();
    await db.insert(table, s.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

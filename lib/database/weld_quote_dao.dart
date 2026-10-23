/// Wyceny spawalnicze — tabela `weld_quotes` (v26). W `cutlist.db`, więc
/// kopia zapasowa je obejmuje. Usuwanie miękkie (kosz z przywracaniem).
/// v34: wyceny należą do konta (`owner_scope`; dawne — gościa). Każdy odczyt
/// i zapis dotyczy właściciela uchwyconego na początku operacji; cudze id
/// jest zajęte, nie wolne. Numeracja liczy się w wycenach właściciela.
library;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart'
    show ConflictAlgorithm, Database, DatabaseExecutor;
import 'package:uuid/uuid.dart';

import '../domain/quotes/quote_calculator.dart';
import '../domain/quotes/weld_quote.dart';
import '../services/account_service.dart' show AccountException;
import 'db.dart';
import 'local_record_owner.dart';

class WeldQuoteDao {
  static final changes = ValueNotifier<int>(0);
  static const String table = 'weld_quotes';

  final int Function() _clock;
  final Future<LocalRecordOwner> Function() _captureOwner;

  WeldQuoteDao(
      {int Function()? clock,
      Future<LocalRecordOwner> Function()? captureOwner})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        _captureOwner = captureOwner ?? LocalRecordOwner.capture;

  Future<(LocalRecordOwner, Database)> _ownerAndDb() async {
    final owner = await _captureOwner();
    owner.requireCurrent();
    final db = await AppDatabase.get();
    owner.requireCurrent();
    return (owner, db);
  }

  /// Wycena o tym id należąca do INNEGO właściciela nie może zostać
  /// nadpisana — id jest zajęte.
  Future<void> _refuseForeign(
      DatabaseExecutor db, String id, LocalRecordOwner owner) async {
    final rows = await db.query(table,
        columns: ['owner_scope'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty && rows.single['owner_scope'] != owner.key) {
      throw AccountException('Ta wycena należy do innego konta. / '
          'This quote belongs to another account.');
    }
  }

  Map<String, Object?> _ownedRow(
          WeldQuote q, QuoteResult totals, LocalRecordOwner owner) =>
      {
        ...q.toRow(
            netGrosze: totals.netGrosze, grossGrosze: totals.grossGrosze),
        'owner_scope': owner.key,
      };

  /// Ostatnio zmieniane pierwsze; usunięte tylko z [includeDeleted] (albo
  /// same usunięte z [onlyDeleted]).
  Future<List<WeldQuote>> listAll({
    bool includeDeleted = false,
    bool onlyDeleted = false,
  }) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(
      table,
      where: onlyDeleted
          ? 'owner_scope = ? AND deleted_at IS NOT NULL'
          : (includeDeleted
              ? 'owner_scope = ?'
              : 'owner_scope = ? AND deleted_at IS NULL'),
      whereArgs: [owner.key],
      orderBy: 'updated_at DESC',
    );
    owner.requireCurrent();
    return rows.map(WeldQuote.fromRow).toList();
  }

  Future<WeldQuote?> byId(String id) async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(table,
        where: 'id = ? AND owner_scope = ?',
        whereArgs: [id, owner.key],
        limit: 1);
    owner.requireCurrent();
    return rows.isEmpty ? null : WeldQuote.fromRow(rows.first);
  }

  /// Zapisuje wycenę z przeliczonymi sumami (lista pokazuje je bez
  /// przeliczania). Zwraca zapisaną wersję (z nowym `updatedAt`).
  Future<WeldQuote> save(WeldQuote q) async {
    final (owner, db) = await _ownerAndDb();
    final saved = q.copyWith(updatedAt: _clock());
    final r = computeQuote(saved);
    await db.transaction((txn) async {
      owner.requireCurrent();
      await _refuseForeign(txn, saved.id, owner);
      // Jedna instrukcja zamiast UPDATE + INSERT — dwa zapisy tej samej
      // nowej wyceny nie wpadną na siebie (UNIQUE na id).
      await txn.insert(table, _ownedRow(saved, r, owner),
          conflictAlgorithm: ConflictAlgorithm.replace);
      owner.requireCurrent();
    });
    return saved;
  }

  /// A new assistant draft never replaces an existing offer. Allocate its
  /// number and insert in one transaction, including numbers in the bin.
  Future<WeldQuote> insertNewDraft(WeldQuote draft) async {
    if (draft.id.isEmpty ||
        draft.status != QuoteStatus.draft ||
        draft.isDeleted ||
        draft.number.isNotEmpty ||
        draft.joints.isNotEmpty ||
        draft.extras.isNotEmpty) {
      throw ArgumentError('Expected a new empty draft');
    }
    final (owner, db) = await _ownerAndDb();
    final saved = await db.transaction((txn) async {
      owner.requireCurrent();
      await _refuseForeign(txn, draft.id, owner);
      final rows = await txn.query(table,
          columns: ['number'],
          where: 'owner_scope = ?',
          whereArgs: [owner.key]);
      final now = _clock();
      final quote = draft.copyWith(
          number: nextQuoteNumber(
              [for (final row in rows) (row['number'] as String?) ?? ''],
              DateTime.fromMillisecondsSinceEpoch(now).year),
          createdAt: now,
          updatedAt: now);
      final totals = computeQuote(quote);
      await txn.insert(table, _ownedRow(quote, totals, owner),
          conflictAlgorithm: ConflictAlgorithm.abort);
      owner.requireCurrent();
      return quote;
    });
    changes.value++;
    return saved;
  }

  /// Undo preserves offers edited after confirmation and retains their number.
  Future<bool> softDeleteIfUnchanged(WeldQuote expected) async {
    final totals = computeQuote(expected);
    final (owner, db) = await _ownerAndDb();
    final snapshot = _ownedRow(expected, totals, owner);
    final removed = await db.transaction((txn) async {
      owner.requireCurrent();
      final rows = await txn.query(table,
          where: 'id = ? AND owner_scope = ?',
          whereArgs: [expected.id, owner.key]);
      if (rows.length != 1 ||
          rows.single.length != snapshot.length ||
          !snapshot.entries.every((e) => rows.single[e.key] == e.value)) {
        return false;
      }
      final now = _clock();
      return await txn.update(table, {'deleted_at': now, 'updated_at': now},
              where: 'id = ? AND owner_scope = ? AND deleted_at IS NULL',
              whereArgs: [expected.id, owner.key]) ==
          1;
    });
    if (removed) changes.value++;
    return removed;
  }

  Future<void> softDelete(String id) async {
    final (owner, db) = await _ownerAndDb();
    await db.update(table, {'deleted_at': _clock()},
        where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
    owner.requireCurrent();
  }

  Future<void> restore(String id) async {
    final (owner, db) = await _ownerAndDb();
    await db.update(table, {'deleted_at': null},
        where: 'id = ? AND owner_scope = ?', whereArgs: [id, owner.key]);
    owner.requireCurrent();
  }

  /// Numery wszystkich wycen właściciela (także usuniętych — numer nie
  /// wraca na inną ofertę).
  Future<List<String>> allNumbers() async {
    final (owner, db) = await _ownerAndDb();
    final rows = await db.query(table,
        columns: ['number'], where: 'owner_scope = ?', whereArgs: [owner.key]);
    owner.requireCurrent();
    return [for (final r in rows) (r['number'] as String?) ?? ''];
  }

  /// Następny wolny numer w roku [now].
  Future<String> nextNumber(DateTime now) async =>
      nextQuoteNumber(await allNumbers(), now.year);

  /// Kopia wyceny jako nowy szkic: nowe id i numer, te same złącza i
  /// stawki (świadomie — „wycena jak poprzednio, inna ilość").
  Future<WeldQuote> duplicate(WeldQuote q,
      {required String titleSuffix}) async {
    final now = _clock();
    final copy = q.copyWith(
      id: const Uuid().v4(),
      number: await nextNumber(DateTime.fromMillisecondsSinceEpoch(now)),
      title: q.title.isEmpty ? titleSuffix.trim() : '${q.title} $titleSuffix',
      status: QuoteStatus.draft,
      createdAt: now,
      updatedAt: now,
      deletedAt: () => null,
    );
    return save(copy);
  }
}

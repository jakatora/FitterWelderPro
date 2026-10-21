/// Wyceny spawalnicze — tabela `weld_quotes` (v26). W `cutlist.db`, więc
/// kopia zapasowa je obejmuje. Usuwanie miękkie (kosz z przywracaniem).
library;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../domain/quotes/quote_calculator.dart';
import '../domain/quotes/weld_quote.dart';
import 'db.dart';

class WeldQuoteDao {
  static final changes = ValueNotifier<int>(0);
  static const String table = 'weld_quotes';

  final int Function() _clock;

  WeldQuoteDao({int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Ostatnio zmieniane pierwsze; usunięte tylko z [includeDeleted] (albo
  /// same usunięte z [onlyDeleted]).
  Future<List<WeldQuote>> listAll({
    bool includeDeleted = false,
    bool onlyDeleted = false,
  }) async {
    final db = await AppDatabase.get();
    final rows = await db.query(
      table,
      where: onlyDeleted
          ? 'deleted_at IS NOT NULL'
          : (includeDeleted ? null : 'deleted_at IS NULL'),
      orderBy: 'updated_at DESC',
    );
    return rows.map(WeldQuote.fromRow).toList();
  }

  Future<WeldQuote?> byId(String id) async {
    final db = await AppDatabase.get();
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : WeldQuote.fromRow(rows.first);
  }

  /// Zapisuje wycenę z przeliczonymi sumami (lista pokazuje je bez
  /// przeliczania). Zwraca zapisaną wersję (z nowym `updatedAt`).
  Future<WeldQuote> save(WeldQuote q) async {
    final db = await AppDatabase.get();
    final saved = q.copyWith(updatedAt: _clock());
    final r = computeQuote(saved);
    final row = saved.toRow(netGrosze: r.netGrosze, grossGrosze: r.grossGrosze);
    // Jedna instrukcja zamiast UPDATE + INSERT — dwa zapisy tej samej nowej
    // wyceny nie wpadną na siebie (UNIQUE na id).
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
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
    final db = await AppDatabase.get();
    final saved = await db.transaction((txn) async {
      final rows = await txn.query(table, columns: ['number']);
      final now = _clock();
      final quote = draft.copyWith(
          number: nextQuoteNumber(
              [for (final row in rows) (row['number'] as String?) ?? ''],
              DateTime.fromMillisecondsSinceEpoch(now).year),
          createdAt: now,
          updatedAt: now);
      final totals = computeQuote(quote);
      await txn.insert(
          table,
          quote.toRow(
              netGrosze: totals.netGrosze, grossGrosze: totals.grossGrosze),
          conflictAlgorithm: ConflictAlgorithm.abort);
      return quote;
    });
    changes.value++;
    return saved;
  }

  /// Undo preserves offers edited after confirmation and retains their number.
  Future<bool> softDeleteIfUnchanged(WeldQuote expected) async {
    final totals = computeQuote(expected);
    final snapshot = expected.toRow(
        netGrosze: totals.netGrosze, grossGrosze: totals.grossGrosze);
    final db = await AppDatabase.get();
    final removed = await db.transaction((txn) async {
      final rows =
          await txn.query(table, where: 'id = ?', whereArgs: [expected.id]);
      if (rows.length != 1 ||
          rows.single.length != snapshot.length ||
          !snapshot.entries.every((e) => rows.single[e.key] == e.value)) {
        return false;
      }
      final now = _clock();
      return await txn.update(table, {'deleted_at': now, 'updated_at': now},
              where: 'id = ? AND deleted_at IS NULL',
              whereArgs: [expected.id]) ==
          1;
    });
    if (removed) changes.value++;
    return removed;
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

  /// Numery wszystkich wycen (także usuniętych — numer nie wraca na inną
  /// ofertę).
  Future<List<String>> allNumbers() async {
    final db = await AppDatabase.get();
    final rows = await db.query(table, columns: ['number']);
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

/// Wyceny spawalnicze — tabela `weld_quotes` (v26). W `cutlist.db`, więc
/// kopia zapasowa je obejmuje. Usuwanie miękkie (kosz z przywracaniem).
library;

import 'package:uuid/uuid.dart';

import '../domain/quotes/quote_calculator.dart';
import '../domain/quotes/weld_quote.dart';
import 'db.dart';

class WeldQuoteDao {
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
    final n = await db.update(table, row, where: 'id = ?', whereArgs: [q.id]);
    if (n == 0) await db.insert(table, row);
    return saved;
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

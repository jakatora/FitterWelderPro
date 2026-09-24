/// Storage of the daily test-coupon log (`weld_coupons`, schema v18/v20).
library;

import '../domain/weld_journal/coupon_entry.dart';
import 'db.dart';

class CouponDao {
  static const String table = 'weld_coupons';

  /// Newest first.
  Future<List<CouponEntry>> listAll() async {
    final db = await AppDatabase.get();
    final rows = await db.query(table, orderBy: 'date DESC, rowid DESC');
    return rows.map(CouponEntry.fromRow).toList();
  }

  Future<CouponEntry?> getById(String id) async {
    final db = await AppDatabase.get();
    final rows =
        await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CouponEntry.fromRow(rows.single);
  }

  Future<void> insert(CouponEntry e) async {
    final db = await AppDatabase.get();
    await db.insert(table, e.toRow());
  }

  Future<void> update(CouponEntry e) async {
    final db = await AppDatabase.get();
    await db.update(table, e.toRow(), where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.get();
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }
}

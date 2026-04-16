import 'dart:math';

import '../../data/app_database.dart';

class DeviceIdProvider {
  static const _key = 'device_id';

  Future<String> getOrCreateDeviceId() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('app_kv', where: 'k = ?', whereArgs: [_key], limit: 1);
    if (rows.isNotEmpty) return rows.first['v'] as String;

    final id = _generate();
    await db.insert('app_kv', {'k': _key, 'v': id});
    return id;
  }

  String _generate() {
    final r = Random.secure();
    String hex(int len) => List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }
}

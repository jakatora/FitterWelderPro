import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cut_list_app/database/db.dart';

/// Real SQLite, privately owned by this test suite/isolate. Never opens the
/// shared cutlist.db or any user file. Initialize outside widget fake-async.
void useTestDatabase() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await AppDatabase.configureForTesting(inMemoryDatabasePath);
    await AppDatabase.get();
  });
  tearDownAll(AppDatabase.clearTestingConfiguration);
}

/// Let native SQLite finish queued work on its real event loop before moving
/// widget time forward. Advancing fake time by 15 seconds only hides pending
/// lock timers; it does not finish an actual read or prove the screen loaded.
Future<void> flushTestDatabase(WidgetTester tester) async {
  await tester.runAsync(() async {
    final db = await AppDatabase.get();
    await db.rawQuery('SELECT 1');
  });
}

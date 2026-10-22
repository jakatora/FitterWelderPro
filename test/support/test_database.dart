import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cut_list_app/database/db.dart';
import 'test_account.dart';

/// Real SQLite, privately owned by this test suite/isolate. Never opens the
/// shared cutlist.db or any user file. Initialize outside widget fake-async.
void useTestDatabase() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await seedGuestAccount();
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
///
/// The SELECT waits behind the database lock. When a transaction started in
/// the widget's fake-async zone holds that lock, its next step runs only on
/// the next pump — waiting for the lock inside runAsync would deadlock. So
/// the wait is bounded: on timeout the caller pumps and flushes again (the
/// queued SELECT runs harmlessly once the transaction commits).
Future<void> flushTestDatabase(WidgetTester tester) async {
  await tester.runAsync(() async {
    final db = await AppDatabase.get();
    try {
      await db.rawQuery('SELECT 1').timeout(const Duration(milliseconds: 300));
    } on TimeoutException {
      // Transaction in flight in the fake zone — see above.
    }
  });
}

// QA entry point only. The normal release entry point is lib/main.dart.
import 'dart:convert';

import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/main.dart' as app;

Future<void> main() async {
  // The driver must initialize the binding before any plugin or app does.
  enableFlutterDriverExtension(handler: (message) async {
    final db = await AppDatabase.get();
    switch (message) {
      case 'projectCount':
        return jsonEncode(
            await db.rawQuery('SELECT count(*) AS count FROM projects'));
      case 'failProjectReads':
        await db.execute('ALTER TABLE projects RENAME TO fixture_projects');
        return 'fixture read failure enabled';
      case 'restoreProjectReads':
        await db.execute('ALTER TABLE fixture_projects RENAME TO projects');
        return 'fixture reads restored';
      default:
        throw ArgumentError.value(message, 'message', 'Unknown QA command');
    }
  });
  // No owner preferences, account credentials or cutlist.db are accessed.
  SharedPreferences.setMockInitialValues({'app_language_v1': 'pl'});
  FlutterSecureStorage.setMockInitialValues({});
  // This file is an explicit QA entry point, never included in a release.
  // ignore: invalid_use_of_visible_for_testing_member
  await AppDatabase.configureForTesting(':memory:');
  await app.main();
}

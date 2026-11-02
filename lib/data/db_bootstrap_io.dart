import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'windows_database_location.dart';

/// Android i iOS mają wbudowaną implementację `sqflite` — nic nie ustawiamy.
/// Windows, Linux i macOS wymagają fabryki FFI.
Future<void> initDatabaseFactory() async {
  final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (defaultTargetPlatform == TargetPlatform.windows) {
      final support = await getApplicationSupportDirectory();
      const suffix = ['.dart_tool', 'sqflite_common_ffi', 'databases'];
      final directory = await WindowsDatabaseLocation(support).resolve(
        legacyDirectories: [
          p.joinAll([Directory.current.path, ...suffix]),
          p.joinAll([p.dirname(Platform.resolvedExecutable), ...suffix]),
        ],
      );
      await databaseFactory.setDatabasesPath(directory);
    }
  }
}

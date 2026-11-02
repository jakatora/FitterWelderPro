import 'dart:io';

import 'package:cut_list_app/data/db_bootstrap_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late Directory previous;
  late Directory support;

  setUp(() async {
    previous = Directory.current;
    root = await Directory.systemTemp.createTemp('fwp-bootstrap-test-');
    support = await Directory(p.join(root.path, 'support')).create();
    final launch = await Directory(p.join(root.path, 'launch')).create();
    Directory.current = launch;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') return support.path;
      throw MissingPluginException(call.method);
    });
  });

  tearDown(() async {
    Directory.current = previous;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (!p.basename(root.path).startsWith('fwp-bootstrap-test-')) {
      throw StateError('Unexpected test directory');
    }
    await root.delete(recursive: true);
  });

  test('actual bootstrap retains old project across working directories',
      () async {
    sqfliteFfiInit();
    final oldDir = Directory(p.join(Directory.current.path, '.dart_tool',
        'sqflite_common_ffi', 'databases'));
    await oldDir.create(recursive: true);
    final dbFile = p.join(oldDir.path, 'cutlist.db');
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final original = await factory.openDatabase(dbFile);
    await original.execute(
        'CREATE TABLE projects (id TEXT, name TEXT, diameter_mm REAL, wall_thickness_mm REAL)');
    await original.execute(
        'CREATE TABLE segments (id TEXT, project_id TEXT, seq_no INTEGER, iso_mm REAL, cut_mm REAL)');
    await original.insert('projects', {'name': 'Zapisany projekt'});
    await original.close();

    await initDatabaseFactory();
    expect(await databaseFactory.getDatabasesPath(), oldDir.path);
    final second = await Directory(p.join(root.path, 'second')).create();
    Directory.current = second;
    await initDatabaseFactory();
    final directory = await databaseFactory.getDatabasesPath();
    expect(directory, oldDir.path);
    final reopened =
        await databaseFactory.openDatabase(p.join(directory, 'cutlist.db'));
    try {
      expect((await reopened.query('projects')).single['name'],
          'Zapisany projekt');
    } finally {
      await reopened.close();
    }
  });
}

import 'dart:io';

import 'package:cut_list_app/data/windows_database_location.dart';
import 'package:cut_list_app/data/database_location_problem.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory temp;
  late Directory support;
  late Directory legacy;
  late WindowsDatabaseLocation resolver;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fwp-location-test-');
    support = Directory(p.join(temp.path, 'support'));
    legacy = await Directory(p.join(temp.path, 'old')).create();
    resolver = WindowsDatabaseLocation(support);
  });

  tearDown(() async {
    if (!p.basename(temp.path).startsWith('fwp-location-test-')) {
      throw StateError('Unexpected test directory');
    }
    await temp.delete(recursive: true);
  });

  test('fresh install uses stable location regardless of working directory',
      () async {
    final first = await resolver.resolve(legacyDirectories: [legacy.path]);
    final second = await resolver
        .resolve(legacyDirectories: [p.join(temp.path, 'elsewhere')]);
    expect(first, p.join(support.path, 'databases'));
    expect(second, first);
  });

  test('existing database remains in place and is remembered', () async {
    final old = File(p.join(legacy.path, 'cutlist.db'));
    await old.writeAsString('existing user data');
    await File('${old.path}-wal').writeAsString('WAL');
    expect(
        await resolver.resolve(legacyDirectories: [legacy.path]), legacy.path);
    expect(await resolver.resolve(legacyDirectories: []), legacy.path);
    expect(await old.readAsString(), 'existing user data');
    expect(await File('${old.path}-wal').readAsString(), 'WAL');
  });

  test('different existing databases do not get silently selected', () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    await File(p.join(legacy.path, 'cutlist.db')).writeAsString('first');
    await File(p.join(other.path, 'cutlist.db')).writeAsString('second');
    await expectLater(
      resolver.resolve(legacyDirectories: [legacy.path, other.path]),
      throwsA(isA<DatabaseLocationProblem>()),
    );
    expect(
        await File(p.join(legacy.path, 'cutlist.db')).readAsString(), 'first');
    expect(
        await File(p.join(other.path, 'cutlist.db')).readAsString(), 'second');
  });

  test('missing previously selected database does not create a new one',
      () async {
    final old = File(p.join(legacy.path, 'cutlist.db'));
    await old.writeAsString('existing');
    await resolver.resolve(legacyDirectories: [legacy.path]);
    await old.delete();
    await expectLater(resolver.resolve(legacyDirectories: []),
        throwsA(isA<DatabaseLocationProblem>()));
    expect(await File(p.join(support.path, 'databases', 'cutlist.db')).exists(),
        isFalse);
  });

  test('duplicate paths identify one database', () async {
    await File(p.join(legacy.path, 'cutlist.db')).writeAsString('existing');
    expect(
      await resolver
          .resolve(legacyDirectories: [legacy.path, p.join(legacy.path, '.')]),
      legacy.path,
    );
  });

  test('a newly discovered second database is never silently ignored',
      () async {
    await File(p.join(legacy.path, 'cutlist.db')).writeAsString('first');
    await resolver.resolve(legacyDirectories: [legacy.path]);
    final other = await Directory(p.join(temp.path, 'other')).create();
    await File(p.join(other.path, 'cutlist.db')).writeAsString('second');
    await expectLater(
      resolver.resolve(legacyDirectories: [other.path]),
      throwsA(isA<DatabaseLocationProblem>()),
    );
  });

  test('an invalid location marker fails closed', () async {
    await support.create(recursive: true);
    await File(p.join(support.path, 'database-location.json'))
        .writeAsString('{"version":1}');
    await expectLater(
      resolver.resolve(legacyDirectories: [legacy.path]),
      throwsFormatException,
    );
  });

  test('remembered location reopens actual SQLite project data', () async {
    final original = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(legacy.path, 'cutlist.db');
    final db = await original.openDatabase(file);
    await db.execute('CREATE TABLE projects (name TEXT)');
    await db.insert('projects', {'name': 'Projekt użytkownika'});
    await db.close();

    await resolver.resolve(legacyDirectories: [legacy.path]);
    final remembered = await resolver.resolve(legacyDirectories: []);
    final nextLaunch = createDatabaseFactoryFfi(noIsolate: true);
    await nextLaunch.setDatabasesPath(remembered);
    final reopened = await nextLaunch.openDatabase(
      p.join(await nextLaunch.getDatabasesPath(), 'cutlist.db'),
    );
    try {
      expect((await reopened.query('projects')).single['name'],
          'Projekt użytkownika');
    } finally {
      await reopened.close();
    }
  });
  test('explicit choice is remembered and all databases stay intact', () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    final first = File(p.join(legacy.path, 'cutlist.db'));
    final second = File(p.join(other.path, 'cutlist.db'));
    await first.writeAsString('first');
    await second.writeAsString('second');
    await resolver.selectExisting(other.path, [legacy.path, other.path]);
    expect(await resolver.resolve(legacyDirectories: [legacy.path, other.path]),
        other.path);
    expect(await first.readAsString(), 'first');
    expect(await second.readAsString(), 'second');
    final third = await Directory(p.join(temp.path, 'third')).create();
    await File(p.join(third.path, 'cutlist.db')).writeAsString('third');
    await expectLater(
        resolver
            .resolve(legacyDirectories: [legacy.path, other.path, third.path]),
        throwsA(isA<DatabaseLocationProblem>()));
  });

  test('a missing database cannot be silently selected', () async {
    await expectLater(
        resolver.selectExisting(legacy.path, [legacy.path]), throwsStateError);
    expect(await File(p.join(support.path, 'database-location.json')).exists(),
        isFalse);
  });

  test('missing choice offers previously acknowledged remaining database',
      () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    final first = File(p.join(legacy.path, 'cutlist.db'));
    await first.writeAsString('first');
    await File(p.join(other.path, 'cutlist.db')).writeAsString('second');
    await resolver.selectExisting(legacy.path, [legacy.path, other.path]);
    await first.delete();
    try {
      await resolver.resolve(legacyDirectories: []);
      fail('Missing selected database should require an explicit choice');
    } on DatabaseLocationProblem catch (problem) {
      expect(problem.missing, legacy.path);
      expect(problem.candidates, [other.path]);
      await resolver.selectExisting(other.path, problem.candidates);
      expect(await resolver.resolve(legacyDirectories: []), other.path);
    }
  });
}

import 'dart:io';

import 'package:cut_list_app/data/windows_database_location.dart';
import 'package:cut_list_app/data/database_location_problem.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<File> createDatabase(Directory directory, String value) async {
  final file = File(p.join(directory.path, 'cutlist.db'));
  final factory = createDatabaseFactoryFfi(noIsolate: true);
  final db = await factory.openDatabase(file.path);
  await db.execute(
      'CREATE TABLE projects (id TEXT, name TEXT, diameter_mm REAL, wall_thickness_mm REAL)');
  await db.execute(
      'CREATE TABLE segments (id TEXT, project_id TEXT, seq_no INTEGER, iso_mm REAL, cut_mm REAL)');
  await db.insert('projects', {'name': value});
  await db.close();
  return file;
}

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
    final old = await createDatabase(legacy, 'existing user data');
    final bytes = await old.readAsBytes();
    expect(
        await resolver.resolve(legacyDirectories: [legacy.path]), legacy.path);
    expect(await resolver.resolve(legacyDirectories: []), legacy.path);
    expect(await old.readAsBytes(), bytes);
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
    final old = await createDatabase(legacy, 'existing');
    await resolver.resolve(legacyDirectories: [legacy.path]);
    await old.delete();
    await expectLater(resolver.resolve(legacyDirectories: []),
        throwsA(isA<DatabaseLocationProblem>()));
    expect(await File(p.join(support.path, 'databases', 'cutlist.db')).exists(),
        isFalse);
  });

  test('duplicate paths identify one database', () async {
    await createDatabase(legacy, 'existing');
    expect(
      await resolver
          .resolve(legacyDirectories: [legacy.path, p.join(legacy.path, '.')]),
      legacy.path,
    );
  });

  test('a newly discovered second database is never silently ignored',
      () async {
    await createDatabase(legacy, 'first');
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
    await createDatabase(legacy, 'Projekt użytkownika');

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
    final first = await createDatabase(legacy, 'first');
    final second = await createDatabase(other, 'second');
    final originalFirst = await first.readAsBytes();
    final originalSecond = await second.readAsBytes();
    await resolver.selectExisting(other.path, [legacy.path, other.path]);
    expect(await resolver.resolve(legacyDirectories: [legacy.path, other.path]),
        other.path);
    expect(await first.readAsBytes(), originalFirst);
    expect(await second.readAsBytes(), originalSecond);
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

  test('an invalid cutlist.db cannot replace the remembered location',
      () async {
    final old = await createDatabase(legacy, 'existing');
    final oldBytes = await old.readAsBytes();
    await resolver.resolve(legacyDirectories: [legacy.path]);
    final marker = File(p.join(support.path, 'database-location.json'));
    final before = await marker.readAsString();
    final broken = await Directory(p.join(temp.path, 'broken')).create();
    await File(p.join(broken.path, 'cutlist.db')).writeAsString('not SQLite');
    await expectLater(
      resolver.selectExisting(broken.path, [legacy.path, broken.path]),
      throwsA(isA<Exception>()),
    );
    expect(await marker.readAsString(), before);
    expect(await old.readAsBytes(), oldBytes);
  });

  test('a forged SQLite header does not pass database validation', () async {
    final file = File(p.join(legacy.path, 'cutlist.db'));
    await file.writeAsBytes([
      ...'SQLite format 3'.codeUnits,
      0,
      ...List<int>.filled(512, 0),
    ]);
    await expectLater(
      resolver.selectExisting(legacy.path, [legacy.path]),
      throwsFormatException,
    );
    expect(await File(p.join(support.path, 'database-location.json')).exists(),
        isFalse);
  });

  test('an unrelated valid SQLite database cannot replace a selected path',
      () async {
    await createDatabase(legacy, 'existing');
    await resolver.resolve(legacyDirectories: [legacy.path]);
    final marker = File(p.join(support.path, 'database-location.json'));
    final before = await marker.readAsString();
    final foreign = await Directory(p.join(temp.path, 'foreign')).create();
    final file = p.join(foreign.path, 'cutlist.db');
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final db = await factory.openDatabase(file);
    await db.execute('CREATE TABLE users (name TEXT)');
    await db.insert('users', {'name': 'nie zmieniaj'});
    await db.close();
    await expectLater(
        resolver.selectExisting(foreign.path, [legacy.path, foreign.path]),
        throwsA(isA<Exception>()));
    expect(await marker.readAsString(), before);
    final reopened = await factory.openDatabase(file,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      expect((await reopened.query('users')).single['name'], 'nie zmieniaj');
    } finally {
      await reopened.close();
    }
  });

  test('a generic projects table is not enough to identify an app database',
      () async {
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(legacy.path, 'cutlist.db');
    final db = await factory.openDatabase(file);
    await db.execute('CREATE TABLE projects (id INTEGER, name TEXT)');
    await db.close();
    await expectLater(resolver.selectExisting(legacy.path, [legacy.path]),
        throwsA(isA<Exception>()));
    expect(await File(p.join(support.path, 'database-location.json')).exists(),
        isFalse);
  });

  test('an automatically discovered foreign database is not opened as app data',
      () async {
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(legacy.path, 'cutlist.db');
    final db = await factory.openDatabase(file);
    await db.execute('CREATE TABLE users (name TEXT)');
    await db.insert('users', {'name': 'zachowaj'});
    await db.close();
    await expectLater(resolver.resolve(legacyDirectories: [legacy.path]),
        throwsA(isA<Exception>()));
    expect(await File(p.join(support.path, 'database-location.json')).exists(),
        isFalse);
    final reopened = await factory.openDatabase(file,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      expect((await reopened.query('users')).single['name'], 'zachowaj');
    } finally {
      await reopened.close();
    }
  });

  test('after a foreign database is discovered the user can select a good one',
      () async {
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final foreign =
        await factory.openDatabase(p.join(legacy.path, 'cutlist.db'));
    await foreign.execute('CREATE TABLE users (name TEXT)');
    await foreign.close();
    final good = await Directory(p.join(temp.path, 'good')).create();
    await createDatabase(good, 'poprawny');
    try {
      await resolver.resolve(legacyDirectories: [legacy.path]);
      fail('Foreign database should require recovery');
    } on DatabaseLocationProblem catch (problem) {
      expect(problem.candidates, [legacy.path]);
      expect(problem.reason, contains('Nie rozpoznano'));
      await resolver
          .selectExisting(good.path, [...problem.candidates, good.path]);
      expect(
          await resolver.resolve(legacyDirectories: [legacy.path]), good.path);
    }
  });

  test('an unrelated database in the stable directory is rejected too',
      () async {
    final stable = await Directory(p.join(support.path, 'databases'))
        .create(recursive: true);
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(stable.path, 'cutlist.db');
    final db = await factory.openDatabase(file);
    await db.execute('CREATE TABLE users (name TEXT)');
    await db.close();
    await expectLater(
        resolver.resolve(legacyDirectories: []), throwsA(isA<Exception>()));
    final reopened = await factory.openDatabase(file,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      expect(await reopened.query('users'), isEmpty);
    } finally {
      await reopened.close();
    }
  });

  test('a previously remembered location is rechecked before use', () async {
    final old = await createDatabase(legacy, 'stary projekt');
    await resolver.resolve(legacyDirectories: [legacy.path]);
    final marker = File(p.join(support.path, 'database-location.json'));
    final before = await marker.readAsString();
    await old.delete();
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final other = await factory.openDatabase(old.path);
    await other.execute('CREATE TABLE users (name TEXT)');
    await other.insert('users', {'name': 'obce dane'});
    await other.close();
    await expectLater(
        resolver.resolve(legacyDirectories: []), throwsA(isA<Exception>()));
    expect(await marker.readAsString(), before);
    final reopened = await factory.openDatabase(old.path,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      expect((await reopened.query('users')).single['name'], 'obce dane');
    } finally {
      await reopened.close();
    }
  });

  test('the actual current application schema is accepted', () async {
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(legacy.path, 'cutlist.db');
    final db = await factory.openDatabase(file);
    await AppDatabase.createSchema(db);
    await db.close();
    await resolver.selectExisting(legacy.path, [legacy.path]);
    expect(await resolver.resolve(legacyDirectories: []), legacy.path);
  });

  test('the original project and segment schemas are accepted', () async {
    // Copied from the repository's initial app schema (e5c54d0).
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    final file = p.join(legacy.path, 'cutlist.db');
    final db = await factory.openDatabase(file);
    await db.execute('''CREATE TABLE projects (
      id TEXT PRIMARY KEY, name TEXT, material_group TEXT NOT NULL DEFAULT 'SS',
      diameter_mm REAL NOT NULL, wall_thickness_mm REAL NOT NULL,
      current_diameter_mm REAL NOT NULL, stock_length_mm REAL NOT NULL DEFAULT 6000,
      saw_kerf_mm REAL NOT NULL DEFAULT 1, gap_mm REAL NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
    await db.execute('''CREATE TABLE segments (
      id TEXT PRIMARY KEY, project_id TEXT NOT NULL, seq_no INTEGER NOT NULL,
      diameter_mm REAL NOT NULL, wall_thickness_mm REAL NOT NULL,
      start_kind TEXT NOT NULL, start_library_id TEXT, start_value_mm REAL NOT NULL,
      end_kind TEXT NOT NULL, end_library_id TEXT, end_value_mm REAL NOT NULL,
      iso_ref TEXT NOT NULL DEFAULT 'FACE', iso_expr TEXT NOT NULL,
      iso_mm REAL NOT NULL, cut_mm REAL NOT NULL,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
      UNIQUE (project_id, seq_no), FOREIGN KEY(project_id) REFERENCES projects(id))''');
    await db.insert('projects', {
      'id': 'old',
      'name': 'Stary projekt',
      'diameter_mm': 50,
      'wall_thickness_mm': 2,
      'current_diameter_mm': 50,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.close();
    await resolver.selectExisting(legacy.path, [legacy.path]);
    final reopened = await factory.openDatabase(file,
        options: OpenDatabaseOptions(readOnly: true));
    try {
      expect(
          (await reopened.query('projects')).single['name'], 'Stary projekt');
    } finally {
      await reopened.close();
    }
  });

  test('missing choice offers previously acknowledged remaining database',
      () async {
    final other = await Directory(p.join(temp.path, 'other')).create();
    final first = await createDatabase(legacy, 'first');
    await createDatabase(other, 'second');
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

  test('a valid database with committed WAL data can be selected', () async {
    final file = p.join(legacy.path, 'cutlist.db');
    final writer = createDatabaseFactoryFfi(noIsolate: true);
    final db = await writer.openDatabase(file);
    try {
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA wal_autocheckpoint=0');
      await db.execute(
          'CREATE TABLE projects (id TEXT, name TEXT, diameter_mm REAL, wall_thickness_mm REAL)');
      await db.execute(
          'CREATE TABLE segments (id TEXT, project_id TEXT, seq_no INTEGER, iso_mm REAL, cut_mm REAL)');
      await db.insert('projects', {'name': 'projekt z WAL'});
      expect(await File('$file-wal').exists(), isTrue);
      await resolver.selectExisting(legacy.path, [legacy.path]);
      expect(await resolver.resolve(legacyDirectories: []), legacy.path);
      expect((await db.query('projects')).single['name'], 'projekt z WAL');
    } finally {
      await db.close();
    }
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite_logger.dart';
import 'package:cut_list_app/database/db.dart';

// Gates only the I/O boundary. Schema creation, seed SQL and persisted rows
// are the real application code running on a real SQLite file.
class StartupFactory implements SqfliteDatabaseFactoryLogger {
  int opens = 0;
  bool failPreparation = false;
  bool failPathSynchronously = false;
  Completer<void>? preparationEntered;
  Completer<void>? preparationRelease;
  Database? lastOpened;
  @override
  Future<Database> openDatabase(String path,
      {OpenDatabaseOptions? options}) async {
    opens++;
    final real = await databaseFactoryFfi.openDatabase(path, options: options);
    lastOpened = real;
    return StartupDatabase(real, this);
  }

  @override
  Future<String> getDatabasesPath() {
    // Tak zachowuje się niezainicjowany `databaseFactory` (widżet-test bez
    // SQLite, zła kolejność startu): getter rzuca SYNCHRONICZNIE, zanim
    // cokolwiek zwróci Future.
    if (failPathSynchronously) {
      failPathSynchronously = false;
      throw StateError('databaseFactory not initialized (injected)');
    }
    return databaseFactoryFfi.getDatabasesPath();
  }
  @override
  Future<void> setDatabasesPath(String path) =>
      databaseFactoryFfi.setDatabasesPath(path);
  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfi.deleteDatabase(path);
  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfi.databaseExists(path);
  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      databaseFactoryFfi.writeDatabaseBytes(path, bytes);
  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      databaseFactoryFfi.readDatabaseBytes(path);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StartupDatabase implements Database {
  final Database real;
  final StartupFactory owner;
  bool firstStatement = true;
  StartupDatabase(this.real, this.owner);
  @override
  bool get isOpen => real.isOpen;
  @override
  String get path => real.path;
  @override
  Future<void> close() => real.close();
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (firstStatement) {
      firstStatement = false;
      owner.preparationEntered?.complete();
      if (owner.preparationRelease != null) {
        await owner.preparationRelease!.future;
      }
      if (owner.failPreparation) {
        owner.failPreparation = false;
        throw StateError('Injected schema preparation failure');
      }
    }
    await real.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
          [List<Object?>? arguments]) =>
      real.rawQuery(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      real.insert(table, values,
          nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late StartupFactory factory;
  setUpAll(() {
    sqfliteFfiInit();
    factory = StartupFactory();
    databaseFactory = factory;
  });
  setUp(() async {
    final root = await Directory('.dart_tool').absolute.create(recursive: true);
    directory = await root.createTemp('fwp-startup-');
    factory.opens = 0;
    factory.failPreparation = false;
    factory.failPathSynchronously = false;
    factory.preparationEntered = null;
    factory.preparationRelease = null;
    await AppDatabase.configureForTesting(p.join(directory.path, 'startup.db'));
  });
  tearDown(() async {
    await AppDatabase.clearTestingConfiguration();
    final root = Directory('.dart_tool').absolute.path;
    if (!p.isWithin(root, directory.path) ||
        !p.basename(directory.path).startsWith('fwp-startup-')) {
      throw StateError('Refusing cleanup outside this test directory');
    }
    await directory.delete(recursive: true);
  });

  test('simultaneous consumers initialise one ready connection, not twelve',
      () async {
    final connections =
        await Future.wait(List.generate(12, (_) => AppDatabase.get()));
    expect(factory.opens, 1);
    expect(connections.every((db) => identical(db, connections.first)), isTrue);
    final seeds = await connections.first
        .rawQuery('SELECT COUNT(*) AS n FROM approved_weld_params');
    expect(seeds.single['n'], greaterThan(0));
  });

  test(
      'another consumer cannot read a database while preparation is unfinished',
      () async {
    factory.preparationEntered = Completer<void>();
    factory.preparationRelease = Completer<void>();
    final first = AppDatabase.get();
    await factory.preparationEntered!.future;
    var returnedEarly = false;
    final second = AppDatabase.get().then((db) {
      returnedEarly = true;
      return db;
    });
    try {
      // An event-loop turn flushes a wrongly cached immediate response;
      // the explicit preparation barrier cannot finish until finally below.
      await Future<void>.delayed(Duration.zero);
      expect(returnedEarly, isFalse);
    } finally {
      factory.preparationRelease!.complete();
      await Future.wait([first, second]);
    }
  });

  test(
      'failed preparation closes the partial connection and a retry prepares again',
      () async {
    factory.failPreparation = true;
    await expectLater(AppDatabase.get(), throwsStateError);
    expect(factory.lastOpened!.isOpen, isFalse);
    final recovered = await AppDatabase.get();
    expect(recovered.isOpen, isTrue);
    expect(factory.opens, 2);
    final seeds = await recovered
        .rawQuery('SELECT COUNT(*) AS n FROM approved_weld_params');
    expect(seeds.single['n'], greaterThan(0));
  });

  test(
      'a failure thrown synchronously does not poison every later get()',
      () async {
    // _open() used to reset `_opening` in its finally BEFORE get() stored the
    // future (a synchronous throw runs the whole try/catch/finally inside the
    // call). get() then cached the failed future forever: every later caller
    // got the same stale error and — in widget tests — awaited a future owned
    // by an already finished test's zone, which never completes.
    factory.failPathSynchronously = true;
    await expectLater(AppDatabase.get(), throwsStateError);
    final recovered = await AppDatabase.get();
    expect(recovered.isOpen, isTrue);
    expect(factory.opens, 1);
  });

  test('closed cached connection reopens without losing a saved project',
      () async {
    final first = await AppDatabase.get();
    await first.insert('projects', {
      'id': 'saved-project',
      'name': 'Zapisany projekt',
      'diameter_mm': 60.3,
      'wall_thickness_mm': 2,
      'current_diameter_mm': 60.3,
      'created_at': 1,
      'updated_at': 1,
    });
    await first.close();
    final reopened = await AppDatabase.get();
    expect(reopened.isOpen, isTrue);
    final rows = await reopened
        .rawQuery('SELECT name FROM projects WHERE id = ?', ['saved-project']);
    expect(rows.single['name'], 'Zapisany projekt');
  });
}

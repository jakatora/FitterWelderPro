// Przywracanie kopii „wszystko albo nic" dla OBU baz aplikacji (cutlist.db
// i cut_list_app.db) oraz kopia zrobiona przez STARSZĄ wersję aplikacji
// (schemat cutlist.db v17 / v18) przywracana do bieżącego schematu.
//
// Wcześniej obie bazy przywracały się po kolei, każda w osobnej transakcji:
// cutlist.db zapisana, cut_list_app.db rzuca (np. klucz obcy przy COMMIT) =>
// telefon z pół nową, pół starą bazą, a zdjęcia z kopii już nadpisane.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/data/app_database.dart' as module_db;
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/services/data_backup.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

class _Phone {
  _Phone(this.root);

  final Directory root;

  Directory get documents => Directory(p.join(root.path, 'documents'));
  Directory get temp => Directory(p.join(root.path, 'tmp'));
  Directory get databases => Directory(p.join(root.path, 'databases'));
  Directory get heatPhotos => Directory(p.join(documents.path, 'heat_photos'));

  Future<void> create() async {
    for (final d in [documents, temp, databases]) {
      await d.create(recursive: true);
    }
  }
}

Future<void> _closeDatabases() async {
  await AppDatabase.clearTestingConfiguration();
  final module = await module_db.AppDatabase.instance.db;
  await module.close();
}

Future<void> _useCurrentPhone(_Phone phone) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProvider, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
      case 'getApplicationSupportDirectory':
        return phone.documents.path;
      case 'getTemporaryDirectory':
        return phone.temp.path;
    }
    return null;
  });
  await _closeDatabases();
  await databaseFactory.setDatabasesPath(phone.databases.path);
}

Future<void> _insertProject(String id, String name) async {
  final db = await AppDatabase.get();
  await db.insert('projects', <String, Object?>{
    'id': id,
    'name': name,
    'diameter_mm': 60.3,
    'wall_thickness_mm': 2.0,
    'current_diameter_mm': 60.3,
    'created_at': 1000,
    'updated_at': 1000,
  });
}

Future<List<String>> _projectNames() async {
  final db = await AppDatabase.get();
  return (await db.query('projects', orderBy: 'id'))
      .map((r) => r['name'] as String)
      .toList();
}

Future<List<String>> _moduleProjectNames() async {
  final db = await module_db.AppDatabase.instance.db;
  return (await db.query('projects', orderBy: 'id'))
      .map((r) => r['name'] as String)
      .toList();
}

Future<void> _insertModuleProject(String name, {int id = 1}) async {
  final db = await module_db.AppDatabase.instance.db;
  await db.insert('projects', <String, Object?>{
    'id': id,
    'name': name,
    'created_at': 1000,
    'updated_at': 1000,
  });
}

// ── Kopia ze starej wersji aplikacji ──────────────────────────────────────
//
// Schemat cutlist.db w wersji 17 i 18 — odtworzony tak samo jak w
// test/database/migration_test.dart (drabina migracji czytana od końca).
// Kopia to ten sam format .zip (manifest + db/*.db + heat_photos/*), tylko
// baza w środku ma stary schemat.

Future<void> _createCutlistV17(Database db) async {
  await db.execute('''
CREATE TABLE component_library (
  id TEXT PRIMARY KEY, type TEXT NOT NULL, diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL, axis_mm REAL, length_mm REAL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  material_group TEXT NOT NULL DEFAULT 'SS', measurement_mode TEXT,
  diameter_out_mm REAL)''');
  await db.execute('''
CREATE TABLE projects (
  id TEXT PRIMARY KEY, name TEXT, diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL, current_diameter_mm REAL NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  material_group TEXT NOT NULL DEFAULT 'SS',
  stock_length_mm REAL NOT NULL DEFAULT 6000,
  saw_kerf_mm REAL NOT NULL DEFAULT 1,
  gap_mm REAL NOT NULL DEFAULT 0)''');
  await db.execute('''
CREATE TABLE segments (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL, seq_no INTEGER NOT NULL,
  diameter_mm REAL NOT NULL, wall_thickness_mm REAL NOT NULL,
  start_kind TEXT NOT NULL, start_library_id TEXT,
  start_value_mm REAL NOT NULL, end_kind TEXT NOT NULL, end_library_id TEXT,
  end_value_mm REAL NOT NULL, iso_expr TEXT NOT NULL, iso_mm REAL NOT NULL,
  cut_mm REAL NOT NULL, created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL, iso_ref TEXT NOT NULL DEFAULT 'FACE',
  UNIQUE (project_id, seq_no))''');
  await db.execute('''
CREATE TABLE heat_photos (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL, library_component_id TEXT,
  image_path TEXT NOT NULL, note TEXT, created_at INTEGER NOT NULL)''');
  await db.execute('''
CREATE TABLE component_heats (
  id TEXT PRIMARY KEY, project_id TEXT NOT NULL, component_key TEXT NOT NULL,
  heat_no TEXT NOT NULL, image_path TEXT, note TEXT,
  created_at INTEGER NOT NULL)''');
  await db.execute('''
CREATE TABLE weld_journal (
  id TEXT PRIMARY KEY, weld_no TEXT, project_name TEXT, pipe_name TEXT,
  material TEXT, od TEXT, t TEXT, method TEXT, welder TEXT, date TEXT,
  notes TEXT, status TEXT)''');
  await db.execute('''
CREATE TABLE weld_coupons (
  id TEXT PRIMARY KEY, date TEXT, welder TEXT, machine TEXT,
  size TEXT, result TEXT, notes TEXT)''');
  await db.execute('PRAGMA user_version = 17');
}

Future<void> _createCutlistV18(Database db) async {
  await _createCutlistV17(db);
  for (final c in const [
    'weld_type', 'fitter', 'heat_no1', 'heat_no2', 'coupon_ref', 'exam',
    'wps_ref', //
  ]) {
    await db.execute('ALTER TABLE weld_journal ADD COLUMN $c TEXT');
  }
  await db.execute('''
CREATE TABLE iso_drawings (
  id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '', json TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)''');
  await db.execute('PRAGMA user_version = 18');
}

/// Buduje .zip kopii w formacie aplikacji z bazą cutlist.db o schemacie
/// [version] i jednym zdjęciem wytopu.
Future<File> _legacyBackup(Directory dir, int version) async {
  final dbFile = File(p.join(dir.path, 'legacy_v$version.db'));
  final db = await databaseFactoryFfi.openDatabase(dbFile.path,
      options: OpenDatabaseOptions(singleInstance: false));
  try {
    if (version == 17) {
      await _createCutlistV17(db);
    } else {
      await _createCutlistV18(db);
    }
    await db.insert('projects', <String, Object?>{
      'id': 'old-project',
      'name': 'Rurociąg z v$version',
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'current_diameter_mm': 114.3,
      'created_at': 1000,
      'updated_at': 1000,
    });
    await db.insert('segments', <String, Object?>{
      'id': 'old-seg',
      'project_id': 'old-project',
      'seq_no': 1,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'start_kind': 'logical',
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_value_mm': 0.0,
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 1000.0,
      'created_at': 1000,
      'updated_at': 1000,
    });
    await db.insert('component_heats', <String, Object?>{
      'id': 'old-heat',
      'project_id': 'old-project',
      'component_key': 'S001_END',
      'heat_no': 'H-777',
      // Ścieżka ze starego telefonu — po przywróceniu ma wskazać ten.
      'image_path': '/data/user/0/old.app/files/heat_photos/mtr-777.jpg',
      'created_at': 1000,
    });
    await db.insert('weld_journal', <String, Object?>{
      'id': 'old-weld',
      'weld_no': 'W-$version',
      'project_name': 'Rurociąg z v$version',
      'welder': 'JK-12',
      'date': '2025-05-01',
      'status': 'OK',
      if (version >= 18) 'wps_ref': 'WPS-141-01',
    });
    await db.insert('weld_coupons', <String, Object?>{
      'id': 'old-coupon',
      'date': '2025-05-01',
      'welder': 'JK-12',
      'result': 'OK',
    });
  } finally {
    await db.close();
  }

  final zipFile = File(p.join(dir.path, 'legacy_v$version.zip'));
  final chunks = <int>[];
  final zip = ZipBuilder(chunks.addAll);
  zip.addFile(
    kManifestEntry,
    utf8.encode(BackupManifest(
      app: kBackupApp,
      formatVersion: kBackupFormatVersion,
      createdAt: DateTime(2025, 5, 2),
      databases: const ['cutlist.db'],
      photoCount: 1,
    ).encode()),
  );
  zip.addFile('${kDbEntryPrefix}cutlist.db', await dbFile.readAsBytes());
  zip.addFile('${kPhotoEntryPrefix}mtr-777.jpg', const [0xFF, 0xD8, 0xFF, 0x77]);
  zip.finish();
  await zipFile.writeAsBytes(chunks, flush: true);
  return zipFile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late _Phone phoneA;
  late _Phone phoneB;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fwp_atomic_restore_');
    phoneA = _Phone(Directory(p.join(sandbox.path, 'phone_a')));
    phoneB = _Phone(Directory(p.join(sandbox.path, 'phone_b')));
    await phoneA.create();
    await phoneB.create();
    await _useCurrentPhone(phoneA);
  });

  tearDown(() async {
    DataBackup.debugBeforeDatabaseCommit = null;
    await _closeDatabases();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    try {
      await sandbox.delete(recursive: true);
    } catch (_) {
      // Windows potrafi zwolnić uchwyt pliku chwilę później.
    }
  });

  Future<File> backupAndCarry() async {
    final archive =
        await DataBackup.createBackupFile(now: DateTime(2026, 9, 24, 10));
    return archive.copy(p.join(sandbox.path, 'carried-backup.zip'));
  }

  /// Telefon B ma już własne dane w obu bazach i własne zdjęcie
  /// `shared.jpg` — o tej samej nazwie co zdjęcie w kopii.
  Future<void> seedPhoneB() async {
    await _useCurrentPhone(phoneB);
    await _insertProject('b-project', 'Dane telefonu B');
    await _insertModuleProject('Moduł telefonu B', id: 7);
    await phoneB.heatPhotos.create(recursive: true);
    await File(p.join(phoneB.heatPhotos.path, 'shared.jpg'))
        .writeAsBytes(const [0xB, 0xB, 0xB]);
  }

  Future<void> expectPhoneBUntouched() async {
    expect(await _projectNames(), ['Dane telefonu B']);
    expect(await _moduleProjectNames(), ['Moduł telefonu B']);
    expect(await File(p.join(phoneB.heatPhotos.path, 'shared.jpg')).readAsBytes(),
        const [0xB, 0xB, 0xB],
        reason: 'zdjęcie o tej samej nazwie nie może zostać nadpisane');
    final names = phoneB.heatPhotos
        .listSync()
        .map((e) => p.basename(e.path))
        .toList();
    expect(names, ['shared.jpg'], reason: 'żadne nowe zdjęcie z kopii');
  }

  /// Telefon A: dane w obu bazach i zdjęcie `shared.jpg`.
  Future<void> seedPhoneA() async {
    await _insertProject('a-project', 'Dane telefonu A');
    await _insertModuleProject('Moduł telefonu A');
    await phoneA.heatPhotos.create(recursive: true);
    await File(p.join(phoneA.heatPhotos.path, 'shared.jpg'))
        .writeAsBytes(const [0xA, 0xA, 0xA]);
  }

  test(
      'błąd drugiej bazy przy zapisie cofa pierwszą bazę i zdjęcia — '
      'telefon zostaje dokładnie taki, jak był', () async {
    await seedPhoneA();
    final carried = await backupAndCarry();
    await seedPhoneB();

    DataBackup.debugBeforeDatabaseCommit = (fileName) async {
      if (fileName == 'cut_list_app.db') {
        throw const FileSystemException('Brak miejsca na urządzeniu (test)');
      }
    };
    await expectLater(
      DataBackup.restore(carried.path),
      throwsA(isA<BackupFormatException>().having(
          (e) => e.messagePl, 'messagePl', contains('Nic nie zostało zmienione'))),
    );

    await expectPhoneBUntouched();
  });

  test(
      'kopia, której druga baza nie przejdzie kontroli kluczy obcych, jest '
      'odrzucona ZANIM cokolwiek zostanie zapisane', () async {
    await seedPhoneA();
    // Osierocony wiersz w bazie modułu (klucze obce włączone przy COMMIT).
    final module = await module_db.AppDatabase.instance.db;
    await module.execute('PRAGMA foreign_keys = OFF');
    await module.insert('heat_numbers', <String, Object?>{
      'project_id': 999,
      'heat_number': 'SIEROTA',
      'created_at': 1000,
    });
    await module.execute('PRAGMA foreign_keys = ON');
    final carried = await backupAndCarry();
    await seedPhoneB();

    var commits = 0;
    DataBackup.debugBeforeDatabaseCommit = (_) async => commits++;
    await expectLater(
      DataBackup.restore(carried.path),
      throwsA(isA<BackupFormatException>()),
    );
    expect(commits, 0, reason: 'walidacja obu baz przed jakimkolwiek zapisem');
    await expectPhoneBUntouched();
  });

  test('udane przywrócenie nadal zapisuje obie bazy i zdjęcia', () async {
    await seedPhoneA();
    final carried = await backupAndCarry();
    await seedPhoneB();

    final commits = <String>[];
    DataBackup.debugBeforeDatabaseCommit = (name) async => commits.add(name);
    final report = await DataBackup.restore(carried.path);
    expect(report.databaseCount, 2);
    expect(commits, ['cutlist.db', 'cut_list_app.db']);
    expect(await _projectNames(), ['Dane telefonu A']);
    expect(await _moduleProjectNames(), ['Moduł telefonu A']);
    expect(await File(p.join(phoneB.heatPhotos.path, 'shared.jpg')).readAsBytes(),
        const [0xA, 0xA, 0xA]);
  });

  for (final version in const [17, 18]) {
    test('kopia zrobiona przez starszą wersję (cutlist.db v$version) wraca '
        'do bieżącego schematu', () async {
      final legacy = await _legacyBackup(sandbox, version);
      await _useCurrentPhone(phoneB);
      await AppDatabase.get();

      final report = await DataBackup.restore(legacy.path);
      expect(report.isComplete, isTrue,
          reason: 'starsza kopia ma mniej kolumn — nic nie może przepaść: '
              '${report.warningPl}');
      expect(report.photoCount, 1);

      final db = await AppDatabase.get();
      final project = (await db.query('projects')).single;
      expect(project['name'], 'Rurociąg z v$version');
      expect(project['stock_length_mm'], 6000);
      expect((await db.query('segments')).single['cut_mm'], 1000.0);

      final heat = (await db.query('component_heats')).single;
      expect(heat['image_path'],
          p.join(phoneB.heatPhotos.path, 'mtr-777.jpg'),
          reason: 'ścieżka ze starego telefonu przepięta na ten');
      expect(
          await File(heat['image_path']! as String).readAsBytes(),
          const [0xFF, 0xD8, 0xFF, 0x77]);

      final weld = (await WeldJournalDao().listAll()).single;
      expect(weld.weldNo, 'W-$version');
      expect(weld.welder, 'JK-12');
      expect(weld.wpsRef, version >= 18 ? 'WPS-141-01' : '');
      // v28: stara kopia nie ma grani / przenoszenia / wyrobu — NULL.
      final weldRow = (await db.query('weld_journal')).single;
      for (final c in AppDatabase.kWeldJournalV28Columns.keys) {
        expect(weldRow.containsKey(c), isTrue, reason: c);
        expect(weldRow[c], isNull, reason: c);
      }
      expect(weld.rootBacking, isEmpty);
      expect((await db.query('weld_coupons')).single['welder'], 'JK-12');
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/data/app_database.dart' as repository_db;
import 'package:cut_list_app/database/db.dart' as cut_db;
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/database/weld_param_dao.dart';
import 'package:cut_list_app/models/project.dart' as cut_model;
import 'package:cut_list_app/models/weld_param.dart';
import 'package:cut_list_app/services/cut_calculator.dart';
import 'package:cut_list_app/services/user_profile.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

cut_model.Project _project(String id, String name) => cut_model.Project(
      id: id,
      name: name,
      materialGroup: 'SS',
      diameterMm: 60.3,
      wallThicknessMm: 2.0,
      currentDiameterMm: 60.3,
      stockLengthMm: 6000,
      sawKerfMm: 1.2,
      gapMm: 1.5,
      createdAt: 1000,
      updatedAt: 1000,
    );

Map<String, Object?> _segment({
  required String id,
  required String projectId,
  required int seqNo,
  required double cutMm,
}) =>
    {
      'id': id,
      'project_id': projectId,
      'seq_no': seqNo,
      'diameter_mm': 60.3,
      'wall_thickness_mm': 2.0,
      'start_kind': 'ELBOW',
      'start_library_id': null,
      'start_value_mm': 152.0,
      'end_kind': 'ELBOW',
      'end_library_id': null,
      'end_value_mm': 152.0,
      'iso_ref': 'FACE',
      'iso_expr': '1200',
      'iso_mm': 1200.0,
      'cut_mm': cutMm,
      'created_at': 1000,
      'updated_at': 1000,
    };

Future<void> _insertProjectGraph(String id) async {
  final db = await cut_db.AppDatabase.get();
  await ProjectDao().insert(_project(id, id));
  await ProjectDao().updateName(id, id);
  await SegmentDao().insert(_segment(
    id: 'segment-$id',
    projectId: id,
    seqNo: 1,
    cutMm: 896,
  ));
  await db.insert('heat_photos', {
    'id': 'photo-$id',
    'project_id': id,
    'library_component_id': null,
    'image_path': '/documents/$id.jpg',
    'note': id,
    'created_at': 1000,
  });
  await db.insert('component_heats', {
    'id': 'heat-$id',
    'project_id': id,
    'component_key': 'pipe-60.3',
    'heat_no': 'H-$id',
    'image_path': null,
    'note': id,
    'created_at': 1000,
  });
}

Future<Map<String, int>> _projectGraphCounts(String id) async {
  final db = await cut_db.AppDatabase.get();
  final result = <String, int>{};
  for (final table in [
    'projects',
    'segments',
    'heat_photos',
    'component_heats'
  ]) {
    result[table] = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM $table WHERE ${table == 'projects' ? 'id' : 'project_id'} = ?',
          [id],
        )) ??
        0;
  }
  return result;
}

Future<void> _createRepositoryV3(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
CREATE TABLE welder_pipe_params (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  material TEXT NOT NULL,
  od_mm REAL NOT NULL,
  wt_mm REAL NOT NULL,
  amps REAL NOT NULL,
  method TEXT NOT NULL,
  cup_size REAL NOT NULL,
  electrode_mm REAL NOT NULL,
  torch_gas TEXT NOT NULL,
  pipe_gas TEXT NOT NULL,
  purge_enabled INTEGER NOT NULL,
  purge_flow_lpm REAL,
  wire_enabled INTEGER NOT NULL,
  wire_mm REAL,
  notes TEXT,
  signature TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
        await db.insert('welder_pipe_params', {
          'material': 'SS316L',
          'od_mm': 60.3,
          'wt_mm': 2.0,
          'amps': 72.0,
          'method': 'WTC',
          'cup_size': 8.0,
          'electrode_mm': 2.4,
          'torch_gas': 'ARGON',
          'pipe_gas': 'ARGON',
          'purge_enabled': 1,
          'purge_flow_lpm': 6.0,
          'wire_enabled': 0,
          'wire_mm': null,
          'notes': 'legacy-row',
          'signature': 'legacy-signature',
          'created_at': 1000,
          'updated_at': 1000,
        });
      },
    ),
  );
  await db.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String repositoryPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('fwp-data-audit-');
    await databaseFactory.setDatabasesPath(tempDir.path);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    repositoryPath = p.join(tempDir.path, 'cut_list_app.db');
    await _createRepositoryV3(repositoryPath);
  });

  tearDownAll(() async {
    final core = await cut_db.AppDatabase.get();
    await core.close();
    final repository = await repository_db.AppDatabase.instance.db;
    await repository.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
  });

  test('migracja v3-v5 zachowuje rekord po restarcie produkcyjnej bazy',
      () async {
    final db = await repository_db.AppDatabase.instance.db;

    final rows = await db.query(
      'welder_pipe_params',
      where: 'signature = ?',
      whereArgs: ['legacy-signature'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['notes'], 'legacy-row');
    expect(rows.single['outlet_holes_count'], 1);
    expect(rows.single['weld_tempo'], 'NORMAL');

    final firstSeedCount = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM tandem_amp_params WHERE approved = 1',
    ));
    expect(firstSeedCount, greaterThan(0));

    await db.close();
    final restarted = await repository_db.AppDatabase.instance.db;
    final restartedSeedCount = Sqflite.firstIntValue(await restarted.rawQuery(
      'SELECT COUNT(*) FROM tandem_amp_params WHERE approved = 1',
    ));
    expect(restartedSeedCount, firstSeedCount,
        reason: 'restart przez produkcyjny AppDatabase nie może duplikować '
            'danych migracyjnych');
    expect(
      await restarted.query('welder_pipe_params',
          where: 'signature = ?', whereArgs: ['legacy-signature']),
      hasLength(1),
    );
  });

  test('edycja projektu i CUT segmentu przeżywa ponowne otwarcie bazy',
      () async {
    const projectId = 'reopen-project';
    const segmentId = 'reopen-segment';
    final projectDao = ProjectDao();
    final segmentDao = SegmentDao();
    final cut = calculateCutOffsets(
      isoMm: 1200,
      startOffsetMm: 152,
      endOffsetMm: 152,
    );

    await projectDao.insert(_project(projectId, 'Przed edycją'));
    await segmentDao.insert(_segment(
      id: segmentId,
      projectId: projectId,
      seqNo: 1,
      cutMm: cut,
    ));
    await projectDao.updateName(projectId, 'Po edycji');
    await segmentDao.update({
      ..._segment(
        id: segmentId,
        projectId: projectId,
        seqNo: 1,
        cutMm: cut,
      ),
      'iso_expr': '1200 FACE',
      'updated_at': 2000,
    });

    final corePath = p.join(await getDatabasesPath(), 'cutlist.db');
    final reopened = await databaseFactoryFfi.openDatabase(
      corePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(reopened.close);

    final projectRows = await reopened.query(
      'projects',
      where: 'id = ?',
      whereArgs: [projectId],
    );
    final segmentRows = await reopened.query(
      'segments',
      where: 'id = ?',
      whereArgs: [segmentId],
    );
    expect(projectRows.single['name'], 'Po edycji');
    expect(segmentRows.single['iso_expr'], '1200 FACE');
    expect(segmentRows.single['cut_mm'], 896.0,
        reason: 'eksport ma czytać zapisany CUT, nie liczyć drugi raz');
  });

  test('usunięcie projektu atomowo usuwa tylko jego dane zależne', () async {
    final db = await cut_db.AppDatabase.get();
    final projectDao = ProjectDao();

    for (final id in ['delete-a', 'keep-b']) {
      await _insertProjectGraph(id);
    }

    final snapshot = await projectDao.deleteWithSnapshot('delete-a');
    expect(snapshot.projectRows, hasLength(1));
    expect(snapshot.segmentRows, hasLength(1));
    expect(snapshot.heatPhotoRows, hasLength(1));
    expect(snapshot.componentHeatRows, hasLength(1));

    for (final table in [
      'projects',
      'segments',
      'heat_photos',
      'component_heats'
    ]) {
      final deleted = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE ${table == 'projects' ? 'id' : 'project_id'} = ?',
        ['delete-a'],
      ));
      final kept = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM $table WHERE ${table == 'projects' ? 'id' : 'project_id'} = ?',
        ['keep-b'],
      ));
      expect(deleted, 0, reason: '$table należy do usuwanego projektu');
      expect(kept, 1, reason: '$table innego projektu musi zostać');
    }
  });

  test('błąd ograniczenia cofa niepełne usunięcie projektu', () async {
    final db = await cut_db.AppDatabase.get();
    final projectDao = ProjectDao();
    await _insertProjectGraph('rollback-project');
    await db.execute('''
CREATE TRIGGER abort_rollback_project
BEFORE DELETE ON projects
WHEN OLD.id = 'rollback-project'
BEGIN
  SELECT RAISE(ABORT, 'project protected by real sqlite trigger');
END;
''');
    addTearDown(
        () => db.execute('DROP TRIGGER IF EXISTS abort_rollback_project'));

    await expectLater(
      projectDao.deleteWithSnapshot('rollback-project'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await projectDao.getById('rollback-project'), isNotNull);
    expect(
        await _projectGraphCounts('rollback-project'),
        {
          'projects': 1,
          'segments': 1,
          'heat_photos': 1,
          'component_heats': 1,
        },
        reason: 'rollback musi przywrócić każdy wcześniej usuwany zbiór');
  });

  test('snapshot Cofnij odtwarza projekt i wszystkie zależności', () async {
    const id = 'undo-project';
    final projectDao = ProjectDao();
    await _insertProjectGraph(id);

    final snapshot = await projectDao.deleteWithSnapshot(id);
    expect(await _projectGraphCounts(id), {
      'projects': 0,
      'segments': 0,
      'heat_photos': 0,
      'component_heats': 0,
    });

    await projectDao.restoreDeletion(snapshot);

    expect(await _projectGraphCounts(id), {
      'projects': 1,
      'segments': 1,
      'heat_photos': 1,
      'component_heats': 1,
    });
  });

  test('ProjectsScreen deleguje usunięcie i Cofnij wyłącznie do atomowego API',
      () {
    final source = File('lib/screens/projects_screen.dart').readAsStringSync();

    expect(source, contains('await _dao.deleteWithSnapshot(p.id)'));
    expect(source, contains('await _dao.restoreDeletion(snapshot)'));
    expect(source, isNot(contains('deleteAllForProject')));
    expect(source, isNot(contains('_segDao')));
    expect(source, contains('zdjęciami i numerami wytopów'));
    expect(source, contains('użyć „Cofnij” przez 6 sekund'));
  });

  test('WeldParamDao zachowuje wszystkie pola parametru podczas edycji',
      () async {
    final dao = WeldParamDao();
    const original = WeldParam(
      id: 'audit-weld-param',
      method: 'TIG_WIRE',
      baseMaterial: 'CS',
      welderModel: 'Kemppi X5',
      diameterMm: 60.3,
      wallThicknessMm: 2.0,
      electrodeMm: 2.4,
      torchGasLpm: 9.0,
      nozzleType: 'gas-lens',
      nozzleSize: '8',
      purgeLpm: 6.0,
      amps: 78.0,
      outletHoles: 3,
      tempo: 'SLOW',
      note: 'pierwszy zapis',
      createdAt: 1000,
      updatedAt: 1000,
    );
    const edited = WeldParam(
      id: 'audit-weld-param',
      method: 'TIG_AUTOGEN',
      baseMaterial: 'SS',
      welderModel: 'Fronius iWave',
      diameterMm: 76.1,
      wallThicknessMm: 2.6,
      electrodeMm: 3.2,
      torchGasLpm: 11.0,
      nozzleType: 'standard',
      nozzleSize: '10',
      purgeLpm: 7.5,
      amps: 94.0,
      outletHoles: 5,
      tempo: 'FAST',
      note: 'po edycji',
      createdAt: 0,
      updatedAt: 2000,
    );

    await dao.insert(original);
    await dao.update(edited);
    final restored = (await dao.listAll())
        .singleWhere((item) => item.id == 'audit-weld-param');

    expect(restored.method, 'TIG_AUTOGEN');
    expect(restored.baseMaterial, 'SS');
    expect(restored.welderModel, 'Fronius iWave');
    expect(restored.diameterMm, 76.1);
    expect(restored.wallThicknessMm, 2.6);
    expect(restored.electrodeMm, 3.2);
    expect(restored.torchGasLpm, 11.0);
    expect(restored.nozzleType, 'standard');
    expect(restored.nozzleSize, '10');
    expect(restored.purgeLpm, 7.5);
    expect(restored.amps, 94.0);
    expect(restored.outletHoles, 5);
    expect(restored.tempo, 'FAST');
    expect(restored.note, 'po edycji');
    expect(restored.createdAt, 1000,
        reason: 'edycja nie może przepisać historii utworzenia');
    expect(restored.updatedAt, 2000);
  });

  test('UserProfileService odczytuje istniejący user_profile_v1', () async {
    SharedPreferences.setMockInitialValues({
      'user_profile_v1': jsonEncode({
        'firstName': 'Łukasz',
        'lastName': 'Żółć',
      }),
    });
    UserProfileService.instance.resetForTest();

    final profile = await UserProfileService.instance.get();

    expect(profile, isNotNull);
    expect(profile!.firstName, 'Łukasz');
    expect(profile.lastName, 'Żółć');
    expect(profile.fullName, 'Łukasz Żółć');
  });
}

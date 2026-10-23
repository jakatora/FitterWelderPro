// Projekty listy cięć, ich dzieci (segmenty, wytopy, zdjęcia, odhaczenia),
// biblioteka kształtek i odczyty ISO należą do właściciela danych (schema34):
// konto nie widzi, nie zmienia i nie usuwa projektów innego konta, a dwa
// konta mogą mieć w bibliotece tę samą kształtkę.

import 'dart:convert';

import 'package:cut_list_app/database/component_heat_dao.dart';
import 'package:cut_list_app/database/component_library_dao.dart';
import 'package:cut_list_app/database/cut_mark_dao.dart';
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/heat_photo_dao.dart';
import 'package:cut_list_app/database/iso_scan_dao.dart';
import 'package:cut_list_app/database/project_dao.dart';
import 'package:cut_list_app/database/segment_dao.dart';
import 'package:cut_list_app/models/component_heat.dart';
import 'package:cut_list_app/models/library_component.dart';
import 'package:cut_list_app/models/project.dart';
import 'package:cut_list_app/services/account_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_account.dart';
import '../support/test_database.dart';

Future<void> signIn(String id) async {
  FlutterSecureStorage.setMockInitialValues({});
  AccountService.instance =
      AccountService.forTesting(MockClient((_) async => http.Response(
          jsonEncode({
            'token': 'test-$id',
            'account': {'id': id, 'role': 'user'}
          }),
          200)));
  await AccountService.instance.signIn('$id@example.test', 'test-password');
}

Project _project(String id) => Project(
      id: id,
      name: 'Rack $id',
      materialGroup: 'SS',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      currentDiameterMm: 114.3,
      stockLengthMm: 6000,
      sawKerfMm: 1,
      gapMm: 0,
      createdAt: 1,
      updatedAt: 1,
    );

Map<String, Object?> _segment(String id, String projectId, int seq) => {
      'id': id,
      'project_id': projectId,
      'seq_no': seq,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'start_kind': 'logical',
      'start_library_id': null,
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_library_id': null,
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 1000.0,
      'created_at': 1,
      'updated_at': 1,
    };

LibraryComponent _elbow(String id) => LibraryComponent(
      id: id,
      materialGroup: 'SS',
      type: 'ELB90',
      diameterMm: 114.3,
      wallThicknessMm: 3.05,
      axisMm: 152.4,
      lengthMm: null,
      measurementMode: null,
      diameterOutMm: null,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  useTestDatabase();
  setUp(() async {
    await seedGuestAccount();
    final db = await AppDatabase.get();
    for (final t in [
      'segments',
      'cut_marks',
      'component_heats',
      'heat_photos',
      'projects',
      'component_library',
      'iso_scans',
    ]) {
      await db.delete(t);
    }
  });

  test('projekt i jego dzieci: konto B nie widzi, nie dopisuje, nie zmienia',
      () async {
    await signIn('a');
    await ProjectDao().insert(_project('pa'));
    await SegmentDao().insert(_segment('sa', 'pa', 1));
    await CutMarkDao().mark(projectId: 'pa', segmentId: 'sa', part: 1, cutMm: 1000);
    final heatId = await ComponentHeatDao().add(
        projectId: 'pa', segmentId: 'sa', side: TraceSide.pipe, heatNo: 'H-1');
    await HeatPhotoDao().insert({
      'id': 'ph-a',
      'project_id': 'pa',
      'library_component_id': null,
      'image_path': '/documents/heat_photos/ph-a.jpg',
      'note': null,
      'created_at': 1,
    });

    await signIn('b');
    expect(await ProjectDao().listAll(), isEmpty);
    expect(await ProjectDao().getById('pa'), isNull);
    expect(await SegmentDao().listForProject('pa'), isEmpty);
    expect(await CutMarkDao().forProject('pa'), isEmpty);
    expect(await ComponentHeatDao().listForProject('pa'), isEmpty);
    expect(await HeatPhotoDao().listForProject('pa'), isEmpty);
    expect(await SegmentDao().sumCutForProject('pa', 114.3, 3.05), 0);

    await expectLater(SegmentDao().insert(_segment('sb', 'pa', 2)),
        throwsA(isA<AccountException>()));
    await expectLater(SegmentDao().nextSeqNo('pa'),
        throwsA(isA<AccountException>()));
    await expectLater(
        CutMarkDao().mark(projectId: 'pa', segmentId: 'sa', part: 2, cutMm: 1),
        throwsA(isA<AccountException>()));
    await expectLater(
        ComponentHeatDao().add(
            projectId: 'pa', segmentId: 'sa', side: TraceSide.end, heatNo: 'X'),
        throwsA(isA<AccountException>()));
    await expectLater(ProjectDao().insert(_project('pa')),
        throwsA(isA<AccountException>()));
    await expectLater(ProjectDao().deleteProjectCascade('pa'),
        throwsA(isA<AccountException>()));

    expect(await SegmentDao().update({..._segment('sa', 'pa', 1), 'cut_mm': 1.0}),
        0);
    expect(await SegmentDao().deleteWithSnapshot('sa'), isNull);
    expect(await ComponentHeatDao().update(heatId, heatNo: 'STOLEN'), 0);
    expect(await ProjectDao().updateIdentity('pa', const ProjectIdentity()), 0);
    await ProjectDao().updateName('pa', 'B-was-here');
    await SegmentDao().deleteById('sa');
    await SegmentDao().deleteAllForProject('pa');
    await CutMarkDao().unmark(segmentId: 'sa', part: 1);
    await ComponentHeatDao().deleteById(heatId);
    await HeatPhotoDao().deleteById('ph-a');
    await expectLater(
        ProjectDao().updateSettings('pa',
            name: 'B', stockLengthMm: 6000, sawKerfMm: 1, gapMm: 3),
        throwsA(isA<StateError>()));

    await signIn('a');
    expect((await ProjectDao().getById('pa'))?.name, 'Rack pa');
    expect((await SegmentDao().listForProject('pa')).single.cutMm, 1000);
    expect(await CutMarkDao().forProject('pa'), hasLength(1));
    expect((await ComponentHeatDao().listForProject('pa')).single.heatNo, 'H-1');
    expect(await HeatPhotoDao().listForProject('pa'), hasLength(1));
  });

  test('Cofnij usunięcia projektu nie przenosi go na inne konto', () async {
    await signIn('a');
    await ProjectDao().insert(_project('pa'));
    await SegmentDao().insert(_segment('sa', 'pa', 1));
    final deleted = await ProjectDao().deleteProjectCascade('pa');
    expect(deleted.existed, isTrue);

    await signIn('b');
    await expectLater(
        ProjectDao().restore(deleted), throwsA(isA<AccountException>()));
    expect(await ProjectDao().listAll(), isEmpty);

    await signIn('a');
    await ProjectDao().restore(deleted);
    expect((await SegmentDao().listForProject('pa')).single.id, 'sa');
  });

  test('stare projekty zostają gościowi', () async {
    await insertTestProject('legacy');
    expect((await ProjectDao().listAll()).map((p) => p.id), ['legacy']);
    await signIn('a');
    expect(await ProjectDao().listAll(), isEmpty);
  });

  test('biblioteka: ta sama kształtka na dwóch kontach, cudza niewidoczna',
      () async {
    await signIn('a');
    await ComponentLibraryDao().insert(_elbow('el-a'));
    await ProjectDao().insert(_project('pa'));
    await SegmentDao().insert(
        {..._segment('sa', 'pa', 1), 'end_library_id': 'el-a'});

    await signIn('b');
    expect(await ComponentLibraryDao().listAll(), isEmpty);
    expect(await ComponentLibraryDao().getById('el-a'), isNull);
    expect(
        await ComponentLibraryDao().listFor(
            materialGroup: 'SS', currentDiameter: 114.3, wallThickness: 3.05),
        isEmpty);
    // Ten sam typ i wymiar — UNIQUE obejmuje właściciela.
    await ComponentLibraryDao().insert(_elbow('el-b'));
    expect(await ComponentLibraryDao().findSameKind(_elbow('new')),
        isA<LibraryComponent>().having((c) => c.id, 'id', 'el-b'));
    await expectLater(ComponentLibraryDao().insert(_elbow('el-a')),
        throwsA(isA<AccountException>()));
    expect(await ComponentLibraryDao().update(_elbow('el-a')), 0);
    expect(await ComponentLibraryDao().usages('el-a'), isEmpty);
    expect(await ComponentLibraryDao().deleteIfUnused('el-a'), isEmpty);

    await signIn('a');
    expect(await ComponentLibraryDao().getById('el-a'), isNotNull,
        reason: 'konto B nie usunęło kształtki A');
    expect((await ComponentLibraryDao().usages('el-a')).single.seqNo, 1);
  });

  test('odczyty ISO: każde konto ma swoje i swój limit', () async {
    IsoScanRecord r(String id, int at) =>
        IsoScanRecord(id: id, envelopeJson: '{}', createdAt: at);
    await IsoScanDao().insert(r('guest-1', 1));
    await signIn('a');
    expect(await IsoScanDao().latest(), isNull);
    for (var i = 0; i < IsoScanDao.keep + 2; i++) {
      await IsoScanDao().insert(r('a-$i', 100 + i));
    }
    expect(await IsoScanDao().listRecent(limit: 100), hasLength(IsoScanDao.keep));
    await IsoScanDao().deleteById('guest-1');
    await expectLater(IsoScanDao().insert(r('guest-1', 5)),
        throwsA(isA<AccountException>()));

    await seedGuestAccount();
    expect((await IsoScanDao().listRecent()).map((x) => x.id), ['guest-1'],
        reason: 'limit konta A nie skasował odczytu gościa');
  });

  test('migracja v34: UNIQUE biblioteki dostaje właściciela, wiersze zostają',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    addTearDown(db.close);
    await db.execute('''
CREATE TABLE component_library (
  id TEXT PRIMARY KEY,
  material_group TEXT NOT NULL DEFAULT 'SS',
  type TEXT NOT NULL,
  diameter_mm REAL NOT NULL,
  wall_thickness_mm REAL NOT NULL,
  axis_mm REAL,
  length_mm REAL,
  measurement_mode TEXT,
  diameter_out_mm REAL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE (material_group, type, diameter_mm, wall_thickness_mm, diameter_out_mm)
)''');
    // Redukcja: przy NULL w diameter_out_mm SQLite nie egzekwuje UNIQUE.
    final row = {
      'material_group': 'SS',
      'type': 'REDUCER',
      'diameter_mm': 114.3,
      'wall_thickness_mm': 3.05,
      'length_mm': 102.0,
      'diameter_out_mm': 60.3,
      'created_at': 1,
      'updated_at': 1,
    };
    await db.insert('component_library', {...row, 'id': 'old'});
    await db.execute("ALTER TABLE component_library ADD COLUMN owner_scope "
        "TEXT NOT NULL DEFAULT 'guest'");

    await AppDatabase.ensureLibraryOwnerUnique(db);
    await AppDatabase.ensureLibraryOwnerUnique(db); // drugi raz nic nie robi

    final kept = await db.query('component_library');
    expect(kept.single['id'], 'old');
    expect(kept.single['owner_scope'], 'guest');
    expect(kept.single['length_mm'], 102.0);
    await db.insert('component_library',
        {...row, 'id': 'other', 'owner_scope': 'account:b'});
    await expectLater(
        db.insert('component_library', {...row, 'id': 'dup'}),
        throwsA(isA<DatabaseException>()),
        reason: 'w obrębie jednego konta duplikat nadal odrzucony');
  });
}

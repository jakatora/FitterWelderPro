// End-to-end backup → restore on REAL SQLite files, the way a fitter moves to
// a new phone: make the backup on phone A, carry the .zip over, restore it on
// a freshly installed phone B.
//
// `data_backup_test.dart` covers the pure half (ZIP codec, manifest, row
// projection). This file drives the platform half — `DataBackup.
// createBackupFile` and `DataBackup.restore` — with only path_provider
// mocked, because the bugs it guards against only exist between the two
// halves:
//   * a register table (weld journal, coupons, pressure tests) that the new
//     phone had not created yet was silently skipped by the restore;
//   * a component heat photo picked from the gallery was referenced by an
//     absolute path outside the app and never made it into the archive.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cut_list_app/data/app_database.dart' as module_db;
import 'package:cut_list_app/database/db.dart';
import 'package:cut_list_app/database/hydrotest_dao.dart';
import 'package:cut_list_app/database/passivation_dao.dart';
import 'package:cut_list_app/domain/passivation/passivation_record.dart';
import 'package:cut_list_app/database/welder_certificate_dao.dart';
import 'package:cut_list_app/database/wps_dao.dart';
import 'package:cut_list_app/domain/qualification/welder_certificate.dart';
import 'package:cut_list_app/domain/wps/wps_record.dart';
import 'package:cut_list_app/screens/coupon_log_screen.dart';
import 'package:cut_list_app/screens/weld_journal_screen.dart';
import 'package:cut_list_app/services/data_backup.dart';
import '../support/test_account.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

/// One simulated device: its own documents, temp and databases directories.
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

/// Points the app's two databases and path_provider at [phone]. Whatever was
/// open for the previous phone is closed, exactly like a fresh process.
///
/// The mock goes in first: closing the module database goes through its
/// `db` getter, which (only when nothing is open yet) opens it under the
/// documents directory — that must be the new phone's, never a real one.
Future<void> _useCurrentPhone(_Phone phone) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProvider, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
        return phone.documents.path;
      case 'getTemporaryDirectory':
        return phone.temp.path;
      case 'getApplicationSupportDirectory':
        return phone.documents.path;
    }
    return null;
  });
  await _closeDatabases();
  await databaseFactory.setDatabasesPath(phone.databases.path);
}

WeldEntry _weld() => WeldEntry(
      id: 'weld-1',
      weldNo: 'W-017',
      projectName: 'Blok 4',
      pipeName: 'L-12',
      material: '316L',
      od: '60,3',
      t: '2',
      method: 'TIG',
      welder: 'JK-12',
      date: '2026-09-20',
      notes: 'Przetop OK, zażółcenie poz. 2',
      status: 'OK',
      weldType: 'ORBITAL',
      fitter: 'M. Nowak',
      heatNo1: 'H-1001',
      heatNo2: 'H-1002',
      couponRef: 'K-7',
      exam: 'VT OK / boroskop OK',
      wpsRef: 'WPS-141-01',
    );

CouponEntry _coupon() => CouponEntry(
      id: 'coupon-1',
      date: '2026-09-20',
      welder: 'JK-12',
      machine: 'Orbitalna M-3',
      size: '2"×1.65',
      result: 'OK',
      notes: 'boroskop poz. 2',
    );

const _hydro = HydrotestRecord(
  id: 'hydro-1',
  systemName: 'WFI-101',
  date: '2026-09-21',
  gauge: 'M-12 / kal. 2026-03',
  pressureStartBar: 15.0,
  pressureEndBar: 14.9,
  temperatureC: 12.5,
  holdMinutes: 30,
  result: kHydrotestPass,
  witness: 'J. Kowalski',
  odMm: 60.3,
  wallMm: 3.91,
  lineLengthMm: 120000,
  designBar: 10.0,
  factor: 1.5,
  testPressureBar: 15.0,
  volumeL: 259.4,
  notes: 'Odpowietrzenie na najwyższym punkcie.',
  createdAt: 1758450000000,
);

Future<void> _insertProject(String id) async {
  final db = await AppDatabase.get();
  await db.insert('projects', <String, Object?>{
    'id': id,
    'name': 'Rack 12',
    'diameter_mm': 60.3,
    'wall_thickness_mm': 2.0,
    'current_diameter_mm': 60.3,
    'created_at': 1000,
    'updated_at': 1000,
  });
}

Future<void> _insertComponentHeat(String id, String? imagePath) async {
  final db = await AppDatabase.get();
  await db.insert('component_heats', <String, Object?>{
    'id': id,
    'project_id': 'project-1',
    'component_key': 'S001_END',
    'heat_no': 'HEAT-$id',
    'image_path': imagePath,
    'note': null,
    'created_at': 1000,
  });
}

Future<String?> _componentHeatPath(String id) async {
  final db = await AppDatabase.get();
  final rows = await db.query('component_heats',
      where: 'id = ?', whereArgs: <Object?>[id]);
  return rows.single['image_path'] as String?;
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
    await seedGuestAccount();
    sandbox = await Directory.systemTemp.createTemp('fwp_restore_');
    phoneA = _Phone(Directory(p.join(sandbox.path, 'phone_a')));
    phoneB = _Phone(Directory(p.join(sandbox.path, 'phone_b')));
    await phoneA.create();
    await phoneB.create();
    await _useCurrentPhone(phoneA);
  });

  tearDown(() async {
    await _closeDatabases();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProvider, null);
    try {
      await sandbox.delete(recursive: true);
    } catch (_) {
      // A Windows file handle released a moment late must not fail the test.
    }
  });

  /// Makes the backup on the current phone and "carries" it off the device,
  /// so nothing on phone B can read phone A's temp directory by accident.
  Future<File> backupAndCarry() async {
    final archive =
        await DataBackup.createBackupFile(now: DateTime(2026, 9, 24, 10));
    return archive.copy(p.join(sandbox.path, 'carried-backup.zip'));
  }

  test(
      'odtworzenie na świeżym telefonie przywraca dziennik spoin, kupony '
      'i próby ciśnieniowe', () async {
    await WeldJournalDao().insert(_weld());
    await CouponDao().insert(_coupon());
    await HydrotestDao().insert(_hydro);

    final carried = await backupAndCarry();

    // New phone: the app was just installed and opened once — nobody has
    // ever visited the journal, coupon or pressure-test screens on it.
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();

    final report = await DataBackup.restore(carried.path);
    expect(report.skippedTables, isEmpty,
        reason: 'every table of our own schema has to be restorable');

    final welds = await WeldJournalDao().listAll();
    expect(welds.map((w) => w.toRow()), [_weld().toRow()]);

    final coupons = await CouponDao().listAll();
    expect(coupons.map((c) => c.toRow()), [_coupon().toRow()]);

    final tests = await HydrotestDao().listAll();
    expect(tests.map((t) => t.toRow()), [_hydro.toRow()]);
  });

  test('v23: heat przypięty do segmentu, numer na zdjęciu i odhaczone cięcia '
      'jadą z kopią', () async {
    await _insertProject('project-1');
    final db = await AppDatabase.get();
    await db.insert('component_heats', <String, Object?>{
      'id': 'heat-v23',
      'project_id': 'project-1',
      'component_key': 'seg-7_PIPE',
      'heat_no': 'A12345',
      'image_path': null,
      'note': 'atest 3.1',
      'created_at': 1000,
      'segment_id': 'seg-7',
      'side': 'PIPE',
    });
    await db.insert('heat_photos', <String, Object?>{
      'id': 'photo-v23',
      'project_id': 'project-1',
      'library_component_id': null,
      'image_path': p.join(phoneA.heatPhotos.path, 'missing.jpg'),
      'note': null,
      'created_at': 1000,
      'heat_no': 'B-777',
    });
    await db.insert('cut_marks', <String, Object?>{
      'project_id': 'project-1',
      'segment_id': 'seg-7',
      'part': 1,
      'cut_mm': 1234.5,
      'marked_at': 1001,
    });

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    final report = await DataBackup.restore(carried.path);
    expect(report.skippedTables, isEmpty);

    final restored = await AppDatabase.get();
    final heat = (await restored.query('component_heats')).single;
    expect(heat['segment_id'], 'seg-7');
    expect(heat['side'], 'PIPE');
    expect(heat['heat_no'], 'A12345');
    expect((await restored.query('heat_photos')).single['heat_no'], 'B-777');
    final mark = (await restored.query('cut_marks')).single;
    expect(mark['segment_id'], 'seg-7');
    expect((mark['cut_mm']! as num).toDouble(), 1234.5);
  });

  test('zdjęcie wytopu wybrane z galerii jedzie razem z kopią', () async {
    // Rows written before the component-heat picker started copying into
    // <documents>/heat_photos hold the gallery path FilePicker returned.
    final gallery = Directory(p.join(phoneA.root.path, 'DCIM', 'Camera'));
    await gallery.create(recursive: true);
    final picked = File(p.join(gallery.path, 'IMG_0001.jpg'));
    await picked.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0x01, 0x02, 0x03]);

    await _insertProject('project-1');
    await _insertComponentHeat('heat-gallery', picked.path);

    final carried = await backupAndCarry();

    // Making a backup must not rewrite the live row on the source phone.
    expect(await _componentHeatPath('heat-gallery'), picked.path);

    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    await DataBackup.restore(carried.path);

    final restoredPath = await _componentHeatPath('heat-gallery');
    expect(restoredPath, isNotNull);
    expect(p.isWithin(phoneB.heatPhotos.path, restoredPath!), isTrue,
        reason: 'the restored row must point into this phone\'s heat_photos, '
            'not at phone A\'s gallery: $restoredPath');
    expect(await File(restoredPath).readAsBytes(),
        <int>[0xFF, 0xD8, 0xFF, 0x01, 0x02, 0x03]);
  });

  test(
      'dwa zdjęcia o tej samej nazwie z różnych folderów nie nadpisują się '
      'w kopii', () async {
    final camera = Directory(p.join(phoneA.root.path, 'DCIM', 'Camera'));
    final downloads = Directory(p.join(phoneA.root.path, 'Download'));
    await camera.create(recursive: true);
    await downloads.create(recursive: true);
    final first = File(p.join(camera.path, 'photo.jpg'));
    final second = File(p.join(downloads.path, 'photo.jpg'));
    await first.writeAsBytes(<int>[1, 1, 1]);
    await second.writeAsBytes(<int>[2, 2, 2]);
    // And an app-owned photo that happens to share the name.
    await phoneA.heatPhotos.create(recursive: true);
    await File(p.join(phoneA.heatPhotos.path, 'photo.jpg'))
        .writeAsBytes(<int>[3, 3, 3]);

    await _insertProject('project-1');
    await _insertComponentHeat('heat-camera', first.path);
    await _insertComponentHeat('heat-download', second.path);
    await _insertComponentHeat(
        'heat-owned', p.join(phoneA.heatPhotos.path, 'photo.jpg'));

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    await DataBackup.restore(carried.path);

    Future<List<int>> bytesOf(String id) async =>
        File((await _componentHeatPath(id))!).readAsBytes();

    expect(await bytesOf('heat-camera'), <int>[1, 1, 1]);
    expect(await bytesOf('heat-download'), <int>[2, 2, 2]);
    expect(await bytesOf('heat-owned'), <int>[3, 3, 3]);
  });

  test(
      'tabela znana schematowi, której brakuje w żywej bazie, zostaje '
      'utworzona i wypełniona; nieznana trafia do raportu', () async {
    // A live file that lacks weld_journal (dropped, or an odd legacy state)
    // and a backup from a newer version carrying a table this one has never
    // heard of. Before the fix both were skipped without a word.
    final live = await databaseFactory.openDatabase(
      p.join(sandbox.path, 'odd-live.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(live.close);
    await live.execute('CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT)');

    final result = await restoreTablesInto(
      live,
      <String, List<Map<String, Object?>>>{
        'projects': [
          <String, Object?>{'id': 'p1', 'name': 'Rack 12'},
        ],
        'weld_journal': [_weld().toRow()],
        'future_register': [
          <String, Object?>{'id': 'x1', 'payload': 'a'},
          <String, Object?>{'id': 'x2', 'payload': 'b'},
        ],
      },
      heatPhotosDir: phoneA.heatPhotos.path,
      restoredPhotoNames: const <String>{},
      ensureKnownTables: AppDatabase.ensureTables,
    );

    expect((await live.query('weld_journal')).single, _weld().toRow());
    expect(result.skippedTables, {'future_register': 2});
    expect(result.rowsWritten, 2);
    expect(await live.query('projects'), hasLength(1));
  });

  test(
      'v22: linia / ISO / rewizja / klient / klasa projektu i oznaczenie '
      'sztuki ze spoolem wracają z kopii', () async {
    // The backup dumps every column of every table, so the new columns ride
    // along without a line of backup code — this pins that down.
    final db = await AppDatabase.get();
    await db.insert('projects', <String, Object?>{
      'id': 'project-v22',
      'name': 'Rack 12',
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'current_diameter_mm': 114.3,
      'created_at': 1000,
      'updated_at': 1000,
      'line_no': 'DN100-CWS-1234',
      'iso_no': 'ISO-7',
      'iso_rev': 'B',
      'client': 'Orlen',
      'spec': 'A1B',
    });
    await db.insert('segments', <String, Object?>{
      'id': 'seg-v22',
      'project_id': 'project-v22',
      'seq_no': 1,
      'diameter_mm': 114.3,
      'wall_thickness_mm': 6.02,
      'start_kind': 'logical',
      'start_value_mm': 0.0,
      'end_kind': 'logical',
      'end_value_mm': 0.0,
      'iso_ref': 'OPEN|OPEN',
      'iso_expr': '1000',
      'iso_mm': 1000.0,
      'cut_mm': 1000.0,
      'created_at': 1000,
      'updated_at': 1000,
      'label': 'SP02-03',
      'spool_id': 'SP02',
    });

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    await DataBackup.restore(carried.path);

    final restored = await AppDatabase.get();
    final project = (await restored.query('projects')).single;
    expect(project['line_no'], 'DN100-CWS-1234');
    expect(project['iso_no'], 'ISO-7');
    expect(project['iso_rev'], 'B');
    expect(project['client'], 'Orlen');
    expect(project['spec'], 'A1B');
    final segment = (await restored.query('segments')).single;
    expect(segment['label'], 'SP02-03');
    expect(segment['spool_id'], 'SP02');
  });

  test(
      'v28: grań, przenoszenie metalu i wyrób spoiny jadą z kopią na nowy '
      'telefon', () async {
    final v28 = _weld().copyWith(
      method: 'MIG/MAG',
      rootBacking: WeldRootBacking.bs,
      metalTransfer: WeldMetalTransfer.dip,
      productForm: WeldProductKind.plate,
    );
    await WeldJournalDao().insert(v28);

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    final report = await DataBackup.restore(carried.path);
    expect(report.skippedTables, isEmpty);
    expect(report.droppedColumns, isEmpty);

    final back = (await WeldJournalDao().getById(v28.id))!;
    expect(back.rootBacking, 'bs');
    expect(back.metalTransfer, 'dip');
    expect(back.productForm, 'P');
    expect(back.toRow(), v28.toRow());
  });

  test(
      'kopia sprzed v28 (dziennik bez kolumn grani / przenoszenia / wyrobu) '
      'wczytuje się — pola puste, nic nie ginie', () async {
    final live = await AppDatabase.get();
    final oldRow = _weld().toRow()
      ..removeWhere(
          (k, _) => AppDatabase.kWeldJournalV28Columns.containsKey(k));
    expect(oldRow.keys, isNot(contains('root_backing')));

    final result = await restoreTablesInto(
      live,
      <String, List<Map<String, Object?>>>{
        'weld_journal': [oldRow],
      },
      heatPhotosDir: phoneA.heatPhotos.path,
      restoredPhotoNames: const <String>{},
      ensureKnownTables: AppDatabase.ensureTables,
    );
    expect(result.rowsWritten, 1);
    expect(result.droppedColumns, isEmpty);

    final row = (await live.query('weld_journal')).single;
    for (final c in AppDatabase.kWeldJournalV28Columns.keys) {
      expect(row[c], isNull, reason: c);
    }
    final weld = (await WeldJournalDao().getById(_weld().id))!;
    expect(weld.weldNo, 'W-017');
    expect(weld.wpsRef, 'WPS-141-01');
    expect(weld.rootBacking, isEmpty);
    expect(weld.metalTransfer, isEmpty);
    expect(weld.productForm, isEmpty);
  });

  test('kolumna z danymi, której ta wersja nie zna, jest zgłaszana', () async {
    final live = await databaseFactory.openDatabase(
      p.join(sandbox.path, 'narrow-live.db'),
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(live.close);
    await live.execute('CREATE TABLE weld_coupons (id TEXT PRIMARY KEY, date TEXT)');

    final result = await restoreTablesInto(
      live,
      <String, List<Map<String, Object?>>>{
        'weld_coupons': [
          <String, Object?>{'id': 'c1', 'date': '2026-09-20', 'machine': 'M-3', 'notes': null},
        ],
      },
      heatPhotosDir: phoneA.heatPhotos.path,
      restoredPhotoNames: const <String>{},
    );

    // `notes` was NULL — nothing lost, nothing to report.
    expect(result.droppedColumns, {
      'weld_coupons': ['machine'],
    });
    expect((await live.query('weld_coupons')).single['date'], '2026-09-20');
  });

  test('brakujący plik zdjęcia nie psuje kopii i ścieżka zostaje jak była',
      () async {
    final gone = p.join(phoneA.root.path, 'DCIM', 'deleted.jpg');
    await _insertProject('project-1');
    await _insertComponentHeat('heat-gone', gone);

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    await DataBackup.restore(carried.path);

    // The only record of which file the heat once pointed at stays.
    expect(await _componentHeatPath('heat-gone'), gone);
  });

  test(
      'rejestr uprawnień i biblioteka WPS jadą z kopią — skan certyfikatu '
      'i plik WPS przepięte na nowy telefon', () async {
    // v21: oba pliki leżą w <documents>/heat_photos (tak zapisują je
    // formularze), więc archiwum je zabiera; wiersze muszą po odtworzeniu
    // wskazywać katalog telefonu B, nie ścieżkę z telefonu A.
    await phoneA.heatPhotos.create(recursive: true);
    final scan = File(p.join(phoneA.heatPhotos.path, 'cert-scan.jpg'));
    await scan.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0x09]);
    final pdf = File(p.join(phoneA.heatPhotos.path, 'wps-141.pdf'));
    await pdf.writeAsBytes(<int>[0x25, 0x50, 0x44, 0x46]); // %PDF

    await WelderCertificateDao().upsert(WelderCertificate(
      id: 'cert-1',
      standard: QualificationStandard.iso9606_1,
      certNo: 'PL-UDT-0142/2026',
      expiryDate: DateTime(2028, 6, 9),
      lastConfirmedDate: DateTime(2026, 9, 1),
      processes: '141',
      thicknessMinMm: 1.5,
      photoPath: scan.path,
      createdAt: 1,
      updatedAt: 1,
    ));
    await WpsDao().upsert(WpsRecord(
      id: 'wps-1',
      wpsNo: 'WPS-141-01',
      heatInputMaxKjMm: 1.2,
      attachmentPath: pdf.path,
      createdAt: 1,
      updatedAt: 1,
    ));

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    final report = await DataBackup.restore(carried.path);
    expect(report.skippedTables, isEmpty);

    final cert = (await WelderCertificateDao().listAll()).single;
    expect(cert.certNo, 'PL-UDT-0142/2026');
    expect(cert.expiryDate, DateTime(2028, 6, 9));
    expect(cert.lastConfirmedDate, DateTime(2026, 9, 1));
    expect(cert.thicknessMinMm, 1.5);
    expect(p.isWithin(phoneB.heatPhotos.path, cert.photoPath!), isTrue,
        reason: 'skan certyfikatu wskazuje telefon A: ${cert.photoPath}');
    expect(await File(cert.photoPath!).readAsBytes(),
        <int>[0xFF, 0xD8, 0xFF, 0x09]);

    final wps = (await WpsDao().listAll()).single;
    expect(wps.heatInputMaxKjMm, 1.2);
    expect(p.isWithin(phoneB.heatPhotos.path, wps.attachmentPath!), isTrue,
        reason: 'plik WPS wskazuje telefon A: ${wps.attachmentPath}');
    expect(await File(wps.attachmentPath!).readAsBytes(),
        <int>[0x25, 0x50, 0x44, 0x46]);
  });

  test(
      'v25: historia potwierdzeń, historia kuponów, wersje WPS, rejestr '
      'pasywacji i odbiór sprzed naprawy jadą z kopią', () async {
    await WelderCertificateDao().upsert(const WelderCertificate(
      id: 'cert-25',
      standard: QualificationStandard.iso9606_1,
      createdAt: 1,
      updatedAt: 1,
    ));
    await WelderCertificateDao().addConfirmation(CertificateConfirmation(
      id: 'conf-1',
      certificateId: 'cert-25',
      date: DateTime(2026, 7, 5),
      confirmedBy: 'J. Koordynator',
      createdAt: 2,
    ));
    await CouponDao().insert(_coupon().copyWith(acceptedBy: 'QC Nowak'),
        by: 'JK-12');
    await WpsDao().upsert(const WpsRecord(
        id: 'wps-25',
        wpsNo: 'WPS-25',
        docStatus: WpsDocStatus.approved,
        createdAt: 1,
        updatedAt: 1));
    await PassivationDao().save(const PassivationRecord(
        id: 'pas-1', date: '2026-09-25', line: 'L-7', createdAt: 1,
        updatedAt: 1));
    await WeldJournalDao().insert(_weld().copyWith(
        inspector: 'J. Inspektor', inspectedAt: '2026-09-21'));
    await WeldJournalDao()
        .addRepair(_weld().id, date: '2026-09-22', reason: 'x', by: 'JK-12');

    final carried = await backupAndCarry();
    await _useCurrentPhone(phoneB);
    await AppDatabase.get();
    final report = await DataBackup.restore(carried.path);
    expect(report.skippedTables, isEmpty);

    final cert = (await WelderCertificateDao().getById('cert-25'))!;
    expect(cert.confirmations.single.confirmedBy, 'J. Koordynator');
    expect(cert.lastConfirmedDate, DateTime(2026, 7, 5));
    final coupon = (await CouponDao().listAll()).single;
    expect(coupon.acceptedBy, 'QC Nowak');
    expect(await CouponDao().history(coupon.id), hasLength(1));
    expect((await WpsDao().versionsOf('wps-25')), hasLength(1));
    expect((await WpsDao().getById('wps-25'))!.docStatus,
        WpsDocStatus.approved);
    expect((await PassivationDao().listAll()).single.line, 'L-7');
    final weld = (await WeldJournalDao().getById(_weld().id))!;
    expect(weld.inspector, isEmpty);
    expect(weld.repairs.single.prevAcceptance.inspector, 'J. Inspektor');
  });
}

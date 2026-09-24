import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cut_list_app/services/data_backup.dart';

/// Fixed moment so file names and manifests are asserted, not guessed.
final DateTime _when = DateTime(2026, 8, 30, 14, 35, 2);

/// Builds a ZIP in memory with the same writer the app ships, so every test
/// below exercises the real codec end to end — no fixtures on disk.
Uint8List _zip(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  final zip = ZipBuilder(out.add);
  entries.forEach((name, data) => zip.addFile(name, data, modified: _when));
  zip.finish();
  return out.takeBytes();
}

/// Minimal bytes that pass [looksLikeSqliteDatabase].
List<int> _fakeDb() => [...utf8.encode(kSqliteMagic), 0x01, 0x02, 0x03];

String _manifest({
  String app = kBackupApp,
  int format = kBackupFormatVersion,
  List<String> databases = const ['cutlist.db'],
  int photoCount = 0,
}) =>
    jsonEncode({
      'app': app,
      kBackupFormatKey: format,
      'createdAt': _when.toUtc().toIso8601String(),
      'databases': databases,
      'photoCount': photoCount,
    });

void main() {
  group('backupFileName', () {
    test('is sortable, zero padded and second-resolution', () {
      expect(backupFileName(DateTime(2026, 8, 30, 14, 35, 2)),
          'fitter-welder-pro-backup-2026-08-30-143502.zip');
    });

    test('pads single-digit month, day, hour, minute and second', () {
      expect(backupFileName(DateTime(2026, 1, 2, 3, 4, 5)),
          'fitter-welder-pro-backup-2026-01-02-030405.zip');
    });

    test('two backups one second apart do not collide', () {
      final a = backupFileName(DateTime(2026, 8, 30, 14, 35, 2));
      final b = backupFileName(DateTime(2026, 8, 30, 14, 35, 3));
      expect(a, isNot(b));
    });

    test('contains nothing a file system or share target rejects', () {
      final name = backupFileName(DateTime(2026, 12, 31, 23, 59, 59));
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name), isTrue,
          reason: 'name must survive Android, iOS and e-mail attachments');
    });
  });

  group('formatBackupTimestamp', () {
    test('renders minutes, zero padded', () {
      expect(formatBackupTimestamp(DateTime(2026, 8, 30, 9, 5)),
          '2026-08-30 09:05');
    });

    test('converts a UTC stamp back to local time', () {
      final utc = DateTime(2026, 8, 30, 14, 35).toUtc();
      expect(formatBackupTimestamp(utc),
          formatBackupTimestamp(DateTime(2026, 8, 30, 14, 35)));
    });
  });

  group('crc32', () {
    test('matches the published IEEE test vectors', () {
      expect(crc32(const <int>[]), 0);
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
      expect(crc32(utf8.encode('The quick brown fox jumps over the lazy dog')),
          0x414FA339);
    });

    test('changes when a single byte changes', () {
      expect(crc32(utf8.encode('heat A')), isNot(crc32(utf8.encode('heat B'))));
    });
  });

  group('ZIP codec', () {
    test('produces a file desktop tools recognise as a ZIP', () {
      final bytes = _zip({'a.txt': utf8.encode('x')});
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]); // "PK\x03\x04"
    });

    test('round-trips several entries with content intact', () {
      final bytes = _zip({
        kManifestEntry: utf8.encode(_manifest()),
        'db/cutlist.db': _fakeDb(),
        'heat_photos/a.jpg': List<int>.generate(5000, (i) => i % 256),
      });
      final source = BytesZipSource(bytes);
      final entries = {for (final e in readZipDirectory(source)) e.name: e};

      expect(entries.keys.toSet(),
          {kManifestEntry, 'db/cutlist.db', 'heat_photos/a.jpg'});
      expect(readZipEntryBytes(source, entries['db/cutlist.db']!), _fakeDb());
      expect(readZipEntryBytes(source, entries['heat_photos/a.jpg']!).length, 5000);
      expect(readZipEntryBytes(source, entries['heat_photos/a.jpg']!)[4999],
          4999 % 256);
    });

    test('stores every entry uncompressed', () {
      final source = BytesZipSource(_zip({'a.bin': List<int>.filled(1000, 7)}));
      final entry = readZipDirectory(source).single;
      expect(entry.method, 0);
      expect(entry.size, 1000);
      expect(entry.compressedSize, entry.size);
    });

    test('keeps non-ASCII entry names readable', () {
      final source = BytesZipSource(_zip({'heat_photos/wytop-ąćę.jpg': [1, 2]}));
      expect(readZipDirectory(source).single.name, 'heat_photos/wytop-ąćę.jpg');
    });

    test('handles an empty entry', () {
      final source = BytesZipSource(_zip({'empty.bin': const <int>[]}));
      final entry = readZipDirectory(source).single;
      expect(entry.size, 0);
      expect(readZipEntryBytes(source, entry), isEmpty);
    });

    test('rejects a file that is not a ZIP at all', () {
      final source = BytesZipSource(utf8.encode('%PDF-1.7 this is a drawing'));
      expect(() => readZipDirectory(source), throwsA(isA<BackupFormatException>()));
    });

    test('rejects a truncated archive', () {
      final full = _zip({'a.txt': utf8.encode('hello')});
      final cut = BytesZipSource(full.sublist(0, full.length - 10));
      expect(() => readZipDirectory(cut), throwsA(isA<BackupFormatException>()));
    });

    test('a flipped byte inside an entry fails the CRC check', () {
      final bytes = _zip({'a.txt': utf8.encode('heat 12345')});
      // Entry data starts after the 30-byte local header plus the name.
      bytes[30 + 'a.txt'.length + 2] ^= 0xFF;
      final source = BytesZipSource(bytes);
      final entry = readZipDirectory(source).single;
      expect(() => readZipEntryBytes(source, entry),
          throwsA(isA<BackupFormatException>()));
    });

    test('addFile after finish is a programming error, not silent corruption', () {
      final zip = ZipBuilder(BytesBuilder().add);
      zip.finish();
      expect(() => zip.addFile('a', const [1]), throwsStateError);
    });
  });

  group('looksLikeSqliteDatabase', () {
    test('accepts a real SQLite header', () {
      expect(looksLikeSqliteDatabase(_fakeDb()), isTrue);
    });

    test('rejects a renamed text file and anything too short', () {
      expect(looksLikeSqliteDatabase(utf8.encode('not a database at all')), isFalse);
      expect(looksLikeSqliteDatabase(const [1, 2, 3]), isFalse);
    });
  });

  group('BackupManifest', () {
    test('round-trips across time zones', () {
      final manifest = BackupManifest(
        app: kBackupApp,
        formatVersion: kBackupFormatVersion,
        createdAt: _when,
        databases: const ['cutlist.db', 'cut_list_app.db'],
        photoCount: 12,
      );
      final decoded = BackupManifest.decode(utf8.encode(manifest.encode()));
      expect(decoded.app, kBackupApp);
      expect(decoded.formatVersion, kBackupFormatVersion);
      expect(decoded.createdAt.toUtc(), _when.toUtc());
      expect(decoded.databases, ['cutlist.db', 'cut_list_app.db']);
      expect(decoded.photoCount, 12);
    });

    test('rejects json from another app', () {
      expect(
        () => BackupManifest.decode(utf8.encode(_manifest(app: 'some-other-app'))),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects a payload that is not json', () {
      expect(() => BackupManifest.decode(utf8.encode('<html>nope</html>')),
          throwsA(isA<BackupFormatException>()));
    });

    test('refuses a format version it does not understand', () {
      expect(
        () => BackupManifest.decode(
            utf8.encode(_manifest(format: kBackupFormatVersion + 1))),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.messageEn.contains('newer version'))),
      );
    });
  });

  group('describeBackup', () {
    test('lists the databases and photos it will restore', () {
      final contents = describeBackup(
        entryNames: const [
          kManifestEntry,
          'db/cutlist.db',
          'db/cut_list_app.db',
          'heat_photos/a.jpg',
          'heat_photos/b.jpg',
        ],
        manifestBytes: utf8.encode(
            _manifest(databases: ['cutlist.db', 'cut_list_app.db'], photoCount: 2)),
      );
      expect(contents.databaseEntries,
          {'cutlist.db': 'db/cutlist.db', 'cut_list_app.db': 'db/cut_list_app.db'});
      expect(contents.photoCount, 2);
      expect(contents.manifest.createdAt.toUtc(), _when.toUtc());
    });

    test('a foreign ZIP without our manifest is refused', () {
      expect(
        () => describeBackup(
            entryNames: const ['photo.jpg', 'notes.txt'], manifestBytes: null),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('an archive with a manifest but no database is refused', () {
      expect(
        () => describeBackup(
          entryNames: const [kManifestEntry, 'heat_photos/a.jpg'],
          manifestBytes: utf8.encode(_manifest(databases: const [])),
        ),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a manifest promising a database the archive lacks is refused', () {
      expect(
        () => describeBackup(
          entryNames: const [kManifestEntry, 'db/cutlist.db'],
          manifestBytes: utf8
              .encode(_manifest(databases: ['cutlist.db', 'cut_list_app.db'])),
        ),
        throwsA(predicate((e) =>
            e is BackupFormatException && e.messageEn.contains('incomplete'))),
      );
    });

    test('ignores stray entries outside the two known folders', () {
      final contents = describeBackup(
        entryNames: const [
          kManifestEntry,
          'db/cutlist.db',
          'db/nested/other.db',
          'README.txt',
          'heat_photos/',
        ],
        manifestBytes: utf8.encode(_manifest()),
      );
      expect(contents.databaseEntries.keys, ['cutlist.db']);
      expect(contents.photoEntries, isEmpty);
    });

    test('reads an archive produced by our own writer', () {
      final bytes = _zip({
        kManifestEntry: utf8.encode(_manifest(photoCount: 1)),
        'db/cutlist.db': _fakeDb(),
        'heat_photos/a.jpg': const [0xFF, 0xD8, 0xFF],
      });
      final source = BytesZipSource(bytes);
      final entries = readZipDirectory(source);
      final manifestEntry = entries.firstWhere((e) => e.name == kManifestEntry);
      final contents = describeBackup(
        entryNames: entries.map((e) => e.name).toList(),
        manifestBytes: readZipEntryBytes(source, manifestEntry),
      );
      expect(contents.databaseEntries['cutlist.db'], 'db/cutlist.db');
      expect(contents.photoEntries, ['heat_photos/a.jpg']);
    });
  });

  group('zipEntryBaseName', () {
    test('handles both separators, so Android backups restore on iOS', () {
      expect(zipEntryBaseName('/data/user/0/app/files/heat_photos/x.jpg'), 'x.jpg');
      expect(zipEntryBaseName(r'C:\Users\jan\heat_photos\x.jpg'), 'x.jpg');
      expect(zipEntryBaseName('x.jpg'), 'x.jpg');
      expect(zipEntryBaseName(''), '');
    });
  });

  group('relinkPhotoPath', () {
    const heatDir = '/phone/documents/heat_photos';

    test('re-anchors a photo the archive actually carried', () {
      expect(
        relinkPhotoPath('/old/phone/heat_photos/uuid-1.jpg',
            heatPhotosDir: heatDir, restoredPhotoNames: {'uuid-1.jpg'}),
        p.join(heatDir, 'uuid-1.jpg'),
      );
    });

    test('keeps the original path when the photo is not in the archive', () {
      const stored = '/old/phone/heat_photos/missing.jpg';
      expect(
        relinkPhotoPath(stored,
            heatPhotosDir: heatDir, restoredPhotoNames: {'uuid-1.jpg'}),
        stored,
      );
    });

    test('leaves null and blank alone', () {
      expect(
          relinkPhotoPath(null,
              heatPhotosDir: heatDir, restoredPhotoNames: const {}),
          isNull);
      expect(
          relinkPhotoPath('  ',
              heatPhotosDir: heatDir, restoredPhotoNames: const {}),
          '  ');
    });
  });

  group('isRestorableTable', () {
    test('accepts the app tables', () {
      for (final t in const [
        'projects',
        'segments',
        'heat_photos',
        'component_heats',
        'weld_params'
      ]) {
        expect(isRestorableTable(t), isTrue, reason: t);
      }
    });

    test("refuses SQLite's and Android's own bookkeeping", () {
      expect(isRestorableTable('sqlite_sequence'), isFalse);
      expect(isRestorableTable('sqlite_stat1'), isFalse);
      expect(isRestorableTable('android_metadata'), isFalse);
    });

    test('refuses anything that is not a plain identifier', () {
      expect(isRestorableTable('drop table; --'), isFalse);
      expect(isRestorableTable('weld"params'), isFalse);
      expect(isRestorableTable(''), isFalse);
      expect(isRestorableTable('9lives'), isFalse);
    });
  });

  group('prepareRows', () {
    const heatDir = '/phone/documents/heat_photos';

    test('drops columns the live schema no longer has', () {
      final rows = prepareRows(
        table: 'projects',
        rows: [
          {'id': 'p1', 'name': 'Rack 12', 'removed_in_v18': 'junk'}
        ],
        liveColumns: {'id', 'name'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: const {},
      );
      expect(rows.single, {'id': 'p1', 'name': 'Rack 12'});
    });

    test('keeps a row from an older backup that lacks newer columns', () {
      final rows = prepareRows(
        table: 'projects',
        rows: [
          {'id': 'p1', 'name': 'Rack 12'}
        ],
        liveColumns: {'id', 'name', 'gap_mm'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: const {},
      );
      // gap_mm is left out so SQLite fills its schema default, in millimetres.
      expect(rows.single.containsKey('gap_mm'), isFalse);
      expect(rows.single['id'], 'p1');
    });

    test('skips a row that shares no column with the live table', () {
      final rows = prepareRows(
        table: 'projects',
        rows: [
          {'totally': 1, 'unknown': 2}
        ],
        liveColumns: {'id', 'name'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: const {},
      );
      expect(rows, isEmpty);
    });

    test('re-anchors heat photo paths onto this device', () {
      final rows = prepareRows(
        table: 'heat_photos',
        rows: [
          {'id': 'h1', 'image_path': '/old/heat_photos/uuid-1.jpg'},
          {'id': 'h2', 'image_path': '/old/heat_photos/gone.jpg'},
        ],
        liveColumns: {'id', 'image_path'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: {'uuid-1.jpg'},
      );
      expect(rows[0]['image_path'], p.join(heatDir, 'uuid-1.jpg'));
      expect(rows[1]['image_path'], '/old/heat_photos/gone.jpg');
    });

    test('re-anchors component_heats too, and tolerates a null path', () {
      final rows = prepareRows(
        table: 'component_heats',
        rows: [
          {'id': 'c1', 'image_path': r'D:\old\heat_photos\uuid-2.jpg'},
          {'id': 'c2', 'image_path': null},
        ],
        liveColumns: {'id', 'image_path'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: {'uuid-2.jpg'},
      );
      expect(rows[0]['image_path'], p.join(heatDir, 'uuid-2.jpg'));
      expect(rows[1]['image_path'], isNull);
    });

    test('does not touch paths in tables that hold no photos', () {
      final rows = prepareRows(
        table: 'projects',
        rows: [
          {'id': 'p1', 'image_path': '/old/heat_photos/uuid-1.jpg'}
        ],
        liveColumns: {'id', 'image_path'},
        heatPhotosDir: heatDir,
        restoredPhotoNames: {'uuid-1.jpg'},
      );
      expect(rows.single['image_path'], '/old/heat_photos/uuid-1.jpg');
    });
  });

  group('archiveNameForExternalPhoto', () {
    test('keeps the file name readable and marks it as adopted', () {
      final taken = <String>{};
      final name =
          archiveNameForExternalPhoto('/storage/DCIM/Camera/IMG_0001.jpg', taken);
      expect(name, startsWith('ext-'));
      expect(name, endsWith('-IMG_0001.jpg'));
      expect(taken, contains(name));
    });

    test('is stable for the same source path across two backups', () {
      expect(
        archiveNameForExternalPhoto('/a/b/photo.jpg', <String>{}),
        archiveNameForExternalPhoto('/a/b/photo.jpg', <String>{}),
      );
    });

    test('two folders with the same file name never share an entry', () {
      final taken = <String>{'photo.jpg'};
      final a = archiveNameForExternalPhoto('/DCIM/photo.jpg', taken);
      final b = archiveNameForExternalPhoto('/Download/photo.jpg', taken);
      expect(a, isNot(b));
      expect(a, isNot('photo.jpg'));
      expect(b, isNot('photo.jpg'));
    });

    test('an exact name clash gets a counter before the extension', () {
      final taken = <String>{};
      final first = archiveNameForExternalPhoto('/x/photo.jpg', taken);
      final second = archiveNameForExternalPhoto('/x/photo.jpg', taken);
      expect(second, isNot(first));
      expect(second, endsWith('-2.jpg'));
    });

    test('never produces a name that climbs out of the photo folder', () {
      final name = archiveNameForExternalPhoto('/weird/..', <String>{});
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(r'\')));
      expect(name, isNot('..'));
    });
  });

  group('droppedColumnsWithData', () {
    test('reports only columns that carried a value', () {
      expect(
        droppedColumnsWithData(
          [
            {'id': 'a', 'machine': 'M-3', 'extra': null},
            {'id': 'b', 'zeta': 0},
          ],
          {'id'},
        ),
        ['machine', 'zeta'],
      );
    });

    test('is empty when every column has a place', () {
      expect(
        droppedColumnsWithData([
          {'id': 'a', 'date': '2026-09-20'}
        ], {'id', 'date'}),
        isEmpty,
      );
    });
  });

  group('RestoreReport', () {
    RestoreReport report({
      List<SkippedTable> skipped = const [],
      Map<String, List<String>> dropped = const {},
    }) =>
        RestoreReport(
          createdAt: _when,
          databaseCount: 2,
          rowCount: 10,
          photoCount: 1,
          skippedTables: skipped,
          droppedColumns: dropped,
        );

    test('a complete restore carries no warning', () {
      final r = report();
      expect(r.isComplete, isTrue);
      expect(r.warningPl, isNull);
      expect(r.warningEn, isNull);
    });

    test('an empty unknown table is not worth a warning', () {
      final r = report(skipped: const [
        SkippedTable(database: 'cutlist.db', table: 'future', rowCount: 0),
      ]);
      expect(r.isComplete, isTrue);
    });

    test('names the skipped table and the lost columns in both languages', () {
      final r = report(
        skipped: const [
          SkippedTable(database: 'cutlist.db', table: 'future', rowCount: 3),
        ],
        dropped: const {
          'cutlist.db/weld_coupons': ['machine'],
        },
      );
      expect(r.isComplete, isFalse);
      expect(r.warningPl, contains('future (rekordy: 3)'));
      expect(r.warningPl, contains('machine'));
      expect(r.warningEn, contains('future (records: 3)'));
    });
  });
}
